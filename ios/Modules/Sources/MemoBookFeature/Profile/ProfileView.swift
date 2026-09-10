import MemoBookCore
import MemoBookDesign
import SwiftUI

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

    /// Le paywall se présente **par-dessus tout**, feuille comprise : c'est un
    /// écran entier, pas une feuille de plus. La feuille qui l'a ouvert se
    /// referme donc d'abord, sans quoi on la retrouverait dessous en sortant.
    @State private var showsPaywall = false

    /// L'alerte de suppression du compte. Une alerte du système, et non une
    /// feuille de la marque : c'est le seul geste de l'app qui ne se rattrape
    /// pas, et il doit ressembler à ce que l'utilisateur a déjà appris à
    /// craindre ailleurs.
    @State private var isConfirmingDeletion = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.subscriptionSession) private var subscriptionSession

    public init(
        model: ProfileModel = ProfileModel(),
        onSignOut: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.onSignOut = onSignOut
    }

    public var body: some View {
        ScrollView {
            // **L'écran se dessine tout de suite, entier.** Il n'attendait
            // rien de tout ça : ses intitulés, ses groupes, ses boutons et ses
            // actions de sortie appartiennent à l'app, pas au serveur. Seules
            // les valeurs viennent du réseau, et elles seules portent une barre
            // d'attente — voir ``BrandSkeleton``.
            //
            // Trois blocs font exception et n'apparaissent qu'une fois le
            // profil connu, parce qu'ils **existent ou non** selon le palier du
            // compte : la pastille d'état, le bouton d'abonnement et la ligne
            // « Mon abonnement ». Les montrer par défaut puis les retirer
            // serait pire que de les voir arriver.
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                header

                identity
                subscriptionCallToAction
                statsGroup
                contactGroup
                servicesGroup
                paymentGroup
                legalGroup
                ConnectorsCallout { sheet = .connectors }

                if let message = model.errorMessage {
                    ErrorBanner(message: message) {
                        Task { await model.load() }
                    }
                }

                helpLink
                exitActions
                legalMention
            }
            .animation(.snappy(duration: 0.25), value: model.profile == nil)
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.top, MemoBookSpacing.xs)
            .padding(.bottom, MemoBookSpacing.l)
        }
        .scrollIndicators(.hidden)
        // Faire défiler referme le clavier — et refermer le clavier enregistre
        // la ligne qu'on était en train de corriger. C'est la moitié du contrat
        // des lignes modifiables ; l'autre moitié est dans `BrandRow`.
        //
        // `.immediately` et non `.interactively` : le mode interactif n'obéit
        // qu'à un glissé *sur* le clavier, et une ligne corrigée resterait en
        // attente pendant qu'on lit le bas de l'écran.
        .scrollDismissesKeyboard(.immediately)
        .brandKeyboardDismissBar()
        .background(MemoBookColor.background.ignoresSafeArea())
        // L'écran dessine son propre en-tête, comme la maquette : la flèche et
        // le titre partagent une ligne, à la marge de la colonne. Une barre de
        // navigation ne sait pas faire ça — sur iOS 26 elle enferme d'office un
        // élément personnalisé dans une pastille de verre, qui avale le titre.
        .brandHiddenNavigationBar()
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
        .task { await model.load() }
        .brandSheet(item: $sheet) { destination in
            sheetContent(destination)
        }
        .fullScreenCover(isPresented: $showsPaywall) {
            PaywallView(subscription: effectiveSubscription) {
                model.activateSubscription()
                subscriptionSession?.record(isSubscribed: true)
                showsPaywall = false
            }
        }
        .alert("Supprimer mon compte ?", isPresented: $isConfirmingDeletion) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) {
                Task {
                    // La sortie est la même que la déconnexion : le compte
                    // n'existe plus, l'app ne peut que revenir à l'entrée.
                    if await model.deleteAccount() { onSignOut() }
                }
            }
        } message: {
            // Le même texte que la modale dessinée dans Figma, resserré : une
            // alerte du système ne tient pas un paragraphe. Ce qu'elle ne perd
            // jamais, c'est ce qui disparaît pour **les autres**.
            Text(
                """
                Tes voyages, tes souvenirs et tes carnets seront effacés, ainsi \
                que tes commandes. Les voyages que tu partages restent à tes \
                co-voyageurs. Ta cagnotte et ton abonnement sont clos.

                C'est immédiat et sans retour.
                """
            )
        }
    }

    // MARK: - L'abonnement, tel qu'il faut le lire ici

    /// L'abonnement du profil, **corrigé par la session**.
    ///
    /// ``ProfileModel`` est un `@State` : l'écran se reconstruit à chaque fois
    /// qu'on y revient, et repartirait donc du jeu d'essai — abonnement
    /// rétabli, résiliation oubliée. Tant que rien n'est persisté, c'est la
    /// session qui a le dernier mot, ici comme sur l'accueil.
    private var effectiveSubscription: Subscription? {
        guard var subscription = model.profile?.subscription else { return nil }
        subscription.isActive = freemiumStatus == .subscriber
        return subscription
    }

    /// Le palier du compte, lu sur le modèle **et** sur la session.
    private var freemiumStatus: FreemiumStatus {
        model.profile?.freemiumStatus(override: subscriptionSession?.override) ?? .subscriber
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
                    .frame(
                        width: MemoBookSpacing.navigationIcon,
                        height: MemoBookSpacing.navigationIcon
                    )
                    // La cible tactile est alignée à gauche sur la marge de la
                    // colonne, et le dessin est centré dedans. Elle débordait de
                    // la colonne ; la moitié gauche des touches tombait alors à
                    // côté, et le retour ne marchait qu'une fois sur deux.
                    .frame(
                        width: MemoBookSpacing.minimumTapTarget,
                        height: MemoBookSpacing.minimumTapTarget
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retour")

            Text("Profile")
                .font(MemoBookFont.h2)
                .foregroundStyle(MemoBookColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            statusPill
        }
    }

    /// Ce que vaut le compte, dit en un mot sur la ligne du titre.
    ///
    /// **Elle partage la ligne du titre et ne flotte pas dans le coin** : c'est
    /// une étiquette posée sur l'écran. Droite, contrairement à celle de
    /// l'accueil : celle-ci est alignée sur un titre, et un libellé de travers
    /// à côté d'un mot horizontal se lit comme un défaut de rendu, pas comme un
    /// geste. L'accueil, lui, la pose sur un avatar, où rien n'impose
    /// l'horizontale.
    @ViewBuilder
    private var statusPill: some View {
        if model.profile != nil {
            let pill = BrandTagPill(
                freemiumStatus.profilePillLabel,
                tone: .accentOutlined,
                isUppercased: true,
                // « 3 ÉTAPES GRATUITES RESTANTES » est plus large que ce que la
                // ligne lui laisse : elle se resserre plutôt que de renvoyer
                // « Profile » à la ligne.
                shrinksToFit: true
            )
            // Le libellé du palier gratuit est long : à partir d'AX1 il prendrait
            // la ligne entière et pousserait le titre hors de l'écran. Il garde
            // alors sa taille, et lui seul.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            // **« ABONNE-TOI » se touche.** Tant qu'il y a quelque chose à
            // vendre, la pastille ouvre la même feuille que le gros bouton lime
            // juste en dessous : c'est la même proposition, et quelqu'un qui
            // vise le mot y a autant droit que celui qui vise le bouton.
            // « ABONNÉ », lui, est un constat — il ne mène nulle part.
            if freemiumStatus.wantsSubscription {
                Button { sheet = .subscription } label: { pill }
                    .buttonStyle(.plain)
                    .frame(minHeight: MemoBookSpacing.minimumTapTarget)
                    .contentShape(.rect)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Découvrir l’abonnement")
            } else {
                pill
            }
        }
    }

    /// Le gros bouton lime de la maquette, et **rien d'autre au-dessus** : pour
    /// quelqu'un qui n'a pas d'abonnement, c'est la première chose de l'écran
    /// après son nom.
    ///
    /// Il disparaît une fois abonné, où la ligne « Mon abonnement » des services
    /// suffit : on ne revend pas ce qui est déjà acheté. C'est aussi ce qui fait
    /// que **résilier le fait revenir** — la feuille se referme sur un profil
    /// qui n'a plus d'abonnement, et l'offre reprend sa place.
    @ViewBuilder
    private var subscriptionCallToAction: some View {
        if freemiumStatus.wantsSubscription {
            BrandButton(
                "Découvrir l’abonnement",
                icon: Image(brand: "IconArrowForward"),
                iconPlacement: .trailing,
                style: .accent,
                fillsWidth: true
            ) {
                sheet = .subscription
            }
        }
    }

    /// Les chiffres du compte : combien de voyages, et lequel est en cours.
    ///
    /// **Le seul groupe cerclé de vert de l'écran.** C'est ce qu'on vient
    /// chercher du regard en ouvrant son profil ; tout le reste se range.
    /// Sans abonnement, la première ligne dit qu'elle est sous clé plutôt que
    /// de disparaître : une case vide n'explique pas ce qu'on gagnerait.
    private var statsGroup: some View {
        let profile = model.profile
        let isLoading = profile == nil

        // Les valeurs sont préparées ici plutôt que dans les appels : trois
        // ternaires imbriqués dans une liste de lignes, et l'inférence de type
        // de Swift rend les armes sans rien dire d'utile.
        let isSubscriber = freemiumStatus == .subscriber
        let statistics: String? = profile.map {
            isSubscriber ? $0.tripCountLabel : "Réservé aux abonnés"
        }
        let lockBadge: String? = profile != nil && !isSubscriber ? "Locked" : nil
        let currentTrip: String? = profile.map {
            $0.currentTrip?.dateRangeLabel ?? "Aucun pour l’instant"
        }

        // Sous clé — ou sans voyage en cours — la ligne ne mène nulle part : un
        // chevron promettrait un écran qu'on n'a pas le droit d'ouvrir.
        let openStatistics: (() -> Void)? = isSubscriber ? { notYetRouted() } : nil
        let openCurrentTrip: (() -> Void)? = profile?.currentTrip == nil ? nil : { notYetRouted() }

        return BrandRowGroup(tone: .highlighted) {
            BrandRow(
                "Statistiques",
                value: statistics,
                titleTone: .accent,
                badge: lockBadge,
                isValueLoading: isLoading,
                action: openStatistics
            )

            // La ligne reste, même sans voyage en cours : sa disparition ferait
            // sauter la carte d'une hauteur de ligne à chaque chargement. Elle
            // dit alors qu'il n'y en a pas.
            BrandRow(
                "Voyage en cours",
                value: currentTrip,
                titleTone: .accent,
                isValueLoading: isLoading,
                action: openCurrentTrip
            )
        }
    }

    private var identity: some View {
        VStack(spacing: MemoBookSpacing.s) {
            ProfileAvatar(profile: model.profile)

            if let profile = model.profile {
                EditableName(name: profile.fullName) { model.setFullName($0) }
            } else {
                // Le nom est un titre : sa barre d'attente est plus large et
                // centrée comme lui, pour que la page ne se recompose pas
                // quand il arrive.
                BrandSkeleton(width: 180)
                    .frame(height: MemoBookSpacing.m)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Les groupes de lignes

    private var contactGroup: some View {
        let profile = model.profile

        return BrandRowGroup {
            // **L'adresse se lit, elle ne se corrige pas.** Elle n'est pas un
            // champ de plus : c'est l'identifiant de connexion. En changer
            // demande de vérifier la nouvelle, de refuser celles déjà prises et
            // de décider du sort de la session ouverte avec l'ancienne — un
            // écran à part entière, que cette ligne ne peut pas tenir. La note
            // dit d'où elle vient quand c'est un compte tiers qui la porte.
            BrandRow(
                "E-mail",
                value: profile?.email,
                isValueLoading: profile == nil,
                note: profile?.signInProvider.map { "Gérée par ton compte \($0.displayName)" }
            )
            BrandRow(
                "Téléphone",
                text: phoneBinding,
                placeholder: "+33 6 00 00 00 00",
                keyboardType: .phonePad,
                textContentType: .telephoneNumber,
                isValueLoading: profile == nil,
                isConfirmed: model.justSaved == .phoneNumber
            )
            BrandRow(
                "Adresse postale",
                value: profile?.address.singleLine,
                isValueLoading: profile == nil
            ) {
                sheet = .postalAddress
            }
            BrandRow("Newsletter mensuelle MemoBook", isOn: newsletterBinding)
        }
        // L'interrupteur est le seul contrôle du groupe qui **agit** avant que
        // la valeur soit là : le basculer sur un profil pas encore chargé
        // enverrait un réglage qu'on n'a pas lu. Le groupe entier attend, ce
        // qui ne coûte rien — les autres lignes ne font qu'ouvrir des feuilles.
        .disabled(model.profile == nil)
    }

    private var servicesGroup: some View {
        let profile = model.profile

        return BrandRowGroup {
            BrandRow(
                "Ma cagnotte",
                value: profile?.walletBalance.euros,
                isValueProminent: true,
                isValueLoading: profile == nil,
                action: notYetRouted
            )
            // Elle ne s'affiche qu'une fois abonné : sans abonnement, c'est le
            // bouton lime du haut qui porte la proposition, et deux entrées vers
            // la même feuille sur un même écran se marcheraient dessus.
            if freemiumStatus == .subscriber {
                BrandRow("Mon abonnement") { sheet = .subscription }
            }
            BrandRow("Suivi des commandes") { sheet = .orderTracking }
            BrandRow("Confidentialité", action: notYetRouted)
        }
    }

    private var paymentGroup: some View {
        let profile = model.profile

        return BrandRowGroup {
            BrandRow(
                "Carte bancaire enregistrée",
                // Aucune carte enregistrée : la ligne le dit plutôt que de
                // montrer un gabarit vide. État non maquetté.
                value: profile.map { $0.selectedCard?.maskedNumber ?? "Aucune carte enregistrée" },
                valuePlacement: .below,
                isValueLoading: profile == nil
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
                isDestructive: true
            ) {
                // La confirmation est ici, pas dans le modèle : après elle, il
                // n'y a plus rien à annuler.
                isConfirmingDeletion = true
            }
            .disabled(model.isDeletingAccount)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, MemoBookSpacing.xs)
    }

    /// La mention de bas de page. **Du texte, et rien d'autre** : ni bouton, ni
    /// lien, ni cible tactile — on la lit une fois, on n'appuie jamais dessus.
    /// Elle ferme l'écran, sous le dernier bouton.
    private var legalMention: some View {
        Text("MemoBook v1.0 | Tous droits réservés")
            .font(MemoBookFont.mention)
            .foregroundStyle(MemoBookColor.inkFaint)
            .frame(maxWidth: .infinity)
            .padding(.top, MemoBookSpacing.s)
    }

    /// Le même lien qu'en bas de l'accueil, dans le même dessin : c'est la
    /// sortie de secours de l'app. Aucune destination pour l'instant.
    ///
    /// Il passe **avant** les actions de sortie, et pas après : demander de
    /// l'aide n'est pas quitter. Le laisser sous « Supprimer mon compte » le
    /// rangeait avec les portes de sortie, alors qu'il est là pour éviter d'en
    /// prendre une.
    private var helpLink: some View {
        BrandButton("Besoin d’aide ?", style: .link, isSubdued: true) {
            notYetRouted()
        }
        .frame(maxWidth: .infinity)
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
            SubscriptionSheet(
                subscription: effectiveSubscription,
                onActivate: {
                    model.activateSubscription()
                    subscriptionSession?.record(isSubscribed: true)
                },
                onCancel: {
                    model.cancelSubscription(reason: $0)
                    subscriptionSession?.record(isSubscribed: false)
                },
                onLearnMore: {
                    sheet = nil
                    showsPaywall = true
                }
            )
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

    /// Un numéro absent est `nil` dans le modèle et une chaîne vide dans le
    /// champ : la conversion se fait ici, pas dans la vue de la ligne.
    private var phoneBinding: Binding<String> {
        Binding(
            get: { model.profile?.phoneNumber ?? "" },
            set: { model.setPhoneNumber($0) }
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

    /// Ce qu'on est en train de taper. Le modèle ne change qu'à la sortie du
    /// champ.
    @State private var draft = ""

    /// Deux états distincts, et non un seul : le champ n'existe que pendant
    /// l'édition, donc on ne peut pas lui donner le focus avant de l'avoir
    /// posé. Le premier ouvre l'édition, le second suit le clavier.
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    @ScaledMetric(relativeTo: .body) private var pencilSide: CGFloat = 18

    var body: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            // Un contrepoids invisible, de la largeur exacte du crayon.
            //
            // Sans lui, c'est la paire « nom + crayon » qui se centre, et le nom
            // se retrouve donc décalé vers la gauche de la moitié du crayon.
            // Avec lui, **le nom est centré** et le crayon déborde à droite —
            // c'est le décentrage voulu.
            Color.clear
                .frame(width: MemoBookSpacing.minimumTapTarget, height: 0)

            if isEditing {
                editor
            } else {
                label
            }

            pencil
        }
        // La colonne du nom ne prend jamais plus que la largeur de l'écran,
        // marges comprises : c'est cette limite qui déclenche la coupure du
        // texte au lieu de le laisser filer sous le crayon.
        .frame(maxWidth: .infinity)
        .onAppear { draft = name }
        .onChange(of: name) { _, value in
            if !isEditing { draft = value }
        }
        // Même contrat que les lignes : sortir du champ enregistre.
        .onChange(of: isFocused) { _, focused in
            if !focused { endEditing() }
        }
        .onDisappear {
            if isEditing { endEditing() }
        }
    }

    /// Le nom au repos. **Aucune limite de caractères** : c'est la largeur
    /// disponible qui décide, et un nom trop long se termine par des points de
    /// suspension plutôt que de pousser le crayon hors de l'écran.
    private var label: some View {
        Text(name)
            .font(MemoBookFont.h2)
            .foregroundStyle(MemoBookColor.ink)
            .lineLimit(1)
            .truncationMode(.tail)
            .contentShape(.rect)
            .onTapGesture(perform: beginEditing)
            .accessibilityLabel("Ton nom, \(name)")
    }

    /// Pendant l'édition, le champ prend toute la place restante : on doit
    /// pouvoir lire ce qu'on tape, y compris au-delà de ce que la vue au repos
    /// montrait.
    private var editor: some View {
        TextField("", text: $draft)
            .font(MemoBookFont.h2)
            .foregroundStyle(MemoBookColor.ink)
            .tint(MemoBookColor.action)
            .multilineTextAlignment(.center)
            .textContentType(.name)
            .submitLabel(.done)
            .focused($isFocused)
            .onSubmit { isFocused = false }
            .accessibilityLabel("Ton nom")
    }

    private var pencil: some View {
        Button(action: beginEditing) {
            Image(brand: "IconPen")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: pencilSide, height: pencilSide)
                .foregroundStyle(isEditing ? MemoBookColor.action : MemoBookColor.inkMuted)
                .frame(
                    width: MemoBookSpacing.minimumTapTarget,
                    height: MemoBookSpacing.minimumTapTarget
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Modifier ton nom")
    }

    private func beginEditing() {
        guard !isEditing else { return }
        draft = name
        isEditing = true
        // Le champ n'est posé qu'au rendu suivant : lui donner le focus tout de
        // suite ne toucherait rien.
        Task { isFocused = true }
    }

    private func endEditing() {
        isEditing = false
        onCommit(draft)
    }
}

/// La photo du voyageur, ou ses initiales. Jamais un rond gris vide : un profil
/// sans photo reste un profil.
///
/// Tant que le profil n'est pas arrivé, le rond est là quand même, vide : c'est
/// **la seule valeur de l'écran qui n'a pas besoin de barre d'attente**, parce
/// qu'un rond vide est déjà exactement ce qu'on verra si la personne n'a pas de
/// photo. Rien ne bouge quand elle arrive.
private struct ProfileAvatar: View {
    let profile: TravellerProfile?

    /// Taille **fixe**, comme l'avatar de l'accueil. Une photo n'est pas du
    /// texte : la faire grandir avec le Dynamic Type lui faisait prendre la
    /// moitié de l'écran en AX3, au détriment de ce qui, lui, se lit.
    private static let side: CGFloat = 80

    var body: some View {
        AsyncImage(url: profile?.avatarUrl) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Text(profile?.initials ?? "")
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
                // Sora, comme les libellés de bouton de la marque : ce sont
                // des boutons, pas des lignes de réglage. Voir
                // ``MemoBookFont/button``.
                Text(title)
                    .font(MemoBookFont.button)
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

#Preview("Profil — abonné") {
    NavigationStack {
        ProfileView(model: ProfileModel { .subscriberFixture }) {}
    }
}

#Preview("Profil — entré par Apple") {
    NavigationStack {
        ProfileView(model: ProfileModel { .appleFixture }) {}
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
