import MemoBookCore
import MemoBookDesign
import SwiftUI
import UIKit

/// Le profil : qui tu es pour MemoBook, ce que tu lui as confié, et par où on
/// sort.
///
/// **L'écran ne contient aucun contenu.** Nom, adresse, cagnotte, carte,
/// connecteurs, commandes : tout vient du ``TravellerProfile`` que porte
/// ``ProfileModel``. Ce qui est écrit ici, ce sont les seuls libellés qui
/// appartiennent à l'interface.
///
/// **Il ne navigue pas non plus, sauf pour sortir.** Les lignes ouvrent des
/// feuilles, qui vivent dans cet écran ; la déconnexion, elle, change l'étape
/// de l'app entière et remonte donc à ``RootView``.
public struct ProfileView: View {
    private let onSignOut: () -> Void

    @State private var model: ProfileModel
    @State private var sheet: ProfileSheet?

    /// Remonte à l'app le fait qu'une feuille est ouverte, pour qu'elle recule
    /// derrière. Voir ``RootView``.
    @Binding private var isPresentingSheet: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(
        model: ProfileModel = ProfileModel(),
        isPresentingSheet: Binding<Bool> = .constant(false),
        onSignOut: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        _isPresentingSheet = isPresentingSheet
        self.onSignOut = onSignOut
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                header

                if let profile = model.profile {
                    identity(profile)
                    contactGroup(profile)
                    servicesGroup(profile)
                    paymentGroup(profile)
                    legalGroup
                    ConnectorsCallout { sheet = .connectors }
                }

                if let message = model.errorMessage {
                    ErrorBanner(message: message) {
                        Task { await model.load() }
                    }
                }

                exitActions
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.top, MemoBookSpacing.xs)
            .padding(.bottom, MemoBookSpacing.l)
        }
        .scrollIndicators(.hidden)
        // Faire défiler referme le clavier — et refermer le clavier enregistre
        // la ligne qu'on était en train de corriger. C'est la moitié du contrat
        // des lignes modifiables ; l'autre moitié est dans `BrandRow`.
        // `.immediately` et non `.interactively` : le premier geste de
        // défilement referme le clavier, donc enregistre. Le mode interactif
        // n'obéit qu'à un glissé *sur* le clavier, et une ligne corrigée
        // resterait en attente pendant qu'on lit le bas de l'écran.
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { dismissKeyboard() }
                    .font(MemoBookFont.bodySemibold)
                    .tint(MemoBookColor.action)
            }
        }
        .background(MemoBookColor.background.ignoresSafeArea())
        // L'écran dessine son propre en-tête, comme la maquette : la flèche et
        // le titre partagent une ligne, à la marge de la colonne. Une barre de
        // navigation ne sait pas faire ça — sur iOS 26 elle enferme d'office un
        // élément personnalisé dans une pastille de verre, qui avale le titre.
        .toolbar(.hidden, for: .navigationBar)
        // Masquer la barre emporte avec elle le glissé de retour depuis le
        // bord, que le système attache à son bouton. On le rend donc à la main,
        // et `simultaneous` pour que le défilement vertical continue de
        // fonctionner pendant qu'on guette le geste — même montage que le
        // balayage entre inscription et connexion de l'écran d'entrée.
        .simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .global)
                .onEnded(handleEdgeSwipe)
        )
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
        .task { await model.load() }
        .sheet(item: $sheet) { destination in
            sheetContent(destination)
        }
        // Le recul de l'écran pendant qu'une feuille est ouverte n'appartient
        // pas à cet écran-là : c'est **toute l'app** qui recule. On se contente
        // de dire qu'une feuille est ouverte, et `RootView` s'en charge.
        .onChange(of: sheet != nil) { _, isShowing in
            isPresentingSheet = isShowing
        }
        .onDisappear { isPresentingSheet = false }
    }

    // MARK: - En-tête

    private var header: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            Button { dismiss() } label: {
                // La bichrome : c'est le seul retour de l'écran, et la maquette
                // le pose en bleu.
                Image(brand: "IconArrowDuo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: MemoBookSpacing.m, height: MemoBookSpacing.m)
            }
            .frame(
                minWidth: MemoBookSpacing.minimumTapTarget,
                minHeight: MemoBookSpacing.minimumTapTarget
            )
            .contentShape(.rect)
            .accessibilityLabel("Retour")

            Text("Profile")
                .font(MemoBookFont.h2)
                .foregroundStyle(MemoBookColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
        }
        // La flèche s'aligne sur le bord de l'écran comme le reste de la
        // colonne : c'est sa zone tactile qui déborde, pas son dessin.
        .padding(.leading, -MemoBookSpacing.xs - 2)
    }

    /// Le glissé depuis le bord gauche : il doit partir du bord, aller
    /// franchement vers la droite, et rester horizontal. Sans ces trois
    /// conditions, un défilement un peu de travers refermerait l'écran au
    /// milieu de la lecture.
    private func handleEdgeSwipe(_ drag: DragGesture.Value) {
        let horizontal = drag.translation.width
        guard drag.startLocation.x < MemoBookSpacing.m,
            horizontal > 80,
            horizontal > abs(drag.translation.height) * 1.5
        else { return }
        dismiss()
    }

    private func identity(_ profile: TravellerProfile) -> some View {
        VStack(spacing: MemoBookSpacing.s) {
            ProfileAvatar(profile: profile)
            EditableName(name: profile.fullName) { model.setFullName($0) }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Les groupes de lignes

    private func contactGroup(_ profile: TravellerProfile) -> some View {
        BrandRowGroup {
            BrandRow(
                "E-mail",
                text: emailBinding,
                placeholder: "prenom@exemple.com",
                keyboardType: .emailAddress,
                textContentType: .emailAddress
            )
            BrandRow(
                "Téléphone",
                text: phoneBinding,
                placeholder: "+33 6 00 00 00 00",
                keyboardType: .phonePad,
                textContentType: .telephoneNumber
            )
            BrandRow("Adresse postale", value: profile.address.singleLine) {
                sheet = .postalAddress
            }
            BrandRow("Newsletter mensuelle MemoBook", isOn: newsletterBinding)
        }
    }

    private func servicesGroup(_ profile: TravellerProfile) -> some View {
        BrandRowGroup {
            BrandRow(
                "Ma cagnotte",
                value: profile.walletBalance.euros,
                isValueProminent: true,
                action: notYetRouted
            )
            BrandRow("Mon abonnement") { sheet = .subscription }
            BrandRow("Suivi des commandes") { sheet = .orderTracking }
            BrandRow("Confidentialité", action: notYetRouted)
        }
    }

    @ViewBuilder
    private func paymentGroup(_ profile: TravellerProfile) -> some View {
        BrandRowGroup {
            BrandRow(
                "Carte bancaire enregistrée",
                // Aucune carte enregistrée : la ligne le dit plutôt que de
                // montrer un gabarit vide. État non maquetté.
                value: profile.selectedCard?.maskedNumber ?? "Aucune carte enregistrée",
                valuePlacement: .below
            ) {
                sheet = .paymentMethod
            }
        }
    }

    private var legalGroup: some View {
        BrandRowGroup {
            BrandRow("Confidentialité", action: notYetRouted)
            BrandRow("Conditions d’utilisation", action: notYetRouted)
        }
    }

    // MARK: - Sortir

    private var exitActions: some View {
        VStack(spacing: MemoBookSpacing.xs) {
            ProfileExitAction(
                icon: Image(brand: "IconExport"),
                title: "Exporter mes données",
                tint: MemoBookColor.warning,
                action: notYetRouted
            )
            ProfileExitAction(
                icon: Image(brand: "IconExit"),
                title: "Me déconnecter",
                tint: MemoBookColor.ink,
                action: onSignOut
            )
            ProfileExitAction(
                icon: Image(brand: "IconCross"),
                title: "Supprimer mon compte",
                tint: MemoBookColor.error,
                isDestructive: true,
                action: notYetRouted
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.top, MemoBookSpacing.xs)
    }

    // MARK: - Feuilles

    @ViewBuilder
    private func sheetContent(_ destination: ProfileSheet) -> some View {
        switch destination {
        case .postalAddress:
            PostalAddressSheet(address: model.profile?.address ?? PostalAddress()) {
                model.save(address: $0)
            }
        case .paymentMethod:
            PaymentMethodSheet(model: model)
        case .subscription:
            SubscriptionSheet(subscription: model.profile?.subscription) {
                model.activateSubscription()
            }
        case .connectors:
            ConnectorsSheet(model: model)
        case .orderTracking:
            OrderTrackingSheet(orders: model.profile?.orders ?? [])
        }
    }

    // MARK: - Liaisons et actions

    /// L'interrupteur agit vraiment sur le modèle ; c'est le modèle qui n'a pas
    /// encore de serveur où l'écrire.
    private var newsletterBinding: Binding<Bool> {
        Binding(
            get: { model.profile?.wantsNewsletter ?? false },
            set: { model.setNewsletter($0) }
        )
    }

    /// Une adresse absente est `nil` dans le modèle et une chaîne vide dans le
    /// champ : la conversion se fait ici, pas dans la vue de la ligne.
    private var emailBinding: Binding<String> {
        Binding(
            get: { model.profile?.email ?? "" },
            set: { model.setEmail($0) }
        )
    }

    private var phoneBinding: Binding<String> {
        Binding(
            get: { model.profile?.phoneNumber ?? "" },
            set: { model.setPhoneNumber($0) }
        )
    }

    /// Referme le clavier sans savoir quel champ le tenait : les lignes gardent
    /// leur focus pour elles, et c'est leur sortie de champ qui enregistre.
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    /// Les lignes dont l'écran n'est pas encore dessiné.
    ///
    /// Elles gardent leur chevron parce que la maquette le montre, et ne mènent
    /// nulle part parce que rien n'existe derrière — même parti pris que les
    /// intentions non routées de l'accueil, et il se voit ici, en un seul
    /// endroit, plutôt que dispersé dans l'écran.
    private func notYetRouted() {}
}

/// Où mène chaque ligne du profil.
enum ProfileSheet: String, Identifiable, CaseIterable {
    case postalAddress
    case paymentMethod
    case subscription
    case connectors
    case orderTracking

    var id: String { rawValue }
}

// MARK: - Morceaux de l'écran

/// Le nom du voyageur, corrigeable sur place.
///
/// C'est toujours un champ de saisie, jamais un texte qu'on remplace par un
/// champ : le dessin est le même dans les deux états, et le crayon n'a pas à
/// faire apparaître quoi que ce soit — il donne juste le focus. Sans lui, rien
/// ne dirait que ce nom se corrige.
private struct EditableName: View {
    let name: String
    let onCommit: (String) -> Void

    @State private var draft = ""
    @FocusState private var isEditing: Bool

    @ScaledMetric(relativeTo: .body) private var pencilSide: CGFloat = 18

    var body: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            TextField("", text: $draft)
                .font(MemoBookFont.h2)
                .foregroundStyle(MemoBookColor.ink)
                .tint(MemoBookColor.action)
                .multilineTextAlignment(.center)
                .textContentType(.name)
                .submitLabel(.done)
                .focused($isEditing)
                .fixedSize(horizontal: true, vertical: false)
                .onSubmit { isEditing = false }
                .accessibilityLabel("Ton nom")

            Button { isEditing = true } label: {
                Image(brand: "IconPen")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: pencilSide, height: pencilSide)
                    .foregroundStyle(isEditing ? MemoBookColor.action : MemoBookColor.inkMuted)
            }
            .frame(
                minWidth: MemoBookSpacing.minimumTapTarget,
                minHeight: MemoBookSpacing.minimumTapTarget
            )
            .contentShape(.rect)
            .accessibilityLabel("Modifier ton nom")
        }
        .onAppear { draft = name }
        .onChange(of: name) { _, value in
            if !isEditing { draft = value }
        }
        // Même contrat que les lignes : sortir du champ enregistre.
        .onChange(of: isEditing) { _, editing in
            if !editing { onCommit(draft) }
        }
        .onDisappear {
            if isEditing { onCommit(draft) }
        }
        .animation(.easeOut(duration: 0.15), value: isEditing)
    }
}

