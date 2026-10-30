import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Les mesures que le chat partage entre son écran, son squelette et sa barre
/// d'envoi.
///
/// Au même endroit et pour la même raison que ``HomeMetrics`` : c'est parce que
/// le squelette et l'écran réel tombent aux mêmes places que le passage de l'un
/// à l'autre ne saute pas.
enum ChatMetrics {
    /// La hauteur d'une commande ronde de l'en-tête, et sa cible tactile.
    static let control = MemoBookSpacing.minimumTapTarget

    /// L'icône posée dans cette commande — voir ``MemoBookSpacing/contentIcon``.
    static let controlIcon = MemoBookSpacing.contentIcon

    /// Le fond des barres qui flottent au-dessus du fil — en-tête, rail de
    /// suggestions, barre d'envoi.
    ///
    /// La maquette demande du blanc à 50 % **et** un flou de 50 : c'est un
    /// matériau, pas une couleur. On prend celui du système plutôt que de le
    /// refaire, parce qu'il sait ce que la barre a derrière elle et s'adapte à
    /// la vitesse du défilement.
    static let barMaterial = Material.ultraThin

    /// Le pas entre deux messages du fil.
    static let messageSpacing = MemoBookSpacing.snug

    /// L'air laissé entre deux messages **du même auteur**. Plus serré : deux
    /// bulles de MEMO d'affilée sont une même prise de parole, pas deux.
    static let sameAuthorSpacing = MemoBookSpacing.xs / 2

    // ⚠️ `recordingBarCount` a disparu (Hugo, 19/09/2026). La frise ne compte
    // plus ses barres : elle en dessine autant que la place reçue peut en
    // tenir, et c'est ce qui l'empêche à la fois de s'arrêter avant le bord et
    // de faire grandir la barre qui la porte — voir ``BrandWaveform``.

    /// Combien de photos un envoi porte, et combien de vignettes sa bulle
    /// montre : six, le plus que MEMO demande pour une étape sur deux pages
    /// (`backend/src/services/photoBudget.ts`, Hugo, 01/10/2026). Le serveur
    /// applique la même borne (`MAX_PHOTOS`, `routes/chat.ts`).
    static let visiblePhotoCount = 6
}

/// L'en-tête du chat : d'où l'on vient, de quoi on parle, et les deux réglages
/// du voyage.
///
/// Il flotte au-dessus du fil plutôt que de le pousser : le contenu passe
/// dessous et se laisse deviner à travers le flou, ce qui dit que la
/// conversation continue au-delà du bord haut.
struct ChatHeader: View {
    let thread: ChatThread
    let onBack: () -> Void
    let onSettings: () -> Void
    let onBook: () -> Void

    /// Le serveur n'a pas encore reçu ce voyage : la roue et l'imprimante
    /// pâlissent — voir ``TripAwaitingServer``.
    var isAwaitingServer = false

    var body: some View {
        HStack(spacing: 0) {
            ChatHeaderButton(icon: "IconArrow", label: ChatCopy.Voice.back, action: onBack)

            Spacer(minLength: 0)

            identity

            Spacer(minLength: 0)

            ChatHeaderButton(
                icon: "IconSettings",
                label: ChatCopy.Voice.settings,
                action: onSettings
            )
            .dimmedWhileAwaitingServer(isAwaitingServer)
            // L'imprimante, **la même que sur l'accueil du voyage** (Hugo,
            // 17/09/2026) : les deux ouvrent l'aperçu du carnet, et deux dessins
            // pour une même porte se lisaient comme deux portes. C'est le même
            // écran que la bannière bleue du fil ouvre.
            ChatHeaderButton(icon: "IconPrinter", label: ChatCopy.Voice.openPreview, action: onBook)
                .dimmedWhileAwaitingServer(isAwaitingServer)
        }
        .padding(.horizontal, MemoBookSpacing.xs)
        .padding(.bottom, MemoBookSpacing.xs)
        .frame(maxWidth: .infinity)
        .background(ChatMetrics.barMaterial)
    }

