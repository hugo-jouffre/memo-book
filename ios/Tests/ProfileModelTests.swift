import MemoBookCore
@testable import MemoBookFeature
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

    /// Un abonné App Store, dans sa semaine payée.
    private func appStoreSubscriber() -> TravellerProfile {
        var profile = TravellerProfile.fixture
        profile.subscription.isActive = true
        profile.subscription.cancelledAt = nil
        profile.subscription.managedByAppStore = true
        profile.subscription.paidThrough = Date.now.addingTimeInterval(5 * 86_400)
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

    func testARenewalCutInIOSKeepsThePaidWeek() async {
        let subscriber = appStoreSubscriber()
        let model = ProfileModel(source: { subscriber })
        await model.load()

        model.acknowledgeAppStoreRenewal(false)

        XCTAssertEqual(model.profile?.subscription.isActive, false)
        XCTAssertNotNil(model.profile?.subscription.cancelledAt)
        // La semaine est réglée : le micro reste ouvert jusqu'à son terme.
        XCTAssertTrue(model.subscriptionGrantsAccess)

        model.acknowledgeAppStoreRenewal(true)
        XCTAssertEqual(model.profile?.subscription.isActive, true)
        XCTAssertNil(model.profile?.subscription.cancelledAt)
    }
}
