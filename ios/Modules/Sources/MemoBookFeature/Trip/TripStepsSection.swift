import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Les étapes du voyage, et les deux filtres qui les trient.
///
/// Chaque filtre est un `Menu` portant un `Picker` : la liste déroulante, les
/// coches, le retour tactile et l'annonce VoiceOver viennent du système. La
/// pastille n'en est que l'étiquette — voir ``BrandFilterChip``.
///
/// **Deux filtres, pas trois.** Il y a eu un filtre « Étapes », lu comme le
/// filtre littéral qu'il annonçait : ne garder qu'une étape de la liste.
/// Retiré par Hugo, 14/09/2026 (T30) — « pour le moment » : filtrer une liste
/// sur un seul de ses éléments n'a pas trouvé son sens.
struct TripStepsSection: View {
    @Bindable var model: TripHomeModel
    let onOpenStep: (TripStep) -> Void

    private var detail: TripDetail? { model.detail }

    /// Le voyage a au moins une étape. **Sans étape, pas de filtres** : deux
    /// pastilles présentes mais inertes disaient « appuie ici » à quelqu'un qui
    /// n'avait rien à trier — logique, et désagréable (Hugo, 14/09/2026). Elles
    /// arrivent avec la première étape.
    private var hasSteps: Bool { !(detail?.steps ?? []).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            if hasSteps {
                filters
            }
            steps
        }
    }

    // MARK: - Filtres

    /// Une bande qui défile : sur un petit écran, deux pastilles, leurs
    /// chevrons et « Tout afficher » ne tiennent pas toujours sur une ligne, et
    /// les serrer les rendrait illisibles.
    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: MemoBookSpacing.xs) {
                countryFilter
                transportFilter

                if model.hasActiveFilter {
                    BrandButton("Tout afficher", style: .link, action: model.clearFilters)
                        .font(MemoBookFont.label)
                }
            }
        }
        .scrollIndicators(.hidden)
        // La bande prend toute la largeur de l'écran et ses pastilles s'alignent
        // sur la colonne : la dernière peut donc sortir par le bord au lieu de
        // buter sur une marge.
        //
        // ⚠️ **Une marge de contenu, pas un `padding` sous un
        // `scrollClipDisabled`.** C'est ce que faisait cette bande, et une
        // pastille qui sortait par la gauche continuait d'être dessinée
        // **au-delà du bord** : le vert d'un filtre posé bavait jusqu'à
        // l'extrême bord de la dalle et par-dessus tout ce qui traînait là.
        // `contentMargins` place le contenu au même endroit, mais ce qui sort
        // de la bande est **rogné**.
        .contentMargins(.horizontal, MemoBookSpacing.screenMargin, for: .scrollContent)
        // Et ce qui sort par un bord s'y **efface** au lieu d'être tranché à la
        // verticale — voir ``brandHorizontalFade``.
        .brandHorizontalFade()
    }

    @ViewBuilder
    private var countryFilter: some View {
        let countries = detail?.countries ?? []

        Menu {
            Picker("Pays", selection: $model.country) {
                Text("Tous les pays").tag(String?.none)
                ForEach(countries, id: \.name) { destination in
                    Text(destination.flag.map { "\($0)  \(destination.name)" } ?? destination.name)
                        .tag(String?.some(destination.name))
                }
            }
        } label: {
            BrandFilterChip(
                model.country ?? "Pays",
                icon: Image(systemName: "flag"),
                isActive: model.country != nil
            )
        }
        .disabled(countries.isEmpty)
    }

    @ViewBuilder
    private var transportFilter: some View {
        let transports = detail?.transports ?? []

        Menu {
            Picker("Transports", selection: $model.transport) {
                Text("Tous les transports").tag(TripTransport?.none)
                ForEach(transports, id: \.self) { transport in
                    Text(transport.displayName).tag(TripTransport?.some(transport))
                }
            }
        } label: {
            BrandFilterChip(
                model.transport?.displayName ?? "Transports",
                // Un train, et non le symbole système « bifurcation » qui
                // tenait la place : celui-ci ne se dessinait tout simplement
                // pas, et la pastille gardait un trou à gauche de son libellé.
                // Aucune icône de transport dans le jeu de marque — voir
                // ``LucideIcon``.
                icon: LucideIcon.image("train-front"),
                isActive: model.transport != nil
            )
        }
        .disabled(transports.isEmpty)
    }

    // MARK: - La liste

    @ViewBuilder
    private var steps: some View {
        let visible = model.visibleSteps

        if visible.isEmpty {
            // Deux vides très différents : un voyage qui n'a rien à raconter, et
            // un filtre qui ne laisse rien passer. Aucun des deux n'est
            // maquetté — voir la fiche écran.
            if model.hasActiveFilter {
                TripStepsEmptyState(
                    title: "Aucune étape ne correspond",
                    message: "Enlève un filtre pour revoir tout le voyage.",
                    action: ("Tout afficher", model.clearFilters)
                )
            } else {
                TripStepsEmptyState(
                    title: "Le voyage commence ici",
                    message: "Raconte ta première journée : MemoBook en fera une étape.",
                    action: nil
                )
            }
        } else {
            LazyVStack(spacing: MemoBookSpacing.s) {
                ForEach(visible) { step in
                    TripStepCard(step: step) { onOpenStep(step) }
                }
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
        }
    }
}

