import MemoBookCore
@testable import MemoBookFeature
import MemoBookNetworking
import MemoBookPayments
import MemoBookRecording
import XCTest

/// Ce que le profil fait d'une adresse validée dans sa feuille : il la pose
/// tout de suite, l'envoie, et accuse réception. Sans simulateur — le modèle
/// reçoit ses deux fonctions, comme l'app les lui branche.
@MainActor
final class ProfileModelTests: XCTestCase {
    /// Un profil avec la liste des pays, et un double de `PATCH` qui rend ce
    /// qu'il reçoit — le nom du pays dérivé du code, comme le serveur.
    private func model(
        persist: @escaping (ProfileEdit) async throws -> TravellerProfile
    ) async -> ProfileModel {
        let model = ProfileModel(source: { .fixture }, persist: persist)
        await model.load()
        return model
    }

    private func echo(_ edit: ProfileEdit) -> TravellerProfile {
        var profile = TravellerProfile.fixture
        if var address = edit.address {
            address.countryName = profile.shippingCountry(code: address.country)?.name ?? address.country
            profile.address = address
        }
        return profile
    }

    func testSavingAnAddressWritesItAtOnceAndConfirmsOnceTheServerAnswered() async throws {
        var sent: ProfileEdit?
        let model = await model { edit in
            sent = edit
            return self.echo(edit)
        }

        let address = PostalAddress(street: "12 rue Neuve", postalCode: "1000", city: "Bruxelles", country: "BE")
        model.save(address: address)

        // Posée sur l'écran avant toute réponse, et déjà en toutes lettres :
        // le nom vient de la liste servie avec le profil, pas du serveur.
        XCTAssertEqual(model.profile?.address.singleLine, "12 rue Neuve, Bruxelles, Belgique")

        try await waitUntil { model.justSaved == .address }

        XCTAssertEqual(sent?.address?.country, "BE")
        XCTAssertEqual(model.profile?.address.countryName, "Belgique")
        XCTAssertNil(model.errorMessage)
    }

    /// Sans liste de pays, la feuille laisse taper un nom : le modèle le
    /// ramène au code quand la liste le connaît, pour que le serveur reçoive
    /// ce qu'il attend et que la ligne l'écrive proprement.
    func testATypedCountryNameBecomesItsCode() async throws {
        var sent: ProfileEdit?
        let model = await model { edit in
            sent = edit
            return self.echo(edit)
        }

        model.save(address: PostalAddress(street: "1 rue", postalCode: "75001", city: "Paris", country: "france"))
        try await waitUntil { sent != nil }

        XCTAssertEqual(sent?.address?.country, "FR")
        XCTAssertEqual(model.profile?.address.singleLine, "1 rue, Paris, France")
    }

    /// Un code hors liste n'est pas maquillé : la ligne le montre tel quel, et
    /// c'est le serveur qui refusera.
    func testAnUnknownCountryKeepsItsCode() async {
        let model = await model { self.echo($0) }

        model.save(address: PostalAddress(street: "1 rue", postalCode: "98000", city: "Monaco", country: "MC"))

        XCTAssertEqual(model.profile?.address.countryName, "MC")
    }

    func testSavingTheSameAddressSendsNothing() async {
        var calls = 0
        let model = await model { edit in
            calls += 1
            return self.echo(edit)
        }

        model.save(address: TravellerProfile.fixture.address)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(calls, 0)
        XCTAssertNil(model.justSaved)
    }

    /// Un refus du serveur laisse ce qui a été tapé à l'écran, avec le reproche
    /// — effacer sous les doigts serait pire qu'une panne.
    func testARefusalKeepsTheTypedAddressAndSaysWhy() async throws {
        struct Refused: LocalizedError {
            var errorDescription: String? { "Ce pays n'est pas encore livré." }
        }
        let model = await model { _ in throw Refused() }

        model.save(address: PostalAddress(street: "1 rue", postalCode: "98000", city: "Monaco", country: "MC"))
        try await waitUntil { model.errorMessage != nil }

        XCTAssertEqual(model.profile?.address.city, "Monaco")
        XCTAssertEqual(model.errorMessage, "Ce pays n'est pas encore livré.")
        XCTAssertNil(model.justSaved)
    }

