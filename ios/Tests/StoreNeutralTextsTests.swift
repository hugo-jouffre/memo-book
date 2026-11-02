import MemoBookCore
import XCTest

/// **Un seul texte pour les deux stores** (Clara, 02/11/2026). Les CGU, la
/// politique de confidentialité et la FAQ ne sont plus écrites du point de vue
/// d'un téléphone : chaque phrase qui parle d'achat, de résiliation ou de
/// remboursement nomme Android *et* iPhone.
///
/// Ce fichier est le jumeau de `StoreNeutralTextsTest.kt` : les mêmes
/// assertions, sur les mêmes phrases. Tant que les deux passent, les deux apps
/// disent mot pour mot la même chose, et memobook.fr n'a qu'un texte à
/// publier.
final class StoreNeutralTextsTests: XCTestCase {
    private func texts(_ block: LegalBlock) -> [String] {
        switch block {
        case let .heading(text): return [text]
        case let .paragraph(text): return [text]
        case let .lines(lines): return lines
        case let .bullets(lines): return lines
        }
    }

    private var subscriptionChapter: [String] {
        TermsOfUse.subscription.blocks.flatMap(texts)
    }

    private var faqSentences: [String] {
        Faq.entries.flatMap { [$0.question] + $0.answer() }
    }

    /// Payer, résilier, se faire rembourser : les deux stores, à chaque fois.
    func testEverySubscriptionRuleNamesBothStores() throws {
        let paying = try XCTUnwrap(subscriptionChapter.first { $0.contains("prélevé") })
        XCTAssertTrue(paying.contains("Google Play") && paying.contains("App Store"), paying)

        let cancelling = try XCTUnwrap(subscriptionChapter.first { $0.contains("gérer et résilier") })
        XCTAssertTrue(cancelling.contains("Play Store") && cancelling.contains("compte Apple"), cancelling)

        let refunding = try XCTUnwrap(subscriptionChapter.first { $0.contains("remboursement au prorata") })
        XCTAssertTrue(refunding.contains("Google Play") && refunding.contains("reportaproblem"), refunding)
    }

    /// Un abonnement suit le compte, pas le téléphone.
    func testASubscriptionFollowsTheAccountAcrossPhones() {
        XCTAssertTrue(
            subscriptionChapter.contains {
                $0.contains("store où il a été souscrit") && $0.contains("même compte MemoBook")
            },
            "\(subscriptionChapter)"
        )
    }

    /// Aucune phrase ne traite un store comme **le** store de l'app : dès
    /// qu'un texte nomme l'un, il nomme l'autre. C'est la règle qui empêche
    /// les deux versions de se reformer.
    func testNoSentencePrefersOneStore() {
        // La liste des destinataires est faite d'une société par ligne : elle
        // ne peut pas nommer les deux à la fois, et
        // `testBothStoresAreRecipients` la tient à part.
        let chapters = (TermsOfUse.document.chapters + PrivacyPolicy.document.chapters)
            .filter { $0.id != PrivacyPolicy.recipients.id }
        let sentences = chapters.flatMap { $0.blocks.flatMap(texts) } + faqSentences

        for sentence in sentences {
            // « Apple » et « Google » seuls nomment aussi deux fournisseurs de
            // connexion : seuls les mots qui désignent un store comptent ici.
            let saysApple = sentence.contains("App Store") || sentence.contains("iPhone")
            let saysGoogle = sentence.contains("Google Play") || sentence.contains("Play Store")
                || sentence.contains("Android")
            if !saysApple && !saysGoogle { continue }
            if sentence.contains("reconnaissance vocale") { continue } // propre à l'iPhone (2.3)
            XCTAssertTrue(saysApple && saysGoogle, "une seule plateforme nommée : \(sentence)")
        }
    }

    /// Les deux vendeurs d'abonnement sont déclarés comme destinataires.
    func testBothStoresAreRecipients() {
        let recipients = PrivacyPolicy.recipients.blocks.flatMap(texts)
        XCTAssertTrue(recipients.contains { $0.hasPrefix("Apple") && $0.contains("souscrit sur un iPhone") })
        XCTAssertTrue(recipients.contains { $0.contains("Google Play") && $0.contains("Android") })
    }

    /// Le sélecteur de photos est celui du téléphone, quel qu'il soit.
    func testThePhotoAnswerSpeaksOfThePhone() {
        let answer = Faq.entry(id: "faq.photos.provenance")?.answer() ?? []
        XCTAssertTrue(answer.contains { $0.contains("ton téléphone") }, "\(answer)")
        XCTAssertFalse(answer.contains { $0.contains("de ton iPhone.") }, "\(answer)")
    }
}
