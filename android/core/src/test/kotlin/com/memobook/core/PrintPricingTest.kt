package com.memobook.core

import java.math.BigDecimal
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * La grille des prix telle que l'app la lit — voir [PrintPricing]. Le jumeau
 * de `PrintPricingTests.swift`, cas pour cas.
 *
 * Les mêmes bornes que côté serveur (`printPricing.test.ts`), parce que les
 * trois doivent répondre pareil : l'écran annonce ce que la commande
 * facturera.
 */
class PrintPricingTest {
    /**
     * `BigDecimal` compare aussi l'échelle : `55` et `55.0` ne sont pas
     * `equals`, alors qu'ils valent le même prix. On compare donc les
     * valeurs, comme `Decimal` le fait sur iOS.
     */
    private fun assertPrice(attendu: BigDecimal?, obtenu: BigDecimal?, message: String = "") {
        if (attendu == null || obtenu == null) {
            assertEquals(attendu, obtenu, message)
            return
        }
        assertTrue(attendu.compareTo(obtenu) == 0, "$message — attendu $attendu, obtenu $obtenu")
    }

    private fun euros(montant: String) = BigDecimal(montant)

    /** La grille du 21/10/2026, fermée à 300 pages. */
    private val grid = PrintPricing(
        tiers = listOf(
            PrintPricing.Tier("compact", 16, 45, euros("55")),
            PrintPricing.Tier("standard", 46, 65, euros("75")),
            PrintPricing.Tier("detailed", 66, 85, euros("80")),
            PrintPricing.Tier("detailed-plus", 86, 100, euros("85")),
            PrintPricing.Tier("large", 101, 120, euros("105")),
            PrintPricing.Tier("large-plus", 121, 200, euros("110")),
            PrintPricing.Tier("very-large", 201, 300, euros("129")),
        ),
        minPages = 16,
        maxPages = 300,
        tolerancePages = 5,
        freeZonesPrice = euros("3"),
    )

    // MARK: Les bornes

    @Test
    fun eachTierHoldsToItsLastPage() {
        val bornes = listOf(
            16 to "55", 45 to "55",
            46 to "75", 65 to "75",
            66 to "80", 85 to "80",
            86 to "85", 100 to "85",
            101 to "105", 120 to "105",
            121 to "110", 200 to "110",
            201 to "129", 300 to "129",
        )
        for ((pages, prix) in bornes) {
            assertPrice(euros(prix), grid.price(forPages = pages), "$pages pages")
        }
    }

    @Test
    fun underTheMinimumTheBookIsBilledAsSixteenPages() {
        assertPrice(euros("55"), grid.price(forPages = 1))
        assertPrice(euros("55"), grid.price(forPages = 15))
    }

    @Test
    fun beyondTheMaximumThereIsNoPriceToShow() {
        assertNull(grid.price(forPages = 301))
        assertNull(grid.price(forPages = 401))
        assertFalse(grid.allows(pages = 301))
        assertTrue(grid.allows(pages = 300))
        assertFalse(grid.allows(pages = 15))
    }

    @Test
    fun theOpenedLastTierPricesUpToFourHundredPages() {
        val opened = grid.copy(
            tiers = grid.tiers + PrintPricing.Tier("beyond", 301, 400, euros("145")),
            maxPages = 400,
        )
        assertPrice(euros("145"), opened.price(forPages = 301))
        assertPrice(euros("145"), opened.price(forPages = 400))
        assertNull(opened.price(forPages = 401))
    }

    // MARK: Ce que l'écran annonce

    /**
     * Les cas de l'onglet « Cibles » de la feuille, au ratio photo de 50 % :
     * le prix affiché est celui du palier de **cible + 5**, et il ne peut
     * donc qu'être au-dessus de ce qui sera facturé.
     */
    @Test
    fun theDisplayedPriceFollowsTheTargetsOfTheSheet() {
        val cas = listOf(
            Triple(30, "55", listOf("55", "55")),
            Triple(60, "55", listOf("75", "80")),
            Triple(90, "75", listOf("85", "110")),
            Triple(180, "110", listOf("110", "129")),
        )
        val paliers = listOf(BookPageTarget.Compact, BookPageTarget.Standard, BookPageTarget.Detailed)
        for ((jours, compact, reste) in cas) {
            val attendus = listOf(compact) + reste
            for ((target, attendu) in paliers.zip(attendus)) {
                val pages = target.pageCount(forTripDays = jours, ratio = 50)
                assertPrice(
                    euros(attendu),
                    pages?.let { grid.displayedPrice(forTarget = it) },
                    "$jours jours, ${target.rawValue}",
                )
            }
        }

        // Sans date de fin, les cibles sont celles du voyage sans durée.
        val sansDates = listOf("55", "75", "80")
        for ((target, attendu) in paliers.zip(sansDates)) {
            val pages = target.pageCount(forTripDays = null, ratio = 50)
            assertPrice(
                euros(attendu),
                pages?.let { grid.displayedPrice(forTarget = it) },
                "sans dates, ${target.rawValue}",
            )
        }
    }

    @Test
    fun theDisplayedPriceNeverFallsBelowWhatIsBilled() {
        // Le carnet composé tient dans sa cible à ± 5 pages : quoi qu'il
        // arrive, il se facture au plus au prix annoncé.
        for (target in 20..290 step 10) {
            val affiche = grid.displayedPrice(forTarget = target) ?: continue
            for (compose in (target - 5)..(target + 5)) {
                val facture = grid.price(forPages = compose) ?: continue
                assertTrue(
                    facture <= affiche,
                    "cible $target, composé $compose — facturé $facture, affiché $affiche",
                )
            }
        }
    }

    // MARK: Le décodage

    @Test
    fun aServerThatSaysNothingLeavesTheDefaults() {
        val vide = MemoBookJson.decodeFromString<PrintPricing>("{}")
        assertTrue(vide.tiers.isEmpty())
        assertEquals(16, vide.minPages)
        assertEquals(300, vide.maxPages)
        assertEquals(5, vide.tolerancePages)
        assertNull(vide.freeZonesPrice)
        // Sans palier, aucun prix : l'écran se tait plutôt que d'inventer.
        assertNull(vide.price(forPages = 60))
    }

    @Test
    fun itDecodesWhatTheRouteServes() {
        val servi = MemoBookJson.decodeFromString<PrintPricing>(
            """
            {
              "tiers": [{ "id": "compact", "from": 16, "to": 45, "price": 55 }],
              "minPages": 16,
              "maxPages": 45,
              "tolerancePages": 5,
              "freeZonesPrice": 3
            }
            """,
        )
        assertEquals(1, servi.tiers.size)
        assertPrice(euros("55"), servi.price(forPages = 40))
        assertPrice(euros("3"), servi.freeZonesPrice)
        assertEquals("compact", servi.tier(forPages = 40)?.id)
    }

    /** Un `null` servi à la place d'un champ retombe sur le défaut, comme iOS. */
    @Test
    fun aNullFieldFallsBackOnTheDefault() {
        val servi = MemoBookJson.decodeFromString<PrintPricing>(
            """{ "tiers": null, "minPages": null, "maxPages": null, "tolerancePages": null }""",
        )
        assertTrue(servi.tiers.isEmpty())
        assertEquals(16, servi.minPages)
        assertEquals(300, servi.maxPages)
        assertEquals(5, servi.tolerancePages)
    }
}
