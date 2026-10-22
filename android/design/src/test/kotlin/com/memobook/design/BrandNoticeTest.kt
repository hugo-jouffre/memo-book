package com.memobook.design

import androidx.compose.ui.text.font.FontWeight
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Le balisage `**…**` de [BrandNotice]. iOS le confie au Markdown
 * d'`AttributedString` ; ici il est lu à la main, et c'est sa règle qu'on fixe :
 * le gras où on l'a demandé, et rien d'effacé quand le balisage est faux.
 */
class BrandNoticeTest {
    @Test
    fun emphasisBecomesSemibold() {
        val text = BrandNotice.resolved("Tu sembles hors ligne. **Tu peux consulter tes récits**, plus tard.")
        assertEquals("Tu sembles hors ligne. Tu peux consulter tes récits, plus tard.", text.text)
        val span = text.spanStyles.single()
        assertEquals("Tu peux consulter tes récits", text.text.substring(span.start, span.end))
        assertEquals(FontWeight.SemiBold, span.item.fontWeight)
    }

    @Test
    fun severalEmphasesInOneMessage() {
        val text = BrandNotice.resolved("**Un** et **deux**")
        assertEquals("Un et deux", text.text)
        assertEquals(listOf("Un", "deux"), text.spanStyles.map { text.text.substring(it.start, it.end) })
    }

    @Test
    fun plainMessageIsUntouched() {
        val text = BrandNotice.resolved("Ton vocal est bien arrivé.")
        assertEquals("Ton vocal est bien arrivé.", text.text)
        assertTrue(text.spanStyles.isEmpty())
    }

    @Test
    fun invalidMarkupErasesNothing() {
        assertEquals("**sans fermeture", BrandNotice.resolved("**sans fermeture").text)
        assertEquals("deux ** espaces **", BrandNotice.resolved("deux ** espaces **").text)
        assertTrue(BrandNotice.resolved("deux ** espaces **").spanStyles.isEmpty())
    }
}
