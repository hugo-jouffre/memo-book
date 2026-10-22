package com.memobook.feature.order

import com.memobook.core.DayRange
import com.memobook.core.Destination
import com.memobook.core.NewPrintOrderRequest
import com.memobook.core.OrderContext
import com.memobook.core.OrderCopy
import com.memobook.core.OrderPayment
import com.memobook.core.OrderQuote
import com.memobook.core.OrderQuoteGroup
import com.memobook.core.OrderQuoteLine
import com.memobook.core.PaymentCard
import com.memobook.core.PlacedPrintOrder
import com.memobook.core.PrintOrder
import com.memobook.core.PrintOrderStatus
import com.memobook.core.PrintedCopyOptions
import com.memobook.core.ShippingAddress
import com.memobook.core.ShippingCountry
import com.memobook.core.ShippingSpeed
import com.memobook.core.Trip
import com.memobook.core.TripProgress
import com.memobook.core.TripStage
import com.memobook.core.TripStats
import com.memobook.feature.home.fixtureDate
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID

// Jeu d'essai du tunnel de commande. Le jumeau de `OrderFixtures.swift`.
//
// Ce fichier expose, au module `:feature` seulement :
// - `OrderContext.fixture` (80 pages), `OrderContext.fixture(pageCount)` et
//   `OrderContext.notComposedFixture` (un carnet jamais composé) ;
// - `ShippingCountry.fixtures`, les quatorze pays livrés ;
// - [OrderPricing], le barème du serveur recopié pour les aperçus ;
// - `OrderQuote.fixture` et `OrderQuote.fixture(copies, speed, pageCount)` ;
// - `NewPrintOrderRequest.previewRequest`, `PlacedPrintOrder.fixture(memoId,
//   request)` et `PrintOrder.fixture(memoId, request)`, ce que rend le double.
//
// Il porte les chiffres de la maquette — 80 pages estimées — pour que les
// aperçus soient comparables à Figma sans serveur. Les montants du
// récapitulatif se recomposent à partir du même barème que le serveur : un jeu
// d'essai qui annoncerait d'autres totaux ne montrerait pas l'écran qu'on
// livre.

internal val OrderContext.Companion.fixture: OrderContext get() = fixture(pageCount = 80)

internal fun OrderContext.Companion.fixture(pageCount: Int): OrderContext =
    OrderContext(
        memoId = "trip-rome",
        renderId = "render-rome",
        bookTitle = "Rome et la Dolce Vita",
        pageCount = pageCount,
        trip = Trip(
            id = "trip-rome",
            title = "Rome entre frère et sœur",
            destination = Destination(name = "Italie", countryCode = "IT", city = "Rome"),
            stage = TripStage.Past,
            startDate = fixtureDate(26, 8, 2026),
            endDate = fixtureDate(15, 9, 2026),
            stats = TripStats(dayCount = 10, distanceKilometres = 37.0, photoCount = 24),
            companions = listOf(com.memobook.core.Companion(id = "c-1", name = "Léa Marchand")),
            progress = TripProgress(memoryCount = 24, pageCount = pageCount, targetPageCount = pageCount),
            isPrintable = true,
        ),
        unitPrice = OrderPricing.unitPrice(pages = pageCount),
        expressPrice = OrderPricing.express,
        standardDays = DayRange(min = 5, max = 7),
        expressDays = DayRange(min = 2, max = 3),
        shipping = ShippingAddress(
            name = "Clara Perrin",
            line1 = "7 rue Simon Fryd",
            postalCode = "69007",
            city = "Lyon",
            country = "FR",
        ),
        countries = ShippingCountry.fixtures,
        cards = listOf(
            PaymentCard(id = "card-business", label = "Carte business", last4 = "3246"),
            PaymentCard(id = "card-perso", label = "Carte perso", last4 = "1820"),
        ),
        selectedCardId = "card-perso",
        options = PrintedCopyOptions(position = 1),
    )

/** Le carnet n'a jamais été composé : l'étape 1 n'a rien à commander. */
internal val OrderContext.Companion.notComposedFixture: OrderContext
    get() = fixture.copy(renderId = null)

private val shippingCountryFixtures = listOf(
    ShippingCountry(code = "FR", name = "France"),
    ShippingCountry(code = "BE", name = "Belgique"),
    ShippingCountry(code = "CH", name = "Suisse"),
    ShippingCountry(code = "LU", name = "Luxembourg"),
    ShippingCountry(code = "DE", name = "Allemagne"),
    ShippingCountry(code = "ES", name = "Espagne"),
    ShippingCountry(code = "IT", name = "Italie"),
    ShippingCountry(code = "PT", name = "Portugal"),
    ShippingCountry(code = "NL", name = "Pays-Bas"),
    ShippingCountry(code = "IE", name = "Irlande"),
    ShippingCountry(code = "AT", name = "Autriche"),
    ShippingCountry(code = "GB", name = "Royaume-Uni"),
    ShippingCountry(code = "CA", name = "Canada"),
    ShippingCountry(code = "US", name = "États-Unis"),
)

