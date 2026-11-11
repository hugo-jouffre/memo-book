package com.memobook.feature

import kotlin.test.Test
import kotlin.test.assertSame
import kotlin.test.assertTrue

/**
 * **Une photo choisie part en JPEG** — le jumeau de `PhotoEncodingTests.swift`
 * (Hugo, 11/11/2026). Un téléphone réglé sur « HEIF » garde ses photos en
 * HEIC, que le Chromium qui compose le carnet ne décode pas : elles manquaient
 * au livre alors qu'elles s'affichaient dans l'app.
 *
 * Le décodage lui-même appartient à Android (`BitmapFactory`) et se vérifie
 * sur l'émulateur : ce qui se teste ici sur la JVM, c'est la règle qui le
 * précède — **un JPEG ne se réencode pas** — et le repli, qui ne doit jamais
 * perdre la photo.
 */
class PhotoFlowTest {
    private val jpeg = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte(), 0, 1, 2, 3)

    @Test
    fun `rend un jpeg inchange`() {
        assertSame(jpeg, PhotoFlow.galleryJpeg(jpeg))
    }

    @Test
    fun `rend les octets d'origine quand le decodage n'aboutit pas`() {
        val unreadable = "ni une image ni rien du tout".toByteArray()

        assertTrue(PhotoFlow.galleryJpeg(unreadable).contentEquals(unreadable))
    }
}
