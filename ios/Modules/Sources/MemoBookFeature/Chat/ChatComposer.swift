import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Ce qui est posé en bas de l'écran : les réponses que MEMO propose, et de quoi
/// répondre autrement.
///
/// Les deux bandes flottent au-dessus du fil sur le même matériau que
/// l'en-tête : la conversation passe dessous et se laisse deviner, ce qui dit
/// qu'elle continue au-delà du bord.
///
/// **Le crédit du jour** (Hugo, 03/10/2026) : pendant qu'on parle, le bandeau
/// rouge doux paraît à trente secondes de la limite **à la place des puces**
/// — qui n'ont rien à faire sous un micro ouvert. Au repos, « Crédit du jour
/// épuisé » se pose **au-dessus** d'elles quand on touche le micro ou le
/// clavier pâlis, et s'en va de lui-même : les puces sont gratuites, et c'est
/// avec elles qu'on valide une fiche (recette du 03/10/2026). **Dans la pile,
/// jamais en calque** : sinon il ne se toucherait pas (voir la note de
/// ``ChatView``). Quand on écrit, la boîte « trop long » prend la place des
/// puces ; le rappel discret des caractères qui restent se glisse, lui, juste
/// au-dessus du champ.
struct ChatComposer: View {
    @Bindable var model: ChatModel
    @FocusState.Binding var isWriting: Bool
    let onAddPhotos: () -> Void

    /// Ce que fait le bandeau « Crédit du jour épuisé » : ouvrir l'offre.
    var onSubscribe: () -> Void = {}

    /// La puce en vol vers le fil, s'il y en a une : la bande la cache, c'est
    /// sa copie en vol qu'on regarde. Voir ``ChatView/launch(_:from:)``.
    var flyingSuggestionId: String? = nil

    /// Ce qu'une puce fait quand on la touche, avec son cadre à l'écran. `nil`
    /// envoie tout de suite, sans vol.
    var onLaunch: ((ChatSuggestion, CGRect) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            aboveTheBar

            if case .reminder(let reminder) = model.creditTextNotice {
                Text(reminder)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, MemoBookSpacing.screenMargin)
                    .padding(.top, MemoBookSpacing.xs / 2)
                    .transition(.opacity)
            }

            ChatSendingBar(model: model, isWriting: $isWriting, onAddPhotos: onAddPhotos)
        }
        // La place gardée de la bande se rend en douceur quand MEMO a répondu
        // sans nouvelles puces — voir ``ChatModel/reservesSuggestionRail``.
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: model.reservesSuggestionRail)
        // Le bandeau arrive et s'en va en douceur — sur son **état**, pas sur
        // son compte à rebours, qui change chaque seconde.
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: bannerState)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: model.creditTextNotice)
        .background(ChatMetrics.barMaterial)
    }

    /// Ce qui se pose au-dessus de la barre. Pendant qu'on parle, le bandeau
    /// du compte à rebours **à la place** des puces, muettes de toute façon.
    /// Sinon, le bandeau « épuisé » quand il est demandé, **au-dessus** de la
    /// boîte « trop long » ou des puces — jamais à leur place : « Ça me
    /// convient » doit rester à portée de doigt, crédit ou pas.
    @ViewBuilder
    private var aboveTheBar: some View {
        if model.recorder.isRecording, let banner = model.creditBanner {
            creditBanner(banner)
        } else {
            if let banner = model.creditBanner { creditBanner(banner) }
            noticeOrSuggestions
        }
    }

    private func creditBanner(_ banner: DailyCreditBanner) -> some View {
        DailyCreditBannerView(banner: banner, onSubscribe: onSubscribe)
            .padding(.horizontal, MemoBookSpacing.snug)
            .padding(.top, MemoBookSpacing.xs)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// La boîte « trop long », sinon les puces — qui gardent leur place,
    /// vides, pendant qu'on parle.
    @ViewBuilder
    private var noticeOrSuggestions: some View {
        if case .tooLong(let message) = model.creditTextNotice {
            BrandNotice(message, tone: .information) { EmptyView() }
                .padding(.horizontal, MemoBookSpacing.snug)
                .padding(.top, MemoBookSpacing.xs)
                .transition(.opacity)
        } else {
            ChatSuggestionRail(
                model: model,
                onAddPhotos: onAddPhotos,
                flyingSuggestionId: flyingSuggestionId,
                onLaunch: onLaunch,
                isMuted: model.recorder.isRecording
            )
        }
    }

    /// L'état du bandeau sans son chiffre — ce sur quoi il s'anime.
    private var bannerState: Int {
        switch model.creditBanner {
        case nil: 0
        case .warning: 1
        case .urgent: 2
        case .exhausted: 3
        }
    }
}

