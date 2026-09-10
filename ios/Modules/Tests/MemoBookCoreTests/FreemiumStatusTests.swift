import Testing

@testable import MemoBookCore

// Le palier freemium vit dans `MemoBookFeature`, mais ce qu'il décide se teste
// sans écran : ce sont trois règles de lecture, et elles se cassent en silence.

@Suite("Palier freemium")
struct FreemiumStatusTests {
    // MARK: Le voyageur de l'accueil

    @Test("Sans quota, le serveur dit « abonné »")
    func travellerWithoutQuotaIsSubscriber() {
        let traveller = Traveller(id: "t", firstName: "Camille")
        #expect(traveller.freemiumStatus(override: nil) == .subscriber)
        #expect(traveller.freemiumStatus(override: nil).homePillLabel == nil)
    }

    @Test("Rien de consommé : on annonce un cadeau, pas un solde")
    func untouchedQuotaAnnouncesAGift() {
        let traveller = Traveller(id: "t", firstName: "Camille", offeredSteps: 3, remainingSteps: 3)
        #expect(traveller.freemiumStatus(override: nil).homePillLabel == "3 étapes offertes")
    }

    @Test("Quota entamé : on annonce un solde")
    func startedQuotaAnnouncesABalance() {
        let traveller = Traveller(id: "t", firstName: "Camille", offeredSteps: 3, remainingSteps: 2)
        #expect(traveller.freemiumStatus(override: nil).homePillLabel == "2 étapes restantes")
    }

    @Test("Quota épuisé : on propose l'abonnement")
    func exhaustedQuotaOffersTheSubscription() {
        let traveller = Traveller(id: "t", firstName: "Camille", offeredSteps: 3, remainingSteps: 0)
        #expect(traveller.freemiumStatus(override: nil) == .limitReached)
        #expect(traveller.freemiumStatus(override: nil).homePillLabel == "Abonne-toi")
    }

    // MARK: Résilier depuis le profil change l'accueil

    /// Le cœur de la demande : **résilier ne rend pas de crédit.** Le serveur
    /// croit encore l'accueil abonné et lui a laissé son ancien quota ; le lui
    /// rendre ferait repartir un décompte au lieu de proposer l'offre.
    @Test("Après résiliation, l'accueil propose l'abonnement même s'il reste un vieux quota")
    func cancellingNeverRestoresACredit() {
        // Ce que `SubscriptionSession.record(isSubscribed: false)` pose.
        let traveller = Traveller(id: "t", firstName: "Camille", offeredSteps: 3, remainingSteps: 2)
        let status = traveller.freemiumStatus(override: .limitReached)

        #expect(status == .limitReached)
        #expect(status.homePillLabel == "Abonne-toi")
        #expect(status.wantsSubscription)
    }

    @Test("Après souscription, l'accueil se tait, quoi qu'en dise le quota")
    func subscribingSilencesTheHomePill() {
        let traveller = Traveller(id: "t", firstName: "Camille", offeredSteps: 3, remainingSteps: 2)
        let status = traveller.freemiumStatus(override: .subscriber)

        #expect(status == .subscriber)
        #expect(status.homePillLabel == nil)
        #expect(!status.wantsSubscription)
    }

    // MARK: Le profil

    @Test("Abonné : pas de bouton lime, et la pastille dit le statut")
    func subscribedProfileHidesTheOffer() {
        var profile = TravellerProfile(fullName: "Maylis Garde")
        profile.subscription = Subscription(weeklyPrice: 1.99, isActive: true)

        #expect(profile.freemiumStatus(override: nil) == .subscriber)
        #expect(!profile.freemiumStatus(override: nil).wantsSubscription)
        #expect(profile.freemiumStatus(override: nil).profilePillLabel == "Abonné")
    }

    @Test("Résilié : le bouton lime revient et la pastille invite")
    func cancelledProfileShowsTheOfferAgain() {
        var profile = TravellerProfile(fullName: "Maylis Garde")
        profile.subscription = Subscription(weeklyPrice: 1.99, isActive: false)

        #expect(profile.freemiumStatus(override: nil) == .limitReached)
        #expect(profile.freemiumStatus(override: nil).wantsSubscription)
        #expect(profile.freemiumStatus(override: nil).profilePillLabel == "Abonne-toi")
    }
}
