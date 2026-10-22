package com.memobook.core

import java.math.BigDecimal
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ce que le tunnel de commande décide **hors d'une vue** : le rang des étapes,
 * la propagation des options d'un exemplaire à l'autre, et les phrases
 * accordées de la confirmation. Mêmes cas que `PrintOrderFlowTests.swift`.
 *
 * Ces règles vivent dans [PrintOrderDraft] et non dans l'écran précisément pour
 * être vérifiables ici, sans émulateur.
 */
class PrintOrderFlowTest {
    private fun draft(copies: Int): PrintOrderDraft = PrintOrderDraft(
        copies = copies,
        shipping = ShippingAddress(
            name = "Clara Perrin",
            line1 = "7 rue Simon Fryd",
            postalCode = "69007",
            city = "Lyon",
            country = "FR",
        ),
    ).alignCopyOptions(defaults = PrintedCopyOptions(position = 1))

    // MARK: - Les étapes

    @Test
    fun stepsAnnounceTheirRankOutOfSeven() {
        assertEquals("Étape 1/7 - Démarrage", OrderStep.Start.progressLabel)
        assertEquals("Étape 3/7 - Exemplaires", OrderStep.Copies.progressLabel)
        assertEquals("Étape 7/7 - Confirmation", OrderStep.Confirmation.progressLabel)
    }

    /** La confirmation ne recule pas : la commande est passée, revenir sur le
     *  paiement n'a plus de sens. La première non plus — derrière elle, il n'y a
     *  plus le tunnel. */
    @Test
    fun firstAndLastStepsDoNotGoBack() {
        assertFalse(OrderStep.Start.allowsGoingBack)
        assertFalse(OrderStep.Confirmation.allowsGoingBack)
        assertTrue(OrderStep.Payment.allowsGoingBack)
    }

    // MARK: - Les exemplaires

    @Test
    fun addingACopyCopiesTheFirstOne() {
        var draft = draft(copies = 1)
        draft = draft.setOption(PrintedCopyOption.Quiz, isOn = false, forCopyAt = 1)

        draft = draft.copy(copies = 3)
        draft = draft.alignCopyOptions(defaults = PrintedCopyOptions(position = 1))

        assertEquals(3, draft.copyOptions.size)
        assertEquals(listOf(1, 2, 3), draft.copyOptions.map { it.position })
        // Les nouveaux reprennent la version du premier, quiz coupés compris.
        assertTrue(draft.copyOptions.all { !it.quizEnabled })
    }

    @Test
    fun removingACopyDropsTheLastRanks() {
        var draft = draft(copies = 4)
        draft = draft.copy(copies = 2)
        draft = draft.alignCopyOptions(defaults = PrintedCopyOptions(position = 1))

        assertEquals(listOf(1, 2), draft.copyOptions.map { it.position })
    }

    /** Toucher au premier carnet emmène ceux qui portaient encore sa version. */
    @Test
    fun changingTheFirstCopyCarriesAlongTheOnesThatFollowedIt() {
        val draft = draft(copies = 3).setOption(PrintedCopyOption.Crossword, isOn = false, forCopyAt = 1)

        assertTrue(draft.copyOptions.all { !it.crosswordEnabled })
    }

    /** …mais pas ceux qu'on a détachés. Une version choisie ne se fait pas
     *  écraser par un réglage du premier carnet. */
    @Test
    fun changingTheFirstCopyLeavesADetachedCopyAlone() {
        var draft = draft(copies = 2)
        draft = draft.setFollowsFirstCopy(false, forCopyAt = 2)
        val detached = draft.copyOptions[1]

        draft = draft.setOption(PrintedCopyOption.Decorations, isOn = false, forCopyAt = 1)

        assertFalse(draft.copyOptions[0].decorationsEnabled)
        assertEquals(detached, draft.copyOptions[1])
    }

    /** Détacher sans rien changer laisserait deux carnets identiques et un écran
     *  qui prétend le contraire. */
    @Test
    fun detachingACopyMakesItActuallyDifferent() {
        var draft = draft(copies = 2)
        assertTrue(draft.followsFirstCopy(2))

        draft = draft.setFollowsFirstCopy(false, forCopyAt = 2)

        assertFalse(draft.followsFirstCopy(2))
    }

    @Test
    fun reattachingACopyRestoresTheFirstVersion() {
        var draft = draft(copies = 2)
        draft = draft.setOption(PrintedCopyOption.FreeZones, isOn = false, forCopyAt = 1)
        draft = draft.setFollowsFirstCopy(false, forCopyAt = 2)
        draft = draft.setFollowsFirstCopy(true, forCopyAt = 2)

        assertTrue(draft.followsFirstCopy(2))
        assertFalse(draft.copyOptions[1].freeZonesEnabled)
        // Le rang ne se perd pas dans la recopie.
        assertEquals(2, draft.copyOptions[1].position)
    }

