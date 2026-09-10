import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Une réplique du fil : la bulle, et les deux commandes posées à côté d'elle.
///
/// **Le côté est la seule question posée.** L'auteur décide de l'alignement, de
/// la couleur, du sens de la queue et de la nature des commandes — écouter et
/// copier ce que MEMO a dit, corriger et copier ce qu'on a dit soi-même. Tout
/// le reste est commun, et c'est pour ça qu'il n'y a qu'une rangée et pas deux.
struct ChatMessageRow: View {
    let message: ChatMessage
    @Bindable var model: ChatModel
    let isExpanded: Bool
    let onToggleExpansion: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: alignment, spacing: MemoBookSpacing.xs / 2) {
            row
            deliveryNotice
        }
        .frame(maxWidth: .infinity, alignment: horizontalAlignment)
    }

    private var isTraveller: Bool { message.author.isTraveller }

    private var alignment: HorizontalAlignment { isTraveller ? .trailing : .leading }

    private var horizontalAlignment: Alignment { isTraveller ? .trailing : .leading }

    /// La bulle et ses commandes.
    ///
    /// En taille de texte accessible, les commandes passent **sous** la bulle :
    /// deux cibles de 2.75 rem qui grandissent avec le corps ne laisseraient
    /// plus qu'un mot par ligne au texte.
    @ViewBuilder
    private var row: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: alignment, spacing: MemoBookSpacing.xs / 2) {
                bubble
                if !actions.isEmpty {
                    HStack(spacing: 0) { actionButtons }
                }
            }
        } else {
            HStack(alignment: .center, spacing: 0) {
                if isTraveller {
                    Spacer(minLength: 0)
                    actionButtons
                }
                bubble
                if !isTraveller {
                    actionButtons
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        switch message.body {
        case .text(let text):
            BrandChatBubble(author: message.author) {
                Text(text)
                    .font(MemoBookFont.bubble)
                    .foregroundStyle(MemoBookColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

        case .voice(let note):
            ChatVoiceBubble(note: note, author: message.author, model: model)

        case .transcript(let card):
            ChatTranscriptBubble(
                card: card,
                isExpanded: isExpanded,
                onToggleExpansion: onToggleExpansion
            )

        case .photos(let attachments):
            ChatPhotosBubble(attachments: attachments, author: message.author)
        }
    }

    /// Ce que chaque auteur permet de faire de son message.
    ///
    /// Rien sous un vocal : il n'y a pas de texte à copier ni à faire lire, et
    /// son bouton de lecture est déjà dans la bulle.
    private var actions: [ChatMessageAction] {
        guard message.spokenText != nil else { return [] }
        return isTraveller ? [.edit, .copy] : [.readAloud, .copy]
    }

    @ViewBuilder
    private var actionButtons: some View {
        ForEach(actions, id: \.self) { action in
            ChatActionButton(
                action: action,
                isActive: action == .readAloud && model.reader.isReading(message.id),
                isConfirmed: action == .copy && model.copiedMessageId == message.id
            ) {
                switch action {
                case .readAloud: model.toggleReading(of: message)
                case .copy: model.copy(message)
                case .edit: model.edit(message)
                }
            }
        }
    }

    /// « Non envoyé », sous la bulle qui n'est pas passée. La bulle reste :
    /// perdre le message serait perdre ce qu'il racontait.
    @ViewBuilder
    private var deliveryNotice: some View {
        if message.delivery.hasFailed {
            Button(action: model.retry) {
                HStack(spacing: MemoBookSpacing.xs / 2) {
                    Text(ChatCopy.notSent)
                    Text(ChatCopy.retry).underline()
                }
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.error)
            }
            .padding(.horizontal, MemoBookSpacing.snug)
            .accessibilityLabel("\(ChatCopy.notSent). \(ChatCopy.retry)")
        }
    }
}

/// Ce qu'on peut faire d'un message.
enum ChatMessageAction: Hashable {
    case readAloud
    case copy
    case edit

    /// ⚠️ Trois icônes **Lucide**, faute d'équivalent dans le jeu de marque —
    /// voir `assets/icons/lucide/README.md`. Le préfixe du nom d'asset est là
    /// pour que la dette se voie d'ici, et le jour où Clara les dessine, c'est
    /// cette ligne-là qui change.
    var icon: String {
        switch self {
        case .readAloud: "IconLucideSpeaker"
        case .copy: "IconLucideCopy"
        case .edit: "IconPen"
        }
    }

    var label: String {
        switch self {
        case .readAloud: ChatCopy.Voice.readAloud
        case .copy: ChatCopy.Voice.copy
        case .edit: ChatCopy.Voice.edit
        }
    }
}

/// Une commande posée à côté d'une bulle : une icône discrète dans une cible de
/// 2.75 rem.
///
/// Grise et non colorée : ce sont des services rendus au message, pas des
/// actions de l'écran. La seule qui s'allume est la lecture à voix haute, parce
/// qu'elle a un état — quelque chose est en train de parler.
private struct ChatActionButton: View {
    let action: ChatMessageAction
    let isActive: Bool

    /// Le geste vient d'aboutir. Vrai une seconde après une copie — voir
    /// ``ChatModel/copiedMessageId``.
    let isConfirmed: Bool

    let perform: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = MemoBookSpacing.sectionGap

    /// Ce que le bouton montre : la coche s'il vient de servir, l'arrêt s'il
    /// parle, son icône sinon.
    private var icon: String {
        if isConfirmed { return "IconLucideCheck" }
        return isActive ? "IconLucideStop" : action.icon
    }

    private var tint: Color {
        if isConfirmed { return MemoBookColor.valid }
        return isActive ? MemoBookColor.action : MemoBookColor.inkMuted
    }

    var body: some View {
        Button(action: perform) {
            Image(brand: icon)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: side, height: side)
                .foregroundStyle(tint)
                // La coche **remplace** l'icône, elle ne s'ajoute pas à côté :
                // c'est la même commande qui répond, et rien ne bouge autour.
                // Elle arrive avec un petit sursaut, parce qu'un simple fondu
                // se rate quand on regarde ailleurs une demi-seconde.
                .scaleEffect(isConfirmed && !reduceMotion ? 1.18 : 1)
                .frame(
                    width: MemoBookSpacing.minimumTapTarget,
                    height: MemoBookSpacing.minimumTapTarget
                )
        }
        .contentShape(.rect)
        .animation(
            reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.5),
            value: isConfirmed
        )
        .accessibilityLabel(label)
        // VoiceOver n'a pas de coche à regarder : il faut le lui dire.
        .accessibilityValue(isConfirmed ? ChatCopy.Voice.copied : "")
    }

    private var label: String {
        if isActive { return ChatCopy.Voice.stopReading }
        return action.label
    }
}

