package com.memobook.networking

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.stateIn

/**
 * Le vrai réseau de l'appareil — le `Connectivity.system` d'iOS, sur
 * `ConnectivityManager` au lieu de `NWPathMonitor`.
 *
 * Un seul rappel pour tout l'objet, ouvert tant que quelqu'un écoute
 * ([SharingStarted.WhileSubscribed]) et refermé avec le dernier : rien ne
 * survit à l'écran qui l'écoutait. La file d'attente en tient un pour toute la
 * durée de l'app. [isOnline] est un `StateFlow` : il rend l'état courant au
 * premier abonné, avant tout changement.
 *
 * « En ligne » = le réseau par défaut annonce `NET_CAPABILITY_INTERNET` — le
 * `.satisfied` d'iOS, qui ne vérifie pas non plus que l'API répond. Demande la
 * permission `ACCESS_NETWORK_STATE`, déclarée par le manifeste du module.
 */
class AndroidConnectivity(context: Context, scope: CoroutineScope) : Connectivity {
    private val manager = context.applicationContext.getSystemService(ConnectivityManager::class.java)

    val isOnline: StateFlow<Boolean> = callbackFlow {
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                trySend(currentlyOnline())
            }

            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                trySend(capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET))
            }

            override fun onLost(network: Network) {
                // Le réseau par défaut vient de tomber ; s'il y en a un autre,
                // `onAvailable` suit aussitôt.
                trySend(false)
            }
        }
        trySend(currentlyOnline())
        manager.registerDefaultNetworkCallback(callback)
        awaitClose { manager.unregisterNetworkCallback(callback) }
    }
        .distinctUntilChanged()
        .stateIn(scope, SharingStarted.WhileSubscribed(), currentlyOnline())

    override fun updates() = isOnline

    private fun currentlyOnline(): Boolean {
        val capabilities = manager.getNetworkCapabilities(manager.activeNetwork) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }
}