    /// La vignette du voyage et son nom. Un seul élément pour VoiceOver : la
    /// photo ne dit rien que le titre ne dise déjà.
    private var identity: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            avatar

            Text(thread.title)
                .font(MemoBookFont.heading)
                .foregroundStyle(MemoBookColor.ink)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(thread.title)
    }

    /// La photo du voyage. Taille **fixe**, hors Dynamic Type : une photo n'est
    /// pas du texte, et un avatar qui grandit avec le corps pousserait le titre
    /// hors de sa ligne au lieu de l'accompagner.
    /// La photo du voyage — celle qu'on a choisie, sinon celle que le voyage a
    /// élue (`coverPhotoInclude`, côté serveur). Le serveur ne servait que la
    /// première, que presque personne ne choisit : l'en-tête montrait donc sa
    /// montagne pendant que l'accueil montrait une photo (Hugo, 28/10/2026).
    ///
    /// La montagne reste, pour un voyage dont aucune photo n'est encore
    /// arrivée. ``RemoteImage`` garde la photo décodée : elle ne repasse plus
    /// par la montagne à chaque ouverture du fil.
    private var avatar: some View {
        RemoteImage(url: thread.avatarUrl) {
            Image(brand: "IconMountain")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: MemoBookSpacing.m, height: MemoBookSpacing.m)
                .foregroundStyle(MemoBookColor.ink)
        }
        .frame(width: MemoBookSpacing.avatarSide, height: MemoBookSpacing.avatarSide)
        .background(MemoBookColor.outline, in: .circle)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

/// Une commande ronde de l'en-tête : une icône de 2 rem au centre d'une cible
/// de 2.75 rem.
///
/// Sans fond, contrairement à celles de l'accueil d'un voyage : là-bas elles
/// sont posées sur une photo qu'on ne choisit pas et il leur faut un disque
/// pour rester lisibles. Ici le fond est le crème de la marque, et un disque de
/// plus ne ferait qu'alourdir la ligne.
private struct ChatHeaderButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(brand: icon)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: ChatMetrics.controlIcon, height: ChatMetrics.controlIcon)
                .foregroundStyle(MemoBookColor.ink)
                .frame(width: ChatMetrics.control, height: ChatMetrics.control)
        }
        .contentShape(.rect)
        .accessibilityLabel(label)
    }
}

/// « Ton carnet prend forme » — la capsule posée sous l'en-tête, qui mène à
/// l'aperçu du carnet.
///
/// **Une capsule, pas une carte** (Hugo, 18/09/2026). La version d'avant
/// tenait trois lignes et toute la largeur du fil : elle se lisait comme un
/// message de plus, et un message qui revient toutes les dix secondes agace.
/// Celle-ci tient sur une ligne : elle se pose sur le fil sans le couvrir. Le
/// compte de souvenirs et de pages n'est plus écrit — il est dit à VoiceOver,
/// et l'aperçu le montre.
///
/// **Elle se détache par l'ombre, pas par la couleur** (Hugo, 15/10/2026).
/// Elle était en verre teinté du bleu du voyageur — c'est-à-dire de la couleur
/// des bulles qui défilent dessous : un calque ne porte pas la teinte de ce
/// qu'il survole, sinon il s'y fond. Verre crème, filet bleu et ``.raised``
/// désormais, l'ombre que la marque réserve à ce qui flotte au-dessus du fil.
/// Le filet et l'ombre sont aussi ce qui la distingue d'une bulle de MEMO, en
/// ``surface`` elle aussi, mais posée à plat sur la page.
///
/// **Et à droite, sous l'imprimante de l'en-tête** plutôt qu'au milieu (même
/// jour) : les deux ouvrent le même aperçu, et deux portes alignées se lisent
/// comme une seule. Au milieu, elle coupait en plus la première bulle — voir
/// l'``overlay`` de ``ChatView``, qui tient sa place.
struct ChatPreviewBanner: View {
    let preview: ChatBookPreview
    let onOpen: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var iconSide: CGFloat = 18

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: MemoBookSpacing.xs) {
                Image(brand: "IconPDF")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: iconSide, height: iconSide)
                    .accessibilityHidden(true)

                Text(ChatCopy.previewTitle)
                    .font(MemoBookFont.label)
                    .lineLimit(1)

                Image(brand: "IconArrowRight")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: iconSide, height: iconSide)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(MemoBookColor.ink)
            .padding(.horizontal, MemoBookSpacing.s)
            .padding(.vertical, MemoBookSpacing.xs + 2)
            .background(MemoBookColor.surface.opacity(0.75), in: .capsule)
            .background(.ultraThinMaterial, in: .capsule)
            .overlay { Capsule().strokeBorder(MemoBookColor.outline, lineWidth: 1) }
            .brandShadow(.raised)
            .contentShape(.capsule)
        }
        .buttonStyle(CardPressStyle())
        // **Toujours tapable** (Hugo, 30/09/2026). Elle se désactivait tant
        // que le serveur n'avait pas de PDF prêt (`isOpenable`) — donc presque
        // toujours, sans rien dire, alors que l'icône de carnet de l'en-tête
        // ouvre le même aperçu sans condition. C'est l'aperçu qui dit où en
        // est le carnet, pas la capsule.
        .accessibilityLabel(
            "\(ChatCopy.previewTitle). \(ChatCopy.previewSubtitle(memories: preview.memoryCount, pages: preview.pageCount))"
        )
        .accessibilityHint(ChatCopy.Voice.openPreview)
    }
}

