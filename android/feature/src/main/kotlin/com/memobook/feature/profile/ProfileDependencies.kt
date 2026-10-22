package com.memobook.feature.profile

import com.memobook.core.TravelStatistics
import com.memobook.core.TravellerProfile
import com.memobook.feature.AppDependencies
import com.memobook.feature.ContentCache

// Les fabriques du profil — les `profileModel()` et `statisticsModel()` de
// `AppDependencies.swift`, en fonctions d'extension dans le paquet de l'écran.

/**
 * Le profil, servi par `GET /v1/profile` — et corrigé par `PATCH`.
 *
 * Les deux ensemble, et pas seulement la lecture : une ligne du profil
 * s'enregistre en perdant le focus, sans bouton pour valider. Sans la
 * seconde fonction, corriger son numéro de téléphone ne changeait rien
 * ailleurs que sur l'écran, jusqu'au prochain chargement qui le remettait
 * comme avant.
 */
fun AppDependencies.profileModel(): ProfileModel {
    val api = api
    return ProfileModel(
        source = cachedSource(ContentCache.Slot.Profile) { api.profile() },
        persist = { edit -> api.updateProfile(edit) },
        // La troisième, et la seule sans retour : elle supprime le compte
        // et tout ce qui est à lui. L'écran demande confirmation avant.
        remove = { api.deleteAccount() },
        uploadAvatar = { data, mimeType -> api.uploadAvatar(data, mimeType) },
        deleteAvatar = { api.removeAvatar() },
        changePassword = { current, new -> api.changePassword(current, new) },
        requestPasswordReset = { email -> api.requestPasswordReset(email) },
        // La résiliation, qui ne partait nulle part avant le 19/09/2026 —
        // voir `ProfileModel.cancelSubscription`.
        cancelSubscription = { reason -> api.cancelSubscription(reason) },
        // « Exporter mes données » : le lien part par e-mail, l'archive se
        // compose à son ouverture — voir `DataExportSheet`.
        exportData = { api.requestDataExport() },
        cached = cached<TravellerProfile>(ContentCache.Slot.Profile),
    )
}

/**
 * Les chiffres du profil, servis par `GET /v1/profile/statistics`.
 *
 * Un modèle à part du profil, parce qu'il **veille** : il relit sa route
 * tant que le serveur annonce des relevés en attente, et repart à chaque
 * vocal livré — d'où la file, passée en plus de la source. Le cache lui
 * donne son ouverture immédiate, comme aux cinq autres écrans.
 */
fun AppDependencies.statisticsModel(): StatisticsModel {
    val api = api
    return StatisticsModel(
        source = cachedSource(ContentCache.Slot.Statistics) { api.travelStatistics() },
        cached = cached<TravelStatistics>(ContentCache.Slot.Statistics),
        outbox = outbox,
    )
}
