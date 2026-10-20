import Foundation

/// **Ce qu'une correction au clavier modifie** (Hugo, 19/10/2026, QA D8) —
/// le pendant de `correctionCharacters` côté serveur
/// (`services/dailyCredit.ts`), au caractère près.
///
/// Une fiche offre 200 caractères modifiés, cumulés
/// (``DailyCredit/correctionFreeCharacters``) : pot vide, on corrige encore un
/// nom propre, un mot, une phrase. Au-delà, la correction paie comme un texte ;
/// pot vide, elle attend l'illimité. L'app mesure ici pour **prévenir avant
/// l'envoi** — le serveur, lui, tranche.
public enum CorrectionMeasure {
    /// Les blancs entre deux mots : une liste fermée, **la même que le
    /// serveur** (`CORRECTION_BLANKS`) — `isWhitespace` et `\s` ne s'accordent
    /// pas sur chaque scalaire.
    static let blanks: Set<Unicode.Scalar> = [" ", "\t", "\n", "\r", "\u{00A0}", "\u{2007}", "\u{2009}", "\u{202F}"]

    /// Au-delà, l'alignement mot à mot cède la place à la longueur du passage
    /// modifié (`CORRECTION_ALIGNMENT_LIMIT`).
    static let alignmentLimit = 4_000_000

    /// Les caractères du nouveau texte qui n'étaient pas dans l'ancien, en
    /// scalaires Unicode : on écarte le début et la fin communs, puis on aligne
    /// le milieu mot à mot (plus longue sous-suite commune, pondérée par la
    /// longueur des mots). « Famine » → « Fanny » : 3. Retirer : 0.
    public static func changedCharacters(from before: String, to after: String) -> Int {
        let a = Array(before.unicodeScalars)
        let b = Array(after.unicodeScalars)
        var start = 0
        while start < a.count, start < b.count, a[start] == b[start] { start += 1 }
        var endA = a.count
        var endB = b.count
        while endA > start, endB > start, a[endA - 1] == b[endB - 1] {
            endA -= 1
            endB -= 1
        }
        let inserted = endB - start
        if inserted == 0 || endA == start { return inserted }

        let left = tokens(a[start..<endA])
        let right = tokens(b[start..<endB])
        if left.count * right.count > alignmentLimit { return inserted }

        var previous = [Int](repeating: 0, count: right.count + 1)
        for i in 1...left.count {
            var row = [Int](repeating: 0, count: right.count + 1)
            for j in 1...right.count {
                row[j] =
                    left[i - 1] == right[j - 1]
                    ? previous[j - 1] + right[j - 1].count
                    : max(previous[j], row[j - 1])
            }
            previous = row
        }
        return inserted - previous[right.count]
    }

    /// Coupe en mots et en blancs, chacun d'un seul tenant.
    private static func tokens(_ scalars: ArraySlice<Unicode.Scalar>) -> [[Unicode.Scalar]] {
        var result: [[Unicode.Scalar]] = []
        for scalar in scalars {
            if let last = result.last?.first, blanks.contains(last) == blanks.contains(scalar) {
                result[result.count - 1].append(scalar)
            } else {
                result.append([scalar])
            }
        }
        return result
    }
}
