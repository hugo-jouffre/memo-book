package com.memobook.app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.memobook.feature.IncomingLinks
import com.memobook.feature.LaunchSwitches
import com.memobook.feature.RootView

/** La seule activité de l'app : tout le reste est en Compose, sous [RootView]. */
class MainActivity : ComponentActivity() {
    /** Les liens reçus — à froid par l'intention de lancement, app ouverte par [onNewIntent]. */
    private val incomingLinks = IncomingLinks()

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(FrenchLocale.wrap(newBase))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Barres système claires sur le crème, quel que soit le thème du
        // téléphone : la marque ne se retourne pas en sombre.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        // Les interrupteurs de lancement, comme les arguments du simulateur iOS
        // (`-previewSignedIn`…) : des extras de l'intention, sans effet en Release.
        //   make run ARGS="--ez previewSignedIn true"
        val switches = LaunchSwitches.fromIntent(intent, isDebug = BuildConfig.DEBUG)
        val dependencies = (application as MemoBookApplication).dependencies(switches)
        if (savedInstanceState == null) receiveLink(intent)
        setContent {
            RootView(
                dependencies = dependencies,
                showsDeveloperDetails = BuildConfig.DEBUG,
                incomingLinks = incomingLinks,
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        receiveLink(intent)
    }

    private fun receiveLink(intent: Intent?) {
        // Une notification touchée : son lien attend la session dans
        // `PushNotifications`, l'accusé d'ouverture part au serveur.
        if ((application as MemoBookApplication).push.didOpen(intent)) return
        intent?.dataString?.let(incomingLinks::receive)
    }
}