    /// « Supprimer la photo » qui échoue le dit **sous le rond**, là où l'on a
    /// touché, et non au pied de la page (Hugo, 30/09/2026 : l'API rendait 404
    /// et rien ne bougeait à l'écran). La photo reste : c'est le profil relu
    /// qui fait foi.
    func testAFailedPhotoRemovalIsSaidUnderThePhotoAndKeepsIt() async {
        struct NotFound: LocalizedError {
            var errorDescription: String? { "Route introuvable." }
        }
        var withPhoto = TravellerProfile.fixture
        withPhoto.avatarUrl = URL(string: "https://api.test/v1/avatars/photo.jpg")
        let model = ProfileModel(source: { withPhoto }, deleteAvatar: { throw NotFound() })
        await model.load()

        await model.removeAvatar()

        XCTAssertEqual(model.avatarErrorMessage, "Route introuvable.")
        XCTAssertNil(model.errorMessage, "Le bandeau du bas de page, lui, reste pour le chargement.")
        XCTAssertEqual(model.profile?.avatarUrl, withPhoto.avatarUrl)
    }

    func testARemovedPhotoGivesBackTheInitials() async {
        var withPhoto = TravellerProfile.fixture
        withPhoto.avatarUrl = URL(string: "https://api.test/v1/avatars/photo.jpg")
        var withoutPhoto = withPhoto
        withoutPhoto.avatarUrl = nil
        let model = ProfileModel(source: { withPhoto }, deleteAvatar: { withoutPhoto })
        await model.load()

        await model.removeAvatar()

        XCTAssertNil(model.profile?.avatarUrl)
        XCTAssertNil(model.avatarErrorMessage)
        XCTAssertEqual(model.justSaved, .avatar)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            if clock.now > deadline {
                XCTFail("Condition non remplie en \(timeout)")
                throw TimedOut()
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private struct TimedOut: Error {}

    // MARK: - Un abonnement tenu par Apple (01/10/2026)

    /// Un abonné App Store, dans son mois payé.
    private func appStoreSubscriber() -> TravellerProfile {
        var profile = TravellerProfile.fixture
        profile.subscription.isActive = true
        profile.subscription.cancelledAt = nil
        profile.subscription.managedByAppStore = true
        profile.subscription.paidThrough = Date.now.addingTimeInterval(20 * 86_400)
        return profile
    }

    func testTheReasonLeavesWithoutClosingTheSubscription() async throws {
        // Apple seul résilie : la raison part, l'abonnement reste ouvert à
        // l'écran tant que la feuille d'iOS n'a rien coupé.
        var sent: SubscriptionCancellationReason?
        let subscriber = appStoreSubscriber()
        let model = ProfileModel(
            source: { subscriber },
            cancelSubscription: { reason in
                sent = reason
                return subscriber
            }
        )
        await model.load()

        model.recordCancellationReason(.tooExpensive)

        XCTAssertEqual(model.profile?.subscription.isActive, true)
        try await waitUntil { sent == .tooExpensive }
        XCTAssertEqual(model.profile?.subscription.isActive, true)
    }

    func testARenewalCutInIOSKeepsThePaidMonth() async {
        let subscriber = appStoreSubscriber()
        let model = ProfileModel(source: { subscriber })
        await model.load()

        model.acknowledgeAppStoreRenewal(false)

        XCTAssertEqual(model.profile?.subscription.isActive, false)
        XCTAssertNotNil(model.profile?.subscription.cancelledAt)
        // Le mois est réglé : l'illimité reste ouvert jusqu'à son terme.
        XCTAssertTrue(model.subscriptionGrantsAccess)

        model.acknowledgeAppStoreRenewal(true)
        XCTAssertEqual(model.profile?.subscription.isActive, true)
        XCTAssertNil(model.profile?.subscription.cancelledAt)
    }

    /// Souscrire passe l'écran à l'illimité tout de suite, sans attendre que
    /// le serveur relise l'achat — et sans rien d'autre à remettre à zéro : il
    /// n'y a plus d'essai gratuit à décompter (Hugo, 03/10/2026).
    func testSubscribingUnlocksTheUnlimitedAtOnce() async {
        let free = TravellerProfile.freeFixture
        let model = ProfileModel(source: { free })
        await model.load()
        XCTAssertEqual(model.profile?.isSubscriber, false)

        model.activateSubscription()

        XCTAssertEqual(model.profile?.isSubscriber, true)
        XCTAssertTrue(model.subscriptionGrantsAccess)
    }

    // MARK: - Exporter ses données

    private func receipt(alreadyRequested: Bool = false) -> DataExportReceipt {
        DataExportReceipt(
            email: "hugo@memobook.app",
            requestedAt: Date(timeIntervalSince1970: 1_790_870_000),
            expiresAt: Date(timeIntervalSince1970: 1_790_870_000 + 7 * 24 * 3600),
            alreadyRequested: alreadyRequested
        )
    }

    func testTheExportSaysWhereTheLinkWent() async {
        let sent = receipt()
        let model = ProfileModel(source: { .fixture }, exportData: { sent })
        await model.load()

        await model.requestDataExport()

        XCTAssertEqual(model.dataExport, .sent(sent))
    }

    /// Le refus du serveur est dit avec ses mots — « Ton compte n'a pas
    /// d'adresse… » — et la feuille reste sur la proposition.
    func testARefusedExportIsSaidInTheServerWords() async {
        let model = ProfileModel(
            source: { .fixture },
            exportData: {
                throw APIError.server(statusCode: 409, code: "no_email", message: "Ton compte n’a pas d’adresse e-mail.")
            }
        )

        await model.requestDataExport()

        XCTAssertEqual(model.dataExport, .failed("Ton compte n’a pas d’adresse e-mail."))
    }

    /// Un serveur qui ne connaît pas encore la route répond le 404 de Fastify,
    /// en anglais : la feuille dit autre chose.
    func testAServerWithoutTheRouteIsNotQuotedInEnglish() async {
        let model = ProfileModel(
            source: { .fixture },
            exportData: {
                throw APIError.server(
                    statusCode: 404,
                    code: "Not Found",
                    message: "Route POST:/v1/accounts/me/export not found"
                )
            }
        )

        await model.requestDataExport()

        XCTAssertEqual(model.dataExport, .failed(DataExportCopy.notYetAvailable))
    }

    func testClosingTheSheetGoesBackToTheOffer() async {
        let sent = receipt(alreadyRequested: true)
        let model = ProfileModel(source: { .fixture }, exportData: { sent })
        await model.requestDataExport()
        XCTAssertEqual(model.dataExport, .sent(sent))

        model.resetDataExport()

        XCTAssertEqual(model.dataExport, .idle)
    }

    /// « 1er », que le format de date ne sait pas écrire seul.
    func testTheExpiryReadsInFrench() {
        let noon = ISO8601DateFormatter.memoBookDate(from: "2026-10-01T12:00:00.000Z")!
        XCTAssertEqual(DataExportCopy.day(noon), "jeudi 1er octobre")
        XCTAssertEqual(
            DataExportCopy.sentParagraphs(receipt()).last,
            "Rien dans ta boîte d’ici quelques minutes ? Regarde dans tes indésirables."
        )
    }

    // MARK: - Le verdict du serveur (03/10/2026)

    /// Délai de grâce de facturation d'Apple : `isActive` faux, rien de
    /// résilié, et le serveur accorde l'illimité. Le profil le suit.
    func testABillingGracePeriodKeepsTheSubscriberScreen() async throws {
        let json = #"{ "price": 4.99, "interval": "month", "isActive": false, "isUnlimited": true, "managedByAppStore": true }"#
        var profile = TravellerProfile.fixture
        profile.subscription = try JSONDecoder.memoBook.decode(Subscription.self, from: Data(json.utf8))
        let served = profile
        let model = ProfileModel(source: { served })
        await model.load()

        XCTAssertEqual(model.profile?.isSubscriber, true)
        XCTAssertTrue(model.subscriptionGrantsAccess)
    }

    // MARK: - La session d'abonnement (03/10/2026)

    /// **Renouvellement coupé** (Hugo, 06/10/2026) : abonné jusqu'à la date
    /// de fin, puis plus du tout — partout, sans attendre une relecture.
    func testTheSessionLetsTheUnlimitedLapseAtItsDate() {
        let session = SubscriptionSession()
        let end = Date.now.addingTimeInterval(3_600)
        session.learn(isUnlimited: true, hasSubscribedBefore: true, endsAt: end)
        XCTAssertTrue(session.isUnlimited)
        XCTAssertEqual(session.endsAt, end)

        // Avant l'heure, rien ne bouge.
        session.expireIfDue(now: end.addingTimeInterval(-60))
        XCTAssertTrue(session.isUnlimited)

        let revision = session.revision
        session.expireIfDue(now: end.addingTimeInterval(1))
        XCTAssertFalse(session.isUnlimited)
        XCTAssertNil(session.endsAt)
        XCTAssertGreaterThan(session.revision, revision)
        // Le crédit servi la veille, qui disait « illimité », se relit sans.
        XCTAssertEqual(session.applied(to: DailyCredit(isUnlimited: true))?.isUnlimited, false)
        // Le paywall de retour, puisqu'il a été abonné.
        XCTAssertEqual(session.paywallVariant, .returning)

        // Le serveur relu dit qu'il s'est réabonné ailleurs : il fait foi.
        session.learn(isUnlimited: true, hasSubscribedBefore: true)
        XCTAssertTrue(session.isUnlimited)
        XCTAssertEqual(session.applied(to: DailyCredit(isUnlimited: true))?.isUnlimited, true)
    }

    /// Un accueil gardé en cache depuis la veille ne fait pas revivre un
    /// renouvellement coupé dont la date est passée.
    func testACachedHomeDoesNotReviveALapsedSubscription() {
        let session = SubscriptionSession()
        let traveller = Traveller(
            id: "t",
            firstName: "Camille",
            isUnlimited: true,
            hasSubscribedBefore: true,
            subscriptionState: .ending,
            subscriptionEndsAt: Date.now.addingTimeInterval(-60)
        )
        session.learn(traveller)
        XCTAssertFalse(session.isUnlimited)
        XCTAssertNil(session.endsAt)
    }

    /// Résilier dans l'app, avec un mois payé devant soi : l'illimité reste
    /// ouvert jusqu'à sa fin, puis tombe.
    func testACancellationGestureEndsWithThePaidMonth() {
        let session = SubscriptionSession()
        let end = Date.now.addingTimeInterval(86_400)
        session.record(isSubscribed: true, until: end)
        XCTAssertTrue(session.isUnlimited)

        session.expireIfDue(now: end.addingTimeInterval(1))
        XCTAssertFalse(session.isUnlimited)
        XCTAssertNil(session.override)
    }

    /// Un achat que le serveur n'a jamais confirmé, et qu'Apple ne tient plus
    /// (remboursé, révoqué) : le geste rend la main.
    func testAnUnconfirmedPurchaseAppleNoLongerHoldsIsWithdrawn() {
        let session = SubscriptionSession()
        session.learn(isUnlimited: false, hasSubscribedBefore: false)
        session.record(isSubscribed: true)
        XCTAssertTrue(session.isUnlimited)

        session.withdrawUnconfirmedPurchase()
        XCTAssertFalse(session.isUnlimited)
        XCTAssertNil(session.override)
    }

    /// Déconnexion, session refusée, compte supprimé : ce que la session
    /// savait de A ne passe pas à B.
    func testTheSessionForgetsTheAccountItServed() {
        let session = SubscriptionSession()
        session.record(isSubscribed: true)
        session.learn(isUnlimited: false, hasSubscribedBefore: true)

        session.reset()

        XCTAssertNil(session.override)
        XCTAssertNil(session.known)
        XCTAssertFalse(session.isUnlimited)
        XCTAssertEqual(session.paywallVariant, .firstTime)
        XCTAssertEqual(session.applied(to: DailyCredit())?.isUnlimited, false)
    }

    /// Le geste a le dernier mot sur ce qui a été servi avant lui, et rend la
    /// main dès que le serveur dit la même chose : l'échéance qu'il annonce
    /// ensuite fait foi.
    func testTheGestureGivesWayOnceTheServerAgrees() {
        let session = SubscriptionSession()
        session.record(isSubscribed: true)

        // Un serveur qui n'a pas encore reçu l'achat ne lève pas le geste.
        session.learn(isUnlimited: false, hasSubscribedBefore: false)
        XCTAssertEqual(session.override, true)
        XCTAssertTrue(session.isUnlimited)

        // Il le confirme : le geste rend la main…
        session.learn(isUnlimited: true, hasSubscribedBefore: true)
        XCTAssertNil(session.override)

        // … et le mois payé qui s'achève se voit, crédit compris.
        session.learn(isUnlimited: false, hasSubscribedBefore: true)
        XCTAssertFalse(session.isUnlimited)
        XCTAssertEqual(session.applied(to: DailyCredit(isUnlimited: false))?.isUnlimited, false)
        XCTAssertEqual(session.paywallVariant, .returning)
    }

    // MARK: - Les textes de l'abonnement (03/10/2026)

    /// Un abonné de l'ancienne formule hebdomadaire a payé une semaine, pas un
    /// mois — et les phrases s'accordent.
    func testAWeeklySubscriberReadsWeekWhenCancelling() throws {
        let end = Date(timeIntervalSince1970: 1_791_000_000)

        let keepGoing = SubscriptionCopy.keepGoingParagraphs(tripTitle: nil, graceEnd: end, interval: .week)
        XCTAssertTrue(keepGoing[1].contains("la fin de la semaine déjà réglée"), keepGoing[1])
        let reason = try XCTUnwrap(SubscriptionCopy.reasonParagraphs(graceEnd: end, interval: .week).last)
        XCTAssertTrue(reason.hasPrefix("Ta semaine est déjà réglée : "), reason)
        XCTAssertTrue(
            SubscriptionCopy.doneParagraphs(graceEnd: end, interval: .week)[1].hasPrefix("Ta semaine est réglée jusqu’au")
        )
        XCTAssertTrue(
            SubscriptionCopy.doneParagraphs(graceEnd: end, interval: .month)[1].hasPrefix("Ton mois est réglé jusqu’au")
        )
        // L'accueil ne connaît pas la période : l'alerte de fin ne la nomme pas.
        XCTAssertFalse(SubscriptionCopy.endedMessage(tripTitle: "Rome").contains("mois"))
        XCTAssertFalse(SubscriptionCopy.endedMessage(tripTitle: nil).contains("mois"))
    }

    /// Ni l'app ni le serveur ne tiennent le dernier jour payé en entier.
    func testTheGraceDateIsNotSaidInclusive() {
        let end = Date(timeIntervalSince1970: 1_791_000_000)
        XCTAssertFalse(SubscriptionCopy.graceSubtitle(until: end).contains("inclus"))
        XCTAssertFalse(SubscriptionCopy.reasonParagraphs(graceEnd: end).joined().contains("inclus"))
    }

    /// Délai de grâce de facturation d'Apple (`past_due`) : rien n'a été
    /// encaissé, et le serveur met la fin du délai dans `paidThrough`. Aucune
    /// des trois feuilles de la résiliation ne dit « réglé ».
    func testABillingRetryIsNeverCalledPaid() throws {
        let retrying = Subscription(
            price: 4.99,
            isActive: false,
            paidThrough: .now.addingTimeInterval(16 * 86_400),
            managedByAppStore: true,
            servedIsUnlimited: true
        )
        XCTAssertTrue(SubscriptionSheet.isBillingRetry(retrying))
        let graceEnd = retrying.isWithinPaidPeriod() ? retrying.paidThrough : nil
        let paidAhead = SubscriptionSheet.paidAhead(of: retrying, graceEnd: graceEnd, isBillingRetry: true)
        XCTAssertEqual(paidAhead, .billingRetry)

        let all =
            SubscriptionCopy.keepGoingParagraphs(tripTitle: "Rome", graceEnd: graceEnd, paidAhead: paidAhead)
            + SubscriptionCopy.reasonParagraphs(graceEnd: graceEnd, paidAhead: paidAhead)
            + SubscriptionCopy.doneParagraphs(graceEnd: graceEnd, paidAhead: paidAhead)
        for paragraph in all {
            XCTAssertFalse(paragraph.contains("réglé"), paragraph)
        }
        XCTAssertTrue(all.contains { $0.contains("prélèvement") })

        // Une vraie résiliation (`cancelledAt`) n'est pas un prélèvement raté.
        var cancelled = retrying
        cancelled.cancelledAt = .now
        XCTAssertFalse(SubscriptionSheet.isBillingRetry(cancelled))
    }

    // MARK: - Résilier chez Apple un achat que le serveur n'a pas reçu (03/10/2026)

    /// L'achat est encaissé par Apple, le serveur n'en sait rien
    /// (`awaitingServer`) : on coupe le renouvellement dans la feuille
    /// d'Apple. La ligne du serveur n'est pas retouchée, la session garde
    /// l'illimité — Apple honore le mois payé —, et l'écran remettra la
    /// transaction puis relira.
    func testCuttingTheRenewalOfAPurchaseTheServerHasNotSeenKeepsThePaidPeriod() async {
        let model = ProfileModel(source: { .freeFixture })
        await model.load()
        let session = SubscriptionSession()
        session.record(isSubscribed: true)
        XCTAssertTrue(model.isHeldByAppleOnly(session))

        XCTAssertTrue(model.settleAppStoreRenewal(false, session: session))

        XCTAssertEqual(session.override, true)
        XCTAssertTrue(session.isUnlimited)
        XCTAssertNil(model.profile?.subscription.cancelledAt, "La ligne du serveur n'a rien à résilier.")
        XCTAssertEqual(model.profile?.subscription, TravellerProfile.freeFixture.subscription)

        // Et la dernière feuille ne dit pas « s'arrête aujourd'hui » d'un
        // abonnement tenu par Apple dont on ne connaît pas la fin.
        let held = Subscription(price: 4.99, isActive: true, managedByAppStore: true)
        let paidAhead = SubscriptionSheet.paidAhead(of: held, graceEnd: nil, isBillingRetry: false)
        XCTAssertEqual(paidAhead, .heldByApple)
        let done = SubscriptionCopy.doneParagraphs(graceEnd: nil, paidAhead: paidAhead)
        XCTAssertFalse(done.joined().contains("aujourd’hui"), done.joined())
        XCTAssertFalse(
            SubscriptionCopy.keepGoingParagraphs(tripTitle: nil, graceEnd: nil, paidAhead: paidAhead)[1]
                .hasPrefix("Si tu coupes maintenant, tu retrouves")
        )
    }

    /// Le renouvellement est resté armé : rien ne retouche le profil sur
    /// place, et son écho ne lève pas le geste tant que le serveur n'a pas
    /// confirmé l'achat.
    func testKeepingTheRenewalOfAPurchaseTheServerHasNotSeenWaitsForTheServer() async throws {
        let model = ProfileModel(source: { .freeFixture })
        await model.load()
        let session = SubscriptionSession()
        session.record(isSubscribed: true)

        XCTAssertTrue(model.settleAppStoreRenewal(true, session: session))

        XCTAssertEqual(model.profile?.subscription.isActive, false)
        session.learn(try XCTUnwrap(model.profile))
        XCTAssertEqual(session.override, true, "Le serveur n'a rien confirmé : le geste tient.")
    }

    /// Un abonnement que le serveur connaît suit, lui, la règle de toujours :
    /// la ligne retouchée sur place, et l'accès réel retenu par la session.
    func testCuttingTheRenewalOfAKnownSubscriptionIsAcknowledged() async {
        let model = ProfileModel(source: { .subscriberFixture })
        await model.load()
        let session = SubscriptionSession()

        XCTAssertFalse(model.settleAppStoreRenewal(false, session: session))

        XCTAssertNotNil(model.profile?.subscription.cancelledAt)
        XCTAssertEqual(model.profile?.subscription.isActive, false)
        XCTAssertEqual(session.override, model.subscriptionGrantsAccess)
    }

    /// Seul qui a un abonnement App Store à couper lit qu'il faut le couper.
    func testOnlyARenewingSubscriberIsToldToCutIt() {
        let free = DeleteAccountCopy.body(hasOngoingTrip: false, mentionsSubscription: false)
        XCTAssertFalse(free.contains("abonnement"), free)
        XCTAssertEqual(free, DeleteAccountCopy.erasure)

        let subscriber = DeleteAccountCopy.body(hasOngoingTrip: true, mentionsSubscription: true)
        XCTAssertTrue(subscriber.contains(DeleteAccountCopy.subscriptionWarning))
        XCTAssertTrue(subscriber.hasSuffix(DeleteAccountCopy.closeTripInstead))
    }

    /// « 4,99 €/mois » ne se coupe jamais en « 4,99 €/ » puis « mois ».
    func testTheOfferPriceNeverBreaks() {
        let renewal = PaywallCopy.offerFootnotePrice(price: "4,99 €", period: "mois")
        XCTAssertFalse(renewal.price.contains(" "))
        XCTAssertEqual(
            renewal.price
                .replacingOccurrences(of: "\u{2060}", with: "")
                .replacingOccurrences(of: "\u{00A0}", with: " "),
            "4,99 €/mois"
        )
    }

    // MARK: - La jauge du crédit (recette du 03/10/2026)

    /// Pleine au matin, elle se vide, et ne garde rien à zéro — le chiffre
    /// d'à côté dit le reste, la barre aussi.
    func testTheGaugeShowsWhatIsLeft() {
        XCTAssertEqual(DailyCredit(usedMs: 0).gaugeFraction, 1)
        XCTAssertEqual(DailyCredit(usedMs: 60_000).gaugeFraction, 0.8, accuracy: 0.0001)
        XCTAssertEqual(DailyCredit(usedMs: DailyCredit.Catalog.limitMs).gaugeFraction, 0)
        XCTAssertEqual(DailyCredit(limitMs: 0).gaugeFraction, 0)
        XCTAssertEqual(
            DailyCreditCopy.Sheet.gaugeAccessibilityValue(DailyCredit(usedMs: 100_000)),
            "3 min 20 sur 5 min"
        )
    }

    // MARK: - Le crédit du jour de l'accueil (03/10/2026)

    private func homeFeed(credit: DailyCredit) -> HomeFeed {
        HomeFeed(
            traveller: Traveller(id: "camille", firstName: "Camille"),
            trips: [Trip(id: "rome", title: "Rome", stage: .ongoing, dailyCredit: credit)]
        )
    }

    private func voice(seconds: TimeInterval) -> RecordedAudio {
        RecordedAudio(data: Data([0]), filename: "vocal.m4a", mimeType: "audio/m4a", duration: seconds, recordedAt: .now)
    }

    /// Épuisé hier soir, relu du cache ce matin hors ligne : le micro de
    /// l'accueil s'ouvre, le crédit s'est rechargé à minuit.
    func testYesterdaysExhaustedCreditIsRechargedFromTheCache() async {
        let yesterday = DailyCredit(
            usedMs: DailyCredit.Catalog.limitMs,
            day: "2026-10-02",
            resetsAt: .now.addingTimeInterval(-3_600)
        )
        let cached = homeFeed(credit: yesterday)
        let model = HomeModel(source: { throw URLError(.notConnectedToInternet) }, cached: { cached })

        await model.load()

        XCTAssertEqual(model.ongoingTripCredit?.isExhausted, false)
        XCTAssertEqual(model.ongoingTripCredit?.remainingMs, DailyCredit.Catalog.limitMs)
    }

    /// Le crédit d'aujourd'hui, lui, reste épuisé jusqu'à minuit.
    func testTodaysExhaustedCreditStaysExhausted() async {
        let today = DailyCredit(usedMs: DailyCredit.Catalog.limitMs, resetsAt: .now.addingTimeInterval(3_600))
        let served = homeFeed(credit: today)
        let model = HomeModel(source: { served })

        await model.load()

        XCTAssertEqual(model.ongoingTripCredit?.isExhausted, true)
    }

    /// Un vocal de l'accueil mis en file compte tout de suite : le suivant ne
    /// part pas d'un reste trop haut.
    func testAQueuedHomeVoiceCountsAtOnce() async {
        let fresh = DailyCredit(resetsAt: .now.addingTimeInterval(3_600))
        let served = homeFeed(credit: fresh)
        let outbox = RecordingOutbox(send: { _, _ in
            throw APIError.transport(URLError(.notConnectedToInternet), url: nil)
        })
        let model = HomeModel(source: { served }, outbox: outbox)
        await model.load()

        await model.upload(voice(seconds: 90))

        XCTAssertEqual(model.ongoingTripCredit?.usedMs, 90_000)
    }

    /// Arrivé, le vocal rapporte le crédit d'après son tour : c'est lui qui
    /// fait foi, même si la relecture de l'accueil échoue ensuite.
    func testADeliveredHomeVoiceTakesTheCreditOfItsReceipt() async {
        let fresh = DailyCredit(resetsAt: .now.addingTimeInterval(3_600))
        let served = homeFeed(credit: fresh)
        var reads = 0
        let outbox = RecordingOutbox(send: { _, _ in
            ChatTurnReceipt(messages: [], turn: .idle, now: .now, dailyCredit: DailyCredit(usedMs: 200_000))
        })
        let model = HomeModel(
            source: {
                reads += 1
                if reads > 1 { throw URLError(.timedOut) }
                return served
            },
            outbox: outbox
        )
        await model.load()

        await model.upload(voice(seconds: 30))

        XCTAssertEqual(model.ongoingTripCredit?.usedMs, 200_000)
    }

    /// Hors ligne, la relecture de l'accueil — au retour de la conversation
    /// qui suit chaque vocal — rend le cache **sans lever**, comme
    /// `cachedSource` dans l'app : le vocal en file reste décompté, et le
    /// suivant part du bon reste. Relu deux fois, il ne compte qu'une fois.
    func testAQueuedHomeVoiceStillCountsWhenTheReadReturnsTheCache() async {
        let fresh = DailyCredit(resetsAt: .now.addingTimeInterval(3_600))
        let cachedFeed = homeFeed(credit: fresh)
        let outbox = RecordingOutbox(send: { _, _ in
            throw APIError.transport(URLError(.notConnectedToInternet), url: nil)
        })
        let model = HomeModel(source: { cachedFeed }, outbox: outbox)
        await model.load()

        await model.upload(voice(seconds: 180))
        await model.load()
        XCTAssertEqual(model.ongoingTripCredit?.usedMs, 180_000)

        await model.load()
        XCTAssertEqual(model.ongoingTripCredit?.usedMs, 180_000)
    }

    // MARK: - Le bac à sable (03/10/2026)

    /// L'achat du bac à sable passe par la même remise que le vrai : le double
    /// d'API l'apprend, et cesse de compter.
    func testASandboxPurchaseIsDeliveredLikeARealOne() async {
        let store = StubSubscriptionStore()
        let received = ReceivedTransactions()

        let outcome = await store.purchase(appAccountToken: nil) { signed in await received.add(signed.jws) }
        XCTAssertEqual(outcome, .subscribed)
        let count = await received.count
        XCTAssertEqual(count, 1)

        let refused = await store.purchase(appAccountToken: nil) { _ in
            throw TransactionRefused(message: "Cet achat appartient à un autre compte.")
        }
        XCTAssertEqual(refused, .failed("Cet achat appartient à un autre compte."))

        let unreachable = await store.purchase(appAccountToken: nil) { _ in throw URLError(.timedOut) }
        XCTAssertEqual(unreachable, .awaitingServer)
    }

    /// Le double du bac à sable change de jour à **minuit local**, comme l'app
    /// recharge le crédit : à 0 h 30 à Paris, c'est déjà le 3, même si l'UTC
    /// dit encore le 2.
    func testTheSandboxCreditTurnsTheDayAtLocalMidnight() throws {
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        let halfPastMidnight = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-02T22:30:00Z"))
        XCTAssertEqual(SandboxCredit.today(now: halfPastMidnight, calendar: paris), "2026-10-03")
    }

    #if DEBUG
        /// « Jamais abonné » : ni abonnement, ni passé d'abonné — le paywall
        /// s'ouvre sur la découverte en trois écrans.
        func testTheNeverSubscribedPersonaOpensTheDiscovery() {
            let persona = SandboxPersona.neverSubscribed
            let traveller = persona.applied(
                to: Traveller(id: "camille", firstName: "Camille", isUnlimited: true, hasSubscribedBefore: true)
            )
            XCTAssertFalse(traveller.isUnlimited)
            XCTAssertFalse(traveller.hasSubscribedBefore)

            let profile = persona.applied(to: TravellerProfile.fixture)
            XCTAssertFalse(profile.isSubscriber)
            XCTAssertFalse(profile.subscription.hasEndedBefore)

            let session = SubscriptionSession()
            session.record(isSubscribed: false)
            session.reset()
            session.learn(traveller)
            session.learn(profile)
            XCTAssertEqual(session.paywallVariant, .firstTime)
        }
    #endif
}

/// Les transactions remises par le faux magasin, comptées hors de l'acteur
/// principal : la remise est `@Sendable`.
private actor ReceivedTransactions {
    private var jws: [String] = []
    var count: Int { jws.count }
    func add(_ value: String) { jws.append(value) }
}
