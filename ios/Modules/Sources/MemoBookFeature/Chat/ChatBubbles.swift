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
            authorCaption
            row
            deliveryNotice
        }
        .frame(maxWidth: .infinity, alignment: horizontalAlignment)
    }

    /// Le prénom de l'autre voyageur, au-dessus de sa bulle, dans un fil à
    /// plusieurs. **Seulement si le serveur l'a mis** : il sait qui lit, qui
    /// parle, et s'ils sont plusieurs — la vue affiche, elle ne raisonne pas
    /// (`docs/conversation.md` § 2).
    @ViewBuilder
    private var authorCaption: some View {
        if let name = message.authorName, !name.isEmpty {
            Text(name)
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.inkMuted)
                .padding(.horizontal, MemoBookSpacing.snug)
                .accessibilityLabel("\(name) :")
        }
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

    /// « En cours d'envoi » se voit : la bulle est là, un peu en retrait, et
    /// prend sa pleine couleur quand le serveur l'a — tout de suite en ligne,
    /// à la sortie du tunnel sinon (`docs/conversation.md` § 9). Ni spinner
    /// ni libellé : la bulle d'un texte dit dans le métro ne doit pas avoir
    /// l'air cassée, juste pas encore arrivée. VoiceOver le dit en toutes
    /// lettres.
    private var bubble: some View {
        bubbleBody
            .opacity(message.delivery == .sending ? 0.6 : 1)
            .animation(.smooth(duration: 0.3), value: message.delivery)
            .accessibilityHint(message.delivery == .sending ? ChatCopy.Voice.sending : "")
    }

    @ViewBuilder
    private var bubbleBody: some View {
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
            ChatVoiceBubble(note: note, author: message.author, portrait: portrait, model: model)

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

    /// Le portrait de celui qui a parlé, pour la bulle d'un vocal (Clara,
    /// 26/09/2026) : ce que le serveur a mis sur la bulle — la sienne comme
    /// celle d'un co-voyageur —, sinon celui de qui lit, pour une bulle qui
    /// n'est pas encore partie. `nil` pour MEMO, qui signe de son M.
    private var portrait: ChatPortrait? {
        guard isTraveller else { return nil }
        if let initials = message.authorInitials {
            return ChatPortrait(url: message.authorAvatarUrl, initials: initials)
        }
        let context = model.thread?.context
        return ChatPortrait(url: context?.travellerAvatarUrl, initials: context?.travellerInitials ?? "")
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
    /// La photo ou les initiales de celui qui a parlé. `nil` : le M de MEMO.
    var portrait: ChatPortrait?
    @Bindable var model: ChatModel

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = MemoBookSpacing.sectionGap
    @ScaledMetric(relativeTo: .body) private var markSide: CGFloat = MemoBookSpacing.xl + 8

    private var isPlaying: Bool { model.player.isPlaying(note.id) }

    var body: some View {
        BrandChatBubble(author: author) {
            // Tout sur **une ligne, centrée** : le bouton, l'onde, le chrono et
            // la signature partagent le même axe. L'onde vivait au-dessus du
            // chrono, et se retrouvait au-dessus du milieu de la bulle
            // (Clara, 17/09/2026).
            HStack(alignment: .center, spacing: MemoBookSpacing.snug) {
                playButton

                HStack(alignment: .center, spacing: MemoBookSpacing.xs) {
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
                        .fixedSize()
                }
                .frame(minWidth: MemoBookSpacing.xl * 2)

                // Le vocal est signé par celui qui l'a dit : son portrait —
                // sa photo, ou ses initiales comme sur son profil (Clara,
                // 26/09/2026). Le rond vert au M de la marque ne signe plus
                // que MEMO.
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

    @ViewBuilder
    private var signature: some View {
        Group {
            if let portrait {
                ChatPortraitDisc(portrait: portrait, side: markSide)
            } else {
                // Un `BrandMarkDrawing` et non une image : le M du dépôt est un
                // tracé, il se met à l'échelle sans se pixelliser.
                BrandMarkDrawing(progress: 1, color: MemoBookColor.onAction)
                    .frame(width: markSide * 0.55, height: BrandMark.height(forWidth: markSide * 0.55))
                    .frame(width: markSide, height: markSide)
                    .background(MemoBookColor.action, in: .circle)
            }
        }
        // Le micro, **en pastille** sur le bord bas du rond (Clara,
        // 26/09/2026 — « mieux intégré ») : un disque du fond de la bulle qui
        // le détoure, et le glyphe vert dedans. Il se lit comme un badge du
        // portrait, et non plus comme une icône posée à côté.
        .overlay(alignment: .bottomLeading) { micBadge }
        .accessibilityHidden(true)
    }

    /// La pastille du micro : un disque du papier de la marque, cerclé comme
    /// le portrait, et le glyphe vert dedans — le badge d'une photo, pas une
    /// icône de plus dans la bulle.
    private var micBadge: some View {
        let side = markSide * 0.42

        return Image(brand: "IconMic")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(MemoBookColor.action)
            .padding(side * 0.2)
            .frame(width: side, height: side)
            .background(MemoBookColor.surface, in: .circle)
            .overlay { Circle().strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
            .offset(x: -side * 0.3, y: side * 0.12)
    }
}

/// Le portrait d'une bulle de vocal : la photo, ou les initiales **comme sur
/// la page de profil** — le même bleu d'aplat, l'encre. Un cerne du papier de
/// la marque le détache : sans lui, le rond bleu se fondait dans la bulle bleue
/// du voyageur, et il ne restait que deux lettres qui flottaient.
struct ChatPortraitDisc: View {
    let portrait: ChatPortrait
    let side: CGFloat

    var body: some View {
        AsyncImage(url: portrait.url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Text(portrait.initials)
                    .font(MemoBookFont.cardTitle)
                    .foregroundStyle(MemoBookColor.ink)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
        }
        .frame(width: side, height: side)
        .background(MemoBookColor.outline, in: .circle)
        .clipShape(.circle)
        .overlay { Circle().strokeBorder(MemoBookColor.surface, lineWidth: 2) }
    }
}

/// Qui a dit un vocal, pour son rond : une photo quand il y en a une, des
/// initiales sinon.
struct ChatPortrait: Hashable {
    let url: URL?
    let initials: String
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

    /// Les trois temps de la fiche — `docs/conversation.md` § 5. Une fiche sans
    /// texte écoute encore, quel que soit son temps : le moteur local n'en
    /// pose pas.
    private enum Stage { case listening, writing, ready, failed }

    private var stage: Stage {
        guard card.text != nil else { return .listening }
        switch card.phase {
        case .listening: return .listening
        case .writing: return .writing
        case .failed: return .failed
        case .ready, .unknown: return .ready
        }
    }

    var body: some View {
        BrandChatBubble(author: .memo) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
                heading
                body(of: card)
                if let footnote = card.footnote, stage == .ready {
                    Text(footnote)
                        .font(MemoBookFont.caption)
                        .foregroundStyle(MemoBookColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Le texte qui passe du brut au rédigé, la coche qui arrive : un
            // fondu, pas un saut.
            .animation(.smooth(duration: 0.3), value: card)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let day = ChatCopy.Voice.transcript(day: card.capturedAt.chatFullDayLabel)
        let state: String
        switch stage {
        case .listening: state = ChatCopy.transcriptPending
        case .writing: state = "\(ChatCopy.transcriptWriting) \(card.text ?? "")"
        case .failed: state = "\(ChatCopy.transcriptFailed) \(card.text ?? "")"
        case .ready: state = card.text ?? ""
        }
        let validated = card.isValidated ? " \(ChatCopy.Voice.validated)." : ""
        return "\(day). \(state)\(validated)"
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: MemoBookSpacing.xs) {
                // L'intitulé est **écrit à la main** — Gloria Hallelujah, comme
                // la maquette, et comme les titres du carnet (T54). La police
                // est dans le bundle depuis le mot des fondateurs.
                Image(brand: "IconLucideSparkles")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: glyph, height: glyph)
                    .foregroundStyle(MemoBookColor.action)

                Text(card.title)
                    .font(MemoBookFont.handwriting)
                    .foregroundStyle(MemoBookColor.action)

                // « Ça me convient » a été dit : une coche discrète, dans le
                // vert d'action, à la place de rien — la fiche ne change pas
                // de forme pour le dire.
                if card.isValidated {
                    Image(brand: "IconLucideCheck")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: glyph, height: glyph)
                        .foregroundStyle(MemoBookColor.action)
                        .transition(.scale.combined(with: .opacity))
                }
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
        switch stage {
        case .listening:
            HStack(spacing: MemoBookSpacing.xs) {
                ProgressView().controlSize(.small).tint(MemoBookColor.action)
                Text(ChatCopy.transcriptPending)
                    .font(MemoBookFont.bubble)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }

        case .writing:
            // Le brut est là, en gris : le voyageur voit tout de suite qu'il a
            // été entendu, et le texte rédigé viendra le remplacer.
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                HStack(spacing: MemoBookSpacing.xs) {
                    ProgressView().controlSize(.small).tint(MemoBookColor.action)
                    Text(ChatCopy.transcriptWriting)
                        .font(MemoBookFont.caption)
                        .foregroundStyle(MemoBookColor.inkMuted)
                }
                narrative(card.text ?? "", tint: MemoBookColor.inkMuted)
            }

        case .failed:
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                Text(ChatCopy.transcriptFailed)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.error)
                    .fixedSize(horizontal: false, vertical: true)
                if let text = card.text, !text.isEmpty {
                    narrative(text, tint: MemoBookColor.inkMuted)
                }
            }

        case .ready:
            narrative(card.text ?? "", tint: MemoBookColor.ink)
        }
    }

    /// Le récit, replié à sept lignes tant qu'on ne demande pas la suite.
    private func narrative(_ text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            Text(text)
                .font(MemoBookFont.bubble)
                .foregroundStyle(tint)
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