/// Une étape : sa vignette, son rang, ses dates, et qui y était.
struct TripStepCard: View {
    let step: TripStep
    let onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var thumbnailSide: CGFloat = 76

    var body: some View {
        Button(action: onOpen) {
            content
                .padding(MemoBookSpacing.xs + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(CardPressStyle())
        .homeCard()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var content: some View {
        // En taille accessible, la vignette passe au-dessus : lui garder sa
        // colonne ne laisserait au texte que deux mots de large.
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                thumbnail
                text
                openMark
            }
        } else {
            HStack(spacing: MemoBookSpacing.s) {
                thumbnail
                text
                Spacer(minLength: MemoBookSpacing.xs)
                openMark
            }
        }
    }

    private var thumbnail: some View {
        AsyncImage(url: step.photoUrl) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                TripCoverPlaceholder(seed: step.id)
            }
        }
        .frame(width: thumbnailSide, height: thumbnailSide)
        .clipShape(.rect(cornerRadius: MemoBookSpacing.cornerRadius))
        .overlay(alignment: .topLeading) { flag }
        .accessibilityHidden(true)
    }

    /// Le drapeau du pays, posé dans le coin de la vignette. Il se déduit du
    /// code pays — aucun serveur n'a d'emoji à stocker.
    @ViewBuilder
    private var flag: some View {
        if let flag = step.destination?.flag {
            Text(flag)
                .font(MemoBookFont.caption)
                .padding(3)
                .background(MemoBookColor.surface.opacity(0.9), in: .circle)
                .padding(5)
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(step.title)
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.ink)

            if let dates = step.dateRangeLabel {
                Text(dates)
                    .font(MemoBookFont.label)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }

            if let companions = step.companionsLabel {
                Text(companions)
                    .font(MemoBookFont.label)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Le rond fléché de la carte de découverte, repris tel quel : c'est déjà
    /// le signe « ça s'ouvre » de l'app.
    private var openMark: some View {
        Image(brand: "IconArrowRight")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: MemoBookSpacing.m, height: MemoBookSpacing.m)
            .foregroundStyle(MemoBookColor.ink)
            .padding(MemoBookSpacing.xs + 2)
            .background(MemoBookColor.background, in: .circle)
            .accessibilityHidden(true)
    }
}

/// Ce qu'on montre quand la liste est vide. Non maquetté : une phrase qui dit
/// quoi faire vaut mieux qu'un trou.
private struct TripStepsEmptyState: View {
    let title: String
    let message: String
    let action: (title: String, perform: () -> Void)?

    var body: some View {
        VStack(spacing: MemoBookSpacing.xs) {
            Text(title)
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.ink)

            Text(message)
                .font(MemoBookFont.label)
                .foregroundStyle(MemoBookColor.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let action {
                BrandButton(action.title, style: .link, action: action.perform)
                    .padding(.top, MemoBookSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MemoBookSpacing.l)
        .padding(.horizontal, MemoBookSpacing.s)
        .homeCard()
        .padding(.horizontal, MemoBookSpacing.screenMargin)
    }
}

// MARK: - Mise en forme

extension TripStep {
    /// « Etape n°1 » tant que l'étape n'a pas de titre à elle.
    ///
    /// ⚠️ Sans accent sur le E : c'est la copie de la maquette, recopiée telle
    /// quelle (R8). Signalée dans la fiche écran.
    var title: String { "Etape n°\(number)" }

    /// Les dates de l'étape, avec l'année écrite une seule fois. Même règle que
    /// celles d'un voyage.
    var dateRangeLabel: String? {
        switch (startDate, endDate) {
        case let (start?, end?) where start < end:
            (start..<end).formatted(.interval.day().month(.abbreviated).year())
        case let (start?, _):
            start.formatted(.dateTime.day().month(.abbreviated).year())
        case (nil, let end?):
            end.formatted(.dateTime.day().month(.abbreviated).year())
        case (nil, nil):
            nil
        }
    }

    /// « avec Mila », « avec Léa et Tom ». La liste est assemblée par le
    /// système : c'est lui qui sait mettre « et » en français et « and »
    /// ailleurs.
    var companionsLabel: String? {
        guard !companions.isEmpty else { return nil }
        let names = companions.map { $0.name.firstNameOnly }.formatted(.list(type: .and))
        return "avec \(names)"
    }
}

extension String {
    /// Le prénom seul : sur une carte d'étape, « avec Mila Fontaine et Tom
    /// Marchand » prend deux lignes pour ne rien dire de plus.
    fileprivate var firstNameOnly: String {
        split(separator: " ").first.map(String.init) ?? self
    }
}
