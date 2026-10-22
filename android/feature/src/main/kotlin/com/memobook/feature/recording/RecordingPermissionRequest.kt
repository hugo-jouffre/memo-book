package com.memobook.feature.recording

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.memobook.recording.RecordingPermission
import kotlinx.coroutines.CompletableDeferred

/**
 * La demande d'accès au micro, posée par l'écran — sans jumeau Swift : sur
 * iOS, `RecordingPermission.request()` présente la question elle-même ; sur
 * Android, seule une activité le peut, par un `ActivityResultLauncher`.
 *
 * Rend une fonction suspendue qui pose la question si elle doit l'être, et dit
 * si l'app peut enregistrer — le `await RecordingPermission.request()` d'iOS :
 *
 * ```kotlin
 * val requestMicrophone = rememberRecordingPermissionRequest()
 * scope.launch { if (!requestMicrophone()) showsMicrophoneDenied = true }
 * ```
 *
 * L'accueil s'en sert avant d'ouvrir la feuille (« la permission d'abord, la
 * feuille ensuite », Hugo, 17/09/2026) ; [RecordingSheet] aussi, au cas où
 * elle s'ouvrirait sans. [RecordingPermission.current] dit, sans rien
 * demander, si l'accès est accordé, refusé pour de bon, ou pas encore demandé.
 */
@Composable
fun rememberRecordingPermissionRequest(): suspend () -> Boolean {
    val context = LocalContext.current
    val pending = remember { PendingAnswer() }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        pending.answer?.complete(granted)
        pending.answer = null
    }
    return remember(context, launcher) {
        {
            RecordingPermission.request(context) { permission ->
                val answer = CompletableDeferred<Boolean>()
                pending.answer = answer
                launcher.launch(permission)
                answer.await()
            }
        }
    }
}

/** La réponse que la demande en cours attend. */
private class PendingAnswer {
    var answer: CompletableDeferred<Boolean>? = null
}
