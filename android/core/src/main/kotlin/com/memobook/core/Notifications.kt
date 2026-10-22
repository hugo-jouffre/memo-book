package com.memobook.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// Les notifications, côté app : ce que le téléphone dit de lui au serveur. Le
// jumeau de la seconde moitié de `MemoBookCore/Notifications.swift` — où mène
// une notification qu'on touche (`NotificationLink`, `InviteLink`) est dans
// `NotificationLink.kt`. Les règles — quoi envoyer, à qui, quel jour — vivent
// au serveur : `docs/notifications.md`.

/**
 * Le serveur APNs qui connaît un jeton.
 *
 * **Un build Xcode reçoit un jeton du sandbox**, TestFlight et l'App Store un
 * jeton de production. Le serveur doit envoyer chacun au bon endroit, sinon
 * Apple répond `BadDeviceToken` — et seule l'app sait de quel build elle vient.
 */
@Serializable
enum class PushEnvironment(val rawValue: String) {
    @SerialName("sandbox") Sandbox("sandbox"),
    @SerialName("production") Production("production"),
    ;

    companion object {
        /**
         * Celui de ce build : le sandbox en Debug, la production en Release.
         *
         * `:core` ne voit pas `BuildConfig` (le `#if DEBUG` d'iOS) : c'est la
         * cible `app` qui dit de quel build elle vient.
         */
        fun current(isDebug: Boolean): PushEnvironment = if (isDebug) Sandbox else Production
    }
}

/**
 * Qui sait joindre un jeton — `push_tokens.provider` au serveur. L'iPhone ne
 * l'envoie pas (APNs par défaut) ; Android envoie toujours `fcm` (lot B3,
 * 22/10/2026).
 */
enum class PushProvider(val rawValue: String) {
    Apns("apns"),
    Fcm("fcm"),
}

/** Ce que le téléphone dit de lui à `POST /v1/push-tokens`. */
data class PushTokenRegistration(
    /**
     * Le jeton : en hexadécimal pour APNs, **tel que Firebase le donne** pour
     * FCM — le serveur ne le met pas en minuscules, la casse en fait partie.
     */
    var token: String,
    /** Sans effet pour FCM, qui n'a qu'un serveur : retenu pour le support. */
    var environment: PushEnvironment,
    /** Le fuseau du téléphone — `Europe/Paris`. C'est lui qui fait partir une
     *  notification à 10 h chez le voyageur, où qu'il soit. */
    var timeZone: String,
    /** `0.1.0 (8)`, pour le support. */
    var appVersion: String?,
    var provider: PushProvider = PushProvider.Fcm,
) {
    /** Le corps de la requête. */
    val body: Map<String, String>
        get() = buildMap {
            put("token", token)
            put("environment", environment.rawValue)
            put("provider", provider.rawValue)
            put("timeZone", timeZone)
            appVersion?.let { put("appVersion", it) }
        }

    companion object {
        /** Le jeton tel qu'APNs le donne — des octets — écrit comme APNs l'attend. */
        fun hex(deviceToken: ByteArray): String = deviceToken.joinToString("") { "%02x".format(it) }
    }
}