/// La photo du voyageur, ou ses initiales. Jamais un rond gris vide : un profil
/// sans photo reste un profil.
private struct ProfileAvatar: View {
    let profile: TravellerProfile

    /// Taille **fixe**, comme l'avatar de l'accueil. Une photo n'est pas du
    /// texte : la faire grandir avec le Dynamic Type lui faisait prendre la
    /// moitié de l'écran en AX3, au détriment de ce qui, lui, se lit.
    private static let side: CGFloat = 80

    var body: some View {
        AsyncImage(url: profile.avatarUrl) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Text(profile.initials)
                    .font(MemoBookFont.h2)
                    .foregroundStyle(MemoBookColor.ink)
                    // Les initiales, elles, suivent le texte — mais dans un
                    // cadre qui ne bouge pas : elles se réduisent plutôt que
                    // de déborder du rond.
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, MemoBookSpacing.xs)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .background(MemoBookColor.outline, in: .circle)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

/// La carte bleue qui invite à brancher MemoBook sur le reste de ses apps.
///
/// Elle n'est pas une ligne de plus dans un groupe : c'est une proposition, et
/// c'est l'aplat bleu qui le dit.
private struct ConnectorsCallout: View {
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                title
                Text(ConnectorsCopy.promise)
                    .font(MemoBookFont.body)
                    .foregroundStyle(MemoBookColor.blueTextSoft)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MemoBookSpacing.s)
            .background(MemoBookColor.outline.opacity(0.35), in: shape)
            .overlay { shape.strokeBorder(MemoBookColor.outline, lineWidth: 1) }
            .contentShape(shape)
        }
        .buttonStyle(CardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var title: some View {
        let label = Text(ConnectorsCopy.title)
            .font(MemoBookFont.bodySemibold)
            .foregroundStyle(MemoBookColor.ink)

        let icon = Image(brand: "IconPlus")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: MemoBookSpacing.m, height: MemoBookSpacing.m)
            .foregroundStyle(MemoBookColor.ink)
            .accessibilityHidden(true)

        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                icon
                label
            }
        } else {
            HStack(spacing: MemoBookSpacing.xs) {
                icon
                label
            }
        }
    }
}

