package com.memobook.feature.tripsettings

import com.memobook.feature.AppSettings

/**
 * Où l'écran des personnalisations garde la valeur des pointillés d'avant le
 * verrou, voyage par voyage — celle que `BookRulesLock` rend au retour vers
 * l'assortiment par défaut. Jumeau de `TripSettings/BookRulesMemory.swift`.
 *
 * **Sur l'appareil** (Hugo, 02/10/2026) : elle survit à la fermeture de
 * l'écran et de l'app, sans colonne ni route de plus. Ce qu'elle ne couvre pas,
 * et c'est accepté : un autre téléphone, ou un co-voyageur, ne la connaît pas,
 * et le retour au défaut y rallume les pointillés.
 *
 * Deux fonctions et non un [AppSettings] : le modèle reçoit ses dépendances,
 * et un test ou un aperçu lui en donne une qui ne touche pas au disque.
 *
 * @property write `null` efface : le verrou s'est défait, il n'y a plus rien à rendre.
 */
class BookRulesMemory(
    val read: (tripId: String) -> Boolean?,
    val write: (tripId: String, value: Boolean?) -> Unit,
) {
    companion object {
        /**
         * Celle de l'app : une clé par voyage dans les réglages de l'app — les
         * `UserDefaults` d'iOS.
         *
         * Écrite **en texte** : [AppSettings] ne sait pas dire si une clé
         * booléenne existe, et « rien de gardé » n'est pas « éteints ».
         */
        fun device(settings: AppSettings): BookRulesMemory = BookRulesMemory(
            read = { tripId -> settings.getString(key(tripId))?.toBooleanStrictOrNull() },
            write = { tripId, value ->
                if (value != null) {
                    settings.putString(key(tripId), value.toString())
                } else {
                    settings.remove(key(tripId))
                }
            },
        )

        /** Une mémoire qui ne vit que le temps de l'objet : celle des aperçus et des tests. */
        fun inMemory(): BookRulesMemory {
            val values = mutableMapOf<String, Boolean>()
            return BookRulesMemory(
                read = { values[it] },
                write = { tripId, value -> if (value != null) values[tripId] = value else values.remove(tripId) },
            )
        }

        private fun key(tripId: String) = "bookRulesBeforeLock.$tripId"
    }
}
