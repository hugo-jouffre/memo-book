package com.memobook.feature.profile

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import com.memobook.feature.AppDependencies
import com.memobook.feature.ProfileIntent
import com.memobook.feature.order.finishAbandonedOrder

/**
 * Le profil et ses feuilles. `opensSubscription` : « Mon abonnement » ouvert en arrivant (`HomeRoute.ManageSubscription`).
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit les deux
 * modèles — le profil, et ses statistiques, qui ont leur route, leur case de
 * cache et leur veille — et appelle la vue.
 *
 * **La suppression du compte sort par [onSignOut]**, comme sur iOS : le
 * compte n'existe plus, l'app ne peut que revenir à l'entrée.
 */
@Composable
fun ProfileEntry(dependencies: AppDependencies, opensSubscription: Boolean, onSignOut: () -> Unit, onIntent: (ProfileIntent) -> Unit, onBack: () -> Unit) {
    val model = viewModel { dependencies.profileModel() }
    val statistics = viewModel { dependencies.statisticsModel() }
    ProfileView(
        model = model,
        statistics = statistics,
        onSignOut = onSignOut,
        onBack = onBack,
        onIntent = onIntent,
        opening = if (opensSubscription) ProfileSheet.Subscription else null,
        managePaymentMethods = { dependencies.managePaymentMethods() },
        finishAbandonedOrder = { orderId -> dependencies.finishAbandonedOrder(orderId) },
        // Le bac à sable n'a pas de Play Store à ouvrir : son double répond.
        opensStorePage = !dependencies.isPreviewingSignedIn,
    )
}
