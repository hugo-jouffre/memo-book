import Foundation

// La conversation avec MEMO : ce que le voyageur raconte, et ce que l'assistant
// en fait. Modélisé comme le back-end le rendra, et pour la même raison que
// ``HomeFeed`` et ``TripDetail`` : l'écran ne sait rien du contenu, il ne sait
// que le dessiner. Le jour où la route existe, seule la source change.
//
// **Deux couleurs, deux auteurs, et c'est toute la lecture de l'écran** : le
// bleu à droite est ce que le voyageur a dit, le blanc à gauche est ce que MEMO
// en a compris. Aucune bulle blanche ne s'écrit à la main — chacune est produite
// par l'analyse d'un message du voyageur, voir ``MemoResponder``.

/// Qui parle.
public enum ChatAuthor: String, Codable, Sendable, Hashable {
    /// L'assistant. Bulle blanche, alignée à gauche.
    case memo

    /// Le voyageur. Bulle bleue, alignée à droite.
    case traveller

    /// `true` quand c'est le voyageur : c'est cette seule question que l'écran
    /// pose pour décider du côté, de la couleur et du sens de la queue.
    public var isTraveller: Bool { self == .traveller }
}

/// Un vocal, tel qu'il s'affiche dans une bulle.
public struct VoiceNote: Codable, Sendable, Hashable, Identifiable {
    public let id: String

    public let duration: TimeInterval

    /// Les niveaux relevés pendant l'enregistrement, de 0 à 1, dans l'ordre du
    /// temps. C'est **la** waveform : elle dessine ce qui a vraiment été dit, et
    /// non un motif décoratif qui serait le même pour tous les vocaux.
    ///
    /// ``AudioRecorder`` n'expose qu'un niveau **instantané**, sans historique :
    /// c'est donc au modèle de l'écran d'échantillonner pendant qu'on parle.
    /// Peut être vide — un vocal importé n'a pas de relevé —, et la vue dessine
    /// alors une ligne plate plutôt que rien.
    public let levels: [Double]

    /// Où trouver l'audio côté serveur. `nil` tant que le vocal n'a pas quitté
    /// l'appareil : il est alors lisible depuis ``localUrl``.
    public let remoteUrl: URL?

    /// Le fichier sur l'appareil, le temps que l'envoi se fasse.
    ///
    /// Hors ``Codable`` : un chemin local n'a aucun sens pour le serveur, et en
    /// recevoir un d'une réponse serait un bug qu'on préfère ne pas pouvoir
    /// écrire.
    ///
    /// ⚠️ ``AudioRecorder/stop()`` **efface** son fichier temporaire et ne rend
    /// que des `Data` : c'est au modèle de l'écran de les réécrire quelque part
    /// s'il veut que le vocal soit réécoutable. Sans ça, le triangle de lecture
    /// n'a rien à jouer.
    public var localUrl: URL?

    public init(
        id: String,
        duration: TimeInterval,
        levels: [Double] = [],
        remoteUrl: URL? = nil,
        localUrl: URL? = nil
    ) {
        self.id = id
        self.duration = duration
        self.levels = levels
        self.remoteUrl = remoteUrl
        self.localUrl = localUrl
    }

    /// L'audio à jouer : le fichier local s'il est encore là, sinon le distant.
    /// Le local d'abord, pour qu'un vocal soit réécoutable avant même d'être
    /// parti.
    public var playbackUrl: URL? { localUrl ?? remoteUrl }

    private enum CodingKeys: String, CodingKey {
        case id, duration, levels, remoteUrl
    }
}

/// Ce que MEMO a retenu d'un vocal : le récit, daté et titré.
///
/// C'est la première réponse à un vocal, et elle est d'une autre nature qu'une
/// phrase : on la relit, on la corrige, elle finira dans le carnet. D'où sa
/// forme de fiche plutôt que de bulle de conversation.
public struct TranscriptCard: Sendable, Hashable {
    /// L'intitulé manuscrit de la fiche — « Retranscription du contexte ».
    /// Il vient de la réponse et non de l'interface parce qu'il dit **ce qui** a
    /// été retranscrit, et que ça change d'un tour à l'autre.
    public let title: String

    /// Le jour dont on parle, pas celui de l'envoi : quelqu'un raconte souvent
    /// sa journée le soir, ou trois jours plus tard. C'est
    /// ``RecordedAudio/recordedAt`` qui le porte, comme
    /// `MemoDetailModel.finishRecording()` le fait déjà pour `capturedAt`.
    public let capturedAt: Date

    public let placeLabel: String?

    /// La durée du vocal d'origine, pour que la fiche dise de quoi elle est
    /// tirée. `nil` pour une fiche qui ne vient pas d'un vocal.
    public let duration: TimeInterval?

