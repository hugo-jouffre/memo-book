package com.memobook.feature

import android.content.Context
import android.content.SharedPreferences
import android.content.Intent
import androidx.compose.runtime.staticCompositionLocalOf

/**
 * Les interrupteurs de lancement d'un build Debug — les arguments du simulateur
 * iOS (`-previewSignedIn`…), devenus des **extras de l'intention** sous le même
 * nom, sans le tiret. Jumeau des arguments d'`OnboardingStorage.swift`.
 *
 * ```bash
 * make run ARGS="--ez previewSignedIn true"
 * make run ARGS="--ez previewSignedIn true --ez openOrder true"
 * ```
 *
 * Lus par `MainActivity` **en Debug seulement** ([fromIntent] avec
 * `isDebug = false` rend [None]) : ces interrupteurs ne doivent pas exister dans
 * l'app livrée, où effacer la session d'un utilisateur serait une perte de
 * données.
 *
 * @property previewSignedIn saute l'entrée et ouvre l'accueil **avec le jeu
 *   d'essai** (`PreviewApi`) : aucun jeton n'est écrit, aucun accès n'est ouvert.
 * @property openOrder ouvre le tunnel de commande sur le carnet du jeu d'essai.
 * @property composeBook ouvre l'aperçu du carnet en pleine composition.
 * @property lastQuestions ouvre les « Dernières questions » à l'entrée.
 * @property resetOnboarding remet l'app à son tout premier démarrage : le mot
 *   des fondateurs **et** la session.
 * @property designCatalogue l'écran-catalogue du design system.
 */
data class LaunchSwitches(
    val previewSignedIn: Boolean = false,
    val openOrder: Boolean = false,
    val composeBook: Boolean = false,
    val lastQuestions: Boolean = false,
    val resetOnboarding: Boolean = false,
    val designCatalogue: Boolean = false,
) {
    companion object {
        const val PREVIEW_SIGNED_IN = "previewSignedIn"
        const val OPEN_ORDER = "openOrder"
        const val COMPOSE_BOOK = "composeBook"
        const val LAST_QUESTIONS = "lastQuestions"
        const val RESET_ONBOARDING = "resetOnboarding"
        const val DESIGN_CATALOGUE = "designCatalogue"

        val None = LaunchSwitches()

        fun fromIntent(intent: Intent?, isDebug: Boolean): LaunchSwitches {
            if (!isDebug || intent == null) return None
            return LaunchSwitches(
                previewSignedIn = intent.getBooleanExtra(PREVIEW_SIGNED_IN, false),
                openOrder = intent.getBooleanExtra(OPEN_ORDER, false),
                composeBook = intent.getBooleanExtra(COMPOSE_BOOK, false),
                lastQuestions = intent.getBooleanExtra(LAST_QUESTIONS, false),
                resetOnboarding = intent.getBooleanExtra(RESET_ONBOARDING, false),
                designCatalogue = intent.getBooleanExtra(DESIGN_CATALOGUE, false),
            )
        }
    }
}

/**
 * Les petits réglages de l'app — l'`UserDefaults` d'iOS et ses `@AppStorage`.
 * Une interface, pour que les modèles se testent sur la JVM avec
 * [InMemoryAppSettings] ; l'app passe [SharedPreferencesAppSettings].
 *
 * Des réglages, pas des données : ce qui doit survivre et n'existe nulle part
 * ailleurs (un vocal en attente) vit dans des fichiers, jamais ici.
 */
interface AppSettings {
    fun getString(key: String): String?
    fun putString(key: String, value: String?)
    fun getBoolean(key: String, default: Boolean = false): Boolean
    fun putBoolean(key: String, value: Boolean)
    fun remove(key: String)
}

class SharedPreferencesAppSettings(context: Context, name: String = "com.memobook.app.settings") : AppSettings {
    private val preferences: SharedPreferences = context.applicationContext.getSharedPreferences(name, Context.MODE_PRIVATE)

    override fun getString(key: String): String? = preferences.getString(key, null)

    override fun putString(key: String, value: String?) {
        preferences.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
    }

    override fun getBoolean(key: String, default: Boolean): Boolean = preferences.getBoolean(key, default)

    override fun putBoolean(key: String, value: Boolean) {
        preferences.edit().putBoolean(key, value).apply()
    }

    override fun remove(key: String) {
        preferences.edit().remove(key).apply()
    }
}

class InMemoryAppSettings : AppSettings {
    private val values = mutableMapOf<String, Any>()

    @Synchronized override fun getString(key: String): String? = values[key] as? String

    @Synchronized override fun putString(key: String, value: String?) {
        if (value == null) values.remove(key) else values[key] = value
    }

    @Synchronized override fun getBoolean(key: String, default: Boolean): Boolean = values[key] as? Boolean ?: default

    @Synchronized override fun putBoolean(key: String, value: Boolean) {
        values[key] = value
    }

    @Synchronized override fun remove(key: String) {
        values.remove(key)
    }
}

/** Les réglages de l'app, pour une vue qui en lit un comme `@AppStorage`. */
val LocalAppSettings = staticCompositionLocalOf<AppSettings> { InMemoryAppSettings() }

/**
 * Où l'app note l'étape franchie par l'utilisateur. Jumeau d'`OnboardingStorage.swift`.
 *
 * ⚠️ **L'écran d'accueil n'est plus gardé par un réglage** : c'est l'écran de
 * quiconque n'a pas de session ouverte, et il revient à chaque déconnexion.
 */
object OnboardingStorage {
    /**
     * Le mot des fondateurs a été lu au moins une fois. Il s'ouvre **tout
     * seul** au premier aperçu d'un carnet ; une fois lu, il ne revient plus.
     */
    const val HAS_SEEN_FOUNDERS_NOTE = "hasSeenFoundersNote"

    /**
     * À appeler au démarrage, avant toute lecture des réglages, avec les
     * interrupteurs du lancement : `resetOnboarding` oublie le mot des
     * fondateurs **et** la session. Le jeton d'appareil, lui, reste.
     */
    fun resetIfRequested(switches: LaunchSwitches, settings: AppSettings, clearSession: () -> Unit) {
        if (!switches.resetOnboarding) return
        settings.remove(HAS_SEEN_FOUNDERS_NOTE)
        clearSession()
    }
}
