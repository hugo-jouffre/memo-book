package com.memobook.app

import android.app.Application
import android.os.Build
import com.memobook.feature.AppDependencies
import com.memobook.networking.ApiConfiguration

/**
 * Le point d'entrée du processus, comme `MemoBookApp.swift` : il lit la
 * configuration de build et assemble [AppDependencies], une fois.
 */
class MemoBookApplication : Application() {
    lateinit var dependencies: AppDependencies
        private set

    override fun onCreate() {
        super.onCreate()
        dependencies = AppDependencies(apiConfiguration = fromBuildConfiguration())
    }

    /**
     * L'adresse de ce build pour cet appareil. Repli local dans l'émulateur
     * seulement, arrêt net partout ailleurs : un build livré ne doit pas parler
     * dans le vide en silence (`APIConfiguration.fromBuildConfiguration`, iOS).
     */
    private fun fromBuildConfiguration(): ApiConfiguration =
        ApiConfiguration.effective(
            configured = ApiConfiguration.parse(BuildConfig.API_BASE_URL),
            productionFallback = ApiConfiguration.parse(BuildConfig.PRODUCTION_API_BASE_URL),
            runsInEmulator = runsInEmulator(),
        ) ?: error("Aucune adresse d'API lisible dans ce build : voir android/gradle.properties.")

    /** L'émulateur d'Android Studio — le « simulateur » de ce côté-ci. */
    private fun runsInEmulator(): Boolean =
        Build.HARDWARE in setOf("ranchu", "goldfish") ||
            Build.PRODUCT.startsWith("sdk") ||
            Build.FINGERPRINT.startsWith("generic")
}
