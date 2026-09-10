import Foundation

/// MEMO, tant que le back-end n'a pas d'agent de conversation.
///
/// **Une priorité stricte, pas une addition de scores.** Les signaux relevés par
/// ``ChatSignals`` ne se cumulent pas : le premier qui se déclenche choisit la
/// famille de réponse, et les suivants sont ignorés. C'est ce qui distingue un
/// moteur qui écoute d'un tirage au sort — un refus ne reçoit jamais une
/// question, et une question ne reçoit jamais une relance.
///
/// **Aucun état mutable, aucun aléatoire, aucune horloge.** La mémoire du moteur
/// est ``ChatTurn/history`` : avant d'émettre, il écarte toute phrase déjà dite
/// dans le fil et descend d'un cran plutôt que de se répéter. Il reste donc une
/// `struct Sendable` déterministe — le même tour rend toujours la même réponse,
/// ce qui le rend testable ligne à ligne.
///
/// **Le rythme est une donnée.** ``MemoBeat/pauseMilliseconds`` se calcule sur la
/// matière du message : plus il y a à lire, plus MEMO met de temps à répondre.
/// Une latence nulle, ou constante, est le premier signe qu'il n'y a personne en
/// face.
///
/// Le ton, les règles de conduite et les exemples de relance viennent de
/// `agents/agent-conversation.md`, qui est le contrat de cet agent.
public struct LocalMemoResponder: MemoResponder {

    /// Ce que le moteur fait d'un vocal qu'il ne peut pas écouter.
    public enum VoiceMode: Sendable, Hashable {
        /// La fiche ne porte **que du réel** : date d'enregistrement, durée,
        /// lieu, plus une ligne qui dit ce qui manque.
        ///
        /// C'est le défaut en release, et ce n'est pas un choix de confort :
        /// `agents/agent-transcription.md` interdit d'inventer un fait, et une
        /// fiche « Retranscription du contexte » remplie d'un texte que personne
        /// n'a écouté en est un — d'autant qu'il finirait imprimé.
        case unavailable

        /// La fiche porte un texte tiré d'une petite banque, choisi par la durée
        /// du vocal. Déterministe, et marqué ``TranscriptCard/isSimulated``.
        ///
        /// Réservé aux aperçus, aux captures de PR et au simulateur — d'où le
        /// défaut en debug seulement.
        case simulated

        /// Simulé en debug, honnête en release.
        public static var forCurrentBuild: VoiceMode {
            #if DEBUG
                .simulated
            #else
                .unavailable
            #endif
        }
    }

    private let voice: VoiceMode

    /// - Parameter voice: ce que le moteur fait d'un vocal. Par défaut
    ///   ``VoiceMode/simulated`` en debug et ``VoiceMode/unavailable`` en
    ///   release.
    public init(voice: VoiceMode = .forCurrentBuild) {
        self.voice = voice
    }

    // MARK: - L'ouverture

    public func opening(for context: ChatContext) -> MemoReply {
        // La maquette dessine cette bulle en entier : c'est elle, et pas une
        // paraphrase. Quand le voyage porte déjà une relance, elle vient
        // ensuite — les deux écrans doivent dire la même phrase.
        var beats = [
            beat(ChatCopy.opening, id: "memo-opening", pause: 700)
        ]

        if let prompt = context.prompt {
            beats.append(beat(prompt, id: "memo-opening-prompt", pause: pause(forSaying: prompt)))
        }

        return MemoReply(beats: beats, suggestions: Suggestions.opening)
    }

    // MARK: - Le tour de parole

    public func reply(to turn: ChatTurn) async throws -> MemoReply {
        switch turn.message.body {
        case .voice(let note):
            transcriptReply(to: note, turn: turn)
        case .text(let text):
            textReply(to: text, turn: turn)
        case .photos(let attachments):
            photosReply(to: attachments, turn: turn)
        case .transcript:
            // Une fiche est une bulle de MEMO : elle ne lui revient jamais comme
            // un tour de parole. Le cas existe pour que l'énumération reste
            // exhaustive, pas parce qu'il arrive.
            MemoReply(beats: [], suggestions: Suggestions.neutral)
        }
    }

    // MARK: - Un vocal : la fiche, puis la relance

