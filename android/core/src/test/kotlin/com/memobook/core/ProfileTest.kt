package com.memobook.core

import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ce que le profil déduit de ses données. Cinq règles s'y jouent : une adresse
 * ne vaut que complète — et sait dire ce qui lui manque —, elle se résume sans
 * virgule orpheline et avec le pays en toutes lettres, une carte ne montre
 * jamais que ses quatre derniers chiffres, et la ligne « carte enregistrée » ne
 * reste pas vide faute de choix explicite. Mêmes cas que `ProfileTests.swift`.
 */
class ProfileTest {
    private fun profile(json: String): TravellerProfile =
        MemoBookJson.decodeFromString(TravellerProfile.serializer(), json)

    // MARK: - Adresse

    @Test
    fun aCompleteAddressIsComplete() {
        val address = PostalAddress(street = "7 Rue Simon Fryd", postalCode = "69007", city = "Lyon", country = "France")
        assertTrue(address.isComplete)
    }

    /** Un champ rempli d'espaces n'est pas un champ rempli : c'est le cas que
     *  produit un clavier tactile, et il ne doit pas laisser partir un colis. */
    @Test
    fun aBlankFieldMakesTheAddressIncomplete() {
        var address = PostalAddress(street = "7 Rue Simon Fryd", postalCode = "69007", city = "Lyon", country = "France")
        address = address.copy(city = "   ")
        assertFalse(address.isComplete)

        assertFalse(PostalAddress().isComplete)
    }

    @Test
    fun theSingleLineJoinsWhatItHas() {
        val address = PostalAddress(street = "7 Rue Simon Fryd", postalCode = "69007", city = "Lyon", country = "France")
        assertEquals("7 Rue Simon Fryd, Lyon, France", address.singleLine)
    }

    /** Une adresse à moitié saisie se lit quand même, sans virgule en trop. */
    @Test
    fun theSingleLineSkipsEmptyFields() {
        val address = PostalAddress(street = "7 Rue Simon Fryd", city = "Lyon")
        assertEquals("7 Rue Simon Fryd, Lyon", address.singleLine)
        assertEquals("", PostalAddress().singleLine)
    }

    /** Le pays est un code, mais la ligne l'écrit en toutes lettres : « FR » en
     *  bout d'adresse se lirait comme une coquille. */
    @Test
    fun theSingleLineWritesTheCountryName() {
        val address = PostalAddress(
            street = "7 Rue Simon Fryd",
            postalCode = "69007",
            city = "Lyon",
            country = "FR",
            countryName = "France",
        )
        assertEquals("7 Rue Simon Fryd, Lyon, France", address.singleLine)
    }

    /** « Valider » nomme ce qui manque, dans l'ordre des champs et en une phrase qui se lit. */
    @Test
    fun theAddressNamesWhatIsMissing() {
        assertNull(PostalAddress(street = "7 Rue", postalCode = "69007", city = "Lyon", country = "FR").missingFieldsDescription)
        assertEquals("le code postal", PostalAddress(street = "7 Rue", city = "Lyon", country = "FR").missingFieldsDescription)
        assertEquals("le code postal et la ville", PostalAddress(street = "7 Rue", country = "FR").missingFieldsDescription)
        assertEquals("l’adresse, le code postal, la ville et le pays", PostalAddress().missingFieldsDescription)
        assertEquals(PostalAddress.Field.Street, PostalAddress(street = "  ").missingFields.first())
    }

    /** Un serveur d'avant la liste des pays n'envoie ni `countryName` ni
     *  `shippingCountries` : le profil se décode quand même, et le code tient
     *  lieu de nom. */
    @Test
    fun theProfileDecodesWithoutTheCountryList() {
        val profile = profile(
            """
            {
              "fullName": "Maylis Garde",
              "address": { "street": "7 Rue", "postalCode": "69007", "city": "Lyon", "country": "France" },
              "wantsNewsletter": false,
              "walletBalance": 0,
              "cards": [],
              "connectors": [],
              "subscription": { "weeklyPrice": 1.99, "isActive": false, "cancelledAt": null, "paidThrough": null, "hasEndedBefore": false },
              "orders": []
            }
            """,
        )

        assertEquals("France", profile.address.countryName)
        assertEquals("7 Rue, Lyon, France", profile.address.singleLine)
        assertEquals(emptyList(), profile.shippingCountries)
        assertNull(profile.shippingCountry(code = "FR"))
        // Un serveur d'avant D13 ne sert pas les notifications du compte : tout
        // allumé, comme la base.
        assertEquals(AccountNotificationPreferences(), profile.notifications)
    }