internal val ShippingCountry.Companion.fixtures: List<ShippingCountry> get() = shippingCountryFixtures

/**
 * Le barème, recopié du serveur pour les seuls aperçus.
 *
 * ⚠️ **Ce n'est pas la source de vérité** — `services/printPricing.ts` l'est, et
 * c'est lui que l'app interroge en vrai. Ces constantes n'existent que pour que
 * les aperçus montrent des totaux cohérents entre eux.
 */
internal object OrderPricing {
    val paperPerPage = BigDecimal("1.32")
    val cover = BigDecimal("14.90")
    val binding = BigDecimal("9.00")
    val express = BigDecimal("9.90")

    fun unitPrice(pages: Int): BigDecimal = BigDecimal(maxOf(pages, 1)) * paperPerPage + cover + binding
}

internal val OrderQuote.Companion.fixture: OrderQuote get() = fixture(copies = 2, speed = ShippingSpeed.Standard)

internal fun OrderQuote.Companion.fixture(copies: Int, speed: ShippingSpeed, pageCount: Int = 80): OrderQuote {
    val unit = OrderPricing.unitPrice(pages = pageCount)
    val items = unit * BigDecimal(copies)
    val shipping = if (speed == ShippingSpeed.Express) OrderPricing.express else BigDecimal.ZERO
    val due = items + shipping

    return OrderQuote(
        bookTitle = "Rome et la Dolce Vita",
        pageCount = pageCount,
        copies = copies,
        shippingSpeed = speed,
        unitPrice = unit,
        book = OrderQuoteGroup(
            lines = listOf(
                OrderQuoteLine(
                    id = "book",
                    label = OrderCopy.Summary.bookLine(pages = pageCount),
                    amount = unit,
                ),
            ),
            subtotal = unit,
        ),
        specifications = listOf(
            "80g. non couché ivoire",
            "Couverture rigide & matte",
            "Livre relié",
        ),
        fulfilment = OrderQuoteGroup(
            lines = listOf(
                OrderQuoteLine(
                    id = "copies",
                    label = "Exemplaires",
                    detail = "x$copies",
                    amount = items,
                ),
                OrderQuoteLine(
                    id = "shipping",
                    label = if (speed == ShippingSpeed.Express) "Livraison express" else "Livraison standard",
                    amount = shipping,
                ),
            ),
            subtotal = due,
        ),
        total = due,
        estimatedMinDays = if (speed == ShippingSpeed.Express) 2 else 5,
        estimatedMaxDays = if (speed == ShippingSpeed.Express) 3 else 7,
    )
}

/** De quoi fabriquer une commande d'aperçu, quand aucune n'a été passée. */
internal val NewPrintOrderRequest.Companion.previewRequest: NewPrintOrderRequest
    get() = NewPrintOrderRequest(
        renderId = "render-rome",
        copies = 1,
        shippingSpeed = ShippingSpeed.Standard,
        shipping = OrderContext.fixture.shipping,
        copyOptions = listOf(PrintedCopyOptions(position = 1)),
    )

/**
 * Ce que le bac à sable rend : une commande à régler, et une intention
 * **factice** pour le faire.
 *
 * Elle n'atteint jamais Stripe : le modèle qui la reçoit dans le bac à sable et
 * les aperçus est monté avec la feuille de paiement par défaut d'`OrderModel`,
 * qui répond « payé » sans rien ouvrir. C'était la cagnotte qui tenait ce rôle
 * — une commande réglée sans feuille — jusqu'à ce qu'elle parte (T230).
 */
internal fun PlacedPrintOrder.Companion.fixture(memoId: String, request: NewPrintOrderRequest): PlacedPrintOrder {
    val order = PrintOrder.fixture(memoId = memoId, request = request)
    return PlacedPrintOrder(
        order = order,
        payment = OrderPayment(
            amountCents = ((order.total ?: BigDecimal.ZERO) * BigDecimal(100)).toInt(),
            currency = "eur",
            clientSecret = "pi_preview_secret_preview",
            publishableKey = "pk_test_preview",
        ),
    )
}

/** La commande que le double d'aperçu rend, à partir de ce qu'on lui envoie. */
internal fun PrintOrder.Companion.fixture(memoId: String, request: NewPrintOrderRequest): PrintOrder {
    val days = if (request.shippingSpeed == ShippingSpeed.Express) DayRange(min = 2, max = 3) else DayRange(min = 5, max = 7)
    val now = Instant.now()

    return PrintOrder(
        id = UUID.randomUUID().toString().uppercase(),
        memoId = memoId,
        renderId = request.renderId ?: "render-rome",
        status = PrintOrderStatus.Draft,
        copies = request.copies,
        shippingSpeed = request.shippingSpeed,
        shipping = request.shipping,
        pageCount = 80,
        coverImageUrl = null,
        estimatedMinDays = days.min,
        estimatedMaxDays = days.max,
        total = OrderQuote.fixture(copies = request.copies, speed = request.shippingSpeed).total,
        copyOptions = request.copyOptions,
        createdAt = now,
        updatedAt = now,
    )
}
