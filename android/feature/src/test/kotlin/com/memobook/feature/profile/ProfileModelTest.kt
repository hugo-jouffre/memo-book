package com.memobook.feature.profile

import com.memobook.core.DailyCredit
import com.memobook.core.DailyCreditSheetCopy
import com.memobook.core.DataExportReceipt
import com.memobook.core.MemoBookJson
import com.memobook.core.PostalAddress
import com.memobook.core.ProfileEdit
import com.memobook.core.Subscription
import com.memobook.core.SubscriptionCancellationReason
import com.memobook.core.Traveller
import com.memobook.core.TravellerProfile
import com.memobook.feature.PaywallVariant
import com.memobook.feature.SandboxCredit
import com.memobook.feature.SandboxPersona
import com.memobook.feature.SubscriptionSession
import com.memobook.networking.ApiError
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import java.math.BigDecimal
import java.net.URI
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ce que le profil fait d'une adresse validée dans sa feuille : il la pose
 * tout de suite, l'envoie, et accuse réception. Sans émulateur — le modèle
 * reçoit ses fonctions, comme l'app les lui branche. Porté de
 * `ProfileModelTests.swift`, cas pour cas.
 *
 * Ce que le fichier Swift teste aussi, et qui vit ailleurs ici :
 * `testTheOfferPriceNeverBreaks` (`paywall/PaywallCopyTest`),
 * `testASandboxPurchaseIsDeliveredLikeARealOne` (`:payments`,
 * `StubSubscriptionStoreTest`), et les quatre cas du crédit du jour de
 * l'accueil, qui suivent `HomeModel` (lot de l'accueil).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ProfileModelTest {
    private val dispatcher = StandardTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(dispatcher)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
        SandboxPersona.current = null
    }

    /**
     * Un profil avec la liste des pays, et un double de `PATCH` qui rend ce
     * qu'il reçoit — le nom du pays dérivé du code, comme le serveur.
     */
    private suspend fun model(persist: suspend (ProfileEdit) -> TravellerProfile): ProfileModel {
        val model = ProfileModel(source = { TravellerProfile.fixture }, persist = persist)
        model.load()
        return model
    }

    private fun echo(edit: ProfileEdit): TravellerProfile {
        val profile = TravellerProfile.fixture
        val address = edit.address ?: return profile
        return profile.copy(address = address.copy(countryName = profile.shippingCountry(address.country)?.name ?: address.country))
    }

    @Test
    fun savingAnAddressWritesItAtOnceAndConfirmsOnceTheServerAnswered() = runTest(dispatcher) {
        var sent: ProfileEdit? = null
        val model = model { edit ->
            sent = edit
            echo(edit)
        }

        model.save(PostalAddress(street = "12 rue Neuve", postalCode = "1000", city = "Bruxelles", country = "BE"))

        // Posée sur l'écran avant toute réponse, et déjà en toutes lettres :
        // le nom vient de la liste servie avec le profil, pas du serveur.
        assertEquals("12 rue Neuve, Bruxelles, Belgique", model.profile?.address?.singleLine)

        runCurrent()
        assertEquals(ProfileModel.SavedField.Address, model.justSaved)

        assertEquals("BE", sent?.address?.country)
        assertEquals("Belgique", model.profile?.address?.countryName)
        assertNull(model.errorMessage)
    }

    /**
     * Sans liste de pays, la feuille laisse taper un nom : le modèle le
     * ramène au code quand la liste le connaît, pour que le serveur reçoive
     * ce qu'il attend et que la ligne l'écrive proprement.
     */
    @Test
    fun aTypedCountryNameBecomesItsCode() = runTest(dispatcher) {
        var sent: ProfileEdit? = null
        val model = model { edit ->
            sent = edit
            echo(edit)
        }

        model.save(PostalAddress(street = "1 rue", postalCode = "75001", city = "Paris", country = "france"))
        runCurrent()

        assertEquals("FR", sent?.address?.country)
        assertEquals("1 rue, Paris, France", model.profile?.address?.singleLine)
    }

    /**
     * Un code hors liste n'est pas maquillé : la ligne le montre tel quel, et
     * c'est le serveur qui refusera.
     */
    @Test
    fun anUnknownCountryKeepsItsCode() = runTest(dispatcher) {
        val model = model { echo(it) }

        model.save(PostalAddress(street = "1 rue", postalCode = "98000", city = "Monaco", country = "MC"))

        assertEquals("MC", model.profile?.address?.countryName)
    }

    @Test
    fun savingTheSameAddressSendsNothing() = runTest(dispatcher) {
        var calls = 0
        val model = model { edit ->
            calls += 1
            echo(edit)
        }

        model.save(TravellerProfile.fixture.address)
        runCurrent()

        assertEquals(0, calls)
        assertNull(model.justSaved)
    }

    /**
     * Un refus du serveur laisse ce qui a été tapé à l'écran, avec le reproche
     * — effacer sous les doigts serait pire qu'une panne.
     */
    @Test
    fun aRefusalKeepsTheTypedAddressAndSaysWhy() = runTest(dispatcher) {
        val model = model { throw IllegalStateException("Ce pays n'est pas encore livré.") }

        model.save(PostalAddress(street = "1 rue", postalCode = "98000", city = "Monaco", country = "MC"))
        runCurrent()

        assertEquals("Monaco", model.profile?.address?.city)
        assertEquals("Ce pays n'est pas encore livré.", model.errorMessage)
        assertNull(model.justSaved)
    }

    /**
     * « Supprimer la photo » qui échoue le dit **sous le rond**, là où l'on a
     * touché, et non au pied de la page (Hugo, 30/09/2026 : l'API rendait 404
     * et rien ne bougeait à l'écran). La photo reste : c'est le profil relu
     * qui fait foi.
     */
    @Test
    fun aFailedPhotoRemovalIsSaidUnderThePhotoAndKeepsIt() = runTest(dispatcher) {
        val withPhoto = TravellerProfile.fixture.copy(avatarUrl = URI("https://api.test/v1/avatars/photo.jpg"))
        val model = ProfileModel(source = { withPhoto }, deleteAvatar = { throw IllegalStateException("Route introuvable.") })
        model.load()

        model.removeAvatar()

        assertEquals("Route introuvable.", model.avatarErrorMessage)
        assertNull(model.errorMessage, "Le bandeau du bas de page, lui, reste pour le chargement.")
        assertEquals(withPhoto.avatarUrl, model.profile?.avatarUrl)
    }

    @Test
    fun aRemovedPhotoGivesBackTheInitials() = runTest(dispatcher) {
        val withPhoto = TravellerProfile.fixture.copy(avatarUrl = URI("https://api.test/v1/avatars/photo.jpg"))
        val withoutPhoto = withPhoto.copy(avatarUrl = null)
        val model = ProfileModel(source = { withPhoto }, deleteAvatar = { withoutPhoto })
        model.load()

        model.removeAvatar()

        assertNull(model.profile?.avatarUrl)
        assertNull(model.avatarErrorMessage)
        assertEquals(ProfileModel.SavedField.Avatar, model.justSaved)
    }

    // MARK: - Un abonnement tenu par un store (01/10/2026)

    /** Un abonné App Store, dans son mois payé. */
    private fun appStoreSubscriber(): TravellerProfile {
        val profile = TravellerProfile.fixture
        return profile.copy(
            subscription = profile.subscription.updating(
                isActive = true,
                cancelledAt = null,
                managedByAppStore = true,
                paidThrough = Instant.now().plus(Duration.ofDays(20)),
            ),
        )
    }

    @Test
    fun theReasonLeavesWithoutClosingTheSubscription() = runTest(dispatcher) {
        // Le store seul résilie : la raison part, l'abonnement reste ouvert à
        // l'écran tant que sa page n'a rien coupé.
        var sent: SubscriptionCancellationReason? = null
        val subscriber = appStoreSubscriber()
        val model = ProfileModel(
            source = { subscriber },
            cancelSubscription = { reason ->
                sent = reason
                subscriber
            },
        )
        model.load()

        model.recordCancellationReason(SubscriptionCancellationReason.TooExpensive)

        assertEquals(true, model.profile?.subscription?.isActive)
        runCurrent()
        assertEquals(SubscriptionCancellationReason.TooExpensive, sent)
        assertEquals(true, model.profile?.subscription?.isActive)
    }

    @Test
    fun aRenewalCutAtTheStoreKeepsThePaidMonth() = runTest(dispatcher) {
        val subscriber = appStoreSubscriber()
        val model = ProfileModel(source = { subscriber })
        model.load()

        model.acknowledgeAppStoreRenewal(false)

        assertEquals(false, model.profile?.subscription?.isActive)
        assertNotNull(model.profile?.subscription?.cancelledAt)
        // Le mois est réglé : l'illimité reste ouvert jusqu'à son terme.
        assertTrue(model.subscriptionGrantsAccess)

        model.acknowledgeAppStoreRenewal(true)
        assertEquals(true, model.profile?.subscription?.isActive)
        assertNull(model.profile?.subscription?.cancelledAt)
    }

    /**
     * Souscrire passe l'écran à l'illimité tout de suite, sans attendre que
     * le serveur relise l'achat — et sans rien d'autre à remettre à zéro : il
     * n'y a plus d'essai gratuit à décompter (Hugo, 03/10/2026).
     */
    @Test
    fun subscribingUnlocksTheUnlimitedAtOnce() = runTest(dispatcher) {
        val free = TravellerProfile.freeFixture
        val model = ProfileModel(source = { free })
        model.load()
        assertEquals(false, model.profile?.isSubscriber)

        model.activateSubscription()

        assertEquals(true, model.profile?.isSubscriber)
        assertTrue(model.subscriptionGrantsAccess)
    }

    // MARK: - Exporter ses données

    private fun receipt(alreadyRequested: Boolean = false) = DataExportReceipt(
        email = "hugo@memobook.app",
        requestedAt = Instant.ofEpochSecond(1_790_870_000),
        expiresAt = Instant.ofEpochSecond(1_790_870_000L + 7 * 24 * 3600),
        alreadyRequested = alreadyRequested,
    )

    @Test
    fun theExportSaysWhereTheLinkWent() = runTest(dispatcher) {
        val sent = receipt()
        val model = ProfileModel(source = { TravellerProfile.fixture }, exportData = { sent })
        model.load()

        model.requestDataExport()

        assertEquals(ProfileModel.DataExportState.Sent(sent), model.dataExport)
    }

    /**
     * Le refus du serveur est dit avec ses mots — « Ton compte n'a pas
     * d'adresse… » — et la feuille reste sur la proposition.
     */
    @Test
    fun aRefusedExportIsSaidInTheServerWords() = runTest(dispatcher) {
        val model = ProfileModel(
            source = { TravellerProfile.fixture },
            exportData = { throw ApiError.Server(statusCode = 409, code = "no_email", message = "Ton compte n’a pas d’adresse e-mail.") },
        )

        model.requestDataExport()

        assertEquals(ProfileModel.DataExportState.Failed("Ton compte n’a pas d’adresse e-mail."), model.dataExport)
    }

    /**
     * Un serveur qui ne connaît pas encore la route répond le 404 de Fastify,
     * en anglais : la feuille dit autre chose.
     */
    @Test
    fun aServerWithoutTheRouteIsNotQuotedInEnglish() = runTest(dispatcher) {
        val model = ProfileModel(
            source = { TravellerProfile.fixture },
            exportData = {
                throw ApiError.Server(statusCode = 404, code = "Not Found", message = "Route POST:/v1/accounts/me/export not found")
            },
        )

        model.requestDataExport()

        assertEquals(ProfileModel.DataExportState.Failed(DataExportCopy.notYetAvailable), model.dataExport)
    }

    @Test
    fun closingTheSheetGoesBackToTheOffer() = runTest(dispatcher) {
        val sent = receipt(alreadyRequested = true)
        val model = ProfileModel(source = { TravellerProfile.fixture }, exportData = { sent })
        model.requestDataExport()
        assertEquals(ProfileModel.DataExportState.Sent(sent), model.dataExport)

        model.resetDataExport()

        assertEquals(ProfileModel.DataExportState.Idle, model.dataExport)
    }

    /** « 1er », que le format de date ne sait pas écrire seul. */
    @Test
    fun theExpiryReadsInFrench() {
        val noon = Instant.parse("2026-10-01T12:00:00.000Z")
        assertEquals("jeudi 1er octobre", DataExportCopy.day(noon, ZoneId.of("Europe/Paris")))
        assertEquals(
            "Rien dans ta boîte d’ici quelques minutes ? Regarde dans tes indésirables.",
            DataExportCopy.sentParagraphs(receipt()).last(),
        )
    }

    // MARK: - Le verdict du serveur (03/10/2026)

    /**
     * Délai de grâce de facturation du store : `isActive` faux, rien de
     * résilié, et le serveur accorde l'illimité. Le profil le suit.
     */
    @Test
    fun aBillingGracePeriodKeepsTheSubscriberScreen() = runTest(dispatcher) {
        val json = """{ "price": 4.99, "interval": "month", "isActive": false, "isUnlimited": true, "managedByAppStore": true }"""
        val served = TravellerProfile.fixture.copy(subscription = MemoBookJson.decodeFromString(Subscription.serializer(), json))
        val model = ProfileModel(source = { served })
        model.load()

        assertEquals(true, model.profile?.isSubscriber)
        assertTrue(model.subscriptionGrantsAccess)
    }

    // MARK: - La session d'abonnement (03/10/2026)

    /**
     * **Renouvellement coupé** (Hugo, 06/10/2026) : abonné jusqu'à la date
     * de fin, puis plus du tout — partout, sans attendre une relecture.
     */
    @Test
    fun theSessionLetsTheUnlimitedLapseAtItsDate() {
        val session = SubscriptionSession()
        val end = Instant.now().plusSeconds(3_600)
        session.learn(isUnlimited = true, hasSubscribedBefore = true, endsAt = end)
        assertTrue(session.isUnlimited)
        assertEquals(end, session.endsAt)

        // Avant l'heure, rien ne bouge.
        session.expireIfDue(now = end.minusSeconds(60))
        assertTrue(session.isUnlimited)

        val revision = session.revision
        session.expireIfDue(now = end.plusSeconds(1))
        assertFalse(session.isUnlimited)
        assertNull(session.endsAt)
        assertTrue(session.revision > revision)
        // Le crédit servi la veille, qui disait « illimité », se relit sans.
        assertEquals(false, session.applied(DailyCredit(isUnlimited = true))?.isUnlimited)
        // Le paywall de retour, puisqu'il a été abonné.
        assertEquals(PaywallVariant.Returning, session.paywallVariant)

        // Le serveur relu dit qu'il s'est réabonné ailleurs : il fait foi.
        session.learn(isUnlimited = true, hasSubscribedBefore = true)
        assertTrue(session.isUnlimited)
        assertEquals(true, session.applied(DailyCredit(isUnlimited = true))?.isUnlimited)
    }

    /**
     * Un accueil gardé en cache depuis la veille ne fait pas revivre un
     * renouvellement coupé dont la date est passée.
     */
    @Test
    fun aCachedHomeDoesNotReviveALapsedSubscription() {
        val session = SubscriptionSession()
        val traveller = Traveller(
            id = "t",
            firstName = "Camille",
            isUnlimited = true,
            hasSubscribedBefore = true,
            subscriptionState = Subscription.State.Ending,
            subscriptionEndsAt = Instant.now().minusSeconds(60),
        )
        session.learn(traveller)
        assertFalse(session.isUnlimited)
        assertNull(session.endsAt)
    }

    /**
     * Résilier dans l'app, avec un mois payé devant soi : l'illimité reste
     * ouvert jusqu'à sa fin, puis tombe.
     */
    @Test
    fun aCancellationGestureEndsWithThePaidMonth() {
        val session = SubscriptionSession()
        val end = Instant.now().plusSeconds(86_400)
        session.record(isSubscribed = true, until = end)
        assertTrue(session.isUnlimited)

        session.expireIfDue(now = end.plusSeconds(1))
        assertFalse(session.isUnlimited)
        assertNull(session.override)
    }

    /**
     * Un achat que le serveur n'a jamais confirmé, et que le store ne tient
     * plus (remboursé, révoqué) : le geste rend la main.
     */
    @Test
    fun anUnconfirmedPurchaseTheStoreNoLongerHoldsIsWithdrawn() {
        val session = SubscriptionSession()
        session.learn(isUnlimited = false, hasSubscribedBefore = false)
        session.record(isSubscribed = true)
        assertTrue(session.isUnlimited)

        session.withdrawUnconfirmedPurchase()
        assertFalse(session.isUnlimited)
        assertNull(session.override)
    }

    /**
     * Déconnexion, session refusée, compte supprimé : ce que la session
     * savait de A ne passe pas à B.
     */
    @Test
    fun theSessionForgetsTheAccountItServed() {
        val session = SubscriptionSession()
        session.record(isSubscribed = true)
        session.learn(isUnlimited = false, hasSubscribedBefore = true)

        session.reset()

        assertNull(session.override)
        assertNull(session.known)
        assertFalse(session.isUnlimited)
        assertEquals(PaywallVariant.FirstTime, session.paywallVariant)
        assertEquals(false, session.applied(DailyCredit())?.isUnlimited)
    }

    /**
     * Le geste a le dernier mot sur ce qui a été servi avant lui, et rend la
     * main dès que le serveur dit la même chose : l'échéance qu'il annonce
     * ensuite fait foi.
     */
    @Test
    fun theGestureGivesWayOnceTheServerAgrees() {
        val session = SubscriptionSession()
        session.record(isSubscribed = true)

        // Un serveur qui n'a pas encore reçu l'achat ne lève pas le geste.
        session.learn(isUnlimited = false, hasSubscribedBefore = false)
        assertEquals(true, session.override)
        assertTrue(session.isUnlimited)

        // Il le confirme : le geste rend la main…
        session.learn(isUnlimited = true, hasSubscribedBefore = true)
        assertNull(session.override)

        // … et le mois payé qui s'achève se voit, crédit compris.
        session.learn(isUnlimited = false, hasSubscribedBefore = true)
        assertFalse(session.isUnlimited)
        assertEquals(false, session.applied(DailyCredit(isUnlimited = false))?.isUnlimited)
        assertEquals(PaywallVariant.Returning, session.paywallVariant)
    }

    // MARK: - Les textes de l'abonnement (03/10/2026)

    /**
     * Un abonné de l'ancienne formule hebdomadaire a payé une semaine, pas un
     * mois — et les phrases s'accordent.
     */
    @Test
    fun aWeeklySubscriberReadsWeekWhenCancelling() {
        val end = Instant.ofEpochSecond(1_791_000_000)

        val keepGoing = SubscriptionCopy.keepGoingParagraphs(tripTitle = null, graceEnd = end, interval = Subscription.Interval.Week)
        assertTrue(keepGoing[1].contains("la fin de la semaine déjà réglée"), keepGoing[1])
        val reason = SubscriptionCopy.reasonParagraphs(graceEnd = end, interval = Subscription.Interval.Week).last()
        assertTrue(reason.startsWith("Ta semaine est déjà réglée : "), reason)
        assertTrue(SubscriptionCopy.doneParagraphs(graceEnd = end, interval = Subscription.Interval.Week)[1].startsWith("Ta semaine est réglée jusqu’au"))
        assertTrue(SubscriptionCopy.doneParagraphs(graceEnd = end, interval = Subscription.Interval.Month)[1].startsWith("Ton mois est réglé jusqu’au"))
        // L'accueil ne connaît pas la période : l'alerte de fin ne la nomme pas.
        assertFalse(SubscriptionCopy.endedMessage(tripTitle = "Rome").contains("mois"))
        assertFalse(SubscriptionCopy.endedMessage(tripTitle = null).contains("mois"))
    }

    /** Ni l'app ni le serveur ne tiennent le dernier jour payé en entier. */
    @Test
    fun theGraceDateIsNotSaidInclusive() {
        val end = Instant.ofEpochSecond(1_791_000_000)
        assertFalse(SubscriptionCopy.graceSubtitle(until = end).contains("inclus"))
        assertFalse(SubscriptionCopy.reasonParagraphs(graceEnd = end).joinToString("").contains("inclus"))
    }

    /**
     * Délai de grâce de facturation du store (`past_due`) : rien n'a été
     * encaissé, et le serveur met la fin du délai dans `paidThrough`. Aucune
     * des trois feuilles de la résiliation ne dit « réglé ».
     */
    @Test
    fun aBillingRetryIsNeverCalledPaid() {
        val retrying = Subscription(
            price = BigDecimal("4.99"),
            isActive = false,
            paidThrough = Instant.now().plus(Duration.ofDays(16)),
            managedByAppStore = true,
            servedIsUnlimited = true,
        )
        assertTrue(SubscriptionSheet.isBillingRetry(retrying))
        val graceEnd = if (retrying.isWithinPaidPeriod()) retrying.paidThrough else null
        val paidAhead = SubscriptionSheet.paidAhead(retrying, graceEnd = graceEnd, isBillingRetry = true)
        assertEquals(SubscriptionCopy.PaidAhead.BillingRetry, paidAhead)

        val all = SubscriptionCopy.keepGoingParagraphs(tripTitle = "Rome", graceEnd = graceEnd, paidAhead = paidAhead) +
            SubscriptionCopy.reasonParagraphs(graceEnd = graceEnd, paidAhead = paidAhead) +
            SubscriptionCopy.doneParagraphs(graceEnd = graceEnd, paidAhead = paidAhead)
        for (paragraph in all) assertFalse(paragraph.contains("réglé"), paragraph)
        assertTrue(all.any { it.contains("prélèvement") })

        // Une vraie résiliation (`cancelledAt`) n'est pas un prélèvement raté.
        val cancelled = retrying.updating(cancelledAt = Instant.now())
        assertFalse(SubscriptionSheet.isBillingRetry(cancelled))
    }

    // MARK: - Résilier chez le store un achat que le serveur n'a pas reçu (03/10/2026)

    /**
     * L'achat est encaissé par le store, le serveur n'en sait rien
     * (`AwaitingServer`) : on coupe le renouvellement sur la page du store.
     * La ligne du serveur n'est pas retouchée, la session garde l'illimité —
     * le store honore le mois payé —, et l'écran remettra la transaction puis
     * relira.
     */
    @Test
    fun cuttingTheRenewalOfAPurchaseTheServerHasNotSeenKeepsThePaidPeriod() = runTest(dispatcher) {
        val model = ProfileModel(source = { TravellerProfile.freeFixture })
        model.load()
        val session = SubscriptionSession()
        session.record(isSubscribed = true)
        assertTrue(model.isHeldByAppleOnly(session))

        assertTrue(model.settleAppStoreRenewal(false, session))

        assertEquals(true, session.override)
        assertTrue(session.isUnlimited)
        assertNull(model.profile?.subscription?.cancelledAt, "La ligne du serveur n'a rien à résilier.")
        assertEquals(TravellerProfile.freeFixture.subscription, model.profile?.subscription)

        // Et la dernière feuille ne dit pas « s'arrête aujourd'hui » d'un
        // abonnement tenu par un store dont on ne connaît pas la fin.
        val held = Subscription(price = BigDecimal("4.99"), isActive = true, managedByAppStore = true)
        val paidAhead = SubscriptionSheet.paidAhead(held, graceEnd = null, isBillingRetry = false)
        assertEquals(SubscriptionCopy.PaidAhead.HeldByApple, paidAhead)
        val done = SubscriptionCopy.doneParagraphs(graceEnd = null, paidAhead = paidAhead)
        assertFalse(done.joinToString("").contains("aujourd’hui"), done.joinToString(""))
        assertFalse(
            SubscriptionCopy.keepGoingParagraphs(tripTitle = null, graceEnd = null, paidAhead = paidAhead)[1]
                .startsWith("Si tu coupes maintenant, tu retrouves"),
        )
    }

    /**
     * Le renouvellement est resté armé : rien ne retouche le profil sur
     * place, et son écho ne lève pas le geste tant que le serveur n'a pas
     * confirmé l'achat.
     */
    @Test
    fun keepingTheRenewalOfAPurchaseTheServerHasNotSeenWaitsForTheServer() = runTest(dispatcher) {
        val model = ProfileModel(source = { TravellerProfile.freeFixture })
        model.load()
        val session = SubscriptionSession()
        session.record(isSubscribed = true)

        assertTrue(model.settleAppStoreRenewal(true, session))

        assertEquals(false, model.profile?.subscription?.isActive)
        session.learn(assertNotNull(model.profile))
        assertEquals(true, session.override, "Le serveur n'a rien confirmé : le geste tient.")
    }

    /**
     * Un abonnement que le serveur connaît suit, lui, la règle de toujours :
     * la ligne retouchée sur place, et l'accès réel retenu par la session.
     */
    @Test
    fun cuttingTheRenewalOfAKnownSubscriptionIsAcknowledged() = runTest(dispatcher) {
        val model = ProfileModel(source = { TravellerProfile.subscriberFixture })
        model.load()
        val session = SubscriptionSession()

        assertFalse(model.settleAppStoreRenewal(false, session))

        assertNotNull(model.profile?.subscription?.cancelledAt)
        assertEquals(false, model.profile?.subscription?.isActive)
        assertEquals(model.subscriptionGrantsAccess, session.override)
    }

    /** Seul qui a un abonnement App Store à couper lit qu'il faut le couper. */
    @Test
    fun onlyARenewingSubscriberIsToldToCutIt() {
        val free = DeleteAccountCopy.body(hasOngoingTrip = false, mentionsSubscription = false)
        assertFalse(free.contains("abonnement"), free)
        assertEquals(DeleteAccountCopy.erasure, free)

        val subscriber = DeleteAccountCopy.body(hasOngoingTrip = true, mentionsSubscription = true)
        assertTrue(subscriber.contains(DeleteAccountCopy.subscriptionWarning))
        assertTrue(subscriber.endsWith(DeleteAccountCopy.closeTripInstead))
    }

    // MARK: - La jauge du crédit (Hugo, 08/10/2026)

    /**
     * Vide au matin, elle se remplit avec ce qui est raconté — c'est le
     * chiffre d'à côté qui dit le reste.
     */
    @Test
    fun theGaugeFillsWithWhatIsTold() {
        assertEquals(0.0, DailyCredit(usedMs = 0).fraction)
        assertEquals(0.2, DailyCredit(usedMs = 60_000).fraction, absoluteTolerance = 0.0001)
        assertEquals(1.0, DailyCredit(usedMs = DailyCredit.Catalog.limitMs).fraction)
        assertEquals(
            "3 min 20 restantes sur 5 min",
            DailyCreditSheetCopy.gaugeAccessibilityValue(DailyCredit(usedMs = 100_000)).replace('\u00A0', ' ').replace('\u202F', ' '),
        )
    }

    // MARK: - Le bac à sable (03/10/2026)

    /**
     * Le double du bac à sable change de jour à **minuit local**, comme l'app
     * recharge le crédit : à 0 h 30 à Paris, c'est déjà le 3, même si l'UTC
     * dit encore le 2.
     */
    @Test
    fun theSandboxCreditTurnsTheDayAtLocalMidnight() {
        val halfPastMidnight = Instant.parse("2026-10-02T22:30:00Z")
        assertEquals("2026-10-03", SandboxCredit.today(now = halfPastMidnight, zone = ZoneId.of("Europe/Paris")))
    }

    /**
     * « Jamais abonné » : ni abonnement, ni passé d'abonné — le paywall
     * s'ouvre sur la découverte en trois écrans.
     */
    @Test
    fun theNeverSubscribedPersonaOpensTheDiscovery() {
        val persona = SandboxPersona.NeverSubscribed
        val traveller = persona.applied(Traveller(id = "camille", firstName = "Camille", isUnlimited = true, hasSubscribedBefore = true))
        assertFalse(traveller.isUnlimited)
        assertFalse(traveller.hasSubscribedBefore)

        val profile = persona.applied(TravellerProfile.fixture)
        assertFalse(profile.isSubscriber)
        assertFalse(profile.subscription.hasEndedBefore)

        val session = SubscriptionSession()
        session.record(isSubscribed = false)
        session.reset()
        session.learn(traveller)
        session.learn(profile)
        assertEquals(PaywallVariant.FirstTime, session.paywallVariant)
    }

    // MARK: - Android : qui tient l'abonnement

    /**
     * « Gérer » mène au store qui a vendu l'abonnement : un achat que Google
     * Play tient sans que le serveur l'ait reçu va au Play Store, un
     * abonnement de l'App Store ne se gère pas d'ici, et celui que le serveur
     * tient seul se résilie par la route.
     */
    @Test
    fun theSubscriptionIsManagedWhereItWasSold() {
        val apple = Subscription(price = BigDecimal("4.99"), isActive = true, managedByAppStore = true)
        val server = Subscription(price = BigDecimal("4.99"), isActive = true)

        assertEquals(SubscriptionSheet.Store.GooglePlay, SubscriptionSheet.store(server, isHeldByPlay = true, playKnows = false))
        assertEquals(SubscriptionSheet.Store.AppStore, SubscriptionSheet.store(apple, isHeldByPlay = false, playKnows = false))
        assertEquals(SubscriptionSheet.Store.GooglePlay, SubscriptionSheet.store(server, isHeldByPlay = false, playKnows = true))
        assertEquals(SubscriptionSheet.Store.App, SubscriptionSheet.store(server, isHeldByPlay = false, playKnows = false))

        // Un abonnement Google Play sans fin connue va lui aussi à son terme.
        assertEquals(
            SubscriptionCopy.PaidAhead.HeldByApple,
            SubscriptionSheet.paidAhead(server, graceEnd = null, isBillingRetry = false, isHeldByStore = true),
        )
        assertTrue(SubscriptionSheet.playSubscriptionsUrl.contains("sku=com.memobook.app.subscription.monthly&package=com.memobook.app"))
    }

    /** Un prélèvement raté chez Google Play se dit avec son nom, jamais celui d'Apple. */
    @Test
    fun aGooglePlayBillingRetryNamesGooglePlay() {
        val all = SubscriptionCopy.keepGoingParagraphs(
            tripTitle = null,
            graceEnd = null,
            paidAhead = SubscriptionCopy.PaidAhead.BillingRetry,
            holder = SubscriptionCopy.Holder.GooglePlay,
        ) + SubscriptionCopy.reasonParagraphs(
            graceEnd = null,
            paidAhead = SubscriptionCopy.PaidAhead.BillingRetry,
            holder = SubscriptionCopy.Holder.GooglePlay,
        ) + SubscriptionCopy.doneParagraphs(
            graceEnd = null,
            paidAhead = SubscriptionCopy.PaidAhead.BillingRetry,
            holder = SubscriptionCopy.Holder.GooglePlay,
        )
        assertFalse(all.any { it.contains("Apple") }, all.joinToString("\n"))
        assertTrue(all.any { it.contains("Google Play") })
    }

    // MARK: - Le nom, le téléphone, la coche

    /** Le nom se coupe au premier espace : le prénom, puis tout le reste. */
    @Test
    fun theFullNameSplitsAtTheFirstSpace() = runTest(dispatcher) {
        var sent: ProfileEdit? = null
        val model = model { edit ->
            sent = edit
            TravellerProfile.fixture
        }

        model.setFullName("  Jean de La Fontaine ")
        assertEquals("Jean de La Fontaine", model.profile?.fullName)
        runCurrent()

        assertEquals("Jean", sent?.firstName?.value)
        assertEquals("de La Fontaine", sent?.lastName?.value)
        assertEquals(ProfileModel.SavedField.FullName, model.justSaved)
    }

    /** Un téléphone vidé part effacé, et non comme une chaîne vide. */
    @Test
    fun anEmptiedPhoneNumberIsErased() = runTest(dispatcher) {
        var sent: ProfileEdit? = null
        val model = model { edit ->
            sent = edit
            TravellerProfile.fixture
        }

        model.setPhoneNumber("   ")
        // Effacé à l'écran tout de suite, avant la réponse.
        assertNull(model.profile?.phoneNumber)
        runCurrent()

        assertEquals(null, sent?.phoneNumber?.value)
        assertNotNull(sent?.phoneNumber, "La clé part, à `null` : on efface.")
    }

    /** La coche reste quatre secondes, puis s'éteint d'elle-même. */
    @Test
    fun theConfirmationFadesAfterFourSeconds() = runTest(dispatcher) {
        val model = model { TravellerProfile.fixture }

        model.setNewsletter(!TravellerProfile.fixture.wantsNewsletter)
        runCurrent()
        assertEquals(ProfileModel.SavedField.Newsletter, model.justSaved)

        advanceTimeBy(3_900)
        assertEquals(ProfileModel.SavedField.Newsletter, model.justSaved)
        advanceTimeBy(200)
        assertNull(model.justSaved)
    }

    private fun TestScope.advanceTimeBy(milliseconds: Long) {
        testScheduler.advanceTimeBy(milliseconds)
        testScheduler.runCurrent()
    }
}