    // MARK: - Notifications du compte (D13)

    /** Ce que le serveur sert : les quatre interrupteurs du compte, sous les noms
     *  de `serializeAccountNotificationPreferences`. */
    @Test
    fun theProfileReadsTheAccountNotifications() {
        val profile = profile(
            """
            {
              "fullName": "Maylis Garde",
              "address": { "street": "", "postalCode": "", "city": "", "country": "" },
              "wantsNewsletter": false,
              "notifications": { "renewalReminder": true, "schoolHolidays": false, "learnedPeriod": true, "birthday": false },
              "cards": [],
              "connectors": [],
              "subscription": { "weeklyPrice": 4.99, "isActive": false, "cancelledAt": null, "paidThrough": null, "hasEndedBefore": false },
              "orders": []
            }
            """,
        )

        assertEquals(AccountNotificationPreferences(schoolHolidays = false, birthday = false), profile.notifications)
    }

    /** Le `PATCH` envoie le bloc entier sous `notifications`, et rien d'autre
     *  quand il n'y a que lui. */
    @Test
    fun aProfileEditSendsTheAccountNotificationsAsOneBlock() {
        val edit = ProfileEdit(notifications = AccountNotificationPreferences(renewalReminder = false))
        val data = MemoBookJson.encodeToString(ProfileEdit.serializer(), edit)
        val obj = MemoBookJson.parseToJsonElement(data).jsonObject

        assertEquals(listOf("notifications"), obj.keys.toList())
        val notifications = assertNotNull(obj["notifications"] as? JsonObject)
        assertEquals(
            mapOf("renewalReminder" to false, "schoolHolidays" to true, "learnedPeriod" to true, "birthday" to true),
            notifications.mapValues { it.value.jsonPrimitive.boolean },
        )

        // Sans elles, la clé n'existe pas : le serveur ne touche à rien.
        val other = MemoBookJson.encodeToString(ProfileEdit.serializer(), ProfileEdit(wantsNewsletter = true))
        assertFalse(other.contains("notifications"))
    }

    /** Ce que le serveur envoie aujourd'hui : le code, le nom dérivé, et la liste
     *  dans laquelle le choisir. */
    @Test
    fun theProfileReadsTheCountryList() {
        val profile = profile(
            """
            {
              "fullName": "Maylis Garde",
              "address": { "street": "7 Rue", "postalCode": "69007", "city": "Lyon", "country": "FR", "countryName": "France" },
              "shippingCountries": [{ "code": "FR", "name": "France" }, { "code": "BE", "name": "Belgique" }],
              "wantsNewsletter": false,
              "walletBalance": 0,
              "cards": [],
              "connectors": [],
              "subscription": { "weeklyPrice": 1.99, "isActive": false, "cancelledAt": null, "paidThrough": null, "hasEndedBefore": false },
              "orders": []
            }
            """,
        )

        assertEquals("FR", profile.address.country)
        assertEquals("7 Rue, Lyon, France", profile.address.singleLine)
        assertEquals("Belgique", profile.shippingCountry(code = "BE")?.name)
        assertNull(profile.shippingCountry(code = "MC"))
    }

