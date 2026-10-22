package com.memobook.networking

import android.util.Log

/**
 * La trace réseau dans le journal d'Android — le journal unifié d'iOS. Hors
 * d'Android Studio :
 *
 * ```bash
 * adb logcat -s MemoBook.réseau
 * ```
 *
 * `Log.d` n'est pas filtré en Debug, seul build qui trace : rien à régler.
 */
class AndroidLogSink(private val tag: String = "MemoBook.réseau") : NetworkLog.Sink {
    override fun debug(line: String) {
        Log.d(tag, line)
    }

    override fun notice(line: String) {
        Log.i(tag, line)
    }

    override fun error(line: String) {
        Log.e(tag, line)
    }
}
