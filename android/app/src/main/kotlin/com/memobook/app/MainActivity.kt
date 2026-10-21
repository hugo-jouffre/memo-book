package com.memobook.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.memobook.feature.RootView

/** La seule activité de l'app : tout le reste est en Compose, sous [RootView]. */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Barres système claires sur le crème, quel que soit le thème du
        // téléphone : la marque ne se retourne pas en sombre.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        val dependencies = (application as MemoBookApplication).dependencies
        // Les interrupteurs de lancement, comme les arguments du simulateur iOS
        // (`-previewSignedIn`…) : des extras de l'intention, sans effet en Release.
        //   make run ARGS="--ez designCatalogue true"
        val opensDesignCatalogue = BuildConfig.DEBUG && intent.getBooleanExtra("designCatalogue", false)
        setContent {
            RootView(
                dependencies = dependencies,
                showsDeveloperDetails = BuildConfig.DEBUG,
                opensDesignCatalogue = opensDesignCatalogue,
            )
        }
    }
}