    /** Le premier carnet est la référence : il n'a rien à suivre, et l'écran ne
     *  lui propose donc pas de se détacher de lui-même. */
    @Test
    fun theFirstCopyIsItsOwnReference() {
        var draft = draft(copies = 2)
        assertTrue(draft.followsFirstCopy(1))

        draft = draft.setFollowsFirstCopy(false, forCopyAt = 1)
        assertTrue(draft.followsFirstCopy(1))
    }

    // MARK: - Ce qui laisse passer

    @Test
    fun anAddressMissingItsCityDoesNotPass() {
        var draft = draft(copies = 1)
        assertTrue(draft.hasCompleteAddress)

        draft = draft.copy(shipping = draft.shipping.copy(city = "  "))
        assertFalse(draft.hasCompleteAddress)
    }

    /** La deuxième ligne est facultative : beaucoup d'adresses n'en ont pas, et
     *  en exiger une bloquerait tout le monde. */
    @Test
    fun theSecondAddressLineIsOptional() {
        var draft = draft(copies = 1)
        draft = draft.copy(shipping = draft.shipping.copy(line2 = null))
        assertTrue(draft.hasCompleteAddress)
    }

    /** **La commande ne porte plus de carte** (01/10/2026) : elle se choisit dans
     *  la feuille de Stripe. Ce qui part au serveur, c'est le brouillon — et la
     *  version du SDK, posée par l'app, qui fait revenir les cartes du compte. */
    @Test
    fun theRequestCarriesTheDraftAndNoCard() {
        var request = NewPrintOrderRequest(renderId = "render-1", draft = draft(copies = 2))
        assertEquals(2, request.copies)
        assertNull(request.stripeApiVersion)

        request = request.copy(stripeApiVersion = "2020-08-27")
        val json = MemoBookJson.encodeToString(NewPrintOrderRequest.serializer(), request)
        assertTrue(json.contains("\"stripeApiVersion\":\"2020-08-27\""))
        assertFalse(json.contains("paymentCardId"))
    }

    // MARK: - Ce qui se lit

    @Test
    fun delayReadsAsARangeUnlessBothBoundsMeet() {
        assertEquals("5 à 7 jours ouvrés", DayRange(min = 5, max = 7).label)
        assertEquals("3 jours ouvrés", DayRange(min = 3, max = 3).label)
        assertEquals("Dans 2 à 3 jours", DayRange(min = 2, max = 3).deliveryLabel)
    }

    @Test
    fun copyTitlesAreOrdinals() {
        assertEquals("1er carnet", PrintedCopyOptions(position = 1).title)
        assertEquals("2e carnet", PrintedCopyOptions(position = 2).title)
    }

    @Test
    fun confirmationAgreesInNumberOnBothSides() {
        assertEquals("1 exemplaire - 1 page", OrderCopy.Confirmation.summary(copies = 1, pages = 1))
        assertEquals("2 exemplaires - 50 pages", OrderCopy.Confirmation.summary(copies = 2, pages = 50))
    }

    /** Un compte entré par Apple peut n'avoir relayé aucune adresse. Promettre un
     *  email sans destinataire serait pire que de ne rien promettre. */
    @Test
    fun confirmationWithoutAnEmailDoesNotPromiseOne() {
        val detail = OrderCopy.Confirmation.detail(book = "Rome", email = null)
        assertFalse(detail.contains("sur ton email"))
        assertTrue(detail.contains("Rome"))

        val withEmail = OrderCopy.Confirmation.detail(book = "Rome", email = "a@b.com")
        assertTrue(withEmail.contains("a@b.com"))
    }

    /** La cagnotte est partie (T230) : un serveur qui enverrait encore ses
     *  déductions ne doit pas empêcher le récapitulatif de se lire, et le total
     *  reste celui que la carte paiera. */
    @Test
    fun aQuoteWithLeftoverDeductionsStillDecodes() {
        val quote = MemoBookJson.decodeFromString(
            OrderQuote.serializer(),
            """
            {"bookTitle":"Rome","pageCount":10,"copies":1,"shippingSpeed":"standard","unitPrice":30,
             "book":{"lines":[],"subtotal":30},"specifications":[],"fulfilment":{"lines":[],"subtotal":30},
             "deductions":[{"id":"wallet","label":"Cagnotte","amount":30}],
             "total":30,"estimatedMinDays":5,"estimatedMaxDays":7}
            """,
        )
        assertEquals(0, quote.total.compareTo(BigDecimal(30)))
    }
}
