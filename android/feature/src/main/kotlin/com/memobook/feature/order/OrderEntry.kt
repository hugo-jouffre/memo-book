package com.memobook.feature.order

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import com.memobook.feature.AppDependencies
import com.memobook.feature.OrderIntent

/**
 * Le tunnel de commande en sept étapes. `email` : où partira la confirmation, `null` sans adresse.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle et
 * appelle la vue. Sa signature est le contrat avec `RootView`, qui traduit les
 * intentions — `OrderIntent.Finish` vide la pile, `OrderIntent.OpenHelp` pousse
 * le support. Le modèle vit avec la destination : une rotation pendant la
 * feuille de Stripe garde la commande en cours.
 */
@Composable
fun OrderEntry(dependencies: AppDependencies, memoId: String, email: String?, onIntent: (OrderIntent) -> Unit, onBack: () -> Unit) {
    val model = viewModel(key = "order-$memoId") { orderModel(dependencies, memoId, email) }
    OrderView(model, onIntent = onIntent, onBack = onBack)
}

/**
 * Le modèle du tunnel de commande — l'`orderModel(memoId:)` de `RootView.swift`.
 *
 * Sous `previewSignedIn` il travaille **en mémoire** : aucun appel réseau
 * n'aboutirait — c'est la règle de cet interrupteur — et un écran d'erreur ne
 * montre pas la maquette qu'on cherche à vérifier. Le paiement y répond
 * « payé » sans rien ouvrir. Partout ailleurs, les routes du serveur.
 */
private fun orderModel(dependencies: AppDependencies, memoId: String, email: String?): OrderModel =
    if (dependencies.isPreviewingSignedIn) {
        OrderModel(memoId = memoId, email = email)
    } else {
        dependencies.orderModel(memoId = memoId, email = email)
    }