/// L'accueil d'une conversation qui n'a rien dedans : le signe de la marque, le
/// voyage qu'on ouvre, et ce que MEMO propose d'en faire.
///
/// Il occupe la place du fil au lieu de se poser au-dessus : une conversation
/// vide n'a pas de haut ni de bas, elle a un centre.
struct ChatGreetingView: View {
    let greeting: ChatGreeting

    @ScaledMetric(relativeTo: .title3) private var markWidth: CGFloat = 64

    var body: some View {
        VStack(spacing: MemoBookSpacing.s) {
            BrandMarkDrawing(progress: 1, color: MemoBookColor.action)
                .frame(width: markWidth, height: BrandMark.height(forWidth: markWidth))
                .accessibilityHidden(true)

            Text(greeting.title)
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.ink)
                .accessibilityAddTraits(.isHeader)

            Text(greeting.message)
                .font(MemoBookFont.bubble)
                .foregroundStyle(MemoBookColor.inkMuted)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        .padding(.vertical, MemoBookSpacing.xl)
    }
}

/// « Ta conversation est privée… » — la mention posée **en tête du fil**,
/// avant le premier message.
///
/// **Dans le fil, pas par-dessus** : elle défile avec la conversation, comme
/// le début d'une page, au lieu de flotter sous l'en-tête et de cacher une
/// bulle. En gris, en petit : elle rassure sans prendre la parole.
struct ChatPrivacyNote: View {
    /// Le cadenas suit le corps du texte : c'est une ponctuation de la
    /// mention, pas une icône d'interface.
    @ScaledMetric(relativeTo: .caption) private var lockSide: CGFloat = 14

    var body: some View {
        VStack(spacing: MemoBookSpacing.xs / 2) {
            // **Un cadenas au-dessus** (Hugo, 28/10/2026) : la phrase se lit
            // d'un coup d'œil, l'icône dit de quoi elle parle avant même
            // qu'on la lise.
            Image(brand: "IconLocker")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: lockSide, height: lockSide)
                .foregroundStyle(MemoBookColor.inkMuted)
                .accessibilityHidden(true)

            Text(ChatCopy.privacyNote)
            // La seconde phrase sur sa propre ligne, et non à la suite d'un
            // deux-points : c'est elle qui dit qui peut lire.
            Text(ChatCopy.privacyNoteDetail)
        }
        .font(MemoBookFont.caption)
        .foregroundStyle(MemoBookColor.inkMuted)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        .padding(.vertical, MemoBookSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}
