import Foundation
import MemoBookCore
import MemoBookDesign

// Jeu d'essai du chat — **temporaire**, comme celui de l'accueil, du profil et
// de l'accueil d'un voyage.
//
// L'écran est entièrement piloté par ces données : pas un titre, pas une date,
// pas une bulle n'est écrite dans une vue. Le jour où `GET /v1/trips/:id/chat`
// existe, ce fichier disparaît et rien d'autre ne bouge.
//
// Le voyage est **repris de l'accueil**, par `TripDetail.fixture(id:)` : ouvrir
// une étape doit mener à ce qu'elle montrait, et le chat doit s'ouvrir sur la
// même relance que l'écran du voyage. C'est la même règle qui a fait que
// l'accueil d'un voyage ne réinvente pas son voyage.

extension ChatThread {
    /// **Une** conversation par voyage.
    ///
    /// Et non une par étape : un carnet se relit d'un bout à l'autre, et couper
    /// le récit en autant de fils que d'étapes obligerait à changer de fil pour
    /// relire la veille. Ce sont les messages qui portent leur étape — voir
    /// ``ChatMessage/stepId`` —, ce qui permet quand même d'ouvrir le fil **sur**
    /// une journée.
    ///
    /// Le fil arrive avec ce qui a déjà été raconté : une journée par étape
    /// terminée. Sans cet historique, ouvrir une étape depuis sa carte tombait
    /// sur une conversation vide, et « montre-moi où j'en étais » n'avait rien à
    /// montrer.
    public static func fixture(tripId: String) -> ChatThread {
        let detail = TripDetail.fixture(id: tripId)
        let current = detail.steps.last

        var thread = ChatThread(
            id: tripId,
            title: detail.trip.title,
            avatarUrl: detail.trip.coverPhotoUrl,
            destination: detail.trip.destination,
            greeting: greeting(for: detail.trip.destination),
            preview: preview(for: detail.trip),
            context: ChatContext(
                tripId: tripId,
                tripTitle: detail.trip.title,
                travellerFirstName: HomeFeed.fixture.traveller.firstName,
                placeName: current?.placeName,
                stepNumber: current?.number,
                stepId: current?.id,
                prompt: detail.prompt
            )
        )

        thread.messages = history(of: detail)
        thread.suggestions = thread.messages.isEmpty ? [] : openQuestionTrio
        return thread
    }

    /// La même conversation. Le nom reste, employé par les aperçus.
    public static func conversationFixture(tripId: String) -> ChatThread {
        fixture(tripId: tripId)
    }

    // MARK: - Ce qui a déjà été raconté

