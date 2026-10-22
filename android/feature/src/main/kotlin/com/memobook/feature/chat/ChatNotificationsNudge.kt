package com.memobook.feature.chat

import android.content.Context
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.memobook.core.ChatCallToAction
import com.memobook.core.ChatCallToActionState
import com.memobook.feature.AppSettings
import com.memobook.feature.notifications.AndroidNotificationPermission
import com.memobook.feature.notifications.LocalPushNotifications
import com.memobook.feature.notifications.NotificationAuthorization
import com.memobook.feature.notifications.PushNotifications
import com.memobook.feature.notifications.rememberNotificationPermissionRequest
import kotlinx.coroutines.launch

/**
 * **La bulle « Suggestions » qui propose d'activer les notifications** (T246,
 * Hugo, 06/10/2026 : « oui on garde pour les utilisateurs qui ont passé
 * l'étape »). Jumeau de `Chat/ChatNotificationsNudge.swift`.
 *
 * L'autorisation se demande à l'étape « Notifications » de la création d'un
 * voyage, une seule fois : choisir un rythme pose la question du système, la
 * passer ne demande rien. Quelqu'un qui a traversé cette étape **sans
 * autoriser** — question jamais posée, ou refusée — voit dans la conversation
 * une bulle de MEMO (maquette « Suggestions - activer les notifs »,
 * `3207:25190`) :
 *
 * - question jamais posée : « Activer les notifications » la pose (la fenêtre
 *   `POST_NOTIFICATIONS` d'Android 13 et plus) ;
 * - refusée : on ne la repose pas, « Activer dans les Paramètres » ouvre la
 *   page des notifications de MemoBook dans les Paramètres du téléphone.
 *
 * Elle disparaît dès que l'autorisation est donnée — relue à l'ouverture et au
 * retour au premier plan, donc au retour des Paramètres — et « Ignorer » la
 * fait taire sur l'appareil, comme les autres appels à l'action de bulle.
 * C'est le dessin de [ChatCallToActionCard], tel quel : le bouton n'ouvre pas un
 * écran, il pose une question au système.
 *
 * **Posée par l'app**, pas par le serveur : seul le téléphone sait ce que le
 * système a répondu. Un co-voyageur qui a rejoint par un code n'a jamais vu
 * l'étape : il ne la voit pas.
 *
 * L'autorisation est lue **par l'écran** (`ChatView`), à l'ouverture et à
 * chaque retour au premier plan : la bulle vit dans une liste paresseuse, où
 * une ligne vide garderait sa marge.
 *
 * @param onAnswered relit l'autorisation, une fois la question posée.
 */
@Composable
fun ChatNotificationsNudge(
    model: ChatModel,
    authorization: NotificationAuthorization,
    onAnswered: suspend () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val pushNotifications = LocalPushNotifications.current
    val askSystem = rememberNotificationPermissionRequest()
    val answered by rememberUpdatedState(onAnswered)
    val scope = rememberCoroutineScope()
    val isDenied = authorization == NotificationAuthorization.Denied

    ChatCallToActionCard(
        text = NotificationsNudge.text(isDenied),
        callToAction = NotificationsNudge.callToAction(isDenied),
        state = ChatCallToActionState.Pending,
        // Dans le bac à sable, `PushNotifications` n'est pas branché (`null`) :
        // la question se pose alors directement au système, pour que la bulle
        // se vérifie quand même.
        onFollow = {
            if (isDenied) {
                PushNotifications.openSystemSettings(context)
            } else {
                scope.launch {
                    if (pushNotifications != null) pushNotifications.requestAuthorization(askSystem) else askSystem()
                    answered()
                }
            }
        },
        onDismiss = { model.dismissCallToAction(NotificationsNudge.bubbleId) },
        modifier = modifier.fillMaxWidth(),
    )
}

/** Ce que la bulle retient et ce qu'elle dit — logique pure, testée. */
object NotificationsNudge {
    /**
     * L'identifiant de la bulle, sous lequel « Ignorer » est retenu. Un seul
     * pour tous les voyages : c'est l'appareil qu'on autorise, pas un voyage.
     */
    const val bubbleId = "local.notifications-nudge"

    private const val STEP_PASSED_KEY = "memobook.notifications.stepPassed"

    /** L'étape « Notifications » de la création a été traversée — choisie ou passée — sur cet appareil. */
    fun markStepPassed(settings: AppSettings) {
        settings.putBoolean(STEP_PASSED_KEY, true)
    }

    fun hasPassedStep(settings: AppSettings): Boolean = settings.getBoolean(STEP_PASSED_KEY)

    /**
     * La bulle se montre à qui a traversé l'étape, sans que les notifications
     * puissent arriver, et ne l'a pas ignorée.
     */
    fun isShown(hasPassedStep: Boolean, authorization: NotificationAuthorization, state: ChatCallToActionState): Boolean =
        hasPassedStep && !authorization.allowsDelivery && state != ChatCallToActionState.Dismissed

    // MARK: - Les mots

    /**
     * Le texte de la bulle. La maquette (`3207:25190`) le mêle au rythme du
     * récit ; on n'en garde que la phrase des notifications, au tutoiement. Le
     * recours, sur Android, est dans les Paramètres du téléphone.
     */
    fun text(isDenied: Boolean): String =
        if (isDenied) {
            "Les notifications sont coupées pour MemoBook. Active-les dans les Paramètres pour que je t’aide à tenir le rythme que tu t’es fixé."
        } else {
            "Active les notifications pour que je t’aide à tenir le rythme que tu t’es fixé : je te ferai signe quand il sera temps de raconter la suite."
        }

    fun callToAction(isDenied: Boolean): ChatCallToAction = ChatCallToAction(
        id = "enable_notifications",
        kind = ChatCallToAction.Kind.EnableNotifications,
        label = if (isDenied) "Activer dans les Paramètres" else "Activer les notifications",
        // L'en-tête de la maquette.
        eyebrow = "Suggestions",
    )

    /** Ce que le téléphone permet en ce moment — à relire à l'ouverture et au retour au premier plan. */
    fun systemAuthorization(context: Context, settings: AppSettings): NotificationAuthorization =
        AndroidNotificationPermission(context.applicationContext, settings).current()
}
