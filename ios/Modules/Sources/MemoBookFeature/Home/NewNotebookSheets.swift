import MemoBookCore
import MemoBookDesign
import SwiftUI
import UIKit

/// Par où commence un carnet.
///
/// Trois portes, et rien d'autre : partir de zéro, rejoindre l'aventure de
/// quelqu'un, ou reprendre ce qu'une autre app sait déjà du voyage. Elles sont
/// **du même poids** — trois cartes identiques, aucune mise en avant — parce
/// qu'aucune n'est le chemin normal : elles dépendent de ce que la personne a
/// déjà, pas de ce qu'on préfère qu'elle fasse.
///
/// **La feuille ne navigue pas**, comme l'accueil qui la présente : elle émet
/// une ``HomeIntent`` et se referme. La seule exception est « Rejoins une
/// aventure », qui a besoin d'un code avant de mener quelque part : elle ouvre
/// alors ``JoinTripSheet`` par-dessus elle, et c'est ce qui en revient qui
/// devient l'intention.
struct NewNotebookSheet: View {
    /// Le carnet que la dernière ligne propose de retrouver : celui qui est
    /// ouvert, sinon le prochain voyage prévu. `nil` quand il n'y a ni l'un ni
    /// l'autre — la ligne et son filet disparaissent alors ensemble, plutôt que
    /// de laisser un séparateur qui ne sépare plus rien.
    let resumableTrip: Trip?
    let onIntent: (HomeIntent) -> Void

    @State private var isJoining = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BrandSheet(
            "Nouveau carnet",
            subtitle: "L’aventure commence maintenant",
            titleAlignment: .centered
        ) {
            // 12 pt entre les cartes, et non 16 : ce sont trois formulations
            // d'un même choix, pas trois blocs indépendants. Elles doivent se
            // lire comme une liste.
            VStack(spacing: MemoBookSpacing.xs + 4) {
                NewNotebookOptionCard(
                    icon: .brand("IconPlus"),
                    title: "À partir de zéro",
                    detail: "Raconte ton histoire, simplement"
                ) {
                    choose(.createTrip)
                }

                NewNotebookOptionCard(
                    icon: .brand("IconLink"),
                    title: "Rejoins une aventure",
                    // ⚠️ La maquette vouvoie ici (« Écrivez »), alors que l'app
                    // tutoie partout ailleurs. Même cas que les cartes du
                    // Welcome (T8 de `docs/ui-development.md`) : on implémente
                    // la copie de Figma en l'état, la correction se fait dans
                    // Figma.
                    detail: "Écrivez l’aventure à plusieurs"
                ) {
                    isJoining = true
                }

                NewNotebookOptionCard(
                    icon: .thirdParty("IconPolarsteps"),
                    title: "Importe depuis Polarsteps",
                    detail: "On récupérera toutes tes étapes"
                ) {
                    choose(.importFromPolarsteps)
                }

                if let resumableTrip {
                    resumeSection(resumableTrip)
                }
            }
        }
        .brandSheet(isPresented: $isJoining) {
            JoinTripSheet { code in
                // La feuille du code se referme elle-même ; celle-ci s'efface
                // derrière, pour qu'on revienne à l'accueil et non au choix
                // qu'on vient de faire.
                dismiss()
                onIntent(.joinTrip(code: code))
            }
        }
    }

    /// Le carnet déjà commencé, séparé des trois portes par un filet court.
    ///
    /// Il n'est pas une quatrième option : c'est un rappel. Le filet dit
    /// exactement ça — au-dessus on commence quelque chose, en dessous on
    /// revient à ce qui existe.
    private func resumeSection(_ trip: Trip) -> some View {
        VStack(spacing: MemoBookSpacing.xs + 4) {
            Rectangle()
                .fill(MemoBookColor.hairline)
                .frame(width: 48, height: 1)
                .padding(.vertical, MemoBookSpacing.xs - 4)
                .accessibilityHidden(true)

            NewNotebookOptionCard(
                icon: .cover(trip),
                title: Self.resumeTitle(trip),
                detail: Self.resumeDetail(trip)
            ) {
                choose(.openTrip(id: trip.id))
            }
        }
    }

    /// Un carnet ouvert se **reprend** ; un voyage qui n'a pas commencé
    /// s'annonce. Deux situations, deux phrases : « reprendre » devant un
    /// voyage qui n'a pas encore eu lieu ne veut rien dire.
    private static func resumeTitle(_ trip: Trip) -> String {
        trip.stage.isOngoing ? "Reprendre ton carnet en cours" : "Ton voyage en approche"
    }

    /// La précision nomme le voyage : c'est elle qui dit *lequel* on reprend.
    ///
    /// ⚠️ « commence bientôt » ne vient pas de la maquette, qui ne montre que le
    /// cas du carnet en cours — à confirmer avec Clara, en même temps que
    /// l'usage éventuel de la date de départ.
    private static func resumeDetail(_ trip: Trip) -> String {
        trip.stage.isOngoing
            ? "\(trip.title) n’est pas terminé"
            : "\(trip.title) commence bientôt"
    }

    /// Referme la feuille, **puis** dit ce qu'on a choisi : la destination
    /// s'ouvre derrière une feuille qui descend, et non sous elle.
    private func choose(_ intent: HomeIntent) {
        dismiss()
        onIntent(intent)
    }
}

