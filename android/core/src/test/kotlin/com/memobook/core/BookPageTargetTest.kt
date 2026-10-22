package com.memobook.core

import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Le nombre de pages cible : les paliers, la règle des deux changements telle
 * que la route la sert, et le stade du voyage qui décide d'offrir la
 * réécriture (Hugo, 15/10/2026). Mêmes cas que `BookPageTargetTests.swift`.
 */
class BookPageTargetTest {
    // MARK: Les paliers

    @Test
    fun withoutDurationTheTiersAre40_60_80() {
        assertEquals(40, BookPageTarget.Compact.pageCount(forTripDays = null))
        assertEquals(60, BookPageTarget.Standard.pageCount(forTripDays = null))
        assertEquals(80, BookPageTarget.Detailed.pageCount(forTripDays = null))
        assertNull(BookPageTarget.Custom.pageCount(forTripDays = null))
    }

    @Test
    fun theTiersAreTwoThirdsAndFourThirdsOfTheStandard() {
        // Deux mois : 60 pages au palier par défaut.
        assertEquals(40, BookPageTarget.Compact.pageCount(forTripDays = 60))
        assertEquals(80, BookPageTarget.Detailed.pageCount(forTripDays = 60))
        // Trois mois : 90, donc 60 et 120.
        assertEquals(60, BookPageTarget.Compact.pageCount(forTripDays = 90))
        assertEquals(90, BookPageTarget.Standard.pageCount(forTripDays = 90))
        assertEquals(120, BookPageTarget.Detailed.pageCount(forTripDays = 90))
        // Le plancher de 30 vaut pour le palier par défaut ; les deux autres
        // en sont des fractions, à la dizaine.
        assertEquals(20, BookPageTarget.Compact.pageCount(forTripDays = 5))
        assertEquals(40, BookPageTarget.Detailed.pageCount(forTripDays = 5))
    }

    @Test
    fun matchingReadsTheTierBackFromItsCount() {
        assertEquals(BookPageTarget.Compact, BookPageTarget.matching(pageCount = 40, tripDays = null))
        assertEquals(BookPageTarget.Standard, BookPageTarget.matching(pageCount = 60, tripDays = null))
        assertEquals(BookPageTarget.Detailed, BookPageTarget.matching(pageCount = 80, tripDays = null))
        assertEquals(BookPageTarget.Custom, BookPageTarget.matching(pageCount = 90, tripDays = null))
    }

    // MARK: Ce que la route sert

    @Test
    fun aMissingPageTargetBlockCountsNothing() {
        val settings = MemoBookJson.decodeFromString(TripSettings.serializer(), settingsJSON(pageTarget = null))
        assertNull(settings.pageTarget)
        assertEquals(PageTargetAllowance.unrestricted, settings.pageTargetAllowance)
        assertFalse(settings.pageTargetAllowance.changesCount)
        assertFalse(settings.pageTargetAllowance.isExhausted)
    }

    @Test
    fun thePageTargetBlockIsRead() {
        val json = settingsJSON(
            pageTarget = """{"changesLeft":0,"changeLimit":2,"changesCount":true,"rewriteAvailable":true}""",
        )
        val allowance = MemoBookJson.decodeFromString(TripSettings.serializer(), json).pageTargetAllowance
        assertEquals(0, allowance.changesLeft)
        assertTrue(allowance.changesCount)
        assertTrue(allowance.rewriteAvailable)
        assertTrue(allowance.isExhausted)
    }

    @Test
    fun aPartialPageTargetBlockFallsBackFieldByField() {
        val json = settingsJSON(pageTarget = """{"changesLeft":1}""")
        val allowance = MemoBookJson.decodeFromString(TripSettings.serializer(), json).pageTargetAllowance
        assertEquals(PageTargetAllowance(changesLeft = 1), allowance)
    }

    @Test
    fun noChangeLeftBlocksOnlyOnceAChangeCounts() {
        assertFalse(PageTargetAllowance(changesLeft = 0, changesCount = false).isExhausted)
        assertTrue(PageTargetAllowance(changesLeft = 0, changesCount = true).isExhausted)
    }

    // MARK: Le stade du voyage

    @Test
    fun withoutEndDateTheStageMustBeAsked() {
        assertNull(PageTargetTripStage.from(startDate = day(1), endDate = null, today = day(5)))
    }

    @Test
    fun aFinishedTripIsAtTheEnd() {
        assertEquals(PageTargetTripStage.End, PageTargetTripStage.from(startDate = day(1), endDate = day(10), today = day(12)))
    }

    @Test
    fun twoThirdsOfTheDaysElapsedIsTheEnd() {
        // 30 jours, du 1er au 30 : le 21, vingt jours entiers sont passés.
        assertEquals(PageTargetTripStage.End, PageTargetTripStage.from(startDate = day(1), endDate = day(30), today = day(21)))
        assertEquals(
            PageTargetTripStage.BeginningOrMiddle,
            PageTargetTripStage.from(startDate = day(1), endDate = day(30), today = day(20)),
        )
        assertEquals(
            PageTargetTripStage.BeginningOrMiddle,
            PageTargetTripStage.from(startDate = day(1), endDate = day(30), today = day(1)),
        )
    }

