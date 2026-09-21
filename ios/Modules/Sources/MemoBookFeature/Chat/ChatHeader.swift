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

    /// Combien de vignettes une bulle de photos montre avant de compter le
    /// reste. Quatre, comme `agents/agent-conversation.md` le demande — « 2 à 4
    /// photos par souvenir maximum ».
    static let visiblePhotoCount = 4
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
            // L'imprimante, **la même que sur l'accueil du voyage** (Hugo,
            // 17/09/2026) : les deux ouvrent l'aperçu du carnet, et deux dessins
            // pour une même porte se lisaient comme deux portes. C'est le même
            // écran que la bannière bleue du fil ouvre.
            ChatHeaderButton(icon: "IconPrinter", label: ChatCopy.Voice.openPreview, action: onBook)
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
    private var avatar: some View {
        AsyncImage(url: thread.avatarUrl) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(brand: "IconMountain")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: MemoBookSpacing.m, height: MemoBookSpacing.m)
                    .foregroundStyle(MemoBookColor.ink)
            }
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
/// Celle-ci tient sur une ligne, au milieu, en verre teinté du bleu du
/// voyageur : elle se pose sur le fil sans le couvrir. Le compte de souvenirs
/// et de pages n'est plus écrit — il est dit à VoiceOver, et l'aperçu le
/// montre.
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
            .background(MemoBookColor.bubbleTraveller.opacity(0.75), in: .capsule)
            .background(.ultraThinMaterial, in: .capsule)
            .overlay { Capsule().strokeBorder(MemoBookColor.outline, lineWidth: 1) }
            .contentShape(.capsule)
        }
        .buttonStyle(CardPressStyle())
        .disabled(!preview.isOpenable)
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
