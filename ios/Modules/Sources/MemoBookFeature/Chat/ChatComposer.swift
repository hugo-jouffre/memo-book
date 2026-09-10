import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Ce qui est posé en bas de l'écran : les réponses que MEMO propose, et de quoi
/// répondre autrement.
///
/// Les deux bandes flottent au-dessus du fil sur le même matériau que
/// l'en-tête : la conversation passe dessous et se laisse deviner, ce qui dit
/// qu'elle continue au-delà du bord.
struct ChatComposer: View {
    @Bindable var model: ChatModel
    @FocusState.Binding var isWriting: Bool
    let onAddPhotos: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChatSuggestionRail(model: model, onAddPhotos: onAddPhotos)
            ChatSendingBar(model: model, isWriting: $isWriting, onAddPhotos: onAddPhotos)
        }
        .background(ChatMetrics.barMaterial)
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

    /// La hauteur d'une ligne de puce, qui suit le corps du texte.
    @ScaledMetric(relativeTo: .body) private var lineHeight: CGFloat = MemoBookSpacing.m

    /// La hauteur de la bande : une ligne et ses marges, jamais moins qu'une
    /// cible tactile.
    private var railHeight: CGFloat {
        max(MemoBookSpacing.minimumTapTarget, lineHeight + MemoBookSpacing.s)
    }

    var body: some View {
        let suggestions = model.visibleSuggestions

        if !suggestions.isEmpty {
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
        }
    }

    private func chip(_ suggestion: ChatSuggestion) -> some View {
        Button {
            model.choose(suggestion, addPhotos: onAddPhotos)
        } label: {
            HStack(spacing: MemoBookSpacing.xs / 2) {
                if let symbol = suggestion.symbol {
                    // L'emoji est porté à part du libellé : il ne part pas dans
                    // le message envoyé, et VoiceOver ne le lit pas.
                    Text(symbol).accessibilityHidden(true)
                }
                Text(suggestion.label)
                    .font(MemoBookFont.bubble)
                    .foregroundStyle(MemoBookColor.ink)
                    // Une ligne, jamais tronquée : la puce s'allonge autant
                    // qu'il faut, et c'est la bande qui défile.
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, MemoBookSpacing.snug)
            .frame(height: railHeight)
            .background(
                MemoBookColor.surface,
                in: .rect(cornerRadius: MemoBookSpacing.bubbleCornerRadius)
            )
        }
        .buttonStyle(CardPressStyle())
        .contentShape(.rect(cornerRadius: MemoBookSpacing.bubbleCornerRadius))
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
    }

    private var isAtRest: Bool {
        model.composer == .tools && !model.recorder.isRecording
    }

    // MARK: La commande de gauche

    /// Le burger au repos, une croix partout ailleurs.
    ///
    /// C'est **la** sortie de secours : quel que soit l'outil ouvert — clavier,
    /// micro armé, enregistrement en cours —, une tape ramène la barre à ses
    /// trois boutons. Sans elle, il fallait deviner quel autre bouton allait
    /// refermer celui-ci.
    @ViewBuilder
    private var leadingControl: some View {
        if typeSize.isAccessibilitySize {
            // À ce corps-là, la barre n'a plus la largeur pour une quatrième
            // colonne : le burger disparaît, et la croix reste — d'elle, on ne
            // peut pas se passer.
            if !isAtRest { closeButton }
        } else if isAtRest {
            menuButton
        } else {
            closeButton
        }
    }

    /// Le menu de la maquette. ⚠️ Rien n'est dessiné derrière : il garde son
    /// bouton parce que la maquette le montre, et ne mène nulle part — même
    /// parti pris que les intentions non routées de l'accueil et du profil.
    private var menuButton: some View {
        barGlyph("IconMenuBurger", label: ChatCopy.Voice.menu, tint: MemoBookColor.ink) {}
            .transition(.scale(scale: 0.6).combined(with: .opacity))
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

                // ⚠️ « Record » est **en anglais dans la maquette**, au milieu
                // d'une app française, et recopié tel quel (R8) — T51.
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
                .accessibilityLabel(ChatCopy.Voice.microphone)
            }
        }
    }

    // MARK: Au clavier — nœuds `Start Typing` / `Finish Typing`

    private var writingControls: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            field
            micButton(fills: false)
        }
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
    /// écrire pour ça.
    private var field: some View {
        HStack(alignment: .bottom, spacing: MemoBookSpacing.xs) {
            TextField(ChatCopy.composerPlaceholder, text: $model.draft, axis: .vertical)
                .font(MemoBookFont.composer)
                .foregroundStyle(MemoBookColor.ink)
                .tint(MemoBookColor.send)
                // Trois lignes en taille accessible et six sinon : à ce corps-là,
                // six lignes de saisie occupent la moitié de l'écran et poussent
                // la conversation hors de vue au moment précis où on lui répond.
                .lineLimit(typeSize.isAccessibilitySize ? 1...3 : 1...6)
                .focused($isWriting)
                .submitLabel(.return)

            sendButton
        }
        .padding(.horizontal, MemoBookSpacing.s)
        .padding(.vertical, MemoBookSpacing.snug)
        .frame(minHeight: MemoBookSpacing.minimumTapTarget)
        .background(MemoBookColor.surface, in: Self.fieldShape)
        .overlay { Self.fieldShape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
        .brandShadow(.raised)
    }

    /// Une capsule tant que le champ tient sur une ligne, un rectangle arrondi
    /// dès qu'il grandit.
    ///
    /// `Capsule()` seule donnait une **ellipse** haute de six lignes en taille
    /// accessible : un rayon égal à la moitié d'une cible tactile se comporte
    /// comme une capsule à la hauteur d'origine, et cesse de gonfler ensuite.
    /// C'est aussi ce qui rapproche le champ du rayon 25 que la maquette donne à
    /// l'état « modification d'une retranscription ».
    private static let fieldShape = RoundedRectangle(
        cornerRadius: MemoBookSpacing.minimumTapTarget / 2,
        style: .continuous
    )

    /// L'avion en papier. Gris tant qu'il n'y a rien à envoyer, bleu dès qu'il y
    /// a un mot : c'est le seul endroit de la barre où la couleur annonce que
    /// l'action vient de devenir possible.
    private var sendButton: some View {
        barGlyph(
            "IconLucideSend",
            label: ChatCopy.Voice.send,
            tint: model.canSendDraft ? MemoBookColor.send : MemoBookColor.disabledOutline,
            action: model.sendDraft
        )
        .disabled(!model.canSendDraft)
        // Le bleu arrive avec un petit sursaut : c'est le moment où le message
        // devient envoyable, et il vaut d'être vu.
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
                capacity: ChatMetrics.recordingBarCount,
                isDimmed: model.recorder.isPaused
            )

            Text(model.recorder.elapsed.chatDurationLabel)
                .font(MemoBookFont.label)
                .foregroundStyle(MemoBookColor.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: model.recorder.elapsed)

            if !model.recorder.isPaused, !typeSize.isAccessibilitySize {
                Image(brand: "IconMic")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: glyph * 0.7, height: glyph * 0.7)
                    .foregroundStyle(MemoBookColor.action)
                    .accessibilityHidden(true)
            }

            barGlyph(
                "IconLucideSend",
                label: ChatCopy.Voice.send,
                tint: MemoBookColor.send,
                action: model.finishRecording
            )
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
            model.composer = .writing
            isWriting = true
        }
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
                fills: fills
            ) {
                model.composer = .speaking
                model.startRecording()
            }
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