// MARK: - Une porte

/// Une des façons de commencer : une icône, ce qu'elle fait, et la flèche qui
/// dit que ça mène quelque part.
///
/// Le contour est **vert** et non gris : ces cartes ne rangent pas de
/// l'information, elles proposent d'agir. C'est la seule chose qui les
/// distingue d'une carte de contenu, et c'est assez.
struct NewNotebookOptionCard: View {
    /// Ce qui se pose dans la plaque de gauche.
    enum Icon {
        /// Une icône du jeu de marque. Teintée à l'encre par la carte : les
        /// tracés sont livrés dans une couleur figée dont on ne dépend pas.
        case brand(String)

        /// La marque d'un service tiers, redessinée à l'encre de MemoBook pour
        /// tenir dans la plaque. Elle garde **ses** couleurs telles qu'elles
        /// sont dessinées — jamais de teinte : une marque qu'on repeint n'est
        /// plus la marque. À ne pas confondre avec les logos de
        /// `ConnectorsSheet`, qui sont les vrais logotypes en couleurs.
        case thirdParty(String)

        /// La couverture d'un voyage, à la place de l'icône : la ligne parle
        /// d'un carnet précis, autant le montrer.
        case cover(Trip)
    }

    let icon: Icon
    let title: String
    let detail: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// La plaque d'icône du design system : 44 × 40, rayon 12, bleu à 30 %.
    /// Voir « Fond d'icône » dans `docs/ui-development.md`.
    @ScaledMetric(relativeTo: .body) private var plateWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var plateHeight: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var glyphSide: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var arrowSide: CGFloat = 24

    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
    }

    private var plateShape: RoundedRectangle {
        .rect(cornerRadius: 12)
    }

    var body: some View {
        Button(action: action) {
            content
                .padding(MemoBookSpacing.xs + 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(shape)
        }
        .buttonStyle(CardPressStyle())
        .background(MemoBookColor.surface, in: shape)
        .overlay { shape.strokeBorder(MemoBookColor.action, lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var content: some View {
        // En taille accessible le texte prend toute la largeur : lui laisser
        // deux colonnes de plus ne lui laisserait que deux mots par ligne.
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                HStack(spacing: MemoBookSpacing.xs) {
                    plate
                    Spacer(minLength: 0)
                    arrow
                }
                text
            }
        } else {
            HStack(spacing: MemoBookSpacing.xs + 4) {
                plate
                text
                arrow
            }
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(MemoBookFont.bodySemibold)
                // Le vert d'action, comme le contour : le titre **est** l'action.
                .foregroundStyle(MemoBookColor.action)
            Text(detail)
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.inkMuted)
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var plate: some View {
        switch icon {
        case .brand(let name):
            Image(brand: name)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: glyphSide, height: glyphSide)
                .foregroundStyle(MemoBookColor.ink)
                .frame(width: plateWidth, height: plateHeight)
                .background(MemoBookColor.outline.opacity(0.3), in: plateShape)
                .accessibilityHidden(true)

        case .thirdParty(let name):
            Image(brand: name)
                .resizable()
                .scaledToFit()
                .frame(width: glyphSide, height: glyphSide)
                .frame(width: plateWidth, height: plateHeight)
                .background(MemoBookColor.outline.opacity(0.3), in: plateShape)
                .accessibilityHidden(true)

        case .cover(let trip):
            AsyncImage(url: trip.coverPhotoUrl) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    TripCoverPlaceholder(seed: trip.id)
                }
            }
            .frame(width: plateWidth, height: plateHeight)
            .clipShape(plateShape)
            .accessibilityHidden(true)
        }
    }

    /// `IconArrowRight` et non `IconArrow` : celle du jeu de marque pointe à
    /// **gauche**, c'est une flèche de retour.
    private var arrow: some View {
        Image(brand: "IconArrowRight")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: arrowSide, height: arrowSide)
            .foregroundStyle(MemoBookColor.action)
            .accessibilityHidden(true)
    }
}

// MARK: - Rejoindre

/// Entrer le code d'accès d'un voyage qui existe déjà.
///
/// Un seul champ, et le geste qui le remplit : un code d'accès arrive presque
/// toujours par message, donc il se **colle** — le taper à la main est le cas
/// rare, pas l'inverse. C'est pour ça que « Coller » est posé à côté du champ
/// et non caché dans le menu d'un appui long.
struct JoinTripSheet: View {
    /// Le code saisi, une fois nettoyé.
    let onJoin: (String) -> Void

    @State private var code = ""

