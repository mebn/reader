package com.mebn.reader.sync

import android.util.Log
import com.mebn.reader.model.Book
import com.mebn.reader.model.Changes
import com.mebn.reader.model.Device
import com.mebn.reader.model.SyncRecord
import com.mebn.reader.model.User
import com.mebn.reader.model.decode
import com.mebn.reader.model.json
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.File
import java.io.IOException
import java.net.URLEncoder
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class ApiError(message: String, /** 0 when the server couldn't be reached. */ val status: Int) : Exception(message)

/** The sync server's REST API. */
object Api {
    val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    /** For the event stream, which is quiet for long stretches. */
    val streamClient: OkHttpClient = client.newBuilder().readTimeout(120, TimeUnit.SECONDS).build()

    private val jsonType = "application/json".toMediaType()

    private suspend fun raw(session: Session?, method: String, url: String, body: RequestBody?): String {
        val request = Request.Builder().url(url).method(method, body).apply {
            if (session != null && session.token.isNotEmpty()) header("Authorization", "Bearer ${session.token}")
        }.build()
        val response = try {
            client.newCall(request).await()
        } catch (e: IOException) {
            Log.w("api", "request failed", e)
            throw ApiError("Can't reach the server", 0)
        }
        response.use {
            // Large bodies arrive in pieces, which mustn't be waited for on the main thread.
            val text = withContext(Dispatchers.IO) { it.body.string() }
            if (!it.isSuccessful) {
                val message = runCatching { json.parseToJsonElement(text).jsonObject["error"]?.jsonPrimitive?.content }.getOrNull()
                throw ApiError(message ?: it.message.ifEmpty { "Error ${it.code}" }, it.code)
            }
            return text
        }
    }

    private suspend fun send(session: Session, method: String, path: String, body: String? = null): String =
        raw(session, method, session.url(path), body?.toRequestBody(jsonType) ?: if (method == "GET" || method == "DELETE") null else "".toRequestBody())

    @Serializable private data class Credentials(val email: String, val password: String, val device: DeviceInfo)
    @Serializable private data class AuthResponse(val token: String, val user: User)
    @Serializable private data class DeviceBody(val device: DeviceInfo)
    @Serializable data class GoogleStart(val url: String, val state: String, val secret: String)
    /** The poll answers with a session, or with a status while the person hasn't finished. */
    @Serializable private data class GooglePoll(val token: String? = null, val user: User? = null)

    private fun anonymous(server: String) = Session(server, "", "")

    suspend fun login(server: String, email: String, password: String, device: DeviceInfo): Pair<String, User> {
        val body = json.encodeToString(Credentials.serializer(), Credentials(email, password, device))
        val r = json.decodeFromString(AuthResponse.serializer(), send(anonymous(server), "POST", "/auth/login", body))
        return r.token to r.user
    }

    suspend fun register(server: String, email: String, password: String, device: DeviceInfo): Pair<String, User> {
        val body = json.encodeToString(Credentials.serializer(), Credentials(email, password, device))
        val r = json.decodeFromString(AuthResponse.serializer(), send(anonymous(server), "POST", "/auth/register", body))
        return r.token to r.user
    }

    /** Starts Google sign-in: open `url` in a browser, then poll with `state` and `secret`. */
    suspend fun googleStart(server: String, device: DeviceInfo): GoogleStart {
        val body = json.encodeToString(DeviceBody.serializer(), DeviceBody(device))
        return json.decodeFromString(GoogleStart.serializer(), send(anonymous(server), "POST", "/auth/google/start", body))
    }

    /** The session once the person has signed in with Google; null while they haven't. */
    suspend fun googlePoll(server: String, state: String, secret: String): Pair<String, User>? {
        val r = json.decodeFromString(GooglePoll.serializer(), send(anonymous(server), "GET", "/auth/google/poll?state=${escape(state)}&secret=${escape(secret)}"))
        return if (r.token != null && r.user != null) r.token to r.user else null
    }

    suspend fun devices(s: Session): List<Device> =
        json.decodeFromString(ListSerializer(Device.serializer()), send(s, "GET", "/devices"))

    suspend fun removeDevice(s: Session, id: String) {
        send(s, "DELETE", "/devices/${escape(id)}")
    }

    suspend fun sync(s: Session, since: Long): Changes =
        json.decodeFromString(Changes.serializer(), send(s, "GET", "/sync?since=$since"))

    suspend fun put(s: Session, record: SyncRecord): SyncRecord =
        record.collection.decode(send(s, "PUT", "/${record.collection.path}/${escape(record.id)}", record.encode()))

    suspend fun deleteFolder(s: Session, id: String) {
        send(s, "DELETE", "/folders/${escape(id)}")
    }

    suspend fun uploadBook(s: Session, book: Book, file: File, cover: ByteArray?): Book {
        val octet = "application/octet-stream".toMediaType()
        val form = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart("meta", book.encode())
            .addFormDataPart("file", book.fileName.replace("\"", "'"), file.asRequestBody(octet))
            .apply { if (cover != null) addFormDataPart("cover", "cover", cover.toRequestBody(octet)) }
            .build()
        return json.decodeFromString(Book.serializer(), raw(s, "POST", s.url("/books/${book.id}"), form))
    }

    fun bookFileUrl(s: Session, id: String) = s.url("/books/${escape(id)}/file")

    fun coverUrl(s: Session, book: Book) = s.url("/books/${book.id}/cover?v=${book.modifiedAt}&token=${escape(s.token)}")

    fun eventsUrl(s: Session) = s.url("/events?token=${escape(s.token)}")

    /** Like encodeURIComponent. */
    fun escape(s: String): String = URLEncoder.encode(s, "UTF-8").replace("+", "%20")
}

/** Runs a call, cancelling it when the coroutine is cancelled. */
suspend fun Call.await(): Response = suspendCancellableCoroutine { continuation ->
    continuation.invokeOnCancellation { cancel() }
    enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) = continuation.resumeWithException(e)
        override fun onResponse(call: Call, response: Response) = continuation.resume(response) { _, _, _ -> response.close() }
    })
}
