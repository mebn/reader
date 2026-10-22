package com.mebn.reader.sync

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.mebn.reader.ReaderApp
import com.mebn.reader.model.Collection
import com.mebn.reader.model.SyncRecord
import com.mebn.reader.model.decode
import com.mebn.reader.model.json
import com.mebn.reader.model.now
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.KSerializer
import okhttp3.Request
import java.io.File
import kotlin.coroutines.cancellation.CancellationException

/** One write waiting for the server, kept on disk until it's accepted. */
@Serializable
private data class Op(
    /** "put" or "deleteFolder". */
    val type: String,
    val id: String,
    val collection: String? = null,
    val record: String? = null,
) {
    fun replaces(other: Op) = type == "put" && other.type == "put" && collection == other.collection && id == other.id
}

/**
 * Keeps the local library in sync with the server: writes are applied locally first and
 * queued in a persistent outbox, and other devices are heard through the server's event
 * stream, which triggers an incremental pull. Runs on the main thread.
 */
object SyncEngine {
    val library = Library()
    var session by mutableStateOf<Session?>(null); private set
    /** True while the event stream is connected. */
    var live by mutableStateOf(false); private set
    /** Called when the server no longer accepts this device's token. */
    var onSignedOut: (() -> Unit)? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var outbox = listOf<Op>()
    private var flushing = false
    private var pulling = false
    private var pullAgain = false
    private var jobs = listOf<Job>()
    private var retryJob: Job? = null
    private var saveJob: Job? = null

    private const val RETRY_DELAY = 5_000L
    private const val POLL_INTERVAL = 60_000L

    init {
        val connectivity = ReaderApp.context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        connectivity.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                scope.launch { wake() }
            }
        })
    }

    fun start(session: Session) {
        stop()
        this.session = session
        library.reset(read("snapshot", Library.Snapshot.serializer()))
        outbox = read("outbox", ListSerializer(Op.serializer())) ?: emptyList()
        library.onChange = { scheduleSave() }

        jobs = listOf(
            scope.launch { listen() },
            scope.launch {
                while (isActive) {
                    delay(POLL_INTERVAL)
                    pull()
                }
            },
            scope.launch { pull() },
        )
        flush()
    }

    fun stop() {
        jobs.forEach { it.cancel() }
        jobs = emptyList()
        retryJob?.cancel()
        if (session != null) writeSnapshot()
        library.onChange = null
        session = null
        live = false
    }

    /** Back in the foreground or online again: catch up both ways. */
    fun wake() {
        if (session == null) return
        flush()
        scope.launch { pull() }
    }

    // Writes

    /** Saves a record locally and queues it for the server. */
    fun <T : SyncRecord> put(record: T): T {
        @Suppress("UNCHECKED_CAST")
        val stamped = record.stamped(maxOf(now(), record.modifiedAt + 1)) as T
        library.merge(listOf(stamped))
        enqueue(Op("put", stamped.id, stamped.collection.path, stamped.encode()))
        return stamped
    }

    /** Deletes a folder; its books and subfolders move up one level. */
    fun deleteFolder(id: String) {
        val folder = library.folders[id] ?: return
        val parent = folder.parentId
        val time = now()
        library.merge(library.books.values.filter { it.folderId == id }.map { it.copy(folderId = parent, modifiedAt = time) })
        library.merge(
            library.folders.values.filter { it.parentId == id }.map { it.copy(parentId = parent, modifiedAt = time) } +
                folder.copy(deleted = true, modifiedAt = time),
        )
        enqueue(Op("deleteFolder", id))
    }

    /** Records that were created on the server directly (uploads). */
    fun received(record: SyncRecord) = library.merge(listOf(record))

    private fun enqueue(op: Op) {
        outbox = outbox.filterNot { op.replaces(it) } + op
        write("outbox", outbox, ListSerializer(Op.serializer()))
        flush()
    }

    fun flush() {
        if (flushing || session == null) return
        flushing = true
        scope.launch {
            try {
                while (true) {
                    val op = outbox.firstOrNull() ?: break
                    val session = session ?: break
                    try {
                        if (op.type == "deleteFolder") {
                            Api.deleteFolder(session, op.id)
                        } else {
                            val collection = Collection.entries.first { it.path == op.collection }
                            library.merge(listOf(Api.put(session, collection.decode(op.record!!))))
                        }
                    } catch (e: ApiError) {
                        if (e.status == 0 || e.status >= 500) {
                            scheduleRetry()
                            return@launch
                        }
                        handle(e)
                    }
                    outbox = outbox.filter { it != op }
                    write("outbox", outbox, ListSerializer(Op.serializer()))
                }
            } finally {
                flushing = false
            }
        }
    }

    private fun scheduleRetry() {
        retryJob?.cancel()
        retryJob = scope.launch {
            delay(RETRY_DELAY)
            flush()
        }
    }

    // Reads

    suspend fun pull() {
        val session = session ?: return
        if (pulling) {
            pullAgain = true
            return
        }
        pulling = true
        try {
            do {
                pullAgain = false
                val changes = Api.sync(session, library.version)
                if (this.session != session) return
                library.apply(changes)
            } while (pullAgain)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            handle(e)
            library.ready = true
        } finally {
            pulling = false
        }
    }

    /**
     * Listens to the server's event stream, which names the newest version whenever
     * something changes, and reconnects when it drops.
     */
    private suspend fun listen() {
        while (true) {
            val session = session ?: return
            try {
                val request = Request.Builder().url(Api.eventsUrl(session)).build()
                val response = Api.streamClient.newCall(request).await()
                response.use {
                    if (it.code == 401) {
                        handle(ApiError("unauthorized", 401))
                        return
                    }
                    if (it.code != 200) throw ApiError("events", it.code)
                    live = true
                    flush()
                    val source = it.body.source()
                    var event = ""
                    while (true) {
                        val line = withContext(Dispatchers.IO) { source.readUtf8Line() } ?: break
                        if (line.startsWith("event:")) {
                            event = line.drop(6).trim()
                        } else if (line.startsWith("data:") && event == "version") {
                            val version = line.drop(5).trim().toLongOrNull() ?: 0
                            if (version > library.version) pull()
                        }
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
            }
            live = false
            delay(3_000)
        }
    }

    private fun handle(error: Exception) {
        if (error is ApiError && error.status == 401) onSignedOut?.invoke() else Log.w("sync", error)
    }

    // Storage

    private fun scheduleSave() {
        saveJob?.cancel()
        saveJob = scope.launch {
            delay(800)
            writeSnapshot()
        }
    }

    private fun writeSnapshot() = write("snapshot", library.snapshot, Library.Snapshot.serializer())

    private val directory: File?
        get() {
            val email = session?.email ?: return null
            return File(ReaderApp.context.filesDir, "accounts/${Api.escape(email)}").apply { mkdirs() }
        }

    private fun <T> read(name: String, serializer: KSerializer<T>): T? {
        val file = File(directory ?: return null, "$name.json")
        if (!file.exists()) return null
        return runCatching { json.decodeFromString(serializer, file.readText()) }.getOrNull()
    }

    private fun <T> write(name: String, value: T, serializer: KSerializer<T>) {
        val dir = directory ?: return
        runCatching {
            val temp = File(dir, "$name.json.tmp")
            temp.writeText(json.encodeToString(serializer, value))
            temp.renameTo(File(dir, "$name.json"))
        }.onFailure { Log.w("storage", it) }
    }
}