    /// Deux temps, et non un seul : la fiche tombe d'abord, l'indicateur se
    /// rallume, puis MEMO demande quoi en faire. Un bloc unique qui arrive d'un
    /// coup ne ressemble à rien de vivant.
    private func transcriptReply(to note: VoiceNote, turn: ChatTurn) -> MemoReply {
        let text = simulatedTranscript(for: note, context: turn.context)

        let card = TranscriptCard(
            title: ChatCopy.transcriptTitle,
            capturedAt: turn.message.sentAt,
            placeLabel: turn.context.placeName,
            duration: note.duration,
            text: text,
            isSimulated: text != nil,
            entryId: nil,
            footnote: text == nil ? nil : ChatCopy.transcriptFootnote
        )

        let index = turn.history.count
        var beats = [
            MemoBeat(
                message: ChatMessage(
                    id: "memo-\(index)-transcript",
                    author: .memo,
                    body: .transcript(card),
                    sentAt: turn.message.sentAt
                ),
                pauseMilliseconds: min(4_000, 1_200 + Int(note.duration.rounded()) * 45)
            )
        ]

        let follow = text == nil ? ChatCopy.transcriptUnavailable : ChatCopy.afterTranscript
        beats.append(beat(follow, id: "memo-\(index)-after-transcript", pause: 900))

        return MemoReply(
            beats: beats,
            suggestions: text == nil ? Suggestions.withoutTranscript : Suggestions.trio,
            preview: preview(after: turn)
        )
    }

    /// Des photos : on accuse réception du **nombre**, et on demande ce qu'on y
    /// voit. MEMO ne les a pas regardées — décrire une image qu'on n'a pas vue
    /// serait exactement le fait inventé qu'interdit
    /// `agents/agent-transcription.md`.
    private func photosReply(to attachments: [PhotoAttachment], turn: ChatTurn) -> MemoReply {
        let text = ChatCopy.photosReceived(count: attachments.count)
        return MemoReply(
            beats: [
                beat(
                    text,
                    id: "memo-\(turn.history.count)-photos",
                    pause: min(2_600, 800 + attachments.count * 250)
                )
            ],
            suggestions: Suggestions.neutral,
            preview: preview(after: turn)
        )
    }

    /// Le texte de la fiche, ou `nil` quand le moteur refuse d'en inventer un.
    ///
    /// Le choix dans la banque est fait par la durée et le lieu : deux vocaux
    /// différents donnent deux récits différents, et le même vocal donne toujours
    /// le même — aucun aléatoire.
    private func simulatedTranscript(for note: VoiceNote, context: ChatContext) -> String? {
        guard voice == .simulated, !Self.transcriptBank.isEmpty else { return nil }
        let seed = Int(note.duration.rounded()) + (context.placeName?.count ?? 0)
        return Self.transcriptBank[abs(seed) % Self.transcriptBank.count]
    }

    // MARK: - Un texte : une famille, choisie par priorité

    private func textReply(to text: String, turn: ChatTurn) -> MemoReply {
        // Une puce de suggestion revient ici comme n'importe quel message : elle
        // a été postée en bulle bleue. On la reconnaît à son libellé exact —
        // c'est la même constante des deux côtés.
        if let scripted = Self.scriptedAnswers[text] {
            return MemoReply(
                beats: [
                    beat(
                        scripted.text,
                        id: "memo-\(turn.history.count)-scripted",
                        pause: pause(forReading: text)
                    )
                ],
                suggestions: scripted.suggestions,
                preview: preview(after: turn)
            )
        }

        let signals = ChatSignals.read(text)
        let alreadySaid = turn.thingsMemoAlreadySaid

        // Les candidats, dans l'ordre de priorité. Le premier qui n'a pas déjà
        // été dit gagne : c'est ça, et rien d'autre, l'anti-répétition.
        let candidates = self.candidates(for: signals, turn: turn)
        let chosen = candidates.first { !alreadySaid.contains($0.text) } ?? candidates[0]

        return MemoReply(
            beats: [
                beat(
                    chosen.text,
                    id: "memo-\(turn.history.count)-\(chosen.family)",
                    pause: pause(forReading: text)
                )
            ],
            suggestions: chosen.suggestions,
            preview: preview(after: turn)
        )
    }

    /// Un candidat de réponse : la phrase, la famille qui l'a produite, et les
    /// puces qui vont avec.
    private struct Candidate {
        let family: String
        let text: String
        let suggestions: [ChatSuggestion]
    }

