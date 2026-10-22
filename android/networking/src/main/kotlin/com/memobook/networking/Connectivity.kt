package com.memobook.networking

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf

/**
 * L'état du réseau, tel que l'app peut le lire. Le jumeau de
 * `MemoBookNetworking/Connectivity.swift`.
 *
 * Une seule fonction qui rend un flux de « en ligne / hors ligne ». Un test ou
 * un aperçu en fabrique une qui dit ce qu'il veut — `Connectivity { flowOf(false) }` —,
 * sans double à écrire : c'est la même forme que les fonctions-sources des
 * modèles d'écran. Le vrai réseau de l'appareil est [AndroidConnectivity],
 * dans un fichier à part : ce module-ci reste testable sur la JVM.
 *
 * Elle vit dans `:networking` et non dans `:feature` parce qu'elle parle du
 * réseau, comme le client d'API.
 *
 * ⚠️ **« En ligne » ne veut pas dire « l'API répond ».** Le système dit qu'un
 * réseau est monté et annonce l'accès à Internet, rien de plus : un wifi de hall
 * d'hôtel avec un portail captif se déclare satisfait. C'est pourquoi la file
 * d'attente des vocaux ne se fie pas qu'à ce drapeau — un envoi qui échoue au
 * transport y retourne, même « en ligne ». Voir `RecordingOutbox`.
 */
fun interface Connectivity {
    /**
     * Rend l'état courant **tout de suite**, puis à chaque changement. Le
     * premier élément n'attend donc pas la première coupure : un écran qui
     * s'ouvre hors ligne le sait avant de dessiner quoi que ce soit.
     */
    fun updates(): Flow<Boolean>

    companion object {
        /**
         * Toujours en ligne, et rien à suivre : les aperçus et les tests qui ne
         * parlent pas du réseau.
         */
        val online: Connectivity = Connectivity { flowOf(true) }
    }
}