// MARK: - Les photos

/// Des photos jointes : une grande si elle est seule, une grille sinon.
///
/// ⚠️ **Aucune bulle de photo n'est dessinée dans la maquette.** Celle-ci est
/// écrite pour que l'ajout de photos — que la maquette propose, elle, en puce et
/// en bouton — mène quelque part. Elle reprend la bulle et le rayon de vignette
/// de l'app, et rien d'autre n'est inventé. À faire dessiner — voir T60.
struct ChatPhotosBubble: View {
    let attachments: [PhotoAttachment]
    let author: ChatAuthor

    @ScaledMetric(relativeTo: .body) private var thumbnail: CGFloat = 76

    /// Ce qu'on montre, et ce qu'on compte.
    private var shown: [PhotoAttachment] {
        Array(attachments.prefix(ChatMetrics.visiblePhotoCount))
    }

    private var hidden: Int {
        max(0, attachments.count - ChatMetrics.visiblePhotoCount)
    }

    var body: some View {
        BrandChatBubble(author: author) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs / 2) {
                if attachments.count == 1 {
                    photo(attachments[0], side: thumbnail * 2.4)
                } else {
                    // Deux colonnes, jamais plus : à trois, une vignette tombe
                    // sous la largeur d'un pouce sur un iPhone SE.
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: MemoBookSpacing.xs / 2
                    ) {
                        ForEach(shown) { photo($0, side: thumbnail * 1.4) }
                    }
                }

                if hidden > 0 {
                    Text("+\(hidden)")
                        .font(MemoBookFont.caption)
                        .foregroundStyle(MemoBookColor.ink)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ChatCopy.Voice.photos(count: attachments.count))
    }

    private func photo(_ attachment: PhotoAttachment, side: CGFloat) -> some View {
        AsyncImage(url: attachment.displayUrl) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                // La même trame que les vignettes d'étape : une image qui
                // charge ne doit pas laisser un trou de la couleur du fond.
                TripCoverPlaceholder(seed: attachment.id)
            }
        }
        .frame(height: side)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: MemoBookSpacing.snug))
    }
}

// MARK: - Le vocal