/// Les libellés des connecteurs, partagés par la carte du profil et la feuille
/// qu'elle ouvre : la promesse doit être **exactement la même** des deux côtés.
enum ConnectorsCopy {
    static let title = "Ajouter des connecteurs"

    /// ⚠️ Copie recopiée telle quelle de la maquette (R8). Elle porte trois
    /// coquilles — « a » pour « à », « permets » pour « permet », et un
    /// vouvoiement contraire à R9 — signalées à Clara dans la fiche écran.
    static let promise =
        "Connecter MemoBook a des applications externes vous permets d’étoffer vos aventures de manière intelligente."
}

/// Une action de sortie : une icône, un mot, centrés. Ni carte ni bouton plein —
/// on ne met pas en avant la porte de sortie.
private struct ProfileExitAction: View {
    let icon: Image
    let title: String
    let tint: Color
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MemoBookSpacing.xs) {
                icon
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: MemoBookSpacing.m, height: MemoBookSpacing.m)
                    .foregroundStyle(tint)
                Text(title)
                    .font(MemoBookFont.body)
                    .foregroundStyle(isDestructive ? MemoBookColor.error : MemoBookColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: MemoBookSpacing.minimumTapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Aperçus

#Preview("Profil") {
    NavigationStack {
        ProfileView {}
    }
}

#Preview("Profil — compte neuf") {
    NavigationStack {
        ProfileView(model: ProfileModel { .emptyFixture }) {}
    }
}

#Preview("Profil — erreur") {
    NavigationStack {
        ProfileView(model: ProfileModel { throw URLError(.notConnectedToInternet) }) {}
    }
}

#Preview("Profil — Dynamic Type AX3") {
    NavigationStack {
        ProfileView {}
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