    @Test
    fun aTripNotStartedYetIsAtTheBeginning() {
        assertEquals(
            PageTargetTripStage.BeginningOrMiddle,
            PageTargetTripStage.from(startDate = day(10), endDate = day(20), today = day(2)),
        )
    }

    // MARK: Les phrases de la feuille

    @Test
    fun theSummaryNamesBothStoriesAndTheDirection() {
        assertEquals(
            "On passe d’un récit compact à un récit détaillé. Les prochaines étapes seront donc plus étoffées.",
            BookCopy.Pages.doneSummary(from = 40, to = 80, tripDays = null),
        )
        assertEquals(
            "On passe d’un récit standard de 60 pages à un récit de 90 pages. Les prochaines étapes seront donc plus étoffées.",
            BookCopy.Pages.doneSummary(from = 60, to = 90, tripDays = null),
        )
        assertTrue(BookCopy.Pages.doneSummary(from = 80, to = 40, tripDays = null).endsWith("moins étoffées."))
    }

    @Test
    fun theWarningSaysWhatIsLeft() {
        assertTrue(BookCopy.Pages.changeWarning(changesLeft = 2).contains("deux fois"))
        assertTrue(BookCopy.Pages.changeWarning(changesLeft = 1).contains("un seul changement"))
    }

    // MARK: Outils

    /** Le `Calendar.current` du test iOS : le fuseau de la machine, à midi. */
    private fun day(day: Int): Instant =
        LocalDateTime.of(2026, 10, day, 12, 0).atZone(ZoneId.systemDefault()).toInstant()

    private fun settingsJSON(pageTarget: String?): String {
        val block = pageTarget?.let { ""","pageTarget":$it""" } ?: ""
        return """{"tripId":"t1","name":"Rome","wantsNotifications":true,"notifications":{},""" +
            """"companions":[],"isPublicGallery":false,"isPrintable":false$block}"""
    }

    @Test
    fun aCustomTargetNamesBothSidesWithTheirPageCount() {
        // Trois semaines : « Détaillé » vaut 40 pages. Partir de 60 pour y
        // aller, c'est condenser — le nom seul disait le contraire.
        assertEquals(
            "On passe d’un récit de 60 pages à un récit détaillé de 40 pages. Les prochaines étapes seront donc moins étoffées.",
            BookCopy.Pages.doneSummary(from = 60, to = 40, tripDays = 21),
        )
    }

    // MARK: Les paliers suivent le ratio, la cible hors d'atteinte (18/10/2026)

    @Test
    fun theTiersFollowThePhotoRatio() {
        assertEquals(40, BookPageTarget.Standard.pageCount(forTripDays = null, ratio = 0))
        assertEquals(60, BookPageTarget.Standard.pageCount(forTripDays = null, ratio = 50))
        assertEquals(80, BookPageTarget.Standard.pageCount(forTripDays = null, ratio = 100))
        assertEquals(70, BookPageTarget.Detailed.pageCount(forTripDays = 40, ratio = 75))
        assertEquals(BookPageTarget.Standard, BookPageTarget.matching(pageCount = 50, tripDays = 40, ratio = 75))
    }

    @Test
    fun anUnreachableTargetSaysWhatTheBookCanDo() {
        val allowance = PageTargetAllowance(
            reachableByRatio = mapOf(
                25 to PageRange(min = 24, max = 34),
                50 to PageRange(min = 24, max = 44),
                75 to PageRange(min = 24, max = 64),
            ),
        )
        assertNull(allowance.reach(of = 38, ratio = 25), "à 5 pages de la fourchette, la cible passe")
        val reach = allowance.reach(of = 60, ratio = 25)
        assertEquals(PageRange(min = 24, max = 34), reach?.range)
        assertEquals(30, reach?.closestTarget)
        assertEquals(75, reach?.ratioThatReaches)
        assertTrue(reach?.isTooLong == true)
        assertNull(PageTargetAllowance().reach(of = 180, ratio = 50), "sans fourchette servie, rien n'est jugé")
    }

    @Test
    fun theReachableRangeDecodesFromTheServer() {
        val json = """{"changesLeft":2,"changeLimit":2,"changesCount":true,"rewriteAvailable":false,"reachableByRatio":{"0":{"min":24,"max":24},"50":{"min":24,"max":44}}}"""
        val allowance = MemoBookJson.decodeFromString(PageTargetAllowance.serializer(), json)
        assertEquals(PageRange(min = 24, max = 44), allowance.reachableByRatio[50])
        assertEquals(2, allowance.reachableByRatio.size)
    }
}
