package com.memobook.networking

import java.net.URI
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ce qui garantit qu'un téléphone ne parle jamais à `localhost` ni à l'adresse
 * de l'émulateur. Mêmes cas que `APIConfigurationTests.swift`, plus `10.0.2.2`.
 */
class ApiConfigurationTest {
    private val local = ApiConfiguration(URI("http://10.0.2.2:3000"))
    private val localhost = ApiConfiguration(URI("http://localhost:3000"))
    private val loopbackIp = ApiConfiguration(URI("http://127.0.0.1:3000"))
    private val lan = ApiConfiguration(URI("http://192.168.1.20:3000"))
    private val production = ApiConfiguration(URI("https://api-production-9f35a.up.railway.app"))

    @Test
    fun loopbackIsRecognised() {
        assertTrue(local.isLoopback)
        assertTrue(localhost.isLoopback)
        assertTrue(loopbackIp.isLoopback)
        assertTrue(ApiConfiguration(URI("http://[::1]:3000")).isLoopback)
        assertFalse(lan.isLoopback)
        assertFalse(production.isLoopback)
    }

    @Test
    fun emulatorKeepsTheMacWithProductionAsFallback() {
        val resolved = ApiConfiguration.effective(local, production, runsInEmulator = true)
        assertEquals(local.baseUrl, resolved?.baseUrl)
        // La production n'est pas remplacée, elle est **derrière** : le client
        // y bascule si rien n'écoute sur le Mac.
        assertEquals(production.baseUrl, resolved?.fallbackBaseUrl)
    }

    @Test
    fun emulatorWithoutProductionKeepsTheMacAlone() {
        val resolved = ApiConfiguration.effective(local, null, runsInEmulator = true)
        assertEquals(local.baseUrl, resolved?.baseUrl)
        assertNull(resolved?.fallbackBaseUrl)
    }

    @Test
    fun remoteAddressNeverGetsAFallback() {
        // La production, ou l'IP du Mac : une adresse distante qui ne répond pas
        // est une vraie panne, pas un back-end qu'on a oublié de lancer.
        val resolved = ApiConfiguration.effective(lan, production, runsInEmulator = true)
        assertEquals(lan, resolved)
        assertNull(resolved?.fallbackBaseUrl)
    }

    @Test
    fun phoneNeverKeepsALoopback() {
        assertEquals(production, ApiConfiguration.effective(local, production, runsInEmulator = false))
        assertEquals(production, ApiConfiguration.effective(localhost, production, runsInEmulator = false))
        assertEquals(production, ApiConfiguration.effective(loopbackIp, production, runsInEmulator = false))
    }

    @Test
    fun phoneKeepsAnExplicitRemoteAddress() {
        // L'IP du Mac posée dans `secrets.properties`, ou la production elle-même.
        assertEquals(lan, ApiConfiguration.effective(lan, production, runsInEmulator = false))
        assertEquals(production, ApiConfiguration.effective(production, production, runsInEmulator = false))
    }

    @Test
    fun missingConfigurationFallsBackToProduction() {
        assertEquals(production, ApiConfiguration.effective(null, production, runsInEmulator = false))
        assertNull(ApiConfiguration.effective(null, null, runsInEmulator = true))
    }

    @Test
    fun phoneWithoutFallbackKeepsWhatItHas() {
        // Un build construit de travers, sans adresse de production : on rend la
        // seule adresse connue plutôt que rien — c'est l'app qui décide alors de
        // s'arrêter, et le message dit pourquoi.
        assertEquals(local, ApiConfiguration.effective(local, null, runsInEmulator = false))
    }

    @Test
    fun onlyAReadableAddressIsParsed() {
        assertEquals(production, ApiConfiguration.parse(" https://api-production-9f35a.up.railway.app "))
        assertNull(ApiConfiguration.parse(null))
        assertNull(ApiConfiguration.parse(""))
        assertNull(ApiConfiguration.parse("api-production-9f35a.up.railway.app"))
        assertNull(ApiConfiguration.parse("https://une adresse"))
    }
}
