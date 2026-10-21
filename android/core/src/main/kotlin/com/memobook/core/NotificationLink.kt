package com.memobook.core

import java.net.URI
import java.net.URISyntaxException
import java.net.URLDecoder

// Les notifications, côté app : où mène une notification qu'on touche. Les
// règles — quoi envoyer, à qui, quel jour — vivent au serveur :
// `docs/notifications.md`. Le jumeau iOS est `MemoBookCore/Notifications.swift`.

/**
 * Où mène une notification qu'on touche.
 *
 * **Le contrat avec le serveur** : chaque notification porte un lien
 * `memobook://` (`NOTIFICATION_LINKS`, `backend/src/services/notificationPlanner.ts`),
 * et c'est ce type qui le lit. Les mêmes liens marchent depuis n'importe où —
 * un e-mail, une note, `adb shell am start -d` — puisque le schéma est celui de
 * l'app.
 *
 * Un lien qu'on ne sait pas lire donne `null` : l'app s'ouvre là où elle était,
 * au lieu d'aller vers un écran deviné.
 */
sealed interface NotificationLink {
    /** `memobook://paywall` — l'offre. Le serveur ne l'envoie plus, mais des
     *  notifications déjà livrées et des e-mails le portent encore. */
    data object Paywall : NotificationLink

    /** `memobook://subscription` — la gestion de l'abonnement, là où on le coupe. */
    data object Subscription : NotificationLink

    /** `memobook://trips/new` — les vacances, l'anniversaire : créer un voyage. */
    data object NewTrip : NotificationLink

    /** `memobook://trips/<id>/chat` — un carnet qui se tait : la conversation. */
    data class Chat(val tripId: String) : NotificationLink

    /** `memobook://trips/<id>/preview` — l'aperçu, qui porte « Commander ce carnet ».
     *  `…/wallet` y mène aussi : la cagnotte est partie (T230), ses liens restent. */
    data class BookPreview(val tripId: String) : NotificationLink

    /** L'invitation d'un co-voyageur : rejoindre le voyage par son code. Trois
     *  formes, lues par [InviteLink]. */
    data class Join(val code: String) : NotificationLink

    companion object {
        fun from(uri: URI): NotificationLink? {
            InviteLink.code(uri)?.let { return Join(it) }
            if (uri.scheme?.lowercase() != "memobook") return null

            // `memobook://trips/abc/chat` : « trips » est l'hôte, le reste le chemin.
            val segments = listOfNotNull(uri.host) + uri.pathSegments()

            return when {
                segments == listOf("paywall") -> Paywall
                segments == listOf("subscription") -> Subscription
                segments == listOf("trips", "new") -> NewTrip
                segments.size == 3 && segments[0] == "trips" -> when (segments[2]) {
                    "chat" -> Chat(segments[1])
                    "preview", "wallet" -> BookPreview(segments[1])
                    else -> null
                }
                else -> null
            }
        }

        /** Depuis la charge utile d'une notification — la clé `link`. */
        fun from(payloadLink: String?): NotificationLink? = payloadLink?.toUriOrNull()?.let(::from)
    }
}

/**
 * **Le lien d'invitation d'un co-voyageur.**
 *
 * `https://<l'API de production>/j/<code>` : un App Link. L'app installée
 * s'ouvre dessus et rejoint le voyage ; sinon, la page du serveur envoie vers
 * le store (`backend/src/routes/invitePage.ts`). Toujours l'adresse de
 * **production**, même depuis un build de développement : un lien vers
 * l'émulateur ne mènerait nulle part sur le téléphone de l'invité.
 */
object InviteLink {
    /** Le chemin que l'app revendique sur ce domaine (`INVITE_PATH`). */
    internal const val PATH = "j"

    /** Le lien à partager, ou `null` si l'app ne connaît pas l'adresse de production. */
    fun url(code: String, base: URI?): URI? {
        if (base == null || code.isEmpty()) return null
        return URI(base.toString().trimEnd('/') + "/$PATH/$code")
    }

    /** Le code d'un lien d'invitation, quelle que soit sa forme ; `null` pour tout autre lien. */
    fun code(uri: URI): String? {
        val segments = uri.pathSegments()
        val raw = when (uri.scheme?.lowercase()) {
            "https" -> if (segments.size == 2 && segments[0] == PATH) segments[1] else null
            "memobook" -> when {
                uri.host == "join" -> uri.queryParameter("code")
                uri.host == PATH && segments.size == 1 -> segments[0]
                else -> null
            }
            else -> null
        }
        // La forme de la base : majuscules, sans espace ni tiret (`normalizeAccessCode`).
        val code = raw.orEmpty().uppercase().filter { it.isLetterOrDigit() }
        return code.ifEmpty { null }
    }
}

/**
 * Le lien du bouton « Réinitialiser mon mot de passe » de l'e-mail
 * (`passwordResetUrl`, `backend/src/services/mailer.ts`) :
 * `memobook://password/reset?token=…`, ou la page `https://<l'API>/password/reset?token=…`.
 *
 * Sur iOS, ce lecteur vit dans `MemoBookFeature/Auth/PasswordResetLink.swift` ;
 * il est ici parce qu'il ne dépend de rien. Le schéma n'est pas vérifié, seulement
 * le chemin : un App Link sur le même chemin ouvrira la même feuille.
 */
object PasswordResetLink {
    /** Le secret porté par le lien, ou `null` si ce n'en est pas un. */
    fun token(uri: URI): String? {
        // Avec un schéma privé, « password » est lu comme l'hôte et le chemin
        // ne contient que « /reset » ; avec un domaine, tout est dans le chemin.
        val route = (listOfNotNull(uri.host) + uri.pathSegments()).joinToString("/")
        if (!route.endsWith("password/reset")) return null
        return uri.queryParameter("token")?.ifEmpty { null }
    }
}

internal fun String.toUriOrNull(): URI? = try {
    URI(trim())
} catch (_: URISyntaxException) {
    null
}

internal fun URI.pathSegments(): List<String> = path.orEmpty().split('/').filter { it.isNotEmpty() }

internal fun URI.queryParameter(name: String): String? = rawQuery.orEmpty()
    .split('&')
    .map { it.split('=', limit = 2) }
    .firstOrNull { URLDecoder.decode(it[0], Charsets.UTF_8) == name }
    ?.let { URLDecoder.decode(it.getOrElse(1) { "" }, Charsets.UTF_8) }