/// Les réponses toutes prêtes que MEMO propose.
///
/// **Une bande qui défile, comme celle des filtres d'un voyage.** Les puces
/// portent des phrases entières — « J'aimerais faire des modifications à la
/// main » —, aucune largeur d'iPhone n'en tient trois, et les serrer les
/// rendrait illisibles.
///
/// **Elle reste horizontale à toutes les tailles de texte**, contrairement à la
/// règle des composants en colonnes — et **chaque puce tient sur une ligne**,
/// aussi longue soit-elle. Deux détours ont été essayés et rejetés :
///
/// - les **empiler** en taille accessible : trois puces de deux lignes chacune
///   mangeaient la moitié de l'écran au-dessus de la barre d'envoi, et
///   poussaient la conversation hors de vue ;
/// - les laisser **se replier sur deux lignes** : une `ScrollView` horizontale
///   propose une largeur infinie à son contenu, la puce se mesurait donc sur
///   une ligne, et sa seconde ligne se dessinait hors de son fond blanc.
///
/// Une bande qui défile a déjà sa réponse au débordement, et c'est le
/// défilement. Une puce plus large que l'écran se lit en faisant glisser la
/// bande — c'est exactement ce que la maquette montre, la dernière puce sortant
/// par le bord droit.
struct ChatSuggestionRail: View {
    @Bindable var model: ChatModel
    let onAddPhotos: () -> Void
    var flyingSuggestionId: String? = nil
    var onLaunch: ((ChatSuggestion, CGRect) -> Void)? = nil

    /// Un micro est ouvert : les puces s'effacent mais **gardent leur place**.
    /// Une puce touchée pendant qu'on parle partirait par-dessus le vocal, et
    /// la bande qui disparaîtrait ferait sauter le fil au premier mot ; c'est
    /// aussi là que le bandeau du crédit viendra se poser.
    var isMuted = false

    /// La hauteur d'une puce : **plus basse qu'une bulle du fil** (Hugo,
    /// 29/09/2026) — 2 rem, en corps d'accroche — pour qu'on lise une
    /// proposition et non un message déjà dit. Elle suit le corps du texte.
    @ScaledMetric(relativeTo: .subheadline) private var chipHeight: CGFloat = MemoBookSpacing.l

    /// La hauteur de la bande : la puce et ses marges, jamais moins qu'une
    /// cible tactile — la puce est plus basse que 2.75 rem, la bande non.
    private var railHeight: CGFloat {
        max(MemoBookSpacing.minimumTapTarget, chipHeight + MemoBookSpacing.xs)
    }

    /// Les cadres des puces à l'écran, par identifiant : le point de départ du
    /// vol quand on en touche une.
    @State private var frames: [String: CGRect] = [:]