    /// Le récit. **`nil` est un état normal**, pas une erreur : la vraie
    /// transcription est un job asynchrone côté serveur, et la fiche s'affiche
    /// avant lui avec ce qu'on sait déjà — la date, le lieu, la durée. Voir
    /// ``MemoResponder/awaitTranscript(of:)``.
    public let text: String?

    /// Le texte est fabriqué par le moteur local, pas transcrit.
    ///
    /// **Ce drapeau est un garde-fou, pas une information d'affichage.** Un
    /// texte simulé ne doit jamais partir vers le carnet : `agents/agent-
    /// transcription.md` interdit d'inventer un fait, et une fiche qui prétend
    /// restituer un vocal que personne n'a écouté en est un.
    public let isSimulated: Bool

    /// L'entrée créée par ce tour, côté serveur. C'est elle que « à la main »
    /// corrigera. `nil` tant qu'aucune route ne l'a créée.
    public let entryId: String?

    /// La mention « généré par IA », exigée par `docs/reglages-utilisateur.md`
    /// dès qu'un texte vient de la machine.
    public let footnote: String?

    /// Où en est la fiche — `docs/conversation.md` § 5. Trois temps que la
    /// bulle dessine différemment : on écoute, on rédige (le brut est là, en
    /// gris), c'est prêt. Le serveur le calcule depuis le souvenir ; le jeu
    /// d'essai, qui ne le porte pas, décode `ready`.
    public enum Phase: Sendable, Hashable {
        /// La transcription est en cours : la fiche n'a que sa date, son lieu et sa durée.
        case listening
        /// Le brut est arrivé, la rédaction écrit : `text` est la transcription, en gris.
        case writing
        /// Le texte rédigé — ce qui ira dans le carnet.
        case ready
        /// La transcription ou la rédaction a échoué ; `text` garde le brut s'il existe.
        case failed
        /// Un temps que le serveur connaît et pas cette version de l'app.
        case unknown(String)
    }

    public let phase: Phase

    /// « Ça me convient » a été dit sur ce souvenir.
    public let isValidated: Bool

    public init(
        title: String,
        capturedAt: Date,
        placeLabel: String? = nil,
        duration: TimeInterval? = nil,
        text: String? = nil,
        isSimulated: Bool = false,
        entryId: String? = nil,
        footnote: String? = nil,
        phase: Phase = .ready,
        isValidated: Bool = false
    ) {
        self.title = title
        self.capturedAt = capturedAt
        self.placeLabel = placeLabel
        self.duration = duration
        self.text = text
        self.isSimulated = isSimulated
        self.entryId = entryId
        self.footnote = footnote
        self.phase = phase
        self.isValidated = isValidated
    }

    /// La même fiche, une fois le récit revenu.
    public func filled(with text: String, isSimulated: Bool) -> TranscriptCard {
        TranscriptCard(
            title: title,
            capturedAt: capturedAt,
            placeLabel: placeLabel,
            duration: duration,
            text: text,
            isSimulated: isSimulated,
            entryId: entryId,
            footnote: footnote,
            phase: .ready,
            isValidated: isValidated
        )
    }

    /// La fiche attend encore quelque chose du serveur : c'est ce qui décide
    /// si l'écran continue de sonder le fil.
    public var isSettling: Bool {
        switch phase {
        case .listening, .writing: true
        case .ready, .failed, .unknown: false
        }
    }
}

extension TranscriptCard: Codable {
    private enum CodingKeys: String, CodingKey {
        case title, capturedAt, placeLabel, duration, text, isSimulated, entryId, footnote
        case phase, isValidated
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            title: try container.decode(String.self, forKey: .title),
            capturedAt: try container.decode(Date.self, forKey: .capturedAt),
            placeLabel: try container.decodeIfPresent(String.self, forKey: .placeLabel),
            duration: try container.decodeIfPresent(TimeInterval.self, forKey: .duration),
            text: try container.decodeIfPresent(String.self, forKey: .text),
            isSimulated: try container.decodeIfPresent(Bool.self, forKey: .isSimulated) ?? false,
            entryId: try container.decodeIfPresent(String.self, forKey: .entryId),
            footnote: try container.decodeIfPresent(String.self, forKey: .footnote),
            phase: try container.decodeIfPresent(Phase.self, forKey: .phase) ?? .ready,
            isValidated: try container.decodeIfPresent(Bool.self, forKey: .isValidated) ?? false
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encodeIfPresent(placeLabel, forKey: .placeLabel)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encode(isSimulated, forKey: .isSimulated)
        try container.encodeIfPresent(entryId, forKey: .entryId)
        try container.encodeIfPresent(footnote, forKey: .footnote)
        try container.encode(phase, forKey: .phase)
        try container.encode(isValidated, forKey: .isValidated)
    }
}

