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

    /// L'icône posée dans cette commande.
    static let controlIcon = MemoBookSpacing.m

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

    /// Combien de barres la frise de la barre d'envoi affiche.
    ///
    /// La maquette dessine 96 pt de frise ; à 3 pt de barre et 2 pt d'air, ça en
    /// fait dix-neuf. C'est **la** constante qui règle la vitesse apparente du
    /// défilement : avec un relevé toutes les 90 ms, dix-neuf barres font
    /// glisser un peu moins de deux secondes de voix.
    static let recordingBarCount = 19

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
    let onMap: () -> Void

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
            ChatHeaderButton(icon: "IconGlobe", label: ChatCopy.Voice.map, action: onMap)
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
                    .frame(width: MemoBookSpacing.s, height: MemoBookSpacing.s)
                    .foregroundStyle(MemoBookColor.ink)
            }
        }
        .frame(width: MemoBookSpacing.avatarSide, height: MemoBookSpacing.avatarSide)
        .background(MemoBookColor.outline, in: .circle)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

/// Une commande ronde de l'en-tête : une icône de 1.5 rem au centre d'une cible
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

/// La bannière « Aperçu en direct » : ce que la conversation a déjà produit.
///
/// Elle est là pour une seule raison — raconter dans le vide est décourageant.
/// Deux compteurs suffisent à montrer que le carnet monte pendant qu'on parle.
struct ChatPreviewBanner: View {
    let preview: ChatBookPreview
    let onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = MemoBookSpacing.m

    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
    }

    var body: some View {
        Button(action: onOpen) {
            content
                .padding(.horizontal, MemoBookSpacing.s)
                .padding(.vertical, MemoBookSpacing.sectionGap)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MemoBookColor.bubbleTraveller, in: shape)
                .overlay { shape.strokeBorder(MemoBookColor.action, lineWidth: 1) }
                .contentShape(shape)
        }
        .buttonStyle(CardPressStyle())
        .disabled(!preview.isOpenable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            "\(ChatCopy.previewTitle). \(ChatCopy.previewSubtitle(memories: preview.memoryCount, pages: preview.pageCount))"
        )
        .accessibilityHint(ChatCopy.Voice.openPreview)
    }

    /// En taille accessible, la vignette et la flèche passent au-dessus du
    /// texte : leur garder une colonne chacune ne laisserait au titre que deux
    /// mots de large.
    @ViewBuilder
    private var content: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
                HStack(spacing: MemoBookSpacing.snug) {
                    mark
                    Spacer(minLength: 0)
                    arrow
                }
                text
            }
        } else {
            HStack(spacing: MemoBookSpacing.snug) {
                mark
                text
                Spacer(minLength: MemoBookSpacing.xs)
                arrow
            }
        }
    }

    private var mark: some View {
        Image(brand: "IconPDF")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: iconSide, height: iconSide)
            .foregroundStyle(MemoBookColor.ink)
            .padding(MemoBookSpacing.xs + 2)
            .background(MemoBookColor.surface.opacity(0.5), in: .rect(cornerRadius: MemoBookSpacing.snug))
            .accessibilityHidden(true)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            // La pastille de la maquette est en General Sans Semibold 10 ; l'app
            // n'est pas descendue sous 12 et n'a pas de raison de commencer ici.
            // Écart signalé dans la fiche écran.
            Text(ChatCopy.previewOverline)
                .font(MemoBookFont.overline)
                .foregroundStyle(MemoBookColor.action)
                .padding(.horizontal, MemoBookSpacing.xs / 2)
                .padding(.vertical, 2)
                .background(
                    MemoBookColor.bubbleTraveller.opacity(0.2),
                    in: .rect(cornerRadius: MemoBookSpacing.xs)
                )

            Text(ChatCopy.previewTitle)
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.ink)

            Text(ChatCopy.previewSubtitle(memories: preview.memoryCount, pages: preview.pageCount))
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.ink)
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var arrow: some View {
        Image(brand: "IconArrowRight")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: iconSide, height: iconSide)
            .foregroundStyle(MemoBookColor.ink)
            .accessibilityHidden(true)
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