    var body: some View {
        let suggestions = model.visibleSuggestions

        if isMuted {
            if !suggestions.isEmpty || model.reservesSuggestionRail {
                Color.clear
                    .frame(height: railHeight)
                    .padding(.vertical, MemoBookSpacing.xs / 2)
                    .accessibilityHidden(true)
            }
        } else if !suggestions.isEmpty {
            ScrollView(.horizontal) {
                HStack(alignment: .center, spacing: MemoBookSpacing.xs) {
                    ForEach(suggestions, content: chip)
                }
                .padding(.horizontal, MemoBookSpacing.snug)
            }
            .scrollIndicators(.hidden)
            // La bande prend toute la largeur ; ce sont ses puces qui
            // s'alignent sur la colonne, pour que la dernière puisse sortir par
            // le bord au lieu de buter sur une marge.
            .scrollClipDisabled()
            // ⚠️ **La bande impose sa hauteur.** Une `ScrollView` est gourmande
            // sur ses deux axes : posée dans la barre du bas, elle se faisait
            // attribuer une hauteur plus courte que ses puces. Elles restaient
            // dessinées — `scrollClipDisabled` le permet — mais **hors de sa
            // zone tactile** : on les voyait, et taper dessus ne faisait rien.
            .frame(height: railHeight)
            .padding(.vertical, MemoBookSpacing.xs / 2)
            .transition(.opacity)
        } else if model.reservesSuggestionRail {
            // La place de la bande le temps que MEMO réponde — voir
            // ``ChatModel/reservesSuggestionRail``. **Des puces grises qui
            // chargent**, et non une ligne vide (Hugo, 08/10/2026) : la bande
            // dit qu'elle attend les prochaines propositions.
            pendingChips
                .frame(height: railHeight)
                .padding(.vertical, MemoBookSpacing.xs / 2)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }

    /// Les largeurs des puces d'attente : trois propositions de longueurs
    /// différentes, comme les vraies — trois barres égales se liraient comme
    /// un motif, pas comme des phrases qui arrivent.
    private static let pendingChipWidths: [CGFloat] = [132, 176, 112]

    /// Trois puces de la forme et de la hauteur des vraies, en
    /// ``BrandSkeleton`` : le reflet qui les traverse dit que ça charge, et la
    /// place qu'elles tiennent est celle que les propositions prendront.
    private var pendingChips: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            ForEach(Self.pendingChipWidths, id: \.self) { width in
                BrandSkeleton(width: width, height: chipHeight)
            }
        }
        .padding(.horizontal, MemoBookSpacing.snug)
        .frame(maxWidth: .infinity, alignment: .leading)
        // La bande ne défile pas : la dernière puce sort par le bord, comme
        // une vraie proposition trop longue pour l'écran.
        .clipped()
    }

    private func chip(_ suggestion: ChatSuggestion) -> some View {
        let isFlying = flyingSuggestionId == suggestion.id

        return Button {
            if let onLaunch, let frame = frames[suggestion.id] {
                onLaunch(suggestion, frame)
            } else {
                model.choose(suggestion, addPhotos: onAddPhotos)
            }
        } label: {
            HStack(spacing: MemoBookSpacing.xs / 2) {
                if let symbol = suggestion.symbol {
                    // L'emoji est porté à part du libellé : il ne part pas dans
                    // le message envoyé, et VoiceOver ne le lit pas.
                    Text(symbol)
                        .font(MemoBookFont.taglineRegular)
                        .accessibilityHidden(true)
                }
                Text(suggestion.label)
                    // Le corps d'accroche (14) et non celui des bulles (17) :
                    // une proposition se lit plus petit que ce qu'on a dit.
                    .font(MemoBookFont.taglineRegular)
                    .foregroundStyle(MemoBookColor.ink)
                    // Une ligne, jamais tronquée : la puce s'allonge autant
                    // qu'il faut, et c'est la bande qui défile.
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, MemoBookSpacing.snug)
            .frame(height: chipHeight)
            // **Une capsule**, blanche, l'émoji devant : c'est la bulle des
            // propositions de la maquette de Hugo (`3520:35958`, 17/09/2026),
            // et non le rectangle arrondi des bulles du fil.
            .background(MemoBookColor.surface, in: .capsule)
            .overlay { Capsule().strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
            // La cible reste à 2.75 rem, la puce dessinée plus basse (R7).
            .frame(height: railHeight)
            .contentShape(.capsule)
        }
        .buttonStyle(CardPressStyle())
        // Pendant son vol, la puce laisse sa place vide : c'est sa copie en
        // vol qu'on regarde, et elle part d'ici.
        .opacity(isFlying ? 0 : 1)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) {
            frames[suggestion.id] = $0
        }
        .accessibilityLabel(suggestion.label)
    }
}

// MARK: - La barre d'envoi

/// La barre d'envoi, dans ses quatre dispositions.
///
/// | Disposition | Ce qu'on voit | Nœud Figma |
/// |---|---|---|
/// | ``ChatComposerMode/tools`` | burger · photo · clavier · micro, à égalité de largeur | `start` |
/// | ``ChatComposerMode/speaking`` | croix · photo · clavier serrés, « Record » qui s'étire | `Default` |
/// | ``ChatComposerMode/writing`` | croix · le champ · le micro | `Start Typing` / `Finish Typing` |
/// | *en cours d'enregistrement* | croix · pause ou corbeille · la frise · le chrono · envoyer | `Start Recording` / `Finish Recording` |
///
/// Le dernier n'est pas un mode : il se lit sur ``AudioRecorder/isRecording``.
/// Deux sources pour le même fait finissent toujours par se contredire.
///
/// **Chaque disposition a sa variante « sans micro »** — l'accès peut être
/// refusé, et iOS ne redemande pas. Le bouton garde alors sa place, perd son
/// cerne vert et porte un micro **barré** : il a quelque chose à dire (où aller
/// le réautoriser), ce qu'un bouton absent ne dirait pas.
///
/// **Tout bouge au ressort.** Les dispositions ne se remplacent pas, elles
/// s'échangent : ce qui part rétrécit, ce qui arrive dépasse d'un cheveu puis
/// revient. C'est ce léger dépassement qui fait que la barre a l'air vivante
/// plutôt que redessinée — et il s'annule sous « Réduire les animations ».
///
/// ⚠️ La maquette ne dessine **pas** la croix : ses états de saisie n'ont aucune
/// commande à gauche. Elle est ajoutée sur demande de Hugo — pouvoir revenir à
/// l'état d'origine à tout moment — et prend la place du burger, qui n'a de sens
/// qu'au repos.
struct ChatSendingBar: View {
    @Bindable var model: ChatModel
    @FocusState.Binding var isWriting: Bool
    let onAddPhotos: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = MemoBookSpacing.sectionGap

    /// La hauteur des boutons ronds de la barre — celle d'un ``BrandButton``
    /// rond. Le champ de saisie la prend aussi, à une ligne.
    @ScaledMetric(relativeTo: .body) private var barHeight: CGFloat = MemoBookSpacing.controlHeight

