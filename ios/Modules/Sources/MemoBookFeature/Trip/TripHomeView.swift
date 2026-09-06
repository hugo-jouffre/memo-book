import MemoBookCore
import MemoBookDesign
import SwiftUI

/// L'accueil d'un voyage : où on en est de celui-ci, et la relance de MemoBook
/// juste au-dessus du micro.
///
/// **L'écran ne contient aucun contenu.** Titre, compteurs, compagnons, pays,
/// relance, étapes : tout vient du ``TripDetail`` que porte ``TripHomeModel``.
/// Ce qui est écrit ici, ce sont les seuls libellés qui appartiennent à
/// l'interface.
///
/// **Deux couches, et une seule qui défile.** La photo occupe le haut de la
/// page et passe sous la barre d'état ; le panneau crème remonte par-dessus
/// elle, coins arrondis, et porte tout le reste. Les deux défilent ensemble :
/// c'est ce qui fait qu'on « entre » dans le voyage plutôt que de consulter une
/// fiche.
public struct TripHomeView: View {
    @State private var model: TripHomeModel

    @Environment(\.dismiss) private var dismiss

    public init(tripId: String) {
        _model = State(initialValue: TripHomeModel(tripId: tripId))
    }

    /// Pour les aperçus et les tests, qui fournissent leur propre source.
    init(model: TripHomeModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let detail = model.detail {
                    TripHeader(
                        detail: detail,
                        onBack: { dismiss() },
                        onPrint: notYetRouted,
                        onSettings: notYetRouted,
                        onInvite: notYetRouted
                    )
                }

                canopy
            }
        }
        .scrollIndicators(.hidden)
        // La photo monte jusqu'au bord haut de la dalle ; ce sont les commandes
        // de l'en-tête qui se posent sous la barre d'état, pas la page entière.
        .ignoresSafeArea(edges: .top)
        .background(MemoBookColor.background.ignoresSafeArea())
        .brandHiddenNavigationBar()
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    /// Le panneau crème qui recouvre le bas de la photo.
    private var canopy: some View {
        VStack(spacing: MemoBookSpacing.m) {
            if let message = model.errorMessage {
                ErrorBanner(message: message) {
                    Task { await model.load() }
                }
                .padding(.horizontal, MemoBookSpacing.screenMargin)
            }

            if let detail = model.detail {
                header(detail)
                    .padding(.horizontal, MemoBookSpacing.screenMargin)

                TripStepsSection(model: model, onOpenStep: { _ in notYetRouted() })
            }
        }
        .padding(.top, MemoBookSpacing.l)
        .padding(.bottom, MemoBookSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(MemoBookColor.background)
        .clipShape(
            .rect(
                topLeadingRadius: MemoBookSpacing.overlayCornerRadius,
                topTrailingRadius: MemoBookSpacing.overlayCornerRadius
            )
        )
        // Le panneau mord sur la photo : c'est ce chevauchement qui fait qu'il
        // la recouvre au lieu d'être posé en dessous.
        .padding(.top, -MemoBookSpacing.m)
    }

    /// Le pays, la relance, et le micro. Trois blocs qui se lisent d'un trait :
    /// où l'on est, ce qu'on nous demande, et de quoi y répondre.
    @ViewBuilder
    private func header(_ detail: TripDetail) -> some View {
        VStack(spacing: MemoBookSpacing.s) {
            if let destination = detail.trip.destination {
                countryLine(destination)
            }

            if let prompt = detail.prompt {
                Text(prompt)
                    .font(MemoBookFont.h1)
                    .foregroundStyle(MemoBookColor.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            BrandButton(
                "Continuer à enregistrer",
                icon: Image(brand: "IconMic"),
                fillsWidth: true,
                action: notYetRouted
            )
            // Le libellé suit le Dynamic Type, mais s'arrête à AX1 : au-delà,
            // « enregistrer » est plus large que le bouton entier et se coupe
            // en plein mot. VoiceOver, lui, lit le libellé complet quelle que
            // soit la taille. Même limite, et même raison, que le CTA de
            // l'accueil.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.top, MemoBookSpacing.xs)
        }
        .frame(maxWidth: .infinity)
    }

    private func countryLine(_ destination: Destination) -> some View {
        HStack(spacing: MemoBookSpacing.xs) {
            if let flag = destination.flag {
                Text(flag)
            }
            Text(destination.name.uppercased())
                .font(MemoBookFont.overline)
                .tracking(MemoBookFont.tracking(12))
                .foregroundStyle(MemoBookColor.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(destination.name)
    }

    /// Les commandes dont l'écran n'est pas encore dessiné.
    ///
    /// Elles gardent leur bouton parce que la maquette les montre, et ne mènent
    /// nulle part parce que rien n'existe derrière — même parti pris que les
    /// intentions non routées de l'accueil et du profil, et il se voit ici, en
    /// un seul endroit.
    private func notYetRouted() {}
}

// MARK: - Aperçus

#Preview("Voyage") {
    NavigationStack {
        TripHomeView(tripId: "trip-rome")
    }
}

#Preview("Voyage — plusieurs pays") {
    NavigationStack {
        TripHomeView(tripId: "trip-tour-du-monde")
    }
}

#Preview("Voyage — erreur") {
    NavigationStack {
        TripHomeView(
            model: TripHomeModel(tripId: "trip-rome") { _ in
                throw URLError(.notConnectedToInternet)
            }
        )
    }
}

#Preview("Voyage — Dynamic Type AX3") {
    NavigationStack {
        TripHomeView(tripId: "trip-rome")
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