extension TranscriptCard.Phase: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self =
            switch raw {
            case "listening": .listening
            case "writing": .writing
            case "ready": .ready
            case "failed": .failed
            default: .unknown(raw)
            }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .listening: "listening"
        case .writing: "writing"
        case .ready: "ready"
        case .failed: "failed"
        case .unknown(let raw): raw
        }
    }
}

/// Une photo jointe à la conversation.
///
/// Même partage que ``VoiceNote`` entre le local et le distant : le fichier
/// vit dans les caches le temps de l'envoi, et l'URL distante prend la relève.
/// ``localUrl`` est hors ``Codable`` pour la même raison — un chemin d'appareil
/// n'a aucun sens pour le serveur.
public struct PhotoAttachment: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let remoteUrl: URL?
    public var localUrl: URL?

    public init(id: String, remoteUrl: URL? = nil, localUrl: URL? = nil) {
        self.id = id
        self.remoteUrl = remoteUrl
        self.localUrl = localUrl
    }

    public var displayUrl: URL? { localUrl ?? remoteUrl }

    private enum CodingKeys: String, CodingKey {
        case id, remoteUrl
    }
}

/// Ce que porte un message. Quatre formes, et quatre dessins de bulle.
public enum ChatMessageBody: Sendable, Hashable {
    case text(String)
    case voice(VoiceNote)
    case transcript(TranscriptCard)

    /// Des photos, une à quatre. Au-delà, `agents/agent-conversation.md`
    /// demande de n'en garder « 2 à 4 par souvenir maximum » : la bulle en
    /// montre donc quatre et compte le reste.
    case photos([PhotoAttachment])
}

extension ChatMessageBody: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, text, voice, transcript, photos
    }

    private enum Kind: String, Codable {
        case text, voice, transcript, photos
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .voice:
            self = .voice(try container.decode(VoiceNote.self, forKey: .voice))
        case .transcript:
            self = .transcript(try container.decode(TranscriptCard.self, forKey: .transcript))
        case .photos:
            self = .photos(try container.decode([PhotoAttachment].self, forKey: .photos))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(value, forKey: .text)
        case .voice(let note):
            try container.encode(Kind.voice, forKey: .kind)
            try container.encode(note, forKey: .voice)
        case .transcript(let card):
            try container.encode(Kind.transcript, forKey: .kind)
            try container.encode(card, forKey: .transcript)
        case .photos(let attachments):
            try container.encode(Kind.photos, forKey: .kind)
            try container.encode(attachments, forKey: .photos)
        }
    }
}

/// Où en est un message qu'on vient d'envoyer.
///
/// Un message du voyageur apparaît **avant** d'être parti : c'est ce qui fait
/// qu'une conversation répond au doigt. Cet état est donc le seul endroit où se
/// lit la différence entre « affiché » et « arrivé ».
public enum ChatDelivery: Sendable, Hashable {
    case sending
    case sent

    /// L'envoi a échoué, avec de quoi le dire à l'utilisateur. Le message reste
    /// dans la conversation et se renvoie d'une tape : le perdre serait perdre
    /// ce qu'il a raconté.
    case failed(String)

    public var hasFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// Un message de la conversation.
public struct ChatMessage: Sendable, Hashable, Identifiable {
    public let id: String
    public let author: ChatAuthor
    public var body: ChatMessageBody
    public let sentAt: Date
    public var delivery: ChatDelivery

    /// L'étape du voyage dont ce message parle.
    ///
    /// **Un seul fil par voyage**, et non un fil par étape : une conversation
    /// se lit d'un bout à l'autre, et couper le récit en autant de fils que
    /// d'étapes obligerait à en changer pour relire ce qu'on a dit la veille.
    /// C'est cet identifiant qui permet malgré tout d'ouvrir le fil **sur** une
    /// étape — voir ``ChatThread/lastMessage(about:)``.
    ///
    /// `nil` pour ce qui ne parle d'aucune étape en particulier : l'ouverture de
    /// MEMO, une question sur l'abonnement.
    public let stepId: String?

    /// Le prénom de **l'autre** voyageur qui a dit cette bulle, dans un fil à
    /// plusieurs. Le serveur a déjà décidé : `nil` pour soi-même, pour MEMO, et
    /// quand on est seul sur le voyage — la vue affiche, elle ne raisonne pas.
    public let authorName: String?

    /// Le rang dans le fil, tel que le serveur le tient : **la seule vérité sur
    /// l'ordre**. `nil` pour une bulle posée par l'app avant sa réponse.
    public let seq: Int?

    /// Le silence avant cette bulle de MEMO, décidé par le serveur et joué par
    /// l'app — la donnée de rythme de ``MemoBeat``. `nil` pour une bulle du
    /// voyageur.
    public let pauseMilliseconds: Int?

    /// Ce que MEMO a fait de ce tour — `docs/conversation.md` § 4. `nil` pour
    /// une bulle de MEMO, ou tant qu'il n'a pas répondu.
    public let disposition: ChatDisposition?