    /// Ce qui sépare la cible de l'avion du bord droit du champ, pour que son
    /// rond soit **aussi loin du bord que du haut et du bas** : il se pose
    /// dans le champ comme dans une capsule.
    private var sendInset: CGFloat {
        let margin = (barHeight - MemoBookSpacing.contentIcon) / 2
        let targetPadding = (MemoBookSpacing.minimumTapTarget - MemoBookSpacing.contentIcon) / 2
        return max(0, margin - targetPadding)
    }

    /// Le ressort de la barre.
    ///
    /// Sous-amorti **exprès** : la barre dépasse d'un cheveu puis revient, ce
    /// qui donne le rebond. Une courbe amortie à fond aurait glissé sans rien
    /// dire.
    private var bounce: Animation? {
        reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.62)
    }

    var body: some View {
        HStack(spacing: MemoBookSpacing.snug) {
            leadingControl
            controls
        }
        .padding(.horizontal, MemoBookSpacing.snug)
        .padding(.vertical, MemoBookSpacing.xs)
        .animation(bounce, value: model.composer)
        .animation(bounce, value: model.recorder.isRecording)
        .animation(bounce, value: model.recorder.isPaused)
        .animation(bounce, value: model.microphoneIsDenied)
        .animation(bounce, value: model.canSendDraft)
        .animation(bounce, value: model.isCreditExhausted)
    }

    /// **Pâli, pas désactivé** (règle du design system) : le micro et le
    /// clavier d'un crédit épuisé gardent leur place et répondent au doigt —
    /// le toucher fait paraître le bandeau « Crédit du jour épuisé » au lieu de
    /// ne rien faire. Un bouton désactivé ne dirait pas pourquoi.
    private var creditOpacity: Double { model.isCreditExhausted ? 0.45 : 1 }

    /// Ce que VoiceOver dit d'un micro, d'un clavier ou d'un champ pâlis : la
    /// pâleur ne s'entend pas (03/10/2026). Vide quand il reste du crédit.
    private var creditAccessibilityValue: String {
        model.isCreditExhausted ? DailyCreditCopy.exhaustedTitle : ""
    }

    private var creditAccessibilityHint: String {
        model.isCreditExhausted ? DailyCreditCopy.exhaustedDetail : ""
    }

    private var isAtRest: Bool {
        model.composer == .tools && !model.recorder.isRecording
    }

    // MARK: La commande de gauche

    /// La croix, dès qu'un outil est ouvert — et rien au repos.
    ///
    /// C'est **la** sortie de secours : quel que soit l'outil ouvert — clavier,
    /// micro armé, enregistrement en cours —, une tape ramène la barre à ses
    /// trois boutons. Sans elle, il fallait deviner quel autre bouton allait
    /// refermer celui-ci.
    ///
    /// Le burger de la maquette, qui tenait cette place au repos, est parti :
    /// rien n'était dessiné derrière, et un bouton qui ne mène nulle part est
    /// une question posée à chaque ouverture du fil (Hugo, 16/09/2026). Les
    /// trois pavés prennent la largeur, comme ils le faisaient déjà en taille
    /// de texte accessible.
    @ViewBuilder
    private var leadingControl: some View {
        if !isAtRest { closeButton }
    }

    private var closeButton: some View {
        barGlyph(
            "IconLucideClose",
            label: ChatCopy.Voice.collapse,
            tint: MemoBookColor.ink,
            action: model.collapseComposer
        )
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    // MARK: Les dispositions

    @ViewBuilder
    private var controls: some View {
        if model.recorder.isRecording {
            recordingControls
                .transition(.scale(scale: 0.94).combined(with: .opacity))
        } else {
            switch model.composer {
            case .tools:
                toolControls
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            case .writing:
                writingControls
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            case .speaking:
                speakingControls
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
    }

    // MARK: Au repos — nœud `start`

    /// Les trois commandes se partagent la largeur. C'est ce partage égal qui
    /// dit qu'aucune n'est la bonne : on raconte comme on veut.
    private var toolControls: some View {
        HStack(spacing: MemoBookSpacing.snug) {
            cameraButton(fills: true)
            keyboardButton(fills: true)
            micButton(fills: true)
        }
    }

    // MARK: Le micro armé — nœud `Default`

    /// Photo et clavier se serrent pour laisser « Record » s'étirer : la barre
    /// dit alors d'elle-même ce qu'on attend de nous.
    ///
    /// Sans micro, « Record » n'a rien à proposer : la barre bascule sur le
    /// champ de saisie, exactement comme le nœud `Default snas micro`.
    @ViewBuilder
    private var speakingControls: some View {
        if model.microphoneIsDenied {
            writingControls
        } else {
            HStack(spacing: MemoBookSpacing.snug) {
                cameraButton(fills: false)
                keyboardButton(fills: false)

                // « Record » dans la maquette ; « Enregistrer » dans l'app
                // (T51). Aux tailles accessibles, le micro seul : à côté de
                // deux boutons ronds, le libellé se coupait lettre par lettre
                // sur cinq lignes (recette du 30/09/2026). VoiceOver dit
                // toujours ce qu'il fait.
                if typeSize.isAccessibilitySize {
                    BrandButton(
                        icon: Image(brand: "IconMic"),
                        style: .secondary,
                        isRound: true,
                        fillsWidth: true,
                        action: model.startRecording
                    )
                    .brandShadow(.raised)
                    .opacity(creditOpacity)
                    .accessibilityLabel(ChatCopy.Voice.microphone)
                    .accessibilityValue(creditAccessibilityValue)
                    .accessibilityHint(creditAccessibilityHint)
                } else {
                    BrandButton(
                        ChatCopy.record,
                        icon: Image(brand: "IconMic"),
                        iconPlacement: .trailing,
                        style: .secondary,
                        isRound: true,
                        fillsWidth: true,
                        action: model.startRecording
                    )
                    .brandShadow(.raised)
                    .opacity(creditOpacity)
                    .accessibilityLabel(ChatCopy.Voice.microphone)
                    .accessibilityValue(creditAccessibilityValue)
                    .accessibilityHint(creditAccessibilityHint)
                }
            }
        }
    }

    // MARK: Au clavier — nœuds `Start Typing` / `Finish Typing`

    /// Le micro **s'efface** quand on corrige une retranscription : on a
    /// choisi « à la main », et à ce corps-là, un bouton de 44 à côté du champ
    /// coupait chaque ligne à quatorze caractères — on ne relit pas cinquante
    /// mots dans une colonne. Le champ prend toute la barre ; le micro revient
    /// avec le prochain message.
    private var writingControls: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            field
            if !model.isEditingTranscript {
                micButton(fills: false)
            }
        }
        .animation(bounce, value: model.isEditingTranscript)
    }

    /// Le champ grandit avec ce qu'on écrit.
    ///
    /// ``BrandTextField`` ne convient pas ici : c'est un champ de formulaire à
    /// étiquette flottante, d'une seule ligne et de 3.5 rem de haut. Un
    /// composeur de conversation est un autre objet — il n'a pas d'étiquette, il
    /// s'agrandit, et il vit dans une barre. Le contrat de focus, lui, reste
    /// celui de l'app : c'est l'écran qui le tient, pas le champ.
    ///
    /// C'est aussi ce champ qui porte l'état `Modifying transcription` de la
    /// maquette : corriger une retranscription, c'est écrire un long texte, et
    /// le champ s'y étire tout seul. Il n'y avait pas de cinquième disposition à
    /// écrire pour ça — seulement un plafond plus haut, voir ``lineRange``.
    private var field: some View {
        HStack(alignment: .bottom, spacing: MemoBookSpacing.xs) {
            TextField(ChatCopy.composerPlaceholder, text: $model.draft, axis: .vertical)
                .font(MemoBookFont.composer)
                .foregroundStyle(MemoBookColor.ink)
                .tint(MemoBookColor.send)
                .lineLimit(lineRange)
                .focused($isWriting)
                .submitLabel(.return)
                // Le champ qui apparaît prend le clavier. C'est ce qui manquait
                // aux puces « à la main » : elles ouvraient le champ, et il
                // fallait encore le toucher pour écrire dedans.
                .onAppear { isWriting = true }
                // La marge du texte, et **elle seule** : c'est elle qui fait
                // grandir le champ ligne après ligne.
                .padding(.vertical, MemoBookSpacing.xs)
                .frame(minHeight: barHeight)

            // L'avion garde sa cible de 2.75 rem en largeur, et prend la
            // hauteur d'une ligne du champ : son rond se centre sur la
            // première ligne, puis reste en bas quand le texte grandit.
            sendButton
                .frame(height: barHeight)
        }
        .padding(.leading, MemoBookSpacing.s)
        .padding(.trailing, sendInset)
        // Pâli, comme le micro, quand le crédit est épuisé : on peut encore y
        // toucher, le bandeau au-dessus dit pourquoi rien ne partira.
        .opacity(creditOpacity)
        .accessibilityValue(creditAccessibilityValue)
        // **À la hauteur des boutons de la barre, une ligne écrite**
        // (Hugo, 08/10/2026). Le champ ajoutait 8 pt en haut et en bas
        // **autour** d'un avion haut de 44 : 60 pt, plus haut que le micro
        // d'à côté (50), sans rien de plus à montrer. La marge ne borde plus
        // que le texte, et le champ ne grandit que s'il y a des lignes.
        .frame(minHeight: barHeight)
        .background(MemoBookColor.surface, in: Self.fieldShape)
        .overlay { Self.fieldShape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
        .brandShadow(.raised)
    }

    /// Jusqu'où le champ grandit avant de défiler.
    ///
    /// **Trois lignes, et une seule au départ** (Hugo, 19/09/2026). Il en
    /// montait six : le champ s'ouvrait déjà haut sous le clavier, et une fois
    /// rempli il prenait la moitié de ce qui restait de la conversation. Trois
    /// suffisent à relire ce qu'on vient d'écrire ; au-delà, c'est le champ qui
    /// défile.
    ///
    /// **Dix quand on corrige une retranscription** (Hugo, 17/09/2026) : là,
    /// la conversation n'est plus ce qu'on regarde — c'est le texte, et il
    /// faut le lire en entier pour trouver les trois mots à changer. Une fiche
    /// de cinquante mots tient dans dix lignes de ce corps. En taille
    /// accessible, cinq : au-delà, le champ dépasserait l'écran avec le
    /// clavier.
    private var lineRange: ClosedRange<Int> {
        if model.isEditingTranscript {
            return typeSize.isAccessibilitySize ? 1...5 : 1...10
        }
        return 1...3
    }

    /// Une capsule tant que le champ tient sur une ligne, un rectangle arrondi
    /// dès qu'il grandit.
    ///
    /// `Capsule()` seule donnait une **ellipse** haute de six lignes en taille
    /// accessible : un rayon égal à la moitié d'un bouton de la barre se comporte
    /// comme une capsule à la hauteur d'origine, et cesse de gonfler ensuite.
    /// C'est aussi ce qui rapproche le champ du rayon 25 que la maquette donne à
    /// l'état « modification d'une retranscription ».
    private static let fieldShape = RoundedRectangle(
        cornerRadius: MemoBookSpacing.controlHeight / 2,
        style: .continuous
    )

    /// L'avion en papier, **blanc dans un rond bleu**. Gris tant qu'il n'y a
    /// rien à envoyer, bleu dès qu'il y a un mot : c'est le seul endroit de la
    /// barre où la couleur annonce que l'action vient de devenir possible.
    private var sendButton: some View {
        sendGlyph(isActive: model.canSendDraft, action: model.sendDraft)
            .disabled(!model.canSendDraft)
            // Le bleu arrive avec un petit sursaut : c'est le moment où le
            // message devient envoyable, et il vaut d'être vu.
            .scaleEffect(model.canSendDraft ? 1 : 0.86)
    }

    // MARK: Pendant qu'on parle — nœuds `Start Recording` / `Finish Recording`

    /// La frise, le chrono, et de quoi suspendre, jeter ou envoyer.
    ///
    /// Deux temps, comme la maquette : **en cours**, on peut suspendre, et le
    /// micro allumé dit que ça enregistre ; **suspendu**, la pause devient une
    /// corbeille — c'est là qu'on renonce — et la frise s'éteint sans s'effacer.
    /// L'envoi est possible dans les deux.
    private var recordingControls: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            if model.recorder.isPaused {
                discardButton
            } else {
                pauseButton
            }

            BrandWaveform(
                live: model.capturedLevels,
                size: .bar,
                isDimmed: model.recorder.isPaused
            )

            Text(model.recorder.elapsed.chatDurationLabel)
                .font(MemoBookFont.label)
                .foregroundStyle(MemoBookColor.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: model.recorder.elapsed)

            // ⚠️ Il y avait ici un petit micro vert, entre le chrono et
            // l'envoi. Retiré (Hugo, 19/09/2026) : la frise qui bouge et le
            // chrono qui court disent déjà qu'on enregistre, et il ne se
            // touchait pas. Sa place revient à la frise.

            sendGlyph(isActive: true, action: model.finishRecording)
        }
        .padding(.horizontal, MemoBookSpacing.snug)
        .frame(maxWidth: .infinity)
        .frame(minHeight: MemoBookSpacing.minimumTapTarget)
        .background(MemoBookColor.surface, in: Capsule())
        .brandShadow(.raised)
    }

    private var pauseButton: some View {
        barGlyph(
            "IconLucidePauseCircle",
            label: ChatCopy.Voice.pauseRecording,
            tint: MemoBookColor.error,
            action: model.pauseRecording
        )
        .transition(.scale.combined(with: .opacity))
    }

    private var discardButton: some View {
        barGlyph(
            "IconTrash",
            label: ChatCopy.Voice.discardRecording,
            tint: MemoBookColor.error,
            action: model.cancelRecording
        )
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: Les trois pavés ronds

    private func cameraButton(fills: Bool) -> some View {
        roundButton(
            "IconLucideCamera",
            label: ChatCopy.Voice.camera,
            style: .secondary,
            fills: fills,
            action: onAddPhotos
        )
    }

    private func keyboardButton(fills: Bool) -> some View {
        roundButton(
            "IconLucideKeyboard",
            label: ChatCopy.Voice.keyboard,
            style: .raised,
            fills: fills
        ) {
            if model.tapKeyboard() { isWriting = true }
        }
        .opacity(creditOpacity)
        .accessibilityValue(creditAccessibilityValue)
        .accessibilityHint(creditAccessibilityHint)
    }

    /// Le micro, dans ses deux états.
    ///
    /// Refusé, il **garde sa place** : perdre son cerne vert et porter un micro
    /// barré dit où on en est, alors qu'un bouton qui disparaît laisse croire à
    /// un bug. Une tape ouvre alors les Réglages, seul recours après un refus.
    @ViewBuilder
    private func micButton(fills: Bool) -> some View {
        if model.microphoneIsDenied {
            roundButton(
                "IconLucideMicOff",
                label: ChatCopy.Voice.microphoneDenied,
                style: .raised,
                fills: fills,
                isMuted: true,
                action: model.openMicrophoneSettings
            )
        } else {
            roundButton(
                "IconMic",
                label: ChatCopy.Voice.microphone,
                style: .secondary,
                fills: fills,
                action: model.tapMicrophone
            )
            .opacity(creditOpacity)
            .accessibilityValue(creditAccessibilityValue)
            .accessibilityHint(creditAccessibilityHint)
        }
    }

    private func roundButton(
        _ icon: String,
        label: String,
        style: BrandButton.Style,
        fills: Bool,
        isMuted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        BrandButton(
            icon: Image(brand: icon),
            style: style,
            isRound: true,
            fillsWidth: fills,
            action: action
        )
        .overlay {
            // `BrandButton.raised` n'a pas de contour ; le micro refusé, lui, en
            // veut un — gris. C'est le seul cerne de la barre qui ne soit pas
            // vert, et il n'existe que pour cet état-là.
            if isMuted {
                Capsule().strokeBorder(MemoBookColor.disabledOutline, lineWidth: 1)
            }
        }
        .brandShadow(.raised)
        .accessibilityLabel(label)
    }

    /// Une icône nue posée dans la barre, dans une cible de 2.75 rem.
    /// Le bouton d'envoi : **un rond plein du bleu qui s'écrit, l'avion en
    /// blanc dedans** (Hugo, 17/09/2026, T59). Le bleu-violet du kit de
    /// messagerie est parti avec ; le rond est de la taille d'une icône de
    /// contenu, et sa cible garde les 2.75 rem de la barre.
    private func sendGlyph(isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(brand: "IconLucideSend")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: glyph * 0.8, height: glyph * 0.8)
                .foregroundStyle(MemoBookColor.surface)
                // **Un point à gauche, un point en bas** (Hugo, 19/09/2026).
                // L'avion pointe vers le coin haut droit : sa masse est en bas
                // à gauche, et centré au pixel il se lisait poussé vers le haut
                // à droite de son rond. C'est un recentrage optique, comme on
                // en fait pour un triangle de lecture.
                .offset(x: -1, y: 1)
                .frame(width: MemoBookSpacing.contentIcon, height: MemoBookSpacing.contentIcon)
                .background(
                    isActive ? MemoBookColor.send : MemoBookColor.disabledOutline,
                    in: .circle
                )
                .frame(
                    minWidth: MemoBookSpacing.minimumTapTarget,
                    minHeight: MemoBookSpacing.minimumTapTarget
                )
        }
        .contentShape(.rect)
        .accessibilityLabel(ChatCopy.Voice.send)
    }

    private func barGlyph(
        _ icon: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(brand: icon)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: glyph, height: glyph)
                .foregroundStyle(tint)
                .frame(
                    minWidth: MemoBookSpacing.minimumTapTarget,
                    minHeight: MemoBookSpacing.minimumTapTarget
                )
        }
        .contentShape(.rect)
        .accessibilityLabel(label)
    }
}

