import MemoBookCore
import MemoBookDesign
import SwiftUI

/**
 **Les deux gestes d'une fiche qui demandent une réponse** (T288, Hugo —
 « l'appui long sur un message de MEMO ouvre ses gestes à lui : réanalyser,
 modifier à la main, changer les dates (déduites automatiquement), changer le
 nom du lieu, supprimer »).

 Trois des cinq partent tout de suite — ré-analyser, modifier à la main (le
 texte revient dans le champ), supprimer (après confirmation). Les deux autres
 ont une valeur à saisir, et c'est ce que ces feuilles font.

 **Ce qu'on corrige ici est déduit**, pas mesuré : la rédaction a lu le récit
 et en a tiré un jour et un lieu (T308, T280). Elle se trompe, et jusqu'ici
 rien ne permettait de la reprendre — le carnet gardait la date de travers.
 Ce qu'on écrit à la main se range **à côté** de sa lecture, jamais à sa
 place : « revenir aux dates déduites » lui rend la parole.
 */
public enum ChatFactsEdit: Identifiable, Sendable, Hashable {
    /// « Changer les dates » — les jours que ce récit raconte.
    case dates(TranscriptCard)
    /// « Changer le nom du lieu ».
    case place(TranscriptCard)

    public var card: TranscriptCard {
        switch self {
        case .dates(let card), .place(let card): card
        }
    }

    /// L'identité qui présente la feuille : le souvenir **et** le geste — un
    /// second geste sur la même fiche remplace la feuille ouverte.
    public var id: String {
        switch self {
        case .dates(let card): "dates-\(card.entryId ?? "")"
        case .place(let card): "place-\(card.entryId ?? "")"
        }
    }
}

// MARK: - Les jours racontés

/// « Changer les dates » : un jour, ou une période.
///
/// Deux champs et non un calendrier de plage (``BrandRangeCalendar``) : la
/// réponse courante est **une seule journée**, et le second champ ne sert
/// qu'aux récits qui couvrent plusieurs jours. Un calendrier de plage
/// demanderait deux gestes pour le cas le plus fréquent et pousserait la
/// feuille au plafond — c'est la raison même de ``BrandDateField``.
struct TranscriptDatesSheet: View {
    let card: TranscriptCard
    let onSave: (Date?, Date?) -> Void

    @State private var from: Date?
    @State private var to: Date?
    @Environment(\.dismiss) private var dismiss

    init(card: TranscriptCard, onSave: @escaping (Date?, Date?) -> Void) {
        self.card = card
        self.onSave = onSave
        _from = State(initialValue: card.livedFrom)
        _to = State(initialValue: card.livedTo)
    }

    var body: some View {
        BrandSheet(ChatCopy.Facts.datesTitle, paragraphs: [ChatCopy.Facts.datesLead]) {
            VStack(spacing: MemoBookSpacing.s) {
                // On ne raconte pas demain : la borne évite la faute de frappe
                // d'un doigt sur le calendrier, comme pour une photo.
                BrandDateField(ChatCopy.Facts.from, date: $from, in: ...(to ?? .now))

                // La fin n'a de sens qu'avec un départ, et seulement pour une
                // période : elle disparaît tant qu'aucun jour n'est posé.
                if from != nil {
                    BrandDateField(ChatCopy.Facts.to, date: $to, in: (from ?? .distantPast)...)
                }

                BrandButton(ChatCopy.Facts.save, style: .primary, fillsWidth: true) {
                    onSave(from, to)
                }

                // Seulement là où une main est passée : ailleurs, le lien ne
                // ferait rien, et un geste sans effet se lit comme une panne.
                if card.livedDaysByHand {
                    BrandButton(ChatCopy.Facts.revertDates, style: .link, fillsWidth: true) {
                        onSave(nil, nil)
                    }
                }
            }
        }
    }
}

// MARK: - Le nom du lieu

/// « Changer le nom du lieu » : un champ, et le lieu deviné en exemple.
struct TranscriptPlaceSheet: View {
    let card: TranscriptCard
    let onSave: (String?) -> Void

    @State private var name: String
    @FocusState private var focus: Field?

    private enum Field: Hashable { case place }

    init(card: TranscriptCard, onSave: @escaping (String?) -> Void) {
        self.card = card
        self.onSave = onSave
        _name = State(initialValue: card.placeName ?? "")
    }

    var body: some View {
        BrandSheet(ChatCopy.Facts.placeTitle, paragraphs: [ChatCopy.Facts.placeLead]) {
            VStack(spacing: MemoBookSpacing.s) {
                BrandTextField(
                    ChatCopy.Facts.place,
                    text: $name,
                    field: Field.place,
                    focus: $focus,
                    labelPlacement: .above,
                    placeholder: ChatCopy.Facts.placePlaceholder
                )

                BrandButton(ChatCopy.Facts.save, style: .primary, fillsWidth: true) {
                    onSave(name)
                }

                if card.placeByHand {
                    BrandButton(ChatCopy.Facts.revertPlace, style: .link, fillsWidth: true) {
                        onSave(nil)
                    }
                }
            }
            // Le clavier s'ouvre tout seul : la feuille n'a qu'un champ, et
            // c'est pour l'écrire qu'on l'a ouverte.
            .onAppear { focus = .place }
        }
    }
}
