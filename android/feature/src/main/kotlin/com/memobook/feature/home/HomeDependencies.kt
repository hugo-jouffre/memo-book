package com.memobook.feature.home

import com.memobook.core.HomeFeed
import com.memobook.core.TravellerProfile
import com.memobook.feature.AppDependencies
import com.memobook.feature.ContentCache

/**
 * L'accueil, servi par `GET /v1/home`. Exige une session ouverte. Jumeau de
 * `AppDependencies.homeModel()` (`AppDependencies.swift`).
 *
 * La source **passe par le cache** : ce qui arrive du serveur y est recopié,
 * et une panne de réseau relit ce qu'on avait au lieu de vider l'écran. C'est
 * ce qui rend vraie la phrase de la boîte d'information — « tu peux consulter
 * tes récits ».
 *
 * Les vocaux, eux, ne passent plus par une fonction de l'écran : ils vont dans
 * la `RecordingOutbox`, qui décide d'envoyer ou de garder. Un identifiant de
 * voyage est un identifiant de carnet — `trips[].id` et `memos.id` sont la même
 * colonne côté serveur —, donc la route des souvenirs le prend tel quel.
 *
 * Le lieu est laissé vide : l'app ne demande pas encore la position, et
 * inventer un libellé serait pire que de n'en donner aucun.
 *
 * **Les voyages créés hors ligne s'y ajoutent**, devant ceux du serveur : on
 * vient de les créer, et ils doivent être là — sur le cache comme sur la
 * réponse fraîche, tant que le serveur ne les a pas reçus. En supprimer un
 * l'oublie sur le téléphone, avec ce qu'on y avait raconté : personne d'autre
 * ne l'a jamais vu.
 *
 * **Qui tient l'abonnement** — sans jumeau sur iOS : le rappel de fin de
 * voyage ne s'ouvre sur Android que pour un abonnement de Google Play (voir
 * `HomeModel.tripEndReminderCanOpenHere`). L'accueil ne le sait pas, le profil
 * si (`Subscription.managedByAppStore`) : on le relit, le serveur d'abord, le
 * cache du profil si le réseau manque — la même enveloppe que l'écran du
 * profil. Rare : seulement le jour où le rappel doit s'ouvrir.
 */
fun AppDependencies.homeModel(): HomeModel {
    val read = cachedSource(ContentCache.Slot.Home) { api.homeFeed() }
    val readProfile = cachedSource(ContentCache.Slot.Profile) { api.profile() }

    return HomeModel(
        source = {
            // Sur le fil principal, comme la file : rien à attendre.
            outbox.mergingLocalTrips(read())
        },
        cached = {
            content.read<HomeFeed>(ContentCache.Slot.Home)?.let { outbox.mergingLocalTrips(it) }
        },
        outbox = outbox,
        remove = { id ->
            if (!outbox.discardLocalTrip(id)) api.deleteMemo(id)
        },
        join = { code -> api.joinTrip(code) },
        subscriptionIsManagedByAppStore = {
            val profile: TravellerProfile = readProfile()
            profile.subscription.managedByAppStore
        },
    )
}