    /// **La priorité.** C'est le cœur du moteur, et le seul endroit où l'ordre
    /// compte : chaque cran est là parce que l'ignorer produit une réponse à
    /// côté.
    private func candidates(for signals: ChatSignals, turn: ChatTurn) -> [Candidate] {
        var candidates: [Candidate] = []

        // 1. Le refus gagne sur tout. « Ne jamais insister » est la règle la plus
        //    dure du contrat de l'agent.
        if signals.isRefusal {
            return [Candidate(family: "refusal", text: ChatCopy.refusal, suggestions: Suggestions.afterRefusal)]
        }

        // 2. Une question obtient une réponse. Relancer par-dessus une question
        //    est le pire aveu : il prouve que rien n'a été lu.
        if signals.isQuestion {
            return [
                Candidate(
                    family: "answer",
                    text: Self.answer(for: signals.subject),
                    suggestions: Suggestions.afterAnswer
                )
            ]
        }

        // 3. Une émotion difficile s'accuse **avant** toute demande, et la
        //    demande reste optionnelle.
        if signals.mood == .negative {
            for (index, text) in ChatCopy.negativeMood.enumerated() {
                candidates.append(
                    Candidate(family: "negative-\(index)", text: text, suggestions: Suggestions.neutral)
                )
            }
        }

        // 4. Deux mots ne font pas une page : on demande **un** détail précis,
        //    pas « raconte-m'en plus ».
        if signals.length == .tooShort {
            for (index, text) in ChatCopy.tooShort.enumerated() {
                candidates.append(
                    Candidate(family: "short-\(index)", text: text, suggestions: Suggestions.neutral)
                )
            }
        }

        // 5. Le lieu ancre une page du carnet ; il passe avant la date, qui se
        //    déduit de l'horodatage du message.
        if signals.places.isEmpty, turn.context.placeName == nil {
            candidates.append(
                Candidate(family: "missing-place", text: ChatCopy.missingPlace, suggestions: Suggestions.neutral)
            )
        }

        // 6. Un lieu trouvé se répète **verbatim**. C'est l'écho que demande le
        //    contrat de l'agent, et le seul qui ne risque rien : un fragment
        //    reformulé de travers trahit plus vite que pas d'écho du tout.
        for place in signals.places {
            candidates.append(
                Candidate(family: "place", text: ChatCopy.foundPlace(place), suggestions: Suggestions.neutral)
            )
        }

        // 7. La date, une fois le lieu connu.
        if !signals.hasWhen, !signals.places.isEmpty || turn.context.placeName != nil {
            candidates.append(
                Candidate(family: "missing-date", text: ChatCopy.missingDate, suggestions: Suggestions.neutral)
            )
        }

        // 8. Un prénom qui apparaît pour la première fois : la fiche de
        //    cohérence du carnet en a besoin, et c'est vrai — donc on le demande.
        let known = Self.peopleAlreadyMentioned(in: turn)
        for name in signals.people {
            let text = known.contains(name) ? ChatCopy.knownPerson(name) : ChatCopy.newPerson(name)
            candidates.append(Candidate(family: "person", text: text, suggestions: Suggestions.neutral))
        }

        // 9. Un chiffre se recopie. Jamais converti, jamais additionné.
        for figure in signals.figures {
            candidates.append(
                Candidate(family: "figure", text: ChatCopy.figure(figure), suggestions: Suggestions.neutral)
            )
        }

        // 10. Un message très long n'appelle pas plus de matière, mais un
        //     découpage.
        if signals.length == .long {
            candidates.append(
                Candidate(family: "long", text: ChatCopy.longMessage, suggestions: Suggestions.split)
            )
        }

        // 11. Une émotion heureuse s'amplifie, et on demande le détail qui
        //     rendra bien à l'impression.
        if signals.mood == .positive {
            candidates.append(
                Candidate(family: "positive", text: ChatCopy.positiveMood, suggestions: Suggestions.neutral)
            )
        }

        // 12. Rien de saillant : la rotation neutre. Elle **démarre** à un rang
        //     qui dépend du nombre de bulles déjà posées, pour que deux tours
        //     ternes de suite ne posent pas la même question.
        let offset = turn.history.count
        for step in 0..<ChatCopy.rotation.count {
            let text = ChatCopy.rotation[(offset + step) % ChatCopy.rotation.count]
            candidates.append(
                Candidate(family: "rotation-\(step)", text: text, suggestions: Suggestions.neutral)
            )
        }

        return candidates
    }

    // MARK: - Le rythme

    /// La pause avant la première bulle : le temps de **lire** ce qu'on vient de
    /// recevoir.
    private func pause(forReading message: String) -> Int {
        min(2_600, 900 + message.count * 22)
    }