    public init(
        id: String,
        author: ChatAuthor,
        body: ChatMessageBody,
        sentAt: Date,
        stepId: String? = nil,
        delivery: ChatDelivery = .sent,
        authorName: String? = nil,
        seq: Int? = nil,
        pauseMilliseconds: Int? = nil,
        disposition: ChatDisposition? = nil
    ) {
        self.id = id
        self.author = author
        self.body = body
        self.sentAt = sentAt
        self.stepId = stepId
        self.delivery = delivery
        self.authorName = authorName
        self.seq = seq
        self.pauseMilliseconds = pauseMilliseconds
        self.disposition = disposition
    }

    /// Le texte qu'on peut copier ou faire lire à voix haute. `nil` pour un
    /// vocal — il n'a rien à copier, il a un bouton pour se jouer — et pour une
    /// fiche qui attend encore son récit.
    public var spokenText: String? {
        switch body {
        case .text(let value): value
        case .transcript(let card): card.text
        case .voice, .photos: nil
        }
    }

    /// La même bulle, avec ce que l'app sait et que le serveur ne rend pas : le
    /// fichier local d'un vocal ou d'une photo, le temps qu'il soit parti.
    public func keepingLocalFiles(of previous: ChatMessage) -> ChatMessage {
        var merged = self
        switch (body, previous.body) {
        case (.voice(var note), .voice(let known)):
            note.localUrl = known.localUrl ?? note.localUrl
            merged.body = .voice(note)
        case (.photos(let attachments), .photos(let known)):
            merged.body = .photos(
                attachments.map { attachment in
                    var copy = attachment
                    copy.localUrl = known.first { $0.id == attachment.id }?.localUrl ?? copy.localUrl
                    return copy
                }
            )
        default:
            break
        }
        return merged
    }
}

/// Ce que MEMO a fait d'un tour du voyageur — `docs/conversation.md` § 4.
public enum ChatDisposition: Sendable, Hashable {
    /// Un souvenir : une entrée existe pour lui, la rédaction l'écrit.
    case memory
    /// Une précision, rattachée au souvenir en cours.
    case context
    /// Une puce, un refus, une question sur l'app : rien n'entre dans le carnet.
    case command
    case unknown(String)
}

extension ChatDisposition: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self =
            switch raw {
            case "memory": .memory
            case "context": .context
            case "command": .command
            default: .unknown(raw)
            }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .memory: "memory"
        case .context: "context"
        case .command: "command"
        case .unknown(let raw): raw
        }
    }
}

extension ChatMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, author, body, sentAt, stepId
        case authorName, seq, pauseMilliseconds, disposition
    }

    /// L'acheminement n'est **pas** décodé : un message qui arrive du serveur
    /// est arrivé, par définition. `sending` et `failed` n'existent que le temps
    /// d'un aller-retour, côté app.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            author: try container.decode(ChatAuthor.self, forKey: .author),
            body: try container.decode(ChatMessageBody.self, forKey: .body),
            sentAt: try container.decode(Date.self, forKey: .sentAt),
            stepId: try container.decodeIfPresent(String.self, forKey: .stepId),
            authorName: try container.decodeIfPresent(String.self, forKey: .authorName),
            seq: try container.decodeIfPresent(Int.self, forKey: .seq),
            pauseMilliseconds: try container.decodeIfPresent(Int.self, forKey: .pauseMilliseconds),
            disposition: try container.decodeIfPresent(ChatDisposition.self, forKey: .disposition)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(author, forKey: .author)
        try container.encode(body, forKey: .body)
        try container.encode(sentAt, forKey: .sentAt)
        try container.encodeIfPresent(stepId, forKey: .stepId)
        try container.encodeIfPresent(authorName, forKey: .authorName)
        try container.encodeIfPresent(seq, forKey: .seq)
        try container.encodeIfPresent(pauseMilliseconds, forKey: .pauseMilliseconds)
        try container.encodeIfPresent(disposition, forKey: .disposition)
    }
}

/// Une réponse toute prête, proposée par MEMO sous la conversation.
///
/// Ce n'est pas un raccourci d'interface : c'est **MEMO qui prend la main** en
/// proposant la suite. Les libellés viennent donc du même endroit que ses
/// phrases, et changent à chaque tour.
public struct ChatSuggestion: Codable, Sendable, Hashable, Identifiable {
    /// Ce que la puce déclenche **en plus** d'envoyer son libellé.
    ///
    /// La maquette montre « J'aimerais faire des modifications à la main » posée
    /// en bulle bleue dans le fil : une puce **dit** quelque chose, elle n'est
    /// pas un bouton d'interface déguisé. Ce qui change d'une intention à
    /// l'autre, c'est l'outil qu'elle ouvre derrière.
    public enum Intent: Sendable, Hashable {
        /// Envoyer le libellé, et rien de plus.
        case send

