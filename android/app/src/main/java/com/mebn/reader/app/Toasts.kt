package com.mebn.reader.app

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID

/** Short notices over the app, like the desktop's toasts. */
object Toasts {
    data class Toast(
        val title: String,
        val detail: String? = null,
        val progress: Boolean = false,
        val isError: Boolean = false,
        val action: String? = null,
        val id: String = UUID.randomUUID().toString(),
    )

    var current by mutableStateOf<Toast?>(null); private set
    private var onAction: (() -> Unit)? = null
    private var dismissJob: Job? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    fun show(
        title: String,
        detail: String? = null,
        progress: Boolean = false,
        error: Boolean = false,
        action: String? = null,
        duration: Long = 4_000,
        onAction: (() -> Unit)? = null,
    ): String {
        val toast = Toast(title, detail, progress, error, action)
        current = toast
        this.onAction = onAction
        dismissJob?.cancel()
        if (!progress) {
            dismissJob = scope.launch {
                delay(duration)
                dismiss(toast.id)
            }
        }
        return toast.id
    }

    fun dismiss(id: String? = null) {
        if (id == null || current?.id == id) current = null
    }

    fun runAction() {
        onAction?.invoke()
        dismiss()
    }
}