/// La pastille « Retourner en bas », qui n'apparaît que si on est remonté.
///
/// Elle flotte au-dessus de la barre d'envoi plutôt que d'y prendre place :
/// c'est un raccourci de lecture, pas une commande de la conversation, et il
/// disparaît dès qu'il a servi.
struct ChatBackToBottomPill: View {
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = MemoBookSpacing.m

    var body: some View {
        Button(action: action) {
            HStack(spacing: MemoBookSpacing.snug) {
                Text(ChatCopy.backToBottom)
                    .font(MemoBookFont.bodySemibold)
                    .foregroundStyle(MemoBookColor.ink)

                Image(brand: "IconLucideArrowDown")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: glyph, height: glyph)
                    .foregroundStyle(MemoBookColor.ink)
            }
            .padding(.horizontal, MemoBookSpacing.s)
            .padding(.vertical, MemoBookSpacing.xs)
            .frame(minHeight: MemoBookSpacing.minimumTapTarget)
            .background(
                MemoBookColor.surface,
                in: .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
            )
            .brandShadow(.soft)
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel(ChatCopy.backToBottom)
    }
}

// MARK: - Aperçus

#Preview("Barre d’envoi — ses dispositions") {
    ChatSendingBarGallery()
        .environment(\.colorScheme, .light)
}

