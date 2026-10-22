package com.memobook.feature.covers

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import com.memobook.feature.AppDependencies
import com.memobook.feature.LocalSessionViewModelStoreOwner

/**
 * Les deux plats du carnet, servis par `GET /v1/trips/:id/covers` et corrigés
 * par son `PATCH` ; les photos importées partent par
 * `POST /v1/trips/:id/covers/photos` (T88, 29/09/2026). Le style, la photo
 * retenue, les deux textes et les chiffres du dos tiennent dans
 * `memos.coverFront` et `coverBack` : choisir une couverture survit à la
 * fermeture de l'écran. Jumeau de `coversModel(tripId:)` d'`AppDependencies.swift`.
 */
fun AppDependencies.coversModel(tripId: String): CoversModel = CoversModel(
    tripId = tripId,
    source = { id -> api.bookCovers(tripId = id) },
    persist = { id, edit -> api.updateBookCovers(tripId = id, edit = edit) },
    upload = { id, data -> api.uploadCoverPhoto(tripId = id, data = data) },
)

/**
 * Le modèle des couvertures, **partagé par les quatre écrans du parcours** —
 * le `covers(for:)` de `RootView.swift`.
 *
 * Il vit dans le magasin de la session et non dans celui de chaque écran, pour
 * la même raison que `SubscriptionSession` : plusieurs destinations lisent et
 * écrivent le même état. On passe du choix au style, puis à la photo, puis aux
 * textes sans jamais quitter les mêmes deux plats — et l'onglet « 1re / 4e »
 * doit suivre. Quatre modèles auraient rechargé à chaque pas et perdu l'onglet.
 *
 * Un modèle par voyage (`covers-$tripId`) : ouvrir les couvertures d'un autre
 * voyage n'hérite pas des plats du premier. Dans un aperçu, sans magasin de
 * session, l'écran prend celui de sa destination.
 */
@Composable
fun rememberSessionCoversModel(dependencies: AppDependencies, tripId: String): CoversModel {
    val owner = LocalSessionViewModelStoreOwner.current
        ?: checkNotNull(LocalViewModelStoreOwner.current) { "Les couvertures demandent un magasin de modèles." }
    return viewModel(viewModelStoreOwner = owner, key = "covers-$tripId") { dependencies.coversModel(tripId) }
}
