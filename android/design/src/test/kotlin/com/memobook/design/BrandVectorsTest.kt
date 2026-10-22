package com.memobook.design

import androidx.compose.ui.graphics.vector.PathParser
import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Chaque tracé des VectorDrawables de `:design` se lit par le lecteur de
 * Compose, celui de `painterResource`.
 *
 * Un tracé que Compose refuse ne casse ni la compilation ni le lint : l'app
 * plante à l'affichage de l'image, et pas avant. Le convertisseur d'Android
 * Studio en a déjà laissé passer un (21/10/2026, vu dans l'émulateur).
 */
class BrandVectorsTest {
    private val resources = File("src/main").listFiles { file -> file.name.startsWith("res") }.orEmpty()

    @Test
    fun everyVectorPathParses() {
        val failures = mutableListOf<String>()
        val paths = Regex("""android:pathData="([^"]*)"""")
        resources.flatMap { it.walkTopDown().filter { file -> file.extension == "xml" }.toList() }.forEach { file ->
            paths.findAll(file.readText()).forEach { match ->
                try {
                    PathParser().parsePathString(match.groupValues[1])
                } catch (error: IllegalArgumentException) {
                    failures += "${file.name} : ${error.message}"
                }
            }
        }
        assertTrue(failures.isEmpty(), failures.joinToString("\n"))
    }
}