        /// Envoyer le libellé, puis ouvrir le clavier : « à la main ».
        case sendThenWrite

        /// Envoyer le libellé, puis ouvrir le clavier **avec la retranscription
        /// déjà dedans** : « J'aimerais faire des modifications à la main »
        /// sous une fiche remplie. On ne retape pas cinquante mots pour en
        /// changer trois — le texte de MEMO est posé dans le champ, prêt à
        /// être corrigé (Hugo, 17/09/2026).
        case sendThenEditTranscript

        /// Envoyer le libellé, puis armer le micro : « à l'oral ».
        case sendThenSpeak

        /// Ouvrir le sélecteur de photos. La seule qui n'envoie rien : on ne
        /// dit pas « j'importe des photos », on les importe.
        case importPhotos

        /// Une intention que le serveur connaît et pas cette version de l'app.
        /// Elle se comporte alors comme `send` — la puce marche, elle en fait
        /// juste un peu moins. Même parti pris que ``Status/unknown``.
        case unknown(String)
    }

    public let id: String

    /// Le libellé, au caractère près : c'est lui qui part comme message.
    public let label: String

    /// L'emoji de tête, quand la maquette en montre un. Séparé du libellé pour
    /// qu'il ne se retrouve pas dans le message envoyé, ni lu par VoiceOver.
    public let symbol: String?

    public let intent: Intent

    public init(id: String, label: String, symbol: String? = nil, intent: Intent = .send) {
        self.id = id
        self.label = label
        self.symbol = symbol
        self.intent = intent
    }
}

extension ChatSuggestion.Intent: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self =
            switch raw {
            case "send": .send
            case "send_then_write": .sendThenWrite
            case "send_then_edit_transcript": .sendThenEditTranscript
            case "send_then_speak": .sendThenSpeak
            case "import_photos": .importPhotos
            default: .unknown(raw)
            }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .send: "send"
        case .sendThenWrite: "send_then_write"
        case .sendThenEditTranscript: "send_then_edit_transcript"
        case .sendThenSpeak: "send_then_speak"
        case .importPhotos: "import_photos"
        case .unknown(let raw): raw
        }
    }
}

/// La bannière « Aperçu en direct » en haut de la conversation : ce que la
/// conversation a déjà produit.
///
/// Elle est là pour une seule raison — raconter dans le vide est décourageant.
/// Deux compteurs suffisent à montrer que le carnet monte pendant qu'on parle.
public struct ChatBookPreview: Codable, Sendable, Hashable {
    public let memoryCount: Int
    public let pageCount: Int

    /// L'aperçu est prêt à s'ouvrir. Faux tant qu'il n'y a rien à montrer : la
    /// bannière se lit alors comme un compteur, pas comme une porte.
    public let isOpenable: Bool

    public init(memoryCount: Int, pageCount: Int, isOpenable: Bool = true) {
        self.memoryCount = memoryCount
        self.pageCount = pageCount
        self.isOpenable = isOpenable
    }
}

/// L'accueil d'une conversation qui n'a rien dedans : le signe de la marque, une
/// phrase qui nomme le voyage, et ce que MEMO propose d'en faire.
///
/// C'est du **contenu** et non de l'interface : « Nouveau voyage à Rome ! »
/// dépend du voyage, et la relance de ce que le serveur sait déjà.
public struct ChatGreeting: Codable, Sendable, Hashable {
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

/// Ce que MEMO sait du voyage quand il répond. C'est **tout** son contexte : il
/// n'a accès à rien d'autre, ce qui rend ses réponses testables une par une.
public struct ChatContext: Codable, Sendable, Hashable {
    public let tripId: String
    public let tripTitle: String?
    public let travellerFirstName: String?

    /// Le lieu de la dernière étape connue. Il complète l'analyse quand le
    /// message du voyageur n'en nomme aucun.
    public let placeName: String?
    public let stepNumber: Int?

    /// L'étape à laquelle rattacher ce qu'on raconte maintenant.
    ///
    /// C'est l'étape ouverte, ou à défaut la dernière du voyage : dans un carnet
    /// de voyage, ce qu'on dit le soir parle de la journée en cours. C'est elle
    /// qui se retrouve sur ``ChatMessage/stepId``, et qui permet plus tard de
    /// rouvrir le fil sur cette journée-là.
    public let stepId: String?

    /// ``TripDetail/prompt`` — la relance que le voyageur a déjà vue au-dessus
    /// du micro, sur l'accueil du voyage.
    ///
    /// **Le chat n'ouvre plus dessus** (Hugo, 17/09/2026) : la bulle
    /// d'ouverture pose déjà sa question — le contexte du voyage — et la
    /// relance ne doit pas venir par-dessus. Elle reste dans le contexte pour
    /// que le répondeur sache de quelle journée on parle, et pour la
    /// notification qui la portera.
    public let prompt: String?