    /// Une journée par étape : un vocal, la fiche que MEMO en a tirée, sa
    /// relance, et la validation du voyageur.
    ///
    /// Les dates sont **figées** (`Date.fixture`) : un écran qui change de texte
    /// selon le jour n'est plus comparable à la maquette.
    private static func history(of detail: TripDetail) -> [ChatMessage] {
        guard !detail.steps.isEmpty else { return [] }
        let fallbackDay = Date.fixture(26, 8, 2026)

        var messages: [ChatMessage] = [
            ChatMessage(
                id: "memo-opening",
                author: .memo,
                body: .text(ChatCopy.opening),
                sentAt: detail.steps[0].startDate ?? fallbackDay
            )
        ]

        // La dernière étape est celle qu'on est en train de vivre : elle n'a pas
        // encore été racontée, et c'est justement sur elle que le fil s'ouvre.
        for (index, step) in detail.steps.dropLast().enumerated() {
            let day = step.startDate ?? fallbackDay
            let note = VoiceNote(
                id: "voice-\(step.id)",
                duration: 37 + Double(index) * 11,
                levels: BrandWaveform.sampleLevels
            )

            messages.append(
                ChatMessage(
                    id: "voice-\(step.id)",
                    author: .traveller,
                    body: .voice(note),
                    sentAt: day,
                    stepId: step.id
                )
            )
            messages.append(
                ChatMessage(
                    id: "memo-\(step.id)-transcript",
                    author: .memo,
                    body: .transcript(
                        TranscriptCard(
                            title: ChatCopy.transcriptTitle,
                            capturedAt: day,
                            placeLabel: step.placeName,
                            duration: note.duration,
                            text: transcripts[index % transcripts.count],
                            isSimulated: true,
                            footnote: ChatCopy.transcriptFootnote
                        )
                    ),
                    sentAt: day,
                    stepId: step.id
                )
            )
            messages.append(
                ChatMessage(
                    id: "memo-\(step.id)-after",
                    author: .memo,
                    body: .text(ChatCopy.afterTranscript),
                    sentAt: day,
                    stepId: step.id
                )
            )
            messages.append(
                ChatMessage(
                    id: "traveller-\(step.id)-accept",
                    author: .traveller,
                    body: .text(ChatCopy.Suggest.accept),
                    sentAt: day,
                    stepId: step.id
                )
            )
            messages.append(
                ChatMessage(
                    id: "memo-\(step.id)-acknowledged",
                    author: .memo,
                    body: .text(ChatCopy.acknowledged),
                    sentAt: day,
                    stepId: step.id
                )
            )
        }

        // Et la relance du jour, posée sur l'étape en cours.
        if let current = detail.steps.last, let prompt = detail.prompt {
            messages.append(
                ChatMessage(
                    id: "memo-current-prompt",
                    author: .memo,
                    body: .text(prompt),
                    sentAt: current.startDate ?? fallbackDay,
                    stepId: current.id
                )
            )
        }

        return messages
    }

    /// Ce que MEMO propose sous une question ouverte. **Pas** le trio de
    /// validation : celui-là ne suit qu'une fiche qui porte du vrai texte.
    private static let openQuestionTrio = [
        ChatSuggestion(id: "voice", label: ChatCopy.Suggest.tellByVoice, intent: .sendThenSpeak),
        ChatSuggestion(id: "write", label: ChatCopy.Suggest.preferWriting, intent: .sendThenWrite),
        ChatSuggestion(id: "later", label: ChatCopy.Suggest.later, intent: .send),
    ]

    /// L'accueil nomme **la ville du voyage**.
    ///
    /// C'est ce que la maquette écrit — « Nouveau voyage à Rome ! » —, et c'est
    /// désormais une donnée : ``Destination/city``, ajoutée au modèle et à la
    /// base pour ça (D10). Le pays donnerait « à Italie », qui n'est pas du
    /// français. Sans ville — un tour du monde —, la phrase se replie.
    private static func greeting(for destination: Destination?) -> ChatGreeting {
        ChatGreeting(
            title: destination?.city
                .map { ChatCopy.greetingTitle(place: $0, flag: destination?.flag) }
                ?? ChatCopy.greetingTitleWithoutPlace,
            message: ChatCopy.greetingMessage
        )
    }

    /// Les compteurs de la bannière, tirés de l'avancement du carnet que
    /// l'accueil affiche déjà. Un voyage à venir n'a rien à montrer : la
    /// bannière disparaît plutôt que d'annoncer zéro.
    private static func preview(for trip: Trip) -> ChatBookPreview? {
        guard let progress = trip.progress else { return nil }
        return ChatBookPreview(
            memoryCount: progress.memoryCount,
            pageCount: progress.pageCount,
            isOpenable: trip.isPrintable || progress.pageCount > 0
        )
    }

    /// Les récits déjà retranscrits, dans le registre oral d'une transcription
    /// brute. Le premier est celui de la maquette, au caractère près.
    private static let transcripts = [
        """
        Ce voyage commence bien avant le décollage. Depuis plusieurs semaines, \
        l’idée de partir à Lisbonne tourne en boucle dans ma tête.
        Une envie simple : changer d’air, couper avec le rythme habituel, et me \
        retrouver ailleurs, dans une ville que je ne connais pas encore vraiment.
        """,
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
    ]
}
