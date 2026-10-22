package com.mebn.reader

import android.app.Application
import android.content.Context
import com.mebn.reader.app.AppModel

class ReaderApp : Application() {
    override fun onCreate() {
        super.onCreate()
        context = this
        AppModel.start()
    }

    companion object {
        lateinit var context: Context
            private set
    }
}