    /// Combien de personnes sont sur ce voyage, propriétaire compris. Au-delà
    /// de un, le fil est **commun** et les bulles portent un prénom. Un jeu
    /// d'essai qui ne le dit pas décode `1`.
    public let memberCount: Int

    public init(
        tripId: String,
        tripTitle: String? = nil,
        travellerFirstName: String? = nil,
        placeName: String? = nil,
        stepNumber: Int? = nil,
        stepId: String? = nil,
        prompt: String? = nil,
        memberCount: Int = 1
    ) {
        self.tripId = tripId
        self.tripTitle = tripTitle
        self.travellerFirstName = travellerFirstName
        self.placeName = placeName
        self.stepNumber = stepNumber
        self.stepId = stepId
        self.prompt = prompt
        self.memberCount = memberCount
    }

    private enum CodingKeys: String, CodingKey {
        case tripId, tripTitle, travellerFirstName, placeName, stepNumber, stepId, prompt
        case memberCount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            tripId: try container.decode(String.self, forKey: .tripId),
            tripTitle: try container.decodeIfPresent(String.self, forKey: .tripTitle),
            travellerFirstName: try container.decodeIfPresent(String.self, forKey: .travellerFirstName),
            placeName: try container.decodeIfPresent(String.self, forKey: .placeName),
            stepNumber: try container.decodeIfPresent(Int.self, forKey: .stepNumber),
            stepId: try container.decodeIfPresent(String.self, forKey: .stepId),
            prompt: try container.decodeIfPresent(String.self, forKey: .prompt),
            memberCount: try container.decodeIfPresent(Int.self, forKey: .memberCount) ?? 1
        )
    }
}

/// Où en est le tour de parole, vu du serveur : un message du voyageur attend
/// encore la réponse de MEMO, ou non. C'est ce que l'app sonde.
public enum ChatTurnStatus: Sendable, Hashable {
    case idle
    case replying(messageId: String)

    public var isReplying: Bool {
        if case .replying = self { return true }
        return false
    }
}

extension ChatTurnStatus: Codable {
    private enum CodingKeys: String, CodingKey {
        case status, messageId
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)
        if status == "replying", let messageId = try container.decodeIfPresent(String.self, forKey: .messageId) {
            self = .replying(messageId: messageId)
        } else {
            self = .idle
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:
            try container.encode("idle", forKey: .status)
        case .replying(let messageId):
            try container.encode("replying", forKey: .status)
            try container.encode(messageId, forKey: .messageId)
        }
    }
}

/// La suite du fil depuis un instant — ce que `GET /v1/trips/:id/chat?since=`
/// rend, et que le modèle fusionne dans ce qu'il a : on insère ou on remplace
/// par `id`, on trie par `seq`.
public struct ChatThreadUpdate: Codable, Sendable, Hashable {
    public let messages: [ChatMessage]
    public let suggestions: [ChatSuggestion]
    public let preview: ChatBookPreview?
    public let turn: ChatTurnStatus
    /// L'heure du serveur à la lecture : le curseur de la lecture suivante.
    public let now: Date

    public init(
        messages: [ChatMessage],
        suggestions: [ChatSuggestion] = [],
        preview: ChatBookPreview? = nil,
        turn: ChatTurnStatus = .idle,
        now: Date
    ) {
        self.messages = messages
        self.suggestions = suggestions
        self.preview = preview
        self.turn = turn
        self.now = now
    }
}

/// Ce que `POST /v1/trips/:id/chat` rend : les bulles qu'il vient d'écrire —
/// l'ouverture si elle vient d'être posée, le message du voyageur avec son
/// `seq`, la fiche pour un vocal — et l'état du tour.
public struct ChatTurnReceipt: Codable, Sendable, Hashable {
    public let messages: [ChatMessage]
    public let turn: ChatTurnStatus
    public let now: Date

    public init(messages: [ChatMessage], turn: ChatTurnStatus, now: Date) {
        self.messages = messages
        self.turn = turn
        self.now = now
    }
}

/// Ce que « Ça me convient » rend : le souvenir validé, et où en sont les
/// étapes offertes.
public struct EntryValidation: Codable, Sendable, Hashable {
    public let entry: Entry
    public let offeredSteps: Int?
    public let remainingSteps: Int?

    public init(entry: Entry, offeredSteps: Int? = nil, remainingSteps: Int? = nil) {
        self.entry = entry
        self.offeredSteps = offeredSteps
        self.remainingSteps = remainingSteps
    }
}

/// Le tour de parole soumis au répondeur : ce qui vient d'être dit, ce qui l'a
/// précédé, et ce qu'on sait du voyage.
public struct ChatTurn: Sendable, Hashable {
    public let message: ChatMessage

    /// Le fil, sans ``message``, et **borné** : voir ``historyLimit``.
    public let history: [ChatMessage]

