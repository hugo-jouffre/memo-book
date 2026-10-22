package com.memobook.networking

import java.net.URI
import java.net.URISyntaxException

/**
 * Où parle l'app. Le jumeau de `MemoBookNetworking/APIConfiguration.swift`, aux
 * mêmes règles près — seule l'adresse de l'émulateur change.
 *
 * @property timeoutSeconds Au-delà, l'upload d'un vocal long sur un réseau lent
 *   échouerait pour rien.
 * @property fallbackBaseUrl L'adresse de **secours**, si [baseUrl] ne répond
 *   pas — porte close, hôte introuvable. Le client y bascule au premier appel
 *   refusé, pour la durée de la session. Posée par [effective] dans
 *   l'émulateur, et là seulement : le Mac d'abord, la production si rien n'y
 *   écoute. `null` partout ailleurs.
 */
data class ApiConfiguration(
    val baseUrl: URI,
    val timeoutSeconds: Long = 60,
    val fallbackBaseUrl: URI? = null,
) {
    /**
     * L'adresse désigne **l'appareil lui-même**, ou le Mac vu de l'émulateur.
     *
     * Sur Android, l'émulateur joint le Mac à `10.0.2.2` : c'est l'équivalent
     * du `localhost` du simulateur iOS, juste dans l'émulateur et absurde sur un
     * téléphone, où cette adresse ne mène nulle part. Elle compte donc comme une
     * boucle locale.
     */
    val isLoopback: Boolean
        get() {
            val host = baseUrl.host?.lowercase()?.removeSurrounding("[", "]") ?: return false
            return host in LOOPBACK_HOSTS || host.endsWith(".localhost")
        }

    companion object {
        /** Back-end lancé en local (`npm run dev`), vu depuis l'émulateur. */
        val localDevelopment = ApiConfiguration(URI("http://10.0.2.2:3000"))

        private val LOOPBACK_HOSTS = setOf("localhost", "127.0.0.1", "::1", "0.0.0.0", "10.0.2.2")

        /**
         * L'adresse posée par la configuration de build, si elle est lisible.
         * Rien n'est deviné ici : une valeur absente ou mal formée rend `null`.
         */
        fun parse(raw: String?): ApiConfiguration? {
            val trimmed = raw?.trim().orEmpty()
            if (trimmed.isEmpty()) return null
            val uri = try {
                URI(trimmed)
            } catch (_: URISyntaxException) {
                return null
            }
            return if (uri.scheme != null && uri.host != null) ApiConfiguration(uri) else null
        }

        /**
         * L'adresse à retenir **pour cet appareil**.
         *
         * La configurée, sauf si elle est une boucle locale hors de l'émulateur :
         * un téléphone ne parle jamais à `localhost`, c'est lui-même. On retombe
         * alors sur la production, quand le build l'embarque — le filet derrière
         * `app/build.gradle.kts`, qui ne donne déjà la production qu'aux builds
         * Release. Sur iOS, la panne est revenue deux fois avant ce filet (Hugo,
         * 15/09/2026).
         *
         * **Dans l'émulateur**, une boucle locale reste la première adresse — le
         * back-end du Mac, quand il tourne — et la production devient son
         * **secours** ([fallbackBaseUrl]) : rien n'écoute, le client bascule au
         * premier appel. L'émulateur marche donc toujours, back-end lancé ou non.
         *
         * Une fonction pure, testée sans appareil : ce qu'elle décide ne dépend
         * que de ses trois arguments.
         */
        fun effective(
            configured: ApiConfiguration?,
            productionFallback: ApiConfiguration?,
            runsInEmulator: Boolean,
        ): ApiConfiguration? {
            if (configured == null) return productionFallback
            if (!configured.isLoopback) return configured
            if (!runsInEmulator) return productionFallback ?: configured
            return configured.copy(fallbackBaseUrl = configured.fallbackBaseUrl ?: productionFallback?.baseUrl)
        }
    }
}
