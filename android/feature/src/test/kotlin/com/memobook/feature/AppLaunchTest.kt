package com.memobook.feature

import com.memobook.networking.MemoBookApi
import kotlinx.coroutines.test.runTest
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * L'assemblage de l'app. Porté de `AppLaunchTests.swift` ; ses autres cas
 * (`MemoListModel`, `MemoDetailModel`) arriveront avec leurs écrans.
 */
class AppLaunchTest {
    /** Le double, qui compte ses enregistrements d'appareil. */
    private class CountingApi(private val inner: MemoBookApi = PreviewApi(seeded = false)) : MemoBookApi by inner {
        var registrations = 0

        override suspend fun ensureDeviceRegistered() {
            registrations += 1
            inner.ensureDeviceRegistered()
        }
    }

    /**
     * L'enregistrement de l'appareil est paresseux : il ne bloque plus le
     * démarrage, et un deuxième appel ne relance pas de requête.
     */
    @Test fun deviceRegistrationIsLazyAndIdempotent() = runTest {
        val api = CountingApi()
        val dependencies = PreviewSupport.dependencies(
            api = api,
            directory = Files.createTempDirectory("lancement").toFile(),
            scope = this,
        )
        assertEquals(0, api.registrations, "Construire les dépendances n'enregistre rien.")

        dependencies.ensureRegistered()
        dependencies.ensureRegistered()

        assertEquals(1, api.registrations)
    }
}
