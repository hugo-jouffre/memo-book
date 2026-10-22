package com.memobook.recording

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.PackageManager

/**
 * Accès au micro. Jumeau de `RecordingPermission.swift`.
 *
 * iOS ne présente la demande qu'une fois : une fois refusée, le seul recours
 * est l'app Réglages, ce que l'interface doit dire explicitement plutôt que de
 * redemander en boucle. **Android la représente** — une seconde fois après un
 * premier refus, puis plus jamais : c'est alors, et alors seulement, qu'elle
 * est [State.Denied] ici, et que le seul recours est les Paramètres du
 * téléphone.
 *
 * La permission `RECORD_AUDIO` est déclarée dans le manifeste de ce module.
 */
object RecordingPermission {
    enum class State {
        Granted,
        Denied,
        Undetermined,
    }

    /** La permission, telle qu'Android la nomme. */
    const val PERMISSION: String = Manifest.permission.RECORD_AUDIO

    /**
     * Où en est l'accès. Android ne dit pas « refusé pour de bon » : on le
     * déduit d'une demande déjà posée que le système ne propose plus
     * d'expliquer (`shouldShowRequestPermissionRationale` à faux). Sans
     * activité sous la main, un refus se lit « pas encore demandé » — la
     * demande, elle, saura trancher.
     */
    fun current(context: Context): State {
        if (context.checkSelfPermission(PERMISSION) == PackageManager.PERMISSION_GRANTED) return State.Granted
        val activity = context.findActivity() ?: return State.Undetermined
        return if (wasAsked(context) && !activity.shouldShowRequestPermissionRationale(PERMISSION)) {
            State.Denied
        } else {
            State.Undetermined
        }
    }

    /**
     * Demande l'accès si nécessaire. Rend `true` si l'app peut enregistrer.
     *
     * @param launch présente la demande du système et rend sa réponse — un
     *   `ActivityResultLauncher` de l'écran (`rememberRecordingPermissionRequest`
     *   dans `:feature`). Ce module n'a pas d'activité : il ne peut que
     *   demander qu'on la pose.
     */
    suspend fun request(context: Context, launch: suspend (String) -> Boolean): Boolean =
        when (current(context)) {
            State.Granted -> true
            State.Denied -> false
            State.Undetermined -> {
                markAsked(context)
                launch(PERMISSION)
            }
        }

    // La demande a-t-elle déjà été posée ? Android ne le garde pas pour nous.
    private const val PREFERENCES = "memobook-recording"
    private const val ASKED = "microphoneAsked"

    private fun wasAsked(context: Context): Boolean =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getBoolean(ASKED, false)

    private fun markAsked(context: Context) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit().putBoolean(ASKED, true).apply()
    }

    private tailrec fun Context.findActivity(): Activity? = when (this) {
        is Activity -> this
        is ContextWrapper -> baseContext?.findActivity()
        else -> null
    }
}
