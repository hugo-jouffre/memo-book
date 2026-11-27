import MemoBookCore
import MemoBookDesign
import SwiftUI
import UIKit

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

    /// **Cette bulle est celle qu'on a choisie** (T286) : elle se cerne d'un
    /// liseré, et les puces du bas répondent à elle.
    var isSelected: Bool = false

    /// Ce que fait le bouton posé sous une bulle de MEMO — ``ChatCallToAction``.
    /// C'est l'écran qui ouvre ce qu'il ouvre (le paywall, les réglages du
    /// voyage, l'aperçu…) ; la rangée ne fait que transmettre.
    var onCallToAction: (ChatCallToAction) -> Void = { _ in }

    @Environment(\.dynamicTypeSize) private var typeSize

    /// « Supprimer » a été touché sous une bulle qui attend l'illimité : la
    /// confirmation est ouverte.
    @State private var confirmsDiscard = false

    /// « Supprimer » a été touché **dans le menu de l'appui long** (T270) : la
    /// confirmation est ouverte. Une autre que celle du dessus, et qui ne dit
    /// pas la même chose — ici le souvenir quitte aussi le carnet.
    @State private var confirmsDeletion = false

    var body: some View {
        VStack(alignment: alignment, spacing: MemoBookSpacing.xs / 2) {
            authorCaption
            row
            deliveryNotice
            deliveryTicks
        }
        .frame(maxWidth: .infinity, alignment: horizontalAlignment)
    }

    /// **Un appui simple choisit la bulle** (T286, Hugo — « un clic simple sur
    /// un message le cerne d'un liseré bleu clair, et les propositions
    /// s'adaptent à ce message-là »).
    ///
    /// Le liseré se dessine **autour** de la bulle et non dedans : le fond
    /// d'une bulle du voyageur est déjà ce bleu-là (`bubbleTraveller`), et un
    /// contour de la même couleur n'y serait pas visible. D'où le bleu
    /// **soutenu** (`blueText`), à deux points, posé en dehors — c'est le
    /// même bleu que l'app emploie partout pour dire « ceci est désigné ».
    ///
    /// L'appui ne mange rien : les photos ouvrent toujours la visionneuse,
    /// les boutons d'une fiche restent des boutons — ils sont posés **dans**
    /// la bulle, et leur geste l'emporte sur celui-ci (`.highPriorityGesture`
    /// n'est pas nécessaire : SwiftUI sert d'abord le plus intérieur).
    @ViewBuilder
    private func selectable(_ content: some View) -> some View {
        content
            .overlay {
                if isSelected {
                    // **La forme de la bulle elle-même**, queue comprise : un
                    // rectangle arrondi lui couperait sa pointe.
                    BrandBubbleShape(side: isTraveller ? .trailing : .leading)
                        .stroke(MemoBookColor.blueText, lineWidth: 2)
                        .padding(-3)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .contentShape(.rect)
            .onTapGesture { model.select(message.id) }
            .animation(.smooth(duration: 0.2), value: isSelected)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// **Les coches, à la manière de WhatsApp** (Hugo, 08/10/2026), sous les
    /// messages qu'on a dits soi-même : une coche grise, il est **gardé sur
    /// le téléphone** — dans la file, il partira tout seul ; deux, il est
    /// **arrivé chez nous**, et la retranscription a commencé.
    ///
    /// Rien sous une bulle qui attend le crédit ou l'illimité, ni sous un
    /// échec : la mention dessous (``deliveryNotice``) dit déjà où il en est,
    /// et une coche à côté se contredirait avec elle. Rien sous les bulles
    /// d'un co-voyageur : ce n'est pas notre envoi.
    @ViewBuilder
    private var deliveryTicks: some View {
        if isTraveller, message.authorName == nil {
            switch message.delivery {
            case .sending:
                ChatDeliveryTicks(isDelivered: false)
                    .padding(.horizontal, MemoBookSpacing.snug)
            case .sent:
                HStack(spacing: MemoBookSpacing.xs / 2) {
                    // **L'oreille, le temps de la transcription** (T316) :
                    // c'est tout ce qu'on montre pendant qu'un vocal se
                    // transcrit. La fiche, elle, attend d'avoir un texte
                    // (``ChatModel/messages``).
                    if model.isBeingTranscribed(message) { listeningEar }
                    ChatDeliveryTicks(isDelivered: true)
                }
                .padding(.horizontal, MemoBookSpacing.snug)
            case .failed, .waitingForCredit, .waitingForUnlimited:
                EmptyView()
            }
        }
    }

    /// **Le petit 👂 posé sur un vocal qu'on écoute** (T316, Hugo).
    ///
    /// L'emoji et non une icône du jeu de marque : c'est ce que le ticket
    /// demande nommément, et une oreille dessinée au trait, à treize points
    /// à côté des coches, ne se lirait pas. Il suit le corps du texte comme
    /// elles, et VoiceOver le dit en toutes lettres — un emoji seul s'y
    /// annoncerait « oreille ».
    private var listeningEar: some View {
        Text(ChatCopy.Voice.listeningEar)
            .font(MemoBookFont.caption)
            .accessibilityLabel(ChatCopy.Voice.listening)
            .transition(.opacity)
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
                selectable(bubble)
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
                selectable(bubble)
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
    ///
    /// Une bulle qui attend le crédit de demain, ou l'illimité, reste en
    /// retrait de la même façon : elle n'est pas partie non plus. C'est la
    /// mention dessous qui dit pourquoi — voir ``deliveryNotice``.
    private var bubble: some View {
        bubbleBody
            .opacity(isWaiting ? 0.6 : 1)
            .animation(.smooth(duration: 0.3), value: message.delivery)
            .accessibilityHint(waitingHint)
            // **L'appui long** (T270) : le menu du système sur la bulle, et
            // non sur la rangée — les deux commandes à côté ont déjà leur
            // geste, et un menu posé par-dessus volerait leur appui.
            .contextMenu { ChatMessageMenu(message: message, model: model, onShare: share, onDelete: askDeletion) }
            .accessibilityActions {
                ChatMessageMenu.accessibilityActions(
                    for: message,
                    model: model,
                    onShare: share,
                    onDelete: askDeletion
                )
            }
            .confirmationDialog(
                deletionTitle,
                isPresented: $confirmsDeletion,
                titleVisibility: .visible
            ) {
                Button(ChatCopy.Menu.deleteConfirm, role: .destructive) { model.delete(message) }
                Button(ChatCopy.Menu.deleteKeep, role: .cancel) {}
            } message: {
                Text(deletionBody)
            }
    }

    private func share() {
        model.share(message)
    }

    /// Le menu ne supprime jamais directement : le souvenir quitte le carnet,
    /// et pour tout le monde.
    private func askDeletion() {
        confirmsDeletion = true
    }

    /// Une photo, des photos, un souvenir : la confirmation nomme ce qui part.
    private var deletionTitle: String {
        if case .photos(let attachments) = message.body, attachments.count > 1 {
            return ChatCopy.Menu.deletePhotosTitle
        }
        return ChatCopy.Menu.deleteTitle
    }

    private var deletionBody: String {
        if case .photos(let attachments) = message.body, attachments.count > 1 {
            return ChatCopy.Menu.deletePhotosBody
        }
        return ChatCopy.Menu.deleteBody
    }

    /// La bulle n'est pas encore chez le serveur : en route, attendant demain
    /// ou l'illimité.
    private var isWaiting: Bool {
        message.delivery == .sending || message.delivery.isWaitingForCredit
            || message.delivery.isWaitingForUnlimited
    }

    private var waitingHint: String {
        if message.delivery.isWaitingForCredit { return ChatCopy.Voice.leavesTomorrow }
        if message.delivery.isWaitingForUnlimited { return ChatCopy.Voice.tooLongForADay }
        return message.delivery == .sending ? ChatCopy.Voice.sending : ""
    }

    @ViewBuilder
    private var bubbleBody: some View {
        switch message.body {
        case .text(let text) where !isTraveller && model.showsCallToAction(message.callToAction):
            // Une bulle de MEMO qui porte un bouton se dessine en carte.
            if let callToAction = message.callToAction {
                ChatCallToActionCard(
                    text: text,
                    callToAction: callToAction,
                    state: model.callToActionState(for: message.id),
                    onFollow: {
                        model.followCallToAction(of: message.id)
                        onCallToAction(callToAction)
                    },
                    onDismiss: { model.dismissCallToAction(of: message.id) }
                )
            }

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
                onToggleExpansion: onToggleExpansion,
                model: model
            )

        case .photos(let attachments):
            ChatPhotosBubble(
                attachments: attachments,
                author: message.author,
                messageId: message.id,
                model: model
            )
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
    ///
    /// **« Partira demain »**, en gris et sans « Réessayer », sous une bulle que
    /// le serveur a refusée faute de crédit du jour (Hugo, 03/10/2026) : elle
    /// attend sur le téléphone et repart toute seule à la recharge. Un
    /// « Réessayer » rouge ferait renvoyer en boucle vers le même refus.
    ///
    /// **« Trop long pour une journée · Passer en illimité »** sous une bulle
    /// qui coûte plus qu'une journée entière de crédit (03/10/2026) : demain
    /// ne la ferait pas passer, l'illimité si. Gris comme « Partira demain »,
    /// l'offre soulignée en vert d'action ; le toucher ouvre le paywall, et la
    /// bulle part dès que le compte raconte sans limite. **« Supprimer »** à
    /// côté, en gris : sans abonnement, c'est la seule autre sortie — après
    /// confirmation, le tour quitte le téléphone et la bulle le fil.
    @ViewBuilder
    private var deliveryNotice: some View {
        if message.delivery.isWaitingForCredit {
            Text(ChatCopy.leavesTomorrow)
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.inkMuted)
                .padding(.horizontal, MemoBookSpacing.snug)
                .accessibilityHidden(true)
        } else if message.delivery.isWaitingForUnlimited {
            // Côte à côte ; l'un sous l'autre en très grand texte, où deux
            // cibles sur une ligne ne laisseraient qu'un mot par ligne.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 0))
                : AnyLayout(HStackLayout(spacing: MemoBookSpacing.xs))
            layout {
                Button {
                    onCallToAction(.dailyCreditSubscribe)
                } label: {
                    // Une seule phrase, qui se replie en très grand texte au
                    // lieu de couper trois morceaux côte à côte.
                    (Text(ChatCopy.tooLongForADay + " · ").foregroundStyle(MemoBookColor.inkMuted)
                        + Text(DailyCreditCopy.unlimitedCallToAction).foregroundStyle(MemoBookColor.action).underline())
                    .font(MemoBookFont.caption)
                    .multilineTextAlignment(.trailing)
                    .frame(minHeight: MemoBookSpacing.minimumTapTarget)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(ChatCopy.tooLongForADay). \(DailyCreditCopy.unlimitedCallToAction)")
                .accessibilityHint(ChatCopy.Credit.exhaustedHint)

                Button {
                    confirmsDiscard = true
                } label: {
                    (Text(typeSize.isAccessibilitySize ? "" : "· ") + Text(ChatCopy.DiscardWaiting.action).underline())
                        .font(MemoBookFont.caption)
                        .foregroundStyle(MemoBookColor.inkMuted)
                        .frame(minHeight: MemoBookSpacing.minimumTapTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ChatCopy.DiscardWaiting.action)
                .accessibilityHint(ChatCopy.DiscardWaiting.hint)
            }
            .padding(.horizontal, MemoBookSpacing.snug)
            .confirmationDialog(discardTitle, isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button(ChatCopy.DiscardWaiting.confirm, role: .destructive) {
                    model.discardWaitingTurn(message.id)
                }
                Button(ChatCopy.DiscardWaiting.keep, role: .cancel) {}
            } message: {
                Text(ChatCopy.DiscardWaiting.body)
            }
        } else if message.delivery.hasFailed {
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

extension ChatMessageRow {
    /// Le titre de la confirmation de « Supprimer » : un vocal, ou un texte —
    /// rien d'autre n'attend l'illimité.
    fileprivate var discardTitle: String {
        if case .voice = message.body { return ChatCopy.DiscardWaiting.voiceTitle }
        return ChatCopy.DiscardWaiting.textTitle
    }
}

/// Une coche ou deux, sous un message à soi — voir
/// ``ChatMessageRow/deliveryTicks``.
///
/// Grises dans les deux cas, comme les commandes à côté des bulles : elles
/// renseignent, elles ne demandent rien. La seconde arrive en glissant sous
/// la première, de la largeur d'un trait : c'est ce mouvement qui se remarque
/// quand le réseau revient.
struct ChatDeliveryTicks: View {
    let isDelivered: Bool

    @ScaledMetric(relativeTo: .caption) private var side: CGFloat = 13
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: -side * 0.55) {
            tick
            if isDelivered {
                tick.transition(
                    reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity)
                )
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: isDelivered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isDelivered ? ChatCopy.Voice.delivered : ChatCopy.Voice.storedOnPhone)
    }

    private var tick: some View {
        Image(brand: "IconLucideCheck")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: side, height: side)
            .foregroundStyle(MemoBookColor.inkMuted)
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
///
/// **Toutes à la taille du crayon** (Hugo, 08/10/2026 : « un peu plus petites
/// et discrètes, le crayon garde sa taille, les autres descendent à la
/// sienne »). Le crayon du jeu de marque n'encre que 70 % de sa boîte de 24 ;
/// les icônes Lucide, 92 %. À boîte égale, copier et écouter paraissaient donc
/// un tiers plus gros. Elles se dessinent dans une boîte plus petite
/// (``lucideSide``), et les quatre ont la même encre. La cible, elle, reste
/// de 2.75 rem : plus discret ne veut pas dire plus difficile à toucher.
private struct ChatActionButton: View {
    let action: ChatMessageAction
    let isActive: Bool

    /// Le geste vient d'aboutir. Vrai une seconde après une copie — voir
    /// ``ChatModel/copiedMessageId``.
    let isConfirmed: Bool

    let perform: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// La boîte du crayon, inchangée.
    @ScaledMetric(relativeTo: .body) private var penSide: CGFloat = MemoBookSpacing.sectionGap
    /// La boîte des icônes Lucide : celle du crayon, ramenée de 92 % à 70 %
    /// d'encre.
    @ScaledMetric(relativeTo: .body) private var lucideSide: CGFloat = MemoBookSpacing.sectionGap * 0.76

    /// Ce que le bouton montre : la coche s'il vient de servir, l'arrêt s'il
    /// parle, son icône sinon.
    private var icon: String {
        if isConfirmed { return "IconLucideCheck" }
        return isActive ? "IconLucideStop" : action.icon
    }

    /// Seul le crayon vient du jeu de marque ; la coche et l'arrêt sont des
    /// Lucide, comme copier et écouter.
    private var side: CGFloat {
        icon == ChatMessageAction.edit.icon ? penSide : lucideSide
    }

    private var tint: Color {
        if isConfirmed { return MemoBookColor.valid }
        // Au repos, un cran sous le gris du texte secondaire : elles se
        // devinent à côté de la bulle sans lui disputer le regard.
        return isActive ? MemoBookColor.action : MemoBookColor.inkMuted.opacity(0.75)
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
    /// La bulle, pour que la visionneuse sache de quelle étape il s'agit (T270).
    var messageId: String?
    /// C'est le modèle qui charge les photos — voir ``ChatModel/loadImage(_:)``.
    let model: ChatModel

    @ScaledMetric(relativeTo: .body) private var thumbnail: CGFloat = 76

    /// Ce qu'on montre, et ce qu'on compte.
    private var shown: [PhotoAttachment] {
        Array(attachments.prefix(ChatMetrics.visiblePhotoCount))
    }

    private var hidden: Int {
        max(0, attachments.count - ChatMetrics.visiblePhotoCount)
    }

    /// Les vignettes deux par deux, telles que la grille les pose.
    private var rows: [[PhotoAttachment]] {
        stride(from: 0, to: shown.count, by: 2).map { Array(shown[$0..<min($0 + 2, shown.count)]) }
    }

    var body: some View {
        BrandChatBubble(author: author) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs / 2) {
                if attachments.count == 1 {
                    photo(attachments[0], at: 0, side: thumbnail * 2.4)
                } else {
                    // Deux colonnes, jamais plus : à trois, une vignette tombe
                    // sous la largeur d'un pouce sur un iPhone SE.
                    //
                    // ⚠️ **Et une grille qui n'est pas paresseuse** (T295,
                    // 26/11/2026). Une `LazyVGrid` ne connaît la hauteur que
                    // des rangées qu'elle a déjà fabriquées : tant que la
                    // bulle n'est qu'à moitié à l'écran, elle s'annonce plus
                    // courte qu'elle ne sera, et tout ce qui la suit remonte —
                    // puis redescend quand la rangée suivante naît. C'est le
                    // saut que Maÿlis voit **à chaque passage devant ses
                    // photos en attente**, et elles en ont six : la bulle la
                    // plus haute du fil, celle qui ne tient jamais d'un coup.
                    //
                    // Six vignettes au plus (``visiblePhotoCount``) : la
                    // paresse ne faisait rien gagner, elle ne coûtait que
                    // cette hauteur-là.
                    Grid(horizontalSpacing: MemoBookSpacing.xs / 2, verticalSpacing: MemoBookSpacing.xs / 2) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { rank, row in
                            GridRow {
                                ForEach(Array(row.enumerated()), id: \.element.id) { column, attachment in
                                    photo(attachment, at: rank * 2 + column, side: thumbnail * 1.4)
                                }
                                // Un nombre impair laisse la dernière place
                                // vide plutôt que d'étirer la vignette sur
                                // toute la largeur.
                                if row.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                            }
                        }
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
        // VoiceOver ne voit pas l'étoile : elle se dit.
        .accessibilityValue(ChatCoverStars.spokenValue(of: attachments))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(ChatCopy.PhotoViewer.hint)
        .accessibilityAction { model.viewPhotos(attachments, at: 0, from: messageId) }
    }

    /// Une vignette : le fichier local tant qu'il est là, sinon le média du
    /// serveur — **avec la session**, par le modèle. Un `AsyncImage` n'envoyait
    /// pas d'en-tête et `/v1/entries/:id/media` le refusait (T206).
    ///
    /// La photo se pose en calque d'un cadre vide : `scaledToFill` ne se laisse
    /// pas contraindre en largeur et ferait déborder la grille.
    ///
    /// Touchée, elle s'ouvre en plein écran (``ChatPhotoViewer``), avec les
    /// autres photos de la bulle à portée de glissé.
    private func photo(_ attachment: PhotoAttachment, at index: Int, side: CGFloat) -> some View {
        let url = attachment.displayUrl

        return Color.clear
            .frame(height: side)
            .frame(maxWidth: .infinity)
            .overlay {
                if let image = url.flatMap({ model.image(at: $0) }) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    // La même trame que les vignettes d'étape : une image qui
                    // charge ne doit pas laisser un trou de la couleur du fond.
                    TripCoverPlaceholder(seed: attachment.id)
                }
            }
            .clipShape(.rect(cornerRadius: MemoBookSpacing.snug))
            // **Les étoiles, en haut à droite** (T270) : celle de l'étape,
            // celle du voyage, ou les deux — une photo peut être les deux.
            .overlay(alignment: .topTrailing) {
                ChatCoverStars(photo: attachment)
                    .padding(MemoBookSpacing.xs / 2)
            }
            .contentShape(.rect(cornerRadius: MemoBookSpacing.snug))
            .onTapGesture { model.viewPhotos(attachments, at: index, from: messageId) }
            .task(id: url) {
                if let url { model.loadImage(url) }
            }
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

    /// Le lecteur tient ce vocal — en lecture **ou en pause**. C'est lui qui
    /// décide si la bulle montre une position ou repart de zéro.
    private var isLoaded: Bool { model.player.isLoaded(note.id) }

    /// Le doigt est sur la tête de lecture : la position qu'il dicte prend le
    /// pas sur celle du lecteur, pour que le point ne tremble pas entre deux
    /// battements.
    @State private var scrubbed: Double?

    var body: some View {
        BrandChatBubble(author: author) {
            // Le bouton, l'onde et la signature partagent **le même axe**, et le
            // chrono pend sous l'onde (Hugo, 30/09/2026, maquette
            // `3627:31695`). C'est l'onde, et non le bloc onde + chrono, qui se
            // centre sur la bulle — voir ``VerticalAlignment/voiceAxis`` :
            // c'est ce que Clara reprochait le 17/09 à la version en deux
            // lignes, dont l'onde remontait au-dessus du milieu.
            HStack(alignment: .voiceAxis, spacing: MemoBookSpacing.snug) {
                playButton

                VStack(alignment: .leading, spacing: 2) {
                    track
                        .alignmentGuide(.voiceAxis) { $0[VerticalAlignment.center] }
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
        .task(id: note.id) { await model.deriveLevelsIfNeeded(for: note) }
    }

    /// L'onde, et la tête de lecture posée dessus : le point de la maquette,
    /// au début de l'onde au repos, qui avance avec la lecture.
    private var track: some View {
        let progress = scrubbed ?? (isLoaded ? model.player.progress : 0)

        return BrandWaveform(
            // Le relevé du serveur, ou celui relu dans le fichier quand le
            // vocal est arrivé sans — voir ``ChatModel/deriveLevelsIfNeeded(for:)``.
            levels: model.levels(of: note),
            progress: progress,
            tint: MemoBookColor.inkMuted,
            playedTint: MemoBookColor.ink
        )
        .overlay {
            GeometryReader { proxy in
                let dot = MemoBookSpacing.snug
                Circle()
                    .fill(MemoBookColor.ink)
                    .frame(width: dot, height: dot)
                    // **Le même repère que les barres** (Hugo, 03/11/2026) :
                    // le point se posait à `dot / 2 + (largeur - dot) × p`,
                    // les barres se teintaient à `p × largeur` — deux règles
                    // pour une seule position, d'où le décalage qu'on voyait
                    // passer. C'est maintenant `p × largeur` des deux côtés ;
                    // le point déborde d'un demi-rond dans la marge de la
                    // bulle aux extrémités, comme sur WhatsApp.
                    .position(x: proxy.size.width * progress, y: proxy.size.height / 2)
                    .animation(nil, value: progress)
            }
            .allowsHitTesting(false)
        }
        // Mesurée ici, et non dans le `GeometryReader` du calque : écrire un
        // état pendant qu'on dessine redessine en boucle.
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { trackWidth = $0 }
        // **La tête de lecture se déplace au doigt** (Hugo, 03/11/2026).
        // Posé sur toute l'onde et non sur le seul point : viser un rond de
        // 12 pt dans une bulle n'est pas un geste, c'est un concours. Un
        // appui sans glissement déplace aussi la lecture — c'est ce qu'on
        // attend d'une barre de progression.
        .contentShape(.rect)
        .gesture(scrub)
    }

    /// Le glissé qui déplace la lecture. Il ne vaut que pour le vocal **que le
    /// lecteur tient** : déplacer la tête d'un vocal qu'on n'écoute pas
    /// déplacerait celle d'un autre.
    private var scrub: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isLoaded, trackWidth > 0 else { return }
                scrubbed = min(max(value.location.x / trackWidth, 0), 1)
            }
            .onEnded { value in
                guard isLoaded, trackWidth > 0 else { return }
                let position = min(max(value.location.x / trackWidth, 0), 1)
                model.player.seek(to: position)
                scrubbed = nil
            }
    }

    /// La largeur de l'onde, mesurée une fois : c'est elle qui traduit la
    /// position du doigt en fraction du vocal.
    @State private var trackWidth: CGFloat = 0

    /// Le chrono compte **en avançant** pendant la lecture, et affiche la durée
    /// totale au repos : c'est ce que fait un lecteur, et c'est ce qu'on
    /// cherche des yeux dans les deux cas.
    private var elapsedLabel: String {
        // En pause aussi : le chrono garde le temps écoulé, il ne revient pas
        // à la durée totale (Hugo, 03/11/2026).
        (isLoaded ? model.player.elapsed : note.duration).chatDurationLabel
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
                ChatPortraitDisc(
                    portrait: portrait,
                    image: portrait.url.flatMap { model.image(at: $0) },
                    side: markSide
                )
                .task(id: portrait.url) {
                    if let url = portrait.url { model.loadImage(url) }
                }
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
///
/// La photo arrive **déjà chargée**, par ``ChatModel/loadImage(_:)`` : un
/// `AsyncImage` ici repartait de zéro à chaque recomposition du fil, et restait
/// sur les initiales dès qu'une requête était annulée.
struct ChatPortraitDisc: View {
    let portrait: ChatPortrait
    let image: UIImage?
    let side: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
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

extension VerticalAlignment {
    /// L'axe d'une bulle de vocal : le milieu de l'onde, sur lequel le bouton
    /// de lecture et le portrait se centrent. Le chrono pend dessous sans
    /// déplacer l'axe.
    private enum VoiceAxis: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[VerticalAlignment.center]
        }
    }

    static let voiceAxis = VerticalAlignment(VoiceAxis.self)
}

// MARK: - La retranscription

/// La fiche « Retranscription étape N » : ce que MEMO a compris d'un vocal.
///
/// Elle a la forme d'une **fiche** et non d'une réplique, parce qu'elle n'est
/// pas de la même nature : on la relit, on la corrige, elle finira dans le
/// carnet. D'où l'intitulé, la date, et la note de pied qui dit d'où vient le
/// texte.
struct ChatTranscriptBubble: View {
    let card: TranscriptCard
    let isExpanded: Bool
    let onToggleExpansion: () -> Void
    @Bindable var model: ChatModel

    /// **Quelle version on regarde** (Hugo, 28/10/2026). Un état de la vue et
    /// non du souvenir : regarder la transcription littérale ne change rien
    /// au carnet tant qu'on n'a pas dit de la garder.
    ///
    /// Il part de ce qui est gardé : une fiche qui imprime sa littérale
    /// s'ouvre dessus.
    @State private var showsRawText: Bool?

    /// Ce qu'on regarde : le choix de la vue, sinon ce que le souvenir garde.
    private var isShowingRawText: Bool { showsRawText ?? card.prefersTranscript }

    /// Le texte affiché : l'un ou l'autre, selon la bascule. Sans deux
    /// versions à comparer, c'est celui qui part au carnet, et rien d'autre.
    private var shownText: String? {
        guard card.hasTwoVersions else { return card.text }
        return isShowingRawText ? card.rawText : card.writtenText
    }

    /// La version regardée est-elle déjà celle qui part au carnet ?
    private var isShownVersionKept: Bool { isShowingRawText == card.prefersTranscript }

    /// Les deux versions d'un souvenir, pour la bascule.
    private enum Version: String, Hashable, Identifiable, CaseIterable {
        /// Le texte rédigé par l'IA — celui que le carnet imprime par défaut.
        case written
        /// La transcription littérale, mot pour mot.
        case raw

        var id: String { rawValue }

        var label: String {
            switch self {
            case .written: ChatCopy.Transcript.written
            case .raw: ChatCopy.Transcript.raw
            }
        }
    }

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
        (shownText?.count ?? 0) > Self.expandableLength
    }

    /// Les trois temps de la fiche — `docs/conversation.md` § 5. Une fiche sans
    /// texte écoute encore, quel que soit son temps : le moteur local n'en
    /// pose pas.
    private enum Stage { case listening, writing, ready, unwritten, failed }

    private var stage: Stage {
        guard card.text != nil else { return .listening }
        switch card.phase {
        case .listening: return .listening
        case .writing: return .writing
        case .unwritten: return .unwritten
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
        // Le titre seul quand aucune date n'est comprise : VoiceOver
        // annonçait la date d'enregistrement comme celle de l'étape (T308).
        let day = card.livedDatesSpokenLabel.map {
            ChatCopy.Voice.transcript(title: card.title, day: $0)
        } ?? card.title
        let state: String
        switch stage {
        case .listening: state = ChatCopy.transcriptPending
        case .writing: state = "\(ChatCopy.transcriptWriting) \(card.text ?? "")"
        case .failed: state = "\(ChatCopy.transcriptFailed) \(card.text ?? "")"
        case .unwritten: state = "\(ChatCopy.transcriptUnwritten) \(card.text ?? "")"
        case .ready: state = [isShowingRawText ? nil : card.heading, shownText].compactMap { $0 }.joined(separator: ". ")
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

            // **La date et le lieu, une fois compris** (T308) — sinon rien.
            //
            // La ligne portait le jour de l'enregistrement et l'écho du lieu
            // renvoyé par l'app : un dimanche sur une journée de vendredi, et
            // le nom de la ville précédente le jour où l'on en change. Ce
            // qu'on ne sait pas ne s'écrit plus, et la ligne disparaît quand
            // on ne sait rien — le calendrier avec elle, qui n'annoncerait
            // plus aucune date.
            if card.livedDatesLabel != nil || card.placeName != nil {
                HStack(spacing: MemoBookSpacing.snug) {
                    if let dates = card.livedDatesLabel {
                        Image(brand: "IconLucideCalendar")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: glyph, height: glyph)
                            .foregroundStyle(MemoBookColor.ink)

                        Text(dates)
                            .font(MemoBookFont.caption)
                            .foregroundStyle(MemoBookColor.ink)
                    }

                    if let place = card.placeName {
                        Text(place)
                            .font(MemoBookFont.caption)
                            .foregroundStyle(MemoBookColor.inkMuted)
                            .lineLimit(1)
                    }
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

        // **La transcription a échoué** : rien à lire, et la seule panne de
        // la fiche qui mérite du rouge.
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

        // **La rédaction a échoué, pas la transcription** (Hugo,
        // 04/11/2026). Le mot-pour-mot est là, et c'est lui qui part dans le
        // carnet : il se lit donc à l'encre, comme un texte retenu, sous une
        // phrase grise qui dit ce qui manque. Du rouge au-dessus d'un texte
        // complet disait une perte qui n'a pas eu lieu.
        case .unwritten:
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                Text(ChatCopy.transcriptUnwritten)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if let text = card.text, !text.isEmpty {
                    narrative(text, tint: MemoBookColor.ink)
                }
            }

        case .ready:
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                // Le titre est celui du récit **rédigé** : il ne veut rien
                // dire au-dessus de la transcription brute.
                if let title = card.heading, !title.isEmpty, !isShowingRawText {
                    Text(title)
                        .font(MemoBookFont.sectionTitle)
                        .foregroundStyle(MemoBookColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                // La brute en gris, comme pendant la rédaction : c'est ce
                // qu'on a dit, pas ce que le carnet racontera — sauf si on
                // choisit de la garder.
                narrative(
                    shownText ?? "",
                    tint: isShowingRawText && !card.prefersTranscript
                        ? MemoBookColor.inkMuted
                        : MemoBookColor.ink
                )
                versions
            }
        }
    }

    /// **Les deux versions, et ce qu'on en fait** — la bascule, le choix, la
    /// relance (Hugo, 28/10/2026).
    ///
    /// Rien de tout ça sur une fiche qui n'a qu'un texte : un souvenir écrit
    /// au clavier n'a pas de « version brute » à comparer, et une fiche d'un
    /// serveur plus ancien ne la porte pas.
    @ViewBuilder
    private var versions: some View {
        if let entryId = card.entryId, card.hasTwoVersions {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                BrandSegmentedPicker(
                    Version.allCases,
                    selection: Binding(
                        get: { isShowingRawText ? Version.raw : Version.written },
                        set: { showsRawText = $0 == .raw }
                    ),
                    size: .compact
                ) { $0.label }

                HStack(spacing: MemoBookSpacing.s) {
                    // « Garder celle-ci » ne se propose que sur la version
                    // qu'on ne garde pas déjà : sur l'autre, il ne ferait rien.
                    if !isShownVersionKept {
                        BrandButton(ChatCopy.Transcript.keepThisOne, style: .link, size: .small) {
                            model.keepTranscript(isShowingRawText, forEntry: entryId)
                        }
                    }

                    // **La flèche circulaire** (Hugo, 25/10/2026 — « on ne
                    // comprend pas que "ré-écrire" est cliquable, il faudrait
                    // une flèche circulaire pour illustrer le recommencer »).
                    // Un lien seul, entre deux autres liens, ne disait pas
                    // qu'il relançait quelque chose ; le glyphe le dit avant
                    // le mot.
                    BrandButton(
                        ChatCopy.Transcript.reanalyse,
                        icon: Image(brand: "IconLucideRotateCw"),
                        style: .link,
                        size: .small
                    ) {
                        model.reanalyse(entryId: entryId)
                    }
                }

                // Ce que le carnet imprimera, écrit une fois — sans quoi la
                // bascule laisse croire qu'on a changé le carnet en regardant.
                Text(
                    card.prefersTranscript
                        ? ChatCopy.Transcript.keepingRaw
                        : ChatCopy.Transcript.keepingWritten
                )
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, MemoBookSpacing.xs / 2)
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