#Preview("Barre d’envoi — Dynamic Type AX3") {
    ChatSendingBarGallery()
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Barre d’envoi — le crédit du jour") {
    ChatCreditGallery()
        .environment(\.colorScheme, .light)
}

/// Le crédit du jour dans le pied du chat : les trois phases du bandeau, le
/// micro pâli, la boîte « trop long » et le rappel des caractères. Le micro
/// ne tourne pas dans un aperçu : le bandeau d'enregistrement y est posé tel
/// quel (``ChatModel/preview(thread:turn:composer:draft:microphoneIsDenied:focusStepId:dailyCredit:showsExhaustedNotice:creditBanner:)``).
private struct ChatCreditGallery: View {
    var body: some View {
        ScrollView {
            VStack(spacing: MemoBookSpacing.s) {
                composer(
                    "Plus que 24 secondes",
                    .preview(thread: .fixture(tripId: "trip-rome"), dailyCredit: ChatCreditFixture.lastSeconds, creditBanner: .warning(remainingMs: 24_000))
                )
                composer(
                    "Les 5 dernières secondes, qui pulsent",
                    .preview(thread: .fixture(tripId: "trip-rome"), dailyCredit: ChatCreditFixture.lastSeconds, creditBanner: .urgent(remainingMs: 3_000))
                )
                composer(
                    "Épuisé : micro et clavier pâlis, bandeau touché",
                    .preview(thread: .fixture(tripId: "trip-rome"), dailyCredit: ChatCreditFixture.exhausted, showsExhaustedNotice: true)
                )
                composer(
                    "Au clavier, message trop long",
                    .preview(
                        thread: .fixture(tripId: "trip-rome"),
                        composer: .writing,
                        draft: String(repeating: "On a marché jusqu’au marché. ", count: 30),
                        dailyCredit: ChatCreditFixture.lastSeconds
                    )
                )
                composer(
                    "Au clavier, moins d’une minute de crédit",
                    .preview(
                        thread: .fixture(tripId: "trip-rome"),
                        composer: .writing,
                        draft: "On a marché jusqu’au marché",
                        dailyCredit: ChatCreditFixture.lastSeconds
                    )
                )
                composer(
                    "Abonné : rien de tout ça",
                    .preview(thread: .fixture(tripId: "trip-rome"), dailyCredit: ChatCreditFixture.unlimited)
                )
            }
            .padding(.vertical, MemoBookSpacing.s)
        }
        .background(MemoBookColor.background)
    }