    /// Le presse-papiers a quelque chose à coller. Relu à l'ouverture et au
    /// retour dans l'app — c'est là qu'on revient du message où on a copié le
    /// code. `hasStrings` ne lit pas le contenu : il ne déclenche donc aucune
    /// demande d'autorisation.
    @State private var canPaste = false

    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Field: Hashable { case code }

    var body: some View {
        BrandSheet(
            "Rejoindre",
            subtitle: "Colle ici le code d’accès d’un voyage existant",
            titleAlignment: .centered
        ) {
            VStack(spacing: MemoBookSpacing.s) {
                codeEntry

                BrandButton("Rejoindre", fillsWidth: true) {
                    focus = nil
                    dismiss()
                    onJoin(code)
                }
                .disabled(code.isEmpty)

                cancelButton
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { focus = nil }
                        .font(MemoBookFont.bodySemibold)
                        .tint(MemoBookColor.action)
                }
            }
        }
        .task { canPaste = UIPasteboard.general.hasStrings }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { canPaste = UIPasteboard.general.hasStrings }
        }
    }

    /// Le champ et son bouton « Coller », côte à côte.
    ///
    /// Les deux n'ont pas la même hauteur — 56 pour un champ, 50 pour un
    /// bouton — et c'est voulu : ce sont deux hauteurs du design system, dont
    /// l'une est contrainte par le bouton d'Apple. Voir
    /// ``MemoBookSpacing/fieldHeight``. Ils s'alignent donc sur leur milieu.
    @ViewBuilder
    private var codeEntry: some View {
        let field = BrandTextField(
            "Code d’accès",
            text: $code,
            field: Field.code,
            focus: $focus,
            labelPlacement: .hidden,
            placeholder: "JHKFDA"
        )
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .submitLabel(.done)
        .onSubmit { focus = nil }
        .onChange(of: code) { _, value in
            let cleaned = Self.normalized(value)
            if cleaned != value { code = cleaned }
        }

        let pasteButton = BrandButton("Coller", style: .secondary, action: paste)
            .disabled(!canPaste)

        // En taille accessible, « Coller » passe sous le champ : à côté, il ne
        // resterait au code que la place de deux caractères.
        if typeSize.isAccessibilitySize {
            VStack(spacing: MemoBookSpacing.xs) {
                field
                pasteButton.frame(maxWidth: .infinity)
            }
        } else {
            HStack(spacing: MemoBookSpacing.s) {
                field
                pasteButton
            }
        }
    }

    /// La sortie, en rouge et sans cadre : elle annule ce qu'on était en train
    /// de faire, elle ne le fait pas. Même dessin que « Supprimer mon compte »
    /// au bas du profil.
    private var cancelButton: some View {
        Button { dismiss() } label: {
            Text("Annuler")
                .font(MemoBookFont.button)
                .foregroundStyle(MemoBookColor.error)
                .frame(maxWidth: .infinity, minHeight: MemoBookSpacing.minimumTapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Colle le presse-papiers dans le champ, nettoyé.
    ///
    /// Le bouton lit `UIPasteboard` directement plutôt que d'être un
    /// `PasteButton` du système : celui-ci évite la demande d'autorisation
    /// d'iOS, mais impose son propre dessin — ni la typographie de la marque,
    /// ni le contour vert d'un bouton secondaire. Sur une feuille où il est
    /// posé à côté d'un champ, il se lirait comme un contrôle étranger. On
    /// accepte donc l'alerte système, qui reste rare : on ne lit le
    /// presse-papiers que sur ce geste-là.
    private func paste() {
        guard let pasted = UIPasteboard.general.string else { return }
        code = Self.normalized(pasted)
        // Le code est complet : on rend l'écran plutôt que de garder le clavier
        // devant le bouton qui suit.
        focus = nil
    }

    /// Un code d'accès s'écrit en capitales et sans séparateur. On le nettoie
    /// **à la frappe** plutôt que de le refuser à l'envoi : collé depuis un
    /// message, il arrive presque toujours avec une espace ou un retour à la
    /// ligne au bout.
    private static func normalized(_ value: String) -> String {
        value.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}

// MARK: - Aperçus

#Preview("Nouveau carnet") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            NewNotebookSheet(resumableTrip: HomeFeed.fixture.ongoingTrips.first) { _ in }
        }
}

#Preview("Nouveau carnet — voyage à venir") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            NewNotebookSheet(resumableTrip: HomeFeed.fixture.upcomingTrips.first) { _ in }
        }
}

#Preview("Nouveau carnet — aucun carnet") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            NewNotebookSheet(resumableTrip: nil) { _ in }
        }
}

#Preview("Nouveau carnet — AX3") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            NewNotebookSheet(resumableTrip: HomeFeed.fixture.ongoingTrips.first) { _ in }
                .environment(\.dynamicTypeSize, .accessibility3)
        }
}

#Preview("Rejoindre") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            JoinTripSheet { _ in }
        }
}
