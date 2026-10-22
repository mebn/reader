package com.mebn.reader.sync

import android.content.Context
import android.os.Build
import android.provider.Settings
import com.mebn.reader.BuildConfig
import com.mebn.reader.ReaderApp
import com.mebn.reader.model.json
import kotlinx.serialization.Serializable

@Serializable
data class Session(val serverUrl: String, val token: String, val email: String) {
    val signedIn: Boolean get() = token.isNotEmpty()

    fun url(path: String): String = "${serverUrl.trimEnd('/')}/api$path"

    companion object {
        /** The sync server, fixed at build time per build type (SERVER_URL); never shown to people. */
        const val DEFAULT_SERVER = BuildConfig.SERVER_URL
    }
}

@Serializable
data class DeviceInfo(val name: String, val platform: String) {
    companion object {
        /** How this device is listed among the account's devices. */
        val current: DeviceInfo
            get() {
                val name = Settings.Global.getString(ReaderApp.context.contentResolver, Settings.Global.DEVICE_NAME)
                    ?.takeIf { it.isNotBlank() }
                    ?: "${Build.MANUFACTURER.replaceFirstChar { it.uppercase() }} ${Build.MODEL}"
                return DeviceInfo(name, "Android")
            }
    }
}

/** Keeps the session in the app's private storage. Signing out keeps the email for the next sign-in. */
object SessionStore {
    private val prefs get() = ReaderApp.context.getSharedPreferences("session", Context.MODE_PRIVATE)

    fun load(): Session? = prefs.getString("session", null)?.let {
        runCatching { json.decodeFromString(Session.serializer(), it) }.getOrNull()
    }

    fun save(session: Session) {
        prefs.edit().putString("session", json.encodeToString(Session.serializer(), session)).apply()
    }
}