    public let context: ChatContext

    /// Combien de bulles le répondeur relit pour ne pas se répéter.
    ///
    /// Vingt, et pas tout le fil : c'est la mémoire d'une conversation, pas une
    /// archive, et rescanner quatre cents bulles à chaque tour coûterait de plus
    /// en plus cher pour une information de moins en moins utile. La rédaction
    /// borne déjà son contexte de la même façon, à trois étapes.
    public static let historyLimit = 20

    public init(message: ChatMessage, history: [ChatMessage], context: ChatContext) {
        self.message = message
        self.history = history.suffix(Self.historyLimit)
        self.context = context
    }

    /// Tout ce que MEMO a déjà dit dans ce fil. C'est là — et nulle part
    /// ailleurs — que le répondeur va chercher de quoi ne pas se répéter : il
    /// reste donc une valeur sans état mutable.
    public var thingsMemoAlreadySaid: Set<String> {
        Set(
            history
                .filter { $0.author == .memo }
                .compactMap { message in
                    if case .text(let value) = message.body { return value }
                    return nil
                }
        )
    }
}

/// Une bulle de MEMO, et le silence qu'il prend avant de la poser.
///
/// **Le répondeur ne dort jamais, il décrit.** Le rythme est une donnée et non
/// un effet de bord : c'est ce qui laisse le moteur testable — on vérifie
/// qu'aucune pause n'est nulle — et le modèle maître du minutage.
public struct MemoBeat: Codable, Sendable, Hashable {
    public let message: ChatMessage

    /// En millisecondes, et non en `Duration` : `Duration` s'encode en
    /// `{seconds, attoseconds}`, illisible dans un contrat JSON.
    public let pauseMilliseconds: Int

    public init(message: ChatMessage, pauseMilliseconds: Int) {
        self.message = message
        self.pauseMilliseconds = pauseMilliseconds
    }

    public var pause: Duration { .milliseconds(pauseMilliseconds) }
}

/// Ce que MEMO répond à un tour de parole.
///
/// Un tour peut valoir **plusieurs** bulles — une fiche de retranscription puis
/// une relance —, et il remplace toujours les suggestions : celles du tour
/// précédent ne veulent plus rien dire.
public struct MemoReply: Codable, Sendable, Hashable {
    public let beats: [MemoBeat]
    public let suggestions: [ChatSuggestion]

    /// Les compteurs de la bannière, quand ce tour les a fait bouger. `nil`
    /// laisse en place ceux qui sont affichés.
    public let preview: ChatBookPreview?

    public init(
        beats: [MemoBeat],
        suggestions: [ChatSuggestion] = [],
        preview: ChatBookPreview? = nil
    ) {
        self.beats = beats
        self.suggestions = suggestions
        self.preview = preview
    }
}

/// Une conversation ouverte : tout ce qu'il faut pour dessiner l'écran de chat.
public struct ChatThread: Codable, Sendable, Hashable, Identifiable {
    public let id: String

    /// Le titre de l'en-tête — le nom du voyage, ou celui de l'étape dont on
    /// parle.
    public let title: String

    /// La vignette ronde posée devant le titre : la couverture du voyage.
    public let avatarUrl: URL?

    /// Le pays, pour le drapeau de l'accueil de conversation.
    public let destination: Destination?

    public let greeting: ChatGreeting?
    public var preview: ChatBookPreview?
    public let context: ChatContext

    public var messages: [ChatMessage]
    public var suggestions: [ChatSuggestion]

    /// Un tour du voyageur attend encore MEMO — le serveur le sait, l'app le
    /// sonde. `idle` pour un jeu d'essai.
    public var turn: ChatTurnStatus

    /// « Supprimer la conversation » est ouvert à ce compte : le propriétaire
    /// du voyage. Un co-voyageur voit le lien pâli.
    public let canClear: Bool

    /// L'heure du serveur à la lecture — le curseur du sondage. `nil` pour un
    /// jeu d'essai.
    public let now: Date?

