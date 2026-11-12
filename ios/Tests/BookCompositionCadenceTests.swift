@testable import MemoBookFeature
import XCTest

/// **Le rythme de la page qui se monte** (Hugo, 10/11/2026) — « améliorer
/// l'animation de changement de la mise en page PDF pour la rendre plus
/// longue, plus lente, plus logique (ligne par ligne) ».
///
/// Une chorégraphie ne se teste pas à l'œil une fois et pour toutes : c'est une
/// table de nombres, et c'est exactement ce qui se dérègle sans bruit quand on
/// déplace une pièce. Ces cas tiennent les quatre promesses faites à l'écran —
/// elle est longue, les lignes s'écrivent **l'une après l'autre**, rien n'est
/// encore en vol à la fin, et seul ce qu'on colle arrive de l'extérieur.
final class BookCompositionCadenceTests: XCTestCase {
    /// Les huit lignes de texte, dans l'ordre où elles s'écrivent.
    private var textLines: [BookCompositionPiece] {
        BookCompositionPiece.all
            .filter { $0.kind == .bar && $0.frame.minY > 0.2 }
            .sorted { $0.start < $1.start }
    }

    // MARK: - Plus longue

    func testThePageTakesAboutTenSecondsToAssemble() {
        // Elle en prenait 4,2, et c'est ce qui la faisait passer pour une
        // vignette qui clignote. On ne fige pas la valeur exacte — c'est un
        // réglage — mais le plancher, lui, est une promesse.
        XCTAssertGreaterThan(BookCompositionPiece.timeline, 9)
        XCTAssertLessThan(BookCompositionPiece.timeline, 14)
        // Le plancher de l'attente du modèle suit la chorégraphie, sans que
        // personne ait à recopier le nombre.
        XCTAssertEqual(BookCompositionLoop.assembly, BookCompositionPiece.timeline, accuracy: 0.001)
    }

    // MARK: - Ligne par ligne

    func testEachTextLineIsFinishedBeforeTheNextOneStarts() throws {
        let lines = textLines
        XCTAssertEqual(lines.count, 8)

        for (previous, next) in zip(lines, lines.dropFirst()) {
            // À la seconde où la suivante part, la précédente est **écrite** :
            // c'est toute la différence entre « ligne par ligne » et un bloc
            // qui se remplit.
            let whenNextStarts = next.start / BookCompositionPiece.timeline
            XCTAssertEqual(
                BookCompositionPiece.settled(previous, at: whenNextStarts),
                1,
                accuracy: 0.001,
                "La ligne partie à \(previous.start) s n'est pas finie quand celle de \(next.start) s commence."
            )
            // Et elles ne partent pas toutes en même temps : un demi-pas au
            // moins les sépare, sans quoi l'œil ne suit pas.
            XCTAssertGreaterThan(next.start - previous.start, 0.4)
        }
    }

    func testATextLineWritesItselfInsteadOfFlyingIn() {
        for line in textLines {
            guard case .written = line.arrival else {
                return XCTFail("Une ligne de texte doit s'écrire, pas arriver du hors-cadre.")
            }
            XCTAssertEqual(line.rotation, 0)
        }
    }

    // MARK: - Ce qui arrive d'ailleurs

    func testOnlyGluedPiecesTravelAndLean() {
        for piece in BookCompositionPiece.all where piece.rotation != 0 {
            guard case .glued = piece.arrival else {
                return XCTFail("Seul un élément collé penche — \(piece.kind) ne devrait pas.")
            }
        }
        // La carte, la photo et le tampon : trois pièces collées, et elles
        // arrivent **après** le texte, parce qu'on colle sur une page écrite.
        let glued = BookCompositionPiece.all.filter {
            if case .glued = $0.arrival, $0.kind != .bookmark { return true }
            return false
        }
        XCTAssertEqual(glued.count, 3)
        guard let lastLine = textLines.last else { return XCTFail("Pas de ligne de texte.") }
        for piece in glued {
            XCTAssertGreaterThanOrEqual(piece.start, lastLine.start + lastLine.span)
        }
    }

    // MARK: - Les bornes

    func testNothingHasMovedAtZeroAndEverythingIsSettledAtOne() {
        for piece in BookCompositionPiece.all {
            XCTAssertEqual(BookCompositionPiece.settled(piece, at: 0), 0, accuracy: 0.001)
            // Une pièce encore en vol à `progress == 1` ferait sauter le
            // passage à l'aperçu : la page doit être **exactement** finie.
            XCTAssertEqual(BookCompositionPiece.settled(piece, at: 1), 1, accuracy: 0.001)
        }
    }
}
