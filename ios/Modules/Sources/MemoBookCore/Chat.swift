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
public struct TranscriptCard: Codable, Sendable, Hashable {
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

    public init(
        title: String,
        capturedAt: Date,
        placeLabel: String? = nil,
        duration: TimeInterval? = nil,
        text: String? = nil,
        isSimulated: Bool = false,
        entryId: String? = nil,
        footnote: String? = nil
    ) {
        self.title = title
        self.capturedAt = capturedAt
        self.placeLabel = placeLabel
        self.duration = duration
        self.text = text
        self.isSimulated = isSimulated
        self.entryId = entryId
        self.footnote = footnote
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
            footnote: footnote
        )
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

    public init(
        id: String,
        author: ChatAuthor,
        body: ChatMessageBody,
        sentAt: Date,
        stepId: String? = nil,
        delivery: ChatDelivery = .sent
    ) {
        self.id = id
        self.author = author
        self.body = body
        self.sentAt = sentAt
        self.stepId = stepId
        self.delivery = delivery
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
}

extension ChatMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, author, body, sentAt, stepId
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
            stepId: try container.decodeIfPresent(String.self, forKey: .stepId)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(author, forKey: .author)
        try container.encode(body, forKey: .body)
        try container.encode(sentAt, forKey: .sentAt)
        try container.encodeIfPresent(stepId, forKey: .stepId)
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
    /// du micro. **Le chat ouvre dessus** : les deux écrans doivent dire la
    /// même phrase, sinon le même voyage se relance deux fois différemment.
    public let prompt: String?

    public init(
        tripId: String,
        tripTitle: String? = nil,
        travellerFirstName: String? = nil,
        placeName: String? = nil,
        stepNumber: Int? = nil,
        stepId: String? = nil,
        prompt: String? = nil
    ) {
        self.tripId = tripId
        self.tripTitle = tripTitle
        self.travellerFirstName = travellerFirstName
        self.placeName = placeName
        self.stepNumber = stepNumber
        self.stepId = stepId
        self.prompt = prompt
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
    public let preview: ChatBookPreview?
    public let context: ChatContext

    public var messages: [ChatMessage]
    public var suggestions: [ChatSuggestion]

    public init(
        id: String,
        title: String,
        avatarUrl: URL? = nil,
        destination: Destination? = nil,
        greeting: ChatGreeting? = nil,
        preview: ChatBookPreview? = nil,
        context: ChatContext,
        messages: [ChatMessage] = [],
        suggestions: [ChatSuggestion] = []
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
    }

    /// Rien n'a encore été dit. C'est cet état, et lui seul, qui montre
    /// ``greeting`` à la place de la conversation.
    public var isEmpty: Bool { messages.isEmpty }

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
