package com.mebn.reader.login

import android.content.Context
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import com.mebn.reader.sync.Api
import com.mebn.reader.sync.ApiError
import com.mebn.reader.sync.DeviceInfo
import com.mebn.reader.sync.Session
import kotlinx.coroutines.delay

/**
 * Google sign-in the way the desktop app does it: the server talks to Google, the app shows
 * Google's page in a browser tab and polls the server until it has the result.
 */
class GoogleSignIn {
    /** Set when the person comes back to the app, which is how they finish or give up. */
    @Volatile var returned = false

    /** The new session, or null when the person came back without signing in. */
    suspend fun run(context: Context): Session? {
        val server = Session.DEFAULT_SERVER
        val start = Api.googleStart(server, DeviceInfo.current)
        returned = false
        CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, Uri.parse(start.url))

        val deadline = System.currentTimeMillis() + TIMEOUT
        while (System.currentTimeMillis() < deadline) {
            delay(POLL_INTERVAL)
            // One more poll after coming back, in case the page closed right after finishing.
            val back = returned
            Api.googlePoll(server, start.state, start.secret)?.let { (token, user) -> return Session(server, token, user.email) }
            if (back) return null
        }
        throw ApiError("Google sign-in timed out. Try again.", 0)
    }

    private companion object {
        const val POLL_INTERVAL = 1500L
        const val TIMEOUT = 10 * 60 * 1000L
    }
}
