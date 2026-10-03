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
    private let onIntent: (ProfileIntent) -> Void

    @State private var model: ProfileModel
    @State private var sheet: ProfileSheet?

    /// Les chiffres du compte, pour la feuille « Statistiques ». Un modèle à
    /// part : il a sa route, sa case de cache et sa veille, et il ne vit que le
    /// temps de la feuille — voir ``StatisticsModel``.
    @State private var statistics: StatisticsModel

    /// Le paywall se présente **par-dessus tout**, feuille comprise : c'est un
    /// écran entier, pas une feuille de plus. La feuille qui l'a ouvert se
    /// referme donc d'abord, sans quoi on la retrouverait dessous en sortant.
    @State private var showsPaywall = false

    /// L'alerte de suppression du compte. Une alerte du système, et non une
    /// feuille de la marque : c'est le seul geste de l'app qui ne se rattrape
    /// pas, et il doit ressembler à ce que l'utilisateur a déjà appris à
    /// craindre ailleurs.
    @State private var isConfirmingDeletion = false

    /// Le parcours de choix de la photo de profil — la feuille du système
    /// « Prendre une photo / Choisir dans la galerie », comme dans la
    /// conversation (Clara, 17/09/2026, T165).
    @State private var avatarPhotos = PhotoFlow()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.subscriptionSession) private var subscriptionSession

    /// La feuille « Moyens de paiement » de Stripe — posée par `RootView`.
    @Environment(\.managePaymentMethods) private var managePaymentMethods

    /// L'App Store, pour remettre au serveur un achat qu'il n'a pas encore
    /// reçu — voir ``loadProfile()``.
    @Environment(\.subscriptionPurchase) private var subscriptionPurchase

    /// Ce qui a empêché la feuille de Stripe de s'ouvrir.
    @State private var paymentMethodsError: String?

    public init(
        model: ProfileModel = ProfileModel(),
        statistics: StatisticsModel = StatisticsModel(),
        onSignOut: @escaping () -> Void,
        onIntent: @escaping (ProfileIntent) -> Void = { _ in }
    ) {
        _model = State(initialValue: model)
        _statistics = State(initialValue: statistics)
        self.onSignOut = onSignOut
        self.onIntent = onIntent
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
            // profil connu, parce qu'ils **existent ou non** selon que le
            // compte est abonné : la pastille « Abonné(e) », le bouton
            // « Découvrir l'abonnement » et la ligne « Mon abonnement ». Les
            // montrer par défaut puis les retirer serait pire que de les voir
            // arriver.
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                header

                identity
                subscriptionCallToAction
                statsGroup
                contactGroup
                servicesGroup
                paymentGroup
                legalGroup

                #if DEBUG
                    // **Chantier** : les connecteurs ne se branchent pas encore
                    // au serveur, et Tricount attend son intégration (T76). La
                    // carte reste visible en Debug, pas dans la version livrée
                    // (Hugo, 29/09/2026).
                    ConnectorsCallout { sheet = .connectors }
                #endif

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
        .photoFlow(
            avatarPhotos,
            title: "Photo de profil",
            maxSelection: 1,
            // « Supprimer la photo » n'est proposé que s'il y en a une : le
            // rond revient alors aux initiales (Hugo, 29/09/2026).
            onRemove: model.profile?.avatarUrl != nil || pendingAvatar != nil
                ? {
                    pendingAvatar = nil
                    Task { await model.removeAvatar() }
                }
                : nil
        ) { images in
            guard let data = images.first, let jpeg = ProfileAvatar.jpeg(from: data) else { return }
            // Le rond porte la photo **avant** l'aller-retour — voir
            // ``ProfileAvatar/pending``.
            pendingAvatar = UIImage(data: jpeg)
            Task { await model.setAvatar(jpeg) }
        }
        .background(MemoBookColor.background.ignoresSafeArea())
        // L'écran dessine son propre en-tête, comme la maquette : la flèche et
        // le titre partagent une ligne, à la marge de la colonne. Une barre de
        // navigation ne sait pas faire ça — sur iOS 26 elle enferme d'office un
        // élément personnalisé dans une pastille de verre, qui avale le titre.
        .brandHiddenNavigationBar()
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
        .task { await loadProfile() }
        // Ce que le profil sait de l'abonnement sert aux autres écrans : la
        // version du paywall, et l'illimité, qu'on ouvre l'offre depuis la
        // conversation ou les réglages d'un voyage.
        .onChange(of: model.profile, initial: true) { _, profile in
            if let profile { subscriptionSession?.learn(profile) }
        }
        .brandRefreshFlash(model.freshness.isUpdated)
        .brandSheet(item: $sheet) { destination in
            sheetContent(destination)
        }
        .fullScreenCover(isPresented: $showsPaywall) {
            PaywallView(
                subscription: effectiveSubscription,
                variant: paywallVariant,
                previewMemoId: model.profile?.currentTrip?.id,
                onSubscribe: {
                    // **Le geste, pas une copie locale** (03/10/2026) : la
                    // session fait l'écran d'un abonné tout de suite (voir
                    // ``effectiveSubscription``), et le profil se relit pour
                    // que le serveur le confirme — c'est cette confirmation
                    // qui rend la main au serveur. Retoucher le profil sur
                    // place l'aurait « confirmé » sans lui, et un serveur qui
                    // n'avait pas encore reçu l'achat aurait fait recompter un
                    // abonné qui paie.
                    subscriptionSession?.record(isSubscribed: true)
                    showsPaywall = false
                    Task { await model.load() }
                }
            )
        }
        // Les deux modales dessinées dans Figma (`3203:21809` sans voyage en
        // cours, `3206:21854` avec) remplacent l'alerte du système qui tenait
        // la place — Hugo, 14/09/2026 (T23). C'est une feuille de l'app, avec
        // le paragraphe entier : une alerte n'en tenait qu'un résumé.
        .brandSheet(isPresented: $isConfirmingDeletion) {
            DeleteAccountSheet(
                hasOngoingTrip: model.profile?.currentTrip != nil,
                mentionsSubscription: renewsAtApple,
                isDeleting: model.isDeletingAccount,
                onKeep: { isConfirmingDeletion = false },
                onDelete: {
                    Task {
                        // La sortie est la même que la déconnexion : le compte
                        // n'existe plus, l'app ne peut que revenir à l'entrée.
                        if await model.deleteAccount() {
                            isConfirmingDeletion = false
                            onSignOut()
                        }
                    }
                }
            )
        }
    }

    // MARK: - L'abonnement, tel qu'il faut le lire ici

    /// L'abonnement du profil, **corrigé par la session**.
    ///
    /// ``ProfileModel`` est un `@State` : l'écran se reconstruit à chaque fois
    /// qu'on y revient, et repartirait donc du jeu d'essai. La session pouvait
    /// donc **imposer** l'abonnement, et elle avait le dernier mot.
    ///
    /// ⚠️ **Elle ne l'a plus sur une résiliation** (Hugo, 19/09/2026), et c'est
    /// la seconde moitié du défaut qu'il a vu : après avoir confirmé trois
    /// fois, la feuille rouvrait sur « ABONNÉE ». La session ne sait pas si on
    /// est abonné, elle sait si l'on raconte sans limite — et pendant le mois
    /// déjà réglé, on le peut encore (``ProfileModel/subscriptionGrantsAccess``).
    /// Elle répondait donc « abonné » à une question qu'on ne lui posait pas,
    /// et ressuscitait l'abonnement qu'on venait de fermer.
    ///
    /// Elle peut toujours en **donner** un — un achat que le serveur n'a pas
    /// encore reçu, le bac à sable qui fait jouer un abonné —, jamais en
    /// **rendre** un : un abonnement résilié dans son mois payé raconte encore
    /// sans limite, et elle n'a rien à y ajouter.
    ///
    /// **Ce qu'elle donne est tenu par Apple** (03/10/2026). Tout achat fait
    /// dans l'app passe par StoreKit ; un abonnement que le serveur n'a pas
    /// encore vu (`awaitingServer`) gardait pourtant `managedByAppStore` faux,
    /// et « Mon abonnement » le résiliait « localement » par une route qui ne
    /// coupe rien chez Apple — pendant qu'Apple continuait de prélever et que
    /// la conversation recomptait les secondes d'un abonné qui paie. La
    /// résiliation passe donc par la feuille d'iOS, et son issue se lit sur
    /// StoreKit.
    private var effectiveSubscription: Subscription? {
        guard var subscription = model.profile?.subscription else { return nil }
        if model.isHeldByAppleOnly(subscriptionSession) {
            subscription.isActive = true
            subscription.cancelledAt = nil
            subscription.managedByAppStore = true
        }
        return subscription
    }

    /// L'abonnement va se renouveler chez Apple : supprimer le compte ne
    /// l'arrêtera pas, et la feuille de suppression doit le dire — **à lui
    /// seul** (03/10/2026). Le dire à un compte qui n'a jamais souscrit, la
    /// plupart depuis le crédit du jour, lui demandait de couper ce qu'il n'a
    /// pas. Sans profil chargé, on le dit, par prudence.
    private var renewsAtApple: Bool {
        guard let subscription = effectiveSubscription else { return true }
        return subscription.managedByAppStore && subscription.cancelledAt == nil && subscription.isUnlimited
    }

    /// Charge le profil — et, **quand un achat attend encore le serveur**,
    /// remet d'abord la transaction qu'Apple garde ouverte, puis relit
    /// (03/10/2026).
    ///
    /// La session dit « acheté » et le serveur ne connaît pas d'abonnement :
    /// c'est un achat encaissé par Apple que l'API n'a pas pris
    /// (`awaitingServer`). StoreKit ne le redonne de lui-même qu'au prochain
    /// lancement ; l'ouverture du profil est le moment où l'on vient vérifier.
    private func loadProfile() async {
        await model.load()
        guard model.isHeldByAppleOnly(subscriptionSession) else { return }
        await deliverPurchaseAndReload()
    }

    /// Remet à l'API l'achat qu'Apple garde ouvert, puis relit le profil : le
    /// serveur tranche.
    private func deliverPurchaseAndReload() async {
        guard let subscriptionPurchase else { return }
        await subscriptionPurchase.deliverUnfinished()
        await model.load()
    }

    /// Le compte raconte-t-il sans limite — lu sur le modèle **et** sur le
    /// dernier geste de la session (un achat, une résiliation, le bac à
    /// sable). Vrai tant que le profil n'est pas là : les trois blocs qui en
    /// dépendent attendent de le savoir plutôt que d'apparaître puis partir.
    private var isSubscriber: Bool {
        guard let profile = model.profile else { return true }
        return subscriptionSession?.override ?? profile.isSubscriber
    }

    /// Quelle version du paywall montrer.
    ///
    /// Qui a déjà été abonné revoit **deux** écrans au lieu de trois : il
    /// connaît déjà le produit, et l'app lui propose de résilier à la fin de
    /// chaque voyage — repasser par là est donc le cas ordinaire, pas
    /// l'exception. Le profil le sait par `hasEndedBefore`, la session par
    /// ce que l'accueil lui a appris.
    private var paywallVariant: PaywallVariant {
        if model.profile?.subscription.hasEndedBefore == true { return .returning }
        return subscriptionSession?.paywallVariant ?? .firstTime
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

            // « Profil », en français : la maquette écrivait « Profile », et
            // Clara l'a corrigée (14/09/2026, T17).
            Text("Profil")
                .font(MemoBookFont.h2)
                .foregroundStyle(MemoBookColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            subscriberPill
        }
    }

    /// « ABONNÉ(E) », sur la ligne du titre — **pour un abonné seulement**
    /// (Hugo, 03/10/2026). Il n'y a plus d'étapes à décompter : sans
    /// abonnement, c'est le bouton « Découvrir l'abonnement » qui parle, et la
    /// pastille se tait. Un constat, qui ne mène nulle part.
    ///
    /// **Elle partage la ligne du titre et ne flotte pas dans le coin** : c'est
    /// une étiquette posée sur l'écran, droite parce qu'alignée sur un titre —
    /// un libellé de travers à côté d'un mot horizontal se lit comme un défaut
    /// de rendu.
    @ViewBuilder
    private var subscriberPill: some View {
        if let profile = model.profile, isSubscriber {
            BrandTagPill(
                SubscriptionCopy.currentBadge(for: profile.gender),
                tone: .accentOutlined,
                isUppercased: true,
                // Elle se resserre plutôt que de renvoyer « Profil » à la ligne.
                shrinksToFit: true
            )
            // À partir d'AX1 elle prendrait la ligne entière et pousserait le
            // titre hors de l'écran. Elle garde alors sa taille, et elle seule.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }

    /// Le gros bouton lime de la maquette, et **rien d'autre au-dessus** : pour
    /// quelqu'un qui n'a pas d'abonnement, c'est la première chose de l'écran
    /// après son nom.
    ///
    /// Il disparaît une fois abonné, où la ligne « Mon abonnement » des services
    /// suffit : on ne revend pas ce qui est déjà acheté. C'est aussi ce qui fait
    /// que **résilier le fait revenir** — une fois le mois payé écoulé, le
    /// profil n'a plus d'abonnement, et l'offre reprend sa place.
    ///
    /// **Il ouvre le paywall directement** (Hugo, 03/10/2026) : la feuille
    /// « Comment ça fonctionne ? » qui le précédait racontait l'essai gratuit
    /// d'avant le crédit du jour, et elle est partie avec lui.
    @ViewBuilder
    private var subscriptionCallToAction: some View {
        if !isSubscriber {
            BrandButton(
                "Découvrir l’abonnement",
                icon: Image(brand: "IconArrowForward"),
                iconPlacement: .trailing,
                style: .accent,
                fillsWidth: true
            ) {
                showsPaywall = true
            }
            // La même limite que les autres CTA de l'app (accueil, offre) :
            // en très grand texte, « Découvrir l’abonnement » se coupait en
            // plein mot (recette du 03/10/2026). VoiceOver lit le libellé
            // entier quelle que soit la taille.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
    }

    /// Les chiffres du compte : combien de voyages, et lequel est en cours.
    ///
    /// **Le seul groupe cerclé de vert de l'écran.** C'est ce qu'on vient
    /// chercher du regard en ouvrant son profil ; tout le reste se range.
    ///
    /// **Les statistiques sont à tout le monde** (Hugo, 03/10/2026) : elles
    /// étaient « Réservé aux abonnés », sous un badge « Locked ». L'abonnement
    /// n'ouvre plus que l'illimité.
    private var statsGroup: some View {
        let profile = model.profile
        let isLoading = profile == nil

        // Les valeurs sont préparées ici plutôt que dans les appels : des
        // ternaires imbriqués dans une liste de lignes, et l'inférence de type
        // de Swift rend les armes sans rien dire d'utile.
        let statistics: String? = profile?.tripCountLabel
        let currentTrip: String? = profile.map {
            $0.currentTrip?.dateRangeLabel ?? "Aucun pour l’instant"
        }

        // ⚠️ La feuille existait et ne s'ouvrait plus : la ligne était
        // revenue sur `notYetRouted()` (constaté en recette le 30/09/2026).
        let openStatistics: (() -> Void)? = { sheet = .statistics }
        // Le voyage en cours s'ouvre depuis sa ligne — l'accueil du voyage,
        // celui de la carte de l'accueil (Clara, 17/09/2026).
        let openCurrentTrip: (() -> Void)? = profile?.currentTrip.map { trip in
            { onIntent(.openTrip(id: trip.id)) }
        }

        return BrandRowGroup(tone: .highlighted) {
            BrandRow(
                "Statistiques",
                value: statistics,
                titleTone: .accent,
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

    /// La photo qu'on vient de choisir, posée dans le rond le temps que le
    /// serveur la reçoive — et gardée ensuite, tant que l'adresse distante ne
    /// charge pas. Voir ``ProfileAvatar/pending``.
    @State private var pendingAvatar: UIImage?

    private var identity: some View {
        VStack(spacing: MemoBookSpacing.s) {
            VStack(spacing: MemoBookSpacing.xs) {
                ProfileAvatar(
                    profile: model.profile,
                    pending: pendingAvatar,
                    isUploading: model.isUploadingAvatar,
                    onTap: avatarPhotos.begin
                )

                if let denied = avatarPhotos.deniedMessage {
                    BrandNotice(denied, tone: .information)
                }

                // L'échec se dit là où l'on a touché — voir
                // ``ProfileModel/avatarErrorMessage``. « Réessayer » rouvre la
                // feuille : on ne sait pas si c'était un envoi ou un retrait.
                if let failure = model.avatarErrorMessage {
                    ErrorBanner(message: failure, retry: avatarPhotos.begin)
                }
            }

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
            // écran à part entière, que cette ligne ne peut pas tenir.
            //
            // **Le logo dit d'où elle vient**, quand c'est un compte tiers qui
            // la porte : l'autocollant Apple ou Google, petit, après
            // « E-mail » — et non plus la phrase « Gérée par ton compte … »
            // (Hugo, 17/09/2026). VoiceOver garde la phrase, qu'un logo ne
            // sait pas dire.
            // **Le fournisseur se dit, il ne se dessine pas** (Hugo,
            // 19/09/2026). La ligne portait le logo Apple ou Google en petit,
            // devant l'intitulé : cerné de bleu et réduit à quatorze points, il
            // se lisait comme une vignette sale au bout d'une ligne de
            // réglages. Trois mots en gris sous l'adresse disent la même chose
            // sans rien salir — et l'adresse, elle, garde toute la ligne et
            // s'abrège par la fin si elle est longue.
            BrandRow(
                "E-mail",
                value: profile?.email,
                isValueLoading: profile == nil,
                note: profile?.signInProvider.map { "Compte \($0.displayName)" }
            )
            // Sous l'adresse, **quand le compte a un mot de passe** (Hugo,
            // 29/09/2026) : un compte entré par Apple ou Google seul n'en a pas
            // à changer. La valeur est un masque — on ne montre jamais rien.
            if profile?.hasPassword ?? false {
                BrandRow("Mot de passe", value: "••••••••") { sheet = .password }
            }
            BrandRow(
                "Téléphone",
                text: phoneBinding,
                placeholder: "+33 6 00 00 00 00",
                keyboardType: .phonePad,
                textContentType: .telephoneNumber,
                isValueLoading: profile == nil,
                isConfirmed: model.justSaved == .phoneNumber
            )
            // Sans adresse, la ligne **invite** à en donner une, en vert et un
            // cran plus petit — Hugo, 14/09/2026 (T22). Une valeur vide se
            // lisait comme une ligne cassée.
            //
            // Avec une adresse, la ligne la résume et **la rouvre** : c'est la
            // même feuille qui corrige. La coche dit que le serveur l'a bien
            // reçue — la feuille s'est refermée avant sa réponse.
            let hasAddress = !(profile?.address.singleLine.isEmpty ?? true)
            BrandRow(
                "Adresse postale",
                value: profile.map { hasAddress ? $0.address.singleLine : "Ajouter une adresse" },
                valueTone: hasAddress ? .plain : .invitation,
                isValueLoading: profile == nil,
                isConfirmed: model.justSaved == .address
            ) {
                sheet = .postalAddress
            }
            // Juste sous l'adresse (Hugo, 17/09/2026, T76) : deviné sur le
            // prénom par le serveur, corrigé ici. Voir ``Gender``.
            BrandRow(
                "Genre",
                value: profile?.gender.label,
                isValueLoading: profile == nil
            ) {
                sheet = .gender
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
                valueTone: .prominent,
                isValueLoading: profile == nil,
                action: { onIntent(.openWallet) }
            )
            // Elle ne s'affiche qu'une fois abonné : sans abonnement, c'est le
            // bouton lime du haut qui porte la proposition, et deux entrées vers
            // la même feuille sur un même écran se marcheraient dessus.
            if model.profile != nil, isSubscriber {
                BrandRow("Mon abonnement") { sheet = .subscription }
            }
            BrandRow("Suivi des commandes") { sheet = .orderTracking }
            // « Confidentialité » n'est plus ici : la maquette la montrait dans
            // ce groupe **et** dans celui des conditions d'utilisation, et c'est
            // une erreur — elle ne vit que là-bas (Hugo, 14/09/2026, T18).
        }
    }

    /// **Les cartes du compte, chez Stripe** (01/10/2026). La ligne ouvrait un
    /// formulaire fait main qui demandait le numéro complet et ne parlait à
    /// personne ; elle ouvre désormais la feuille « Moyens de paiement » de
    /// Stripe, qui tient les cartes, en ajoute et en retire. L'app ne voit plus
    /// passer un seul numéro — et ne sait donc plus en afficher un ici : la
    /// ligne **invite**, comme celle de l'adresse (T22).
    private var paymentGroup: some View {
        BrandRowGroup {
            BrandRow(
                "Cartes bancaires",
                value: "Gérer mes cartes",
                valuePlacement: .below,
                valueTone: .invitation,
                isValueLoading: model.profile == nil
            ) {
                guard let managePaymentMethods else { return }
                Task { paymentMethodsError = await managePaymentMethods() }
            }
        }
        .alert(
            "Moyens de paiement indisponibles",
            isPresented: Binding(
                get: { paymentMethodsError != nil },
                set: { if !$0 { paymentMethodsError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(paymentMethodsError ?? "")
        }
    }

    private var legalGroup: some View {
        BrandRowGroup {
            BrandRow("Confidentialité") { onIntent(.openPrivacyPolicy) }
            BrandRow(TermsOfUse.document.title) { onIntent(.openTermsOfUse) }
        }
    }

    // MARK: - Sortir

    private var exitActions: some View {
        VStack(spacing: MemoBookSpacing.xs) {
            ProfileExitAction(
                // `Export data.svg`, dessiné pour cette ligne (Clara,
                // 17/09/2026, T162) — `Export.svg` est le partage d'un fichier.
                // Le halo orange que l'export portait autour du signe est
                // retiré du fichier : la ligne se dessine comme les deux
                // d'en dessous, le signe seul dans sa teinte (Hugo, 18/09/2026).
                icon: Image(brand: "IconExportData"),
                title: "Exporter mes données",
                tint: MemoBookColor.warning
            ) {
                // Le lien part par e-mail ; l'archive se compose quand on
                // l'ouvre — voir ``DataExportSheet``.
                sheet = .dataExport
            }
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
    /// sortie de secours de l'app, et il mène désormais au support.
    ///
    /// Il passe **avant** les actions de sortie, et pas après : demander de
    /// l'aide n'est pas quitter. Le laisser sous « Supprimer mon compte » le
    /// rangeait avec les portes de sortie, alors qu'il est là pour éviter d'en
    /// prendre une.
    private var helpLink: some View {
        BrandButton("Besoin d’aide ?", style: .link, isSubdued: true) {
            onIntent(.openHelp)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Feuilles

    @ViewBuilder
    private func sheetContent(_ destination: ProfileSheet) -> some View {
        switch destination {
        case .postalAddress:
            PostalAddressSheet(
                address: model.profile?.address ?? PostalAddress(),
                countries: model.profile?.shippingCountries ?? []
            ) {
                model.save(address: $0)
            }
        case .gender:
            GenderSheet(current: model.profile?.gender ?? .undisclosed) {
                model.setGender($0)
            }
        case .password:
            PasswordChangeSheet(
                model: PasswordChangeModel(
                    email: model.profile?.email ?? "",
                    change: model.changePassword,
                    requestReset: model.requestPasswordReset
                )
            )
        case .subscription:
            SubscriptionSheet(
                subscription: effectiveSubscription,
                onActivate: {
                    model.activateSubscription()
                    subscriptionSession?.record(isSubscribed: true)
                },
                onCancel: {
                    model.cancelSubscription(reason: $0)
                    // **Le mois payé compte comme un abonnement** : l'illimité
                    // reste ouvert jusqu'à sa fin. La session retient donc
                    // l'accès réel, pas le geste — sans ça, la conversation
                    // recompterait les secondes de quelqu'un qui a encore trois
                    // semaines réglées devant lui.
                    subscriptionSession?.record(isSubscribed: model.subscriptionGrantsAccess)
                },
                onRecordReason: { model.recordCancellationReason($0) },
                onAppStoreRenewal: { renews in
                    // Même règle qu'au-dessus — le mois payé garde l'illimité,
                    // même renouvellement coupé —, sauf pour un achat que le
                    // serveur n'a pas encore reçu : Apple tient la période, la
                    // ligne du serveur n'en sait rien. On remet la transaction
                    // et on relit. Voir ``ProfileModel/settleAppStoreRenewal(_:session:)``.
                    if model.settleAppStoreRenewal(renews, session: subscriptionSession) {
                        Task { await deliverPurchaseAndReload() }
                    }
                },
                gender: model.profile?.gender ?? .undisclosed
            )
        case .connectors:
            ConnectorsSheet(model: model)
        case .statistics:
            StatisticsSheet(model: statistics)
        case .dataExport:
            DataExportSheet(model: model)
        case .orderTracking:
            OrderTrackingSheet(
                orders: model.profile?.orders ?? [],
                ongoingTrip: model.profile?.currentTrip,
                onPlanTrip: {
                    // La feuille se referme **avant** que la galerie s'ouvre :
                    // c'est un écran poussé sur la pile du profil, pas une
                    // feuille de plus.
                    sheet = nil
                    onIntent(.openGallery)
                },
                onOrder: { trip in
                    sheet = nil
                    onIntent(.orderBook(memoId: trip.id))
                }
            )
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
}

/// Où mène chaque ligne du profil.
enum ProfileSheet: String, Identifiable, CaseIterable {
    case postalAddress
    case gender
    case password
    case subscription
    case connectors
    case orderTracking
    case statistics
    case dataExport

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

    /// **Petit**, comme celui des lignes (``BrandRow``) : 1 rem de dessin, sans
    /// cerne ni fond, dans une cible de 2.75 rem — Hugo, 14/09/2026 (T24).
    @ScaledMetric(relativeTo: .body) private var pencilSide: CGFloat = 16

    var body: some View {
        Group {
            if isEditing {
                editor
            } else {
                label
            }
        }
        // Le nom se centre dans la colonne entière, et laisse de chaque côté la
        // place du crayon : c'est cette limite qui déclenche la coupure du
        // texte au lieu de le laisser filer dessous.
        .padding(.horizontal, MemoBookSpacing.minimumTapTarget)
        .frame(maxWidth: .infinity)
        // Le crayon est **au bord droit de la colonne**, à l'aplomb des
        // chevrons et des crayons des lignes du dessous — pas collé au nom, qui
        // se décalerait avec lui à chaque lettre (T24).
        .overlay(alignment: .trailing) { pencil }
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

    /// La photo qu'on vient de choisir, avant même que le serveur l'ait reçue.
    ///
    /// **Elle se pose tout de suite** (Hugo, 19/09/2026). Le rond n'affichait
    /// que `avatarUrl`, c'est-à-dire la photo *du serveur* : entre le moment où
    /// l'on choisit dans sa pellicule et celui où l'API répond, le rond gardait
    /// ses initiales — et si l'API déployée ne sert pas encore les avatars, il
    /// les gardait pour toujours. On montre donc ce qu'on vient de choisir, et
    /// l'adresse distante prend le relais quand elle arrive.
    var pending: UIImage?

    /// La photo est en route : le rond s'assombrit et tourne.
    var isUploading = false
    /// Le rond **se touche** : il ouvre la feuille « Prendre une photo /
    /// Choisir dans la galerie » (Clara, 17/09/2026, T165).
    var onTap: () -> Void = {}

    /// Taille **fixe**, comme l'avatar de l'accueil. Une photo n'est pas du
    /// texte : la faire grandir avec le Dynamic Type lui faisait prendre la
    /// moitié de l'écran en AX3, au détriment de ce qui, lui, se lit.
    private static let side: CGFloat = 80

    /// Le plus grand côté envoyé au serveur. Le rond fait 80 pt, l'accueil 40 :
    /// 512 px couvre trois fois l'écran le plus dense, et pèse quelques dizaines
    /// de kilo-octets au lieu des mégaoctets d'une photo d'iPhone.
    private static let uploadSide: CGFloat = 512

    var body: some View {
        Button(action: onTap) {
            AsyncImage(url: profile?.avatarUrl) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else if let pending {
                    Image(uiImage: pending).resizable().scaledToFill()
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
            .overlay {
                if isUploading {
                    Circle().fill(MemoBookColor.ink.opacity(0.35))
                    ProgressView().tint(MemoBookColor.onAction)
                }
            }
            // Le petit crayon cerclé, à cheval sur le bord du rond : c'est lui
            // qui dit que la photo se change — le même dessin que les crayons
            // des couvertures.
            .overlay(alignment: .bottomTrailing) {
                Image(brand: "IconPen")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: MemoBookSpacing.snug, height: MemoBookSpacing.snug)
                    .foregroundStyle(MemoBookColor.action)
                    .frame(width: MemoBookSpacing.m + 4, height: MemoBookSpacing.m + 4)
                    .background(MemoBookColor.surface, in: .circle)
                    .overlay { Circle().strokeBorder(MemoBookColor.outline, lineWidth: 1.5) }
                    .offset(x: 4, y: 4)
            }
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(isUploading || profile == nil)
        .accessibilityLabel("Photo de profil")
        .accessibilityHint("Prendre une photo, en choisir une dans la galerie, ou retirer celle-ci")
    }

    /// Réduit la photo choisie à ce que le serveur a besoin de garder, en
    /// JPEG. `nil` si ce n'est pas une image lisible.
    static func jpeg(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, uploadSide / max(longest, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.85)
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
                    .foregroundStyle(MemoBookColor.blueText)
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
            .frame(width: MemoBookSpacing.contentIcon, height: MemoBookSpacing.contentIcon)
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

    /// La copie corrigée dans Figma le 14/09/2026 (T17) : « à », « permet »,
    /// et le tutoiement de R9. Elle a longtemps été recopiée avec ses trois
    /// coquilles, parce que R8 interdit de corriger en silence.
    static let promise =
        "Connecter MemoBook à des applications externes te permet d’étoffer tes aventures de manière intelligente."
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
                    .frame(width: MemoBookSpacing.contentIcon, height: MemoBookSpacing.contentIcon)
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

#Preview("Profil — sans abonnement") {
    NavigationStack {
        ProfileView(model: ProfileModel { .freeFixture }) {}
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

/// Ce que le profil demande à l'app d'ouvrir.
///
/// Une seule destination pour l'instant, et c'est la cagnotte : toutes les
/// autres lignes de l'écran ouvrent des feuilles, qui vivent dans l'écran. La
/// cagnotte, elle, est un écran entier — et le **même** que celui qu'ouvrent
/// les paramètres d'un voyage, parce que c'est la même somme.
public enum ProfileIntent: Sendable, Hashable {
    case openWallet
    /// Le voyage en cours, depuis sa ligne de la carte de chiffres : l'accueil
    /// du voyage, le même écran que la carte de l'accueil (Clara, 17/09/2026).
    case openTrip(id: String)
    /// Les carnets de la communauté, depuis la feuille des commandes quand il
    /// n'y en a aucune : c'est là que la maquette envoie (`3162:34917`).
    case openGallery
    /// « Besoin d'aide ? », depuis le bas du profil comme depuis la barre du
    /// paywall. La même destination dans les deux cas : le support.
    case openHelp
    /// Les deux lignes du groupe légal : un document en chapitres. Un écran
    /// poussé et non une feuille — un contrat se lit en entier, et une feuille
    /// se ferme d'un glissé sans qu'on l'ait voulu.
    case openTermsOfUse
    case openPrivacyPolicy
    /// « Commander mon carnet », depuis le suivi des commandes sans commande.
    case orderBook(memoId: String)
}