/// Un vocal : de quoi le jouer, sa forme d'onde, sa durée, et le signe de celui
/// qui l'a dit.
///
/// La forme d'onde est **celle du vocal**, pas un motif : les niveaux ont été
/// relevés pendant l'enregistrement. Un dessin décoratif, identique d'un vocal à
/// l'autre, dirait quelque chose de faux sur ce qui a été raconté.
struct ChatVoiceBubble: View {
    let note: VoiceNote
    let author: ChatAuthor
    @Bindable var model: ChatModel

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = MemoBookSpacing.sectionGap
    @ScaledMetric(relativeTo: .body) private var markSide: CGFloat = MemoBookSpacing.xl + 8

    private var isPlaying: Bool { model.player.isPlaying(note.id) }

    var body: some View {
        BrandChatBubble(author: author) {
            HStack(spacing: MemoBookSpacing.snug) {
                playButton

                VStack(alignment: .leading, spacing: 2) {
                    BrandWaveform(
                        levels: note.levels,
                        progress: isPlaying ? model.player.progress : 0,
                        tint: MemoBookColor.inkMuted,
                        playedTint: MemoBookColor.ink
                    )
                    Text(elapsedLabel)
                        .font(MemoBookFont.caption)
                        .foregroundStyle(MemoBookColor.ink)
                        .monospacedDigit()
                }
                .frame(minWidth: MemoBookSpacing.xl * 2)

                // Le signe de la marque dans un rond vert : le vocal est signé
                // par celui qui l'a dit. Un `BrandMarkDrawing` et non une image,
                // parce que le M du dépôt est un tracé et qu'il se met à
                // l'échelle sans se pixelliser.
                if !typeSize.isAccessibilitySize {
                    signature
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ChatCopy.Voice.voiceNote(duration: note.duration.chatSpokenDurationLabel))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.togglePlayback(of: note) }
    }

    /// Le chrono compte **en avançant** pendant la lecture, et affiche la durée
    /// totale au repos : c'est ce que fait un lecteur, et c'est ce qu'on
    /// cherche des yeux dans les deux cas.
    private var elapsedLabel: String {
        (isPlaying ? model.player.elapsed : note.duration).chatDurationLabel
    }

    private var playButton: some View {
        Button { model.togglePlayback(of: note) } label: {
            Image(brand: isPlaying ? "IconLucidePause" : "IconLucidePlay")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: glyph, height: glyph)
                .foregroundStyle(MemoBookColor.ink)
                .frame(
                    minWidth: MemoBookSpacing.minimumTapTarget,
                    minHeight: MemoBookSpacing.minimumTapTarget
                )
        }
        .contentShape(.rect)
        .accessibilityLabel(isPlaying ? ChatCopy.Voice.pause : ChatCopy.Voice.play)
    }

