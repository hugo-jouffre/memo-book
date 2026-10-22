package com.memobook.recording

import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals

class VoiceNoteFormatTest {
    @Test
    fun theFileIsNamedLikeTheIPhoneOne() {
        val id = UUID.fromString("6f1c2e7a-3b2d-4c55-9a7e-0d4b8f2a1c90")
        assertEquals("memo-6F1C2E7A-3B2D-4C55-9A7E-0D4B8F2A1C90.m4a", VoiceNoteFormat.fileName(id))
    }
}