    public init(
        id: String,
        title: String,
        avatarUrl: URL? = nil,
        destination: Destination? = nil,
        greeting: ChatGreeting? = nil,
        preview: ChatBookPreview? = nil,
        context: ChatContext,
        messages: [ChatMessage] = [],
        suggestions: [ChatSuggestion] = [],
        turn: ChatTurnStatus = .idle,
        canClear: Bool = true,
        now: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.avatarUrl = avatarUrl
        self.destination = destination
        self.greeting = greeting
        self.preview = preview
        self.context = context
        self.messages = messages
        self.suggestions = suggestions
        self.turn = turn
        self.canClear = canClear
        self.now = now
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, avatarUrl, destination, greeting, preview, context, messages, suggestions
        case turn, canClear, now
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            avatarUrl: try container.decodeIfPresent(URL.self, forKey: .avatarUrl),
            destination: try container.decodeIfPresent(Destination.self, forKey: .destination),
            greeting: try container.decodeIfPresent(ChatGreeting.self, forKey: .greeting),
            preview: try container.decodeIfPresent(ChatBookPreview.self, forKey: .preview),
            context: try container.decode(ChatContext.self, forKey: .context),
            messages: try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? [],
            suggestions: try container.decodeIfPresent([ChatSuggestion].self, forKey: .suggestions) ?? [],
            turn: try container.decodeIfPresent(ChatTurnStatus.self, forKey: .turn) ?? .idle,
            canClear: try container.decodeIfPresent(Bool.self, forKey: .canClear) ?? true,
            now: try container.decodeIfPresent(Date.self, forKey: .now)
        )
    }

    /// Rien n'a encore été dit. C'est cet état, et lui seul, qui montre
    /// ``greeting`` à la place de la conversation.
    public var isEmpty: Bool { messages.isEmpty }

    /// Le même fil, **sans un mot** : ce qu'on obtient après « Supprimer la
    /// conversation ». Le voyage, son en-tête et son mot d'accueil restent ;
    /// les messages et les puces s'en vont — les puces d'ouverture reviennent
    /// d'elles-mêmes, elles appartiennent au répondeur.
    public func cleared() -> ChatThread {
        var thread = self
        thread.messages = []
        thread.suggestions = []
        return thread
    }

    /// Le dernier message qui parle de cette étape.
    ///
    /// C'est **la** cible d'une ouverture depuis une carte d'étape : on ne veut
    /// pas le début de ce qu'on a raconté ce jour-là, on veut où on en était.
    /// `nil` quand l'étape n'a encore rien — le fil s'ouvre alors sur sa fin,
    /// comme d'habitude.
    public func lastMessage(about stepId: String) -> ChatMessage? {
        messages.last { $0.stepId == stepId }
    }
}

// MARK: - Ce que l'app envoie

/// Un texte ou une puce, tel que `POST /v1/trips/:id/chat` le reçoit.
///
/// `id` est **fourni par l'app** et devient l'identifiant du message : la bulle
/// optimiste et la bulle servie sont la même, et un renvoi après une panne de
/// transport tombe sur l'existant au lieu de créer un doublon.
public struct ChatTextTurn: Encodable, Sendable, Hashable {
    public let id: String
    public let kind = "text"
    public let text: String
    public let stepId: String?
    /// La puce qui a produit ce message, ou une commande silencieuse
    /// (`transcript_edited`). `nil` pour un texte libre.
    public let suggestionId: String?
    /// Le souvenir visé par « Ça me convient ».
    public let entryId: String?

    public init(
        id: String,
        text: String,
        stepId: String? = nil,
        suggestionId: String? = nil,
        entryId: String? = nil
    ) {
        self.id = id
        self.text = text
        self.stepId = stepId
        self.suggestionId = suggestionId
        self.entryId = entryId
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, text, stepId, suggestionId, entryId
    }
}

/// Un vocal, tel que la route le reçoit en `multipart/form-data`.
public struct ChatVoiceTurn: Sendable, Hashable {
    public let id: String
    public let data: Data
    public let filename: String
    public let mimeType: String
    /// Le jour raconté — `RecordedAudio.recordedAt`.
    public let capturedAt: Date
    /// La durée réellement capturée, pauses déduites : c'est elle qui décompte.
    public let durationSeconds: TimeInterval
    /// La forme d'onde relevée pendant l'enregistrement, pour la bulle.
    public let levels: [Double]
    public let placeLabel: String?
    public let stepId: String?

    public init(
        id: String,
        data: Data,
        filename: String,
        mimeType: String,
        capturedAt: Date,
        durationSeconds: TimeInterval,
        levels: [Double] = [],
        placeLabel: String? = nil,
        stepId: String? = nil
    ) {
        self.id = id
        self.data = data
        self.filename = filename
        self.mimeType = mimeType
        self.capturedAt = capturedAt
        self.durationSeconds = durationSeconds
        self.levels = levels
        self.placeLabel = placeLabel
        self.stepId = stepId
    }
}

/// Une photo à envoyer, une à quatre par tour.
public struct ChatPhotoUpload: Sendable, Hashable {
    public let data: Data
    public let filename: String
    public let mimeType: String

    public init(data: Data, filename: String, mimeType: String) {
        self.data = data
        self.filename = filename
        self.mimeType = mimeType
    }
}

public struct ChatPhotosTurn: Sendable, Hashable {
    public let id: String
    public let photos: [ChatPhotoUpload]
    public let capturedAt: Date
    public let stepId: String?

    public init(id: String, photos: [ChatPhotoUpload], capturedAt: Date, stepId: String? = nil) {
        self.id = id
        self.photos = photos
        self.capturedAt = capturedAt
        self.stepId = stepId
    }
}