    private func composer(_ title: String, _ model: ChatModel) -> some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs / 2) {
            Text(title)
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.inkMuted)
                .padding(.horizontal, MemoBookSpacing.screenMargin)
            PreviewComposer(model: model)
        }
    }

    private struct PreviewComposer: View {
        @Bindable var model: ChatModel
        @FocusState private var isWriting: Bool

        var body: some View {
            ChatComposer(model: model, isWriting: $isWriting, onAddPhotos: {})
        }
    }
}

/// Les dispositions de la barre, empilées comme le nœud Figma les aligne.
private struct ChatSendingBarGallery: View {
    var body: some View {
        ScrollView {
            VStack(spacing: MemoBookSpacing.s) {
                bar("Au repos", .preview(thread: .fixture(tripId: "trip-rome")))
                bar(
                    "Micro refusé",
                    .preview(thread: .fixture(tripId: "trip-rome"), microphoneIsDenied: true)
                )
                bar(
                    "Micro armé",
                    .preview(thread: .fixture(tripId: "trip-rome"), composer: .speaking)
                )
                bar(
                    "Au clavier, rien à envoyer",
                    .preview(thread: .fixture(tripId: "trip-rome"), composer: .writing)
                )
                bar(
                    "Au clavier, prêt à envoyer",
                    .preview(
                        thread: .fixture(tripId: "trip-rome"),
                        composer: .writing,
                        draft: "On a marché jusqu’au marché"
                    )
                )
            }
            .padding(.vertical, MemoBookSpacing.s)
        }
        .background(MemoBookColor.background)
    }

    @ViewBuilder
    private func bar(_ title: String, _ model: ChatModel) -> some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs / 2) {
            Text(title)
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.inkMuted)
                .padding(.horizontal, MemoBookSpacing.screenMargin)

            PreviewBar(model: model)
        }
    }

    /// Un `@FocusState` ne se fabrique pas dans une closure : il lui faut une
    /// vue à lui.
    private struct PreviewBar: View {
        @Bindable var model: ChatModel
        @FocusState private var isWriting: Bool

        var body: some View {
            ChatSendingBar(model: model, isWriting: $isWriting, onAddPhotos: {})
                .background(ChatMetrics.barMaterial)
        }
    }
}
