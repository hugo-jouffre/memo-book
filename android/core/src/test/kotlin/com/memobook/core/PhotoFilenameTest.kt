package com.memobook.core

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * **Une photo passée par une messagerie n'a plus de mémoire** (T315). Porté de
 * `PhotoWithoutMemoryTests.swift`, cas pour cas — la moitié qui tient ici,
 * c'est-à-dire la règle ; le parcours de choix de photo d'Android ne porte pas
 * encore de date ni de lieu par photo.
 */
class PhotoFilenameTest {
    @Test fun whatsAppNamesAreRecognised() {
        assertTrue(PhotoFilename.isForwarded("IMG-20260811-WA0012.jpg"))
        assertTrue(PhotoFilename.isForwarded("img-20260811-wa0012.jpeg"), "La casse ne décide de rien.")
        assertTrue(
            PhotoFilename.isForwarded("IMG_20260811_WA0003.jpg"),
            "Certaines versions Android séparent au tiret bas.",
        )
        assertTrue(PhotoFilename.isForwarded("WhatsApp Image 2026-08-11 at 12.34.56.jpeg"))
    }

    /**
     * **Le garde-fou qui compte.** Une question de trop sur une photo saine
     * coûte plus cher qu'une photo mal rangée de plus : ces noms-là portent
     * très bien leur date, et on ne leur demande rien.
     */
    @Test fun aPhotoFromTheCameraIsNotAsked() {
        assertFalse(PhotoFilename.isForwarded("IMG_4821.HEIC"), "L'appareil photo d'un iPhone.")
        assertFalse(
            PhotoFilename.isForwarded("IMG_20260811_123456.jpg"),
            "Un appareil photo Android — même forme, et c'est pour ça que Telegram n'est pas détecté.",
        )
        assertFalse(PhotoFilename.isForwarded("PXL_20260811_123456789.jpg"), "Un Pixel.")
        assertFalse(
            PhotoFilename.isForwarded("IMG-20260811-0012.jpg"),
            "Sans le code de l'app, rien ne dit d'où elle vient.",
        )
        assertFalse(PhotoFilename.isForwarded("capture décran.png"))
        assertFalse(PhotoFilename.isForwarded(""))
    }
}
