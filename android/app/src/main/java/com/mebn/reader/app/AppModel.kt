package com.mebn.reader.app

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.mebn.reader.sync.Session
import com.mebn.reader.sync.SessionStore
import com.mebn.reader.sync.SyncEngine

/** Who is signed in. Signing out keeps the email for the sign-in form. */
object AppModel {
    var session by mutableStateOf<Session?>(null); private set

    val signedIn: Boolean get() = session?.signedIn ?: false

    fun start() {
        session = SessionStore.load()
        SyncEngine.onSignedOut = { signOut() }
        session?.takeIf { it.signedIn }?.let(SyncEngine::start)
        // Back in the foreground: catch up both ways.
        ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) = SyncEngine.wake()
        })
    }

    fun signIn(session: Session) {
        SessionStore.save(session)
        this.session = session
        SyncEngine.start(session)
    }

    fun signOut() {
        SyncEngine.stop()
        val previous = Session(session?.serverUrl ?: Session.DEFAULT_SERVER, "", session?.email ?: "")
        SessionStore.save(previous)
        session = previous
    }
}