    private var signature: some View {
        BrandMarkDrawing(progress: 1, color: MemoBookColor.onAction)
            .frame(width: markSide * 0.55, height: BrandMark.height(forWidth: markSide * 0.55))
            .frame(width: markSide, height: markSide)
            .background(MemoBookColor.action, in: .circle)
            // Le micro à cheval sur le bord du rond, comme la maquette le pose :
            // c'est lui qui dit que ce disque signe un **vocal** et pas un
            // message écrit.
            .overlay(alignment: .leading) {
                Image(brand: "IconMic")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: glyph * 0.8, height: glyph * 0.8)
                    .foregroundStyle(MemoBookColor.ink)
                    .offset(x: -glyph * 0.4)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - La retranscription

/// La fiche « Retranscription du contexte » : ce que MEMO a compris d'un vocal.
///
/// Elle a la forme d'une **fiche** et non d'une réplique, parce qu'elle n'est
/// pas de la même nature : on la relit, on la corrige, elle finira dans le
/// carnet. D'où l'intitulé, la date, et la note de pied qui dit d'où vient le
/// texte.
struct ChatTranscriptBubble: View {
    let card: TranscriptCard
    let isExpanded: Bool
    let onToggleExpansion: () -> Void

    @ScaledMetric(relativeTo: .caption) private var glyph: CGFloat = MemoBookSpacing.snug

    /// Combien de lignes la fiche montre avant « Voir plus ». Sept : de quoi
    /// juger si la transcription est juste, sans que la fiche mange l'écran.
    private static let collapsedLineLimit = 7

    /// À partir de combien de caractères la fiche propose de se déplier.
    ///
    /// Un seuil et non une mesure : SwiftUI ne dit pas si un `Text` a été
    /// tronqué, et le mesurer demanderait de le rendre deux fois à chaque
    /// image de défilement. Sept lignes d'environ trente-cinq signes à la
    /// largeur d'une bulle — le compte est approché **par le haut**, pour qu'un
    /// « Voir plus » qui ne montre rien de plus ne puisse pas arriver.
    private static let expandableLength = Int(Double(collapsedLineLimit) * 35 * 1.15)

    private var isExpandable: Bool {
        (card.text?.count ?? 0) > Self.expandableLength
    }

    var body: some View {
        BrandChatBubble(author: .memo) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
                heading
                body(of: card)
                if let footnote = card.footnote {
                    Text(footnote)
                        .font(MemoBookFont.caption)
                        .foregroundStyle(MemoBookColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(ChatCopy.Voice.transcript(day: card.capturedAt.chatFullDayLabel)). \(card.text ?? ChatCopy.transcriptPending)"
        )
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: MemoBookSpacing.xs) {
                // ⚠️ La maquette écrit cet intitulé en Gloria Hallelujah, une
                // manuscrite qui n'est pas dans le bundle. En attendant qu'elle
                // passe par `make-brand-fonts.py`, c'est le surtitre de l'app,
                // dans le vert de MEMO — voir la fiche écran.
                Image(brand: "IconLucideSparkles")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: glyph, height: glyph)
                    .foregroundStyle(MemoBookColor.action)

                Text(card.title)
                    .font(MemoBookFont.overline)
                    .foregroundStyle(MemoBookColor.action)
            }

            HStack(spacing: MemoBookSpacing.snug) {
                Image(brand: "IconLucideCalendar")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: glyph, height: glyph)
                    .foregroundStyle(MemoBookColor.ink)

                Text(card.capturedAt.chatDayLabel)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.ink)

                if let place = card.placeLabel {
                    Text(place)
                        .font(MemoBookFont.caption)
                        .foregroundStyle(MemoBookColor.inkMuted)
                        .lineLimit(1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityHidden(true)
    }

    /// Le récit, ou ce qui le remplace tant qu'il n'est pas revenu.
    ///
    /// La fiche s'affiche **avant** la transcription, avec ce qu'on sait déjà —
    /// la date, le lieu, la durée. Cacher une information réelle derrière une
    /// attente donnerait l'impression que rien ne se passe.
    @ViewBuilder
    private func body(of card: TranscriptCard) -> some View {
        if let text = card.text {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                Text(text)
                    .font(MemoBookFont.bubble)
                    .foregroundStyle(MemoBookColor.ink)
                    .lineLimit(isExpanded || !isExpandable ? nil : Self.collapsedLineLimit)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if isExpandable {
                    Button(action: onToggleExpansion) {
                        Text(isExpanded ? ChatCopy.seeLess : ChatCopy.seeMore)
                            .font(MemoBookFont.bubbleAction)
                            .foregroundStyle(MemoBookColor.action)
                    }
                    .frame(minHeight: MemoBookSpacing.minimumTapTarget, alignment: .leading)
                    .contentShape(.rect)
                }
            }
        } else {
            HStack(spacing: MemoBookSpacing.xs) {
                ProgressView().controlSize(.small).tint(MemoBookColor.action)
                Text(ChatCopy.transcriptPending)
                    .font(MemoBookFont.bubble)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }
        }
    }
}

// MARK: - MEMO réfléchit

/// Trois points qui respirent, à la place de la bulle qui vient.
///
/// Une bulle et non un `ProgressView` centré : l'attente doit se produire **là
/// où la réponse va apparaître**, sinon le fil saute quand elle arrive. Sans
/// animation quand « Réduire les animations » est activé — trois points fixes
/// disent la même chose.
struct ChatThinkingBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0

    private static let dotCount = 3

    var body: some View {
        HStack(spacing: 0) {
            BrandChatBubble(author: .memo) {
                HStack(spacing: MemoBookSpacing.xs / 2) {
                    ForEach(0..<Self.dotCount, id: \.self) { index in
                        Circle()
                            .fill(MemoBookColor.inkMuted)
                            .frame(width: 7, height: 7)
                            .opacity(reduceMotion || phase == index ? 1 : 0.35)
                    }
                }
                .frame(height: MemoBookSpacing.s)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ChatCopy.Voice.thinking)
        .task {
            guard !reduceMotion else { return }
            // Une boucle plutôt qu'un `repeatForever` : elle s'arrête d'elle-même
            // quand la bulle disparaît, sans qu'on ait à l'annuler.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(320))
                withAnimation(.easeInOut(duration: 0.25)) {
                    phase = (phase + 1) % Self.dotCount
                }
            }
        }
    }
}
