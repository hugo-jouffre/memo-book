package com.memobook.design

import android.content.Context
import android.util.TypedValue
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.vectorResource
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Chaque image du catalogue se charge comme `painterResource` la charge, depuis
 * les ressources compilées : un VectorDrawable que Compose refuse ferait planter
 * l'écran qui l'affiche, et rien avant (21/10/2026, vu dans l'émulateur).
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [36])
class BrandImagesLoadTest {
    @Test
    fun everyCatalogueImageLoads() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val failures = mutableListOf<String>()
        BrandImages.names.forEach { name ->
            val id = BrandImages[name]!!
            val value = TypedValue().also { context.resources.getValue(id, it, true) }
            if (value.string?.endsWith(".xml") != true) return@forEach
            try {
                ImageVector.vectorResource(null, context.resources, id)
            } catch (error: Exception) {
                failures += "$name (${value.string}) : ${error.message}"
            }
        }
        assertTrue(failures.isEmpty(), failures.joinToString("\n"))
    }
}