    /// La pause avant une bulle que MEMO **écrit** : plus sa phrase est longue,
    /// plus elle met de temps à venir.
    private func pause(forSaying text: String) -> Int {
        min(1_800, 700 + text.count * 14)
    }

    private func beat(_ text: String, id: String, pause: Int) -> MemoBeat {
        // `sentAt` reste celui du répondeur distant le jour venu ; ici c'est le
        // modèle qui l'horodate en posant la bulle, parce qu'un moteur
        // déterministe n'a pas le droit de lire l'horloge.
        MemoBeat(
            message: ChatMessage(id: id, author: .memo, body: .text(text), sentAt: .distantPast),
            pauseMilliseconds: pause
        )
    }

    // MARK: - La bannière

    /// Les compteurs de l'aperçu.
    ///
    /// ⚠️ **Le nombre de pages est déduit, pas mesuré.** Le serveur ne le rend
    /// pas : `serializeRender` retient volontairement le payload de mise en
    /// page. Deux pages par souvenir est la moyenne des gabarits — c'est un
    /// ordre de grandeur honnête, et c'est signalé dans la fiche écran.
    private func preview(after turn: ChatTurn) -> ChatBookPreview {
        let memories = turn.history.filter { $0.author.isTraveller }.count + 1
        return ChatBookPreview(memoryCount: memories, pageCount: memories * 2)
    }

    // MARK: - Les réponses écrites d'avance

    /// Ce que MEMO répond à ses propres puces. Le libellé est la clé : c'est la
    /// même constante que celle affichée, donc rien à synchroniser à la main.
    private static let scriptedAnswers: [String: (text: String, suggestions: [ChatSuggestion])] = [
        ChatCopy.Suggest.accept: (ChatCopy.acknowledged, Suggestions.afterAccept),
        ChatCopy.Suggest.editByHand: (ChatCopy.handingOver, []),
        ChatCopy.Suggest.rewrite: (ChatCopy.handingOver, []),
        ChatCopy.Suggest.editByVoice: (ChatCopy.listening, []),
        ChatCopy.Suggest.recordAgain: (ChatCopy.listening, []),
        ChatCopy.Suggest.preferWriting: (ChatCopy.handingOver, []),
        ChatCopy.Suggest.tellByVoice: (ChatCopy.listening, []),
        ChatCopy.Suggest.later: (ChatCopy.refusal, Suggestions.afterRefusal),
        ChatCopy.Suggest.tomorrow: (ChatCopy.refusal, Suggestions.afterRefusal),
        // Pas `Suggestions.opening` : reproposer « Commencer mon carnet » à
        // quelqu'un qui vient de commencer son carnet est le genre de détail
        // qui dit qu'il n'y a personne en face.
        ChatCopy.Suggest.start: (ChatCopy.openingWithoutPrompt, Suggestions.afterAccept),
        ChatCopy.Suggest.dictate: (ChatCopy.listening, []),
    ]

    private static func answer(for subject: ChatSignals.Subject?) -> String {
        switch subject {
        case .book: ChatCopy.Answer.book
        case .subscription: ChatCopy.Answer.subscription
        case .photos: ChatCopy.Answer.photos
        case .corrections: ChatCopy.Answer.corrections
        case .pace: ChatCopy.Answer.pace
        case nil: ChatCopy.Answer.unknown
        }
    }

    /// Les prénoms déjà passés dans le fil. C'est ce qui fait la différence entre
    /// « qui est-ce ? » et « et Camille ? ».
    private static func peopleAlreadyMentioned(in turn: ChatTurn) -> Set<String> {
        var names: Set<String> = []
        for message in turn.history where message.author.isTraveller {
            if case .text(let text) = message.body {
                names.formUnion(ChatSignals.read(text).people)
            }
        }
        return names
    }

    // MARK: - La banque de vocaux simulés
    //
    // Écrits dans le **registre oral** d'une transcription brute — hésitations
    // comprises —, comme le jeu d'essai de `PreviewAPI` le fait déjà. Quatre
    // entrées qui couvrent les quatre familles d'analyse : un lieu et une
    // émotion heureuse, une journée sans date, une journée difficile, et un
    // prénom accompagné d'un chiffre. Une démonstration montre donc quatre
    // relances différentes sans une ligne d'aléatoire.