    /** **Une commande au paiement abandonné n'est pas en route** (T232) : le
     *  serveur le dit, avec le carnet et le net à payer. Celles d'un serveur
     *  d'avant, sans état, restent des livraisons. */
    @Test
    fun ordersTellAnAbandonedPaymentFromADelivery() {
        val orders = MemoBookJson.decodeFromString(
            ListSerializer(OrderTracking.serializer()),
            """
            [
              { "id": "o1", "minimumDays": 5, "maximumDays": 7, "copies": 2, "pageCount": 50, "coverImageUrl": null },
              { "id": "o2", "status": "payment_abandoned", "minimumDays": 5, "maximumDays": 7, "copies": 1,
                "pageCount": 42, "coverImageUrl": null, "memoId": "m2", "tripTitle": "Rome 2026", "total": 89.9,
                "createdAt": "2026-10-06T09:00:00.000Z" },
              { "id": "o3", "status": "in_progress", "minimumDays": 3, "maximumDays": 4, "copies": 1, "pageCount": 30 },
              { "id": "o4", "status": "on_the_moon", "minimumDays": 3, "maximumDays": 4, "copies": 1, "pageCount": 30 }
            ]
            """,
        )

        assertEquals(listOf(false, true, false, false), orders.map { it.isPaymentAbandoned })
        assertEquals("m2", orders[1].memoId)
        assertEquals("Rome 2026", orders[1].tripTitle)
        assertEquals(89.9, (orders[1].total ?: java.math.BigDecimal.ZERO).toDouble(), absoluteTolerance = 0.001)
        assertNotNull(orders[1].createdAt)
        assertNull(orders[0].total)
    }

    /** La liste reconnaît un code comme un nom, sans tenir compte de la casse ni
     *  des accents : c'est ce qui ramène une adresse d'avant la liste sur sa
     *  ligne du menu. */
    @Test
    fun theCountryListMatchesACodeOrAName() {
        val countries = listOf(
            ShippingCountry(code = "FR", name = "France"),
            ShippingCountry(code = "US", name = "États-Unis"),
        )

        assertEquals("FR", countries.matching("FR")?.code)
        assertEquals("FR", countries.matching("fr")?.code)
        assertEquals("FR", countries.matching("FRANCE")?.code)
        assertEquals("FR", countries.matching(" France ")?.code)
        assertEquals("US", countries.matching("Etats-Unis")?.code)
        assertNull(countries.matching("Monaco"))
        assertNull(countries.matching(""))

        val profile = TravellerProfile(fullName = "Maylis Garde", shippingCountries = countries)
        assertEquals("FR", profile.shippingCountry(code = "France")?.code)
    }

    /** Le cache réécrit le profil tel quel : le nom du pays doit survivre à
     *  l'aller-retour, sans quoi la ligne afficherait « FR » au réveil. */
    @Test
    fun theAddressRoundTripsThroughCoding() {
        val address = PostalAddress(street = "7 Rue", postalCode = "69007", city = "Lyon", country = "FR", countryName = "France")
        val data = MemoBookJson.encodeToString(PostalAddress.serializer(), address)
        assertEquals(address, MemoBookJson.decodeFromString(PostalAddress.serializer(), data))
    }

    // MARK: - Carte

    @Test
    fun aCardOnlyEverShowsItsLastFourDigits() {
        val card = PaymentCard(id = "1", label = "Carte perso", last4 = "1820")
        assertEquals("XXXX XXXX XXXX 1820", card.maskedNumber)
    }

    // MARK: - Profil

    /** Sans choix explicite, c'est la première carte qui s'affiche : la ligne du
     *  profil ne doit pas rester vide parce que personne n'a encore tranché. */
    @Test
    fun theSelectedCardFallsBackToTheFirstOne() {
        val cards = listOf(
            PaymentCard(id = "a", label = "Carte business", last4 = "3246"),
            PaymentCard(id = "b", label = "Carte perso", last4 = "1820"),
        )

        val chosen = TravellerProfile(fullName = "Maylis Garde", cards = cards, selectedCardId = "b")
        assertEquals("b", chosen.selectedCard?.id)

        val unchosen = TravellerProfile(fullName = "Maylis Garde", cards = cards)
        assertEquals("a", unchosen.selectedCard?.id)

        assertNull(TravellerProfile(fullName = "Maylis Garde").selectedCard)
    }

    @Test
    fun initialsTakeAtMostTwoWords() {
        assertEquals("MG", TravellerProfile(fullName = "Maylis Garde").initials)
        assertEquals("M", TravellerProfile(fullName = "maylis").initials)
        assertEquals("AM", TravellerProfile(fullName = "Anne Marie Le Goff").initials)
        assertEquals("", TravellerProfile(fullName = "").initials)
    }
}
