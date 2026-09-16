import Foundation
import XCTest

@testable import MemoBookCore

/// La **recherche du support** : ce qui répond à ce qu'on tape.
///
/// Elle se teste ici et non à l'écran parce que c'est une règle, pas un
/// dessin — et parce que les quarante-cinq questions sont dans le binaire.
final class FaqSearchTests: XCTestCase {
    func testAnEmptyQueryKeepsEverything() {
        let query = FaqQuery("   ")
        XCTAssertTrue(query.isEmpty)
        for category in Faq.topics {
            XCTAssertEqual(category.filtered(by: query)?.entries.count, category.entries.count)
        }
    }

    func testIgnoresCaseAndAccents() {
        // On tape « reglage » et on trouve « réglage » : personne ne pense à
        // faire marcher ça, et tout le monde le remarque quand ça ne marche
        // pas.
        let query = FaqQuery("CARNET")
        XCTAssertTrue(query.matches("Où est mon carnet ?"))
        XCTAssertTrue(FaqQuery("impression").matches("L’imprèssion du carnet"))
    }

    func testEveryWordNarrowsTheResults() {
        // Ajouter un mot **réduit**, comme partout ailleurs.
        let one = FaqQuery("carnet")
        let two = FaqQuery("carnet papier")

        XCTAssertTrue(one.matches("Le carnet arrive en combien de temps ?"))
        XCTAssertFalse(two.matches("Le carnet arrive en combien de temps ?"))
        XCTAssertTrue(two.matches("Le papier du carnet est-il recyclé ?"))
    }

    func testSearchesInsideTheAnswerAndNotOnlyTheQuestion() {
        // Quelqu'un qui tape un mot précis cherche une phrase, pas un titre.
        // On prend une question au hasard et un mot de sa réponse.
        let entry = try! XCTUnwrap(Faq.entries.first { $0.answer.contains { $0.count > 40 } })
        let firstAnswer = try! XCTUnwrap(entry.answer(with: .current).first)
        let word = try! XCTUnwrap(
            firstAnswer
                .split(whereSeparator: { !$0.isLetter })
                .first { $0.count > 6 }
                .map(String.init)
        )

        XCTAssertTrue(entry.matches(FaqQuery(word)), "« \(word) » devrait trouver sa réponse")
    }

    func testACategoryTitleBringsItsWholePack() {
        // On cherche souvent le rayon avant l'article.
        let photos = try! XCTUnwrap(Faq.topics.first { $0.title.localizedCaseInsensitiveContains("photo") })
        let filtered = photos.filtered(by: FaqQuery("photo"))
        XCTAssertEqual(filtered?.entries.count, photos.entries.count)
    }

    func testAPackWithNothingToSayDisappears() {
        // Un titre de section sans lignes dessous se lit comme un écran cassé.
        let nonsense = FaqQuery("zzzzqqq")
        for category in Faq.topics {
            XCTAssertNil(category.filtered(by: nonsense))
        }
    }

    func testVariablesAreResolvedBeforeComparing() {
        // On doit pouvoir trouver « 16 » alors que le texte dit
        // `{{nb_pages_min}}`.
        let entry = FaqEntry(
            id: "faq.test.pages",
            question: "Combien de pages minimum ?",
            answer: ["Un Carnet relié fait au moins {{nb_pages_min}} pages."]
        )
        XCTAssertTrue(entry.matches(FaqQuery("16")))
    }
}