    private static let transcriptBank = [
        """
        alors ce matin on est partis tôt pour éviter la chaleur, euh on a marché \
        jusqu’au marché et là on a pris un café debout au comptoir comme tout le \
        monde, c’était le meilleur moment de la journée franchement
        """,
        """
        bon là on vient de rentrer, on a fait le tour du quartier à pied, il y \
        avait une fête dans la rue avec de la musique jusqu’à tard, du coup on a \
        mangé sur le pouce et on a regardé les gens danser
        """,
        """
        journée compliquée, euh le train avait deux heures de retard et on a raté \
        la visite qu’on avait réservée, enfin on a fini par trouver une terrasse \
        et ça s’est arrangé
        """,
        """
        ce soir on est montés voir le coucher de soleil depuis les hauteurs, il y \
        avait un vent fou mais la vue valait le coup, Camille a pris une \
        cinquantaine de photos
        """,
    ]

    // MARK: - Les jeux de suggestions
    //
    // Un jeu par famille de réponse. Le trio de validation de la maquette ne
    // suit qu'une fiche qui porte du **vrai** texte : trois puces « Ça me
    // convient / à la main / à l'oral » sous une question ouverte ne répondent à
    // rien, et ça se voit immédiatement.

    private enum Suggestions {
        static let trio = [
            ChatSuggestion(id: "accept", label: ChatCopy.Suggest.accept, intent: .send),
            ChatSuggestion(id: "edit-hand", label: ChatCopy.Suggest.editByHand, intent: .sendThenWrite),
            ChatSuggestion(id: "edit-voice", label: ChatCopy.Suggest.editByVoice, intent: .sendThenSpeak),
        ]

        static let withoutTranscript = [
            ChatSuggestion(id: "rewrite", label: ChatCopy.Suggest.rewrite, intent: .sendThenWrite),
            ChatSuggestion(id: "record-again", label: ChatCopy.Suggest.recordAgain, intent: .sendThenSpeak),
            ChatSuggestion(id: "later", label: ChatCopy.Suggest.later, intent: .send),
        ]

        static let opening = [
            ChatSuggestion(
                id: "start",
                label: ChatCopy.Suggest.start,
                symbol: ChatCopy.Suggest.startSymbol,
                intent: .sendThenSpeak
            ),
            ChatSuggestion(
                id: "photos",
                label: ChatCopy.Suggest.importPhotos,
                symbol: ChatCopy.Suggest.importPhotosSymbol,
                intent: .importPhotos
            ),
            ChatSuggestion(
                id: "dictate",
                label: ChatCopy.Suggest.dictate,
                symbol: ChatCopy.Suggest.dictateSymbol,
                intent: .sendThenSpeak
            ),
        ]

        static let neutral = [
            ChatSuggestion(id: "voice", label: ChatCopy.Suggest.tellByVoice, intent: .sendThenSpeak),
            ChatSuggestion(id: "write", label: ChatCopy.Suggest.preferWriting, intent: .sendThenWrite),
            ChatSuggestion(id: "later", label: ChatCopy.Suggest.later, intent: .send),
        ]

        static let afterAnswer = [
            ChatSuggestion(id: "clear", label: ChatCopy.Suggest.clear, intent: .send),
            ChatSuggestion(id: "another", label: ChatCopy.Suggest.anotherQuestion, intent: .sendThenWrite),
            ChatSuggestion(id: "resume", label: ChatCopy.Suggest.resume, intent: .sendThenSpeak),
        ]

        static let afterRefusal = [
            ChatSuggestion(id: "tomorrow", label: ChatCopy.Suggest.tomorrow, intent: .send),
            ChatSuggestion(id: "else", label: ChatCopy.Suggest.somethingElse, intent: .sendThenSpeak),
        ]

        static let afterAccept = [
            ChatSuggestion(
                id: "dictate",
                label: ChatCopy.Suggest.dictate,
                symbol: ChatCopy.Suggest.dictateSymbol,
                intent: .sendThenSpeak
            ),
            ChatSuggestion(
                id: "photos",
                label: ChatCopy.Suggest.importPhotos,
                symbol: ChatCopy.Suggest.importPhotosSymbol,
                intent: .importPhotos
            ),
            ChatSuggestion(id: "later", label: ChatCopy.Suggest.later, intent: .send),
        ]

        static let split = [
            ChatSuggestion(id: "split", label: ChatCopy.Suggest.splitInTwo, intent: .send),
            ChatSuggestion(id: "keep", label: ChatCopy.Suggest.keepAsOne, intent: .send),
        ]
    }
}
