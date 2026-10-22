package com.memobook.core

import java.time.Instant
import kotlin.math.abs

/**
 * MEMO, tant que le back-end n'a pas d'agent de conversation. Le jumeau de
 * `MemoBookCore/LocalMemoResponder.swift`.
 *
 * **Une priorité stricte, pas une addition de scores.** Les signaux relevés par
 * [ChatSignals] ne se cumulent pas : le premier qui se déclenche choisit la
 * famille de réponse, et les suivants sont ignorés. C'est ce qui distingue un
 * moteur qui écoute d'un tirage au sort — un refus ne reçoit jamais une
 * question, et une question ne reçoit jamais une relance.
 *
 * **Aucun état mutable, aucun aléatoire, aucune horloge.** La mémoire du moteur
 * est [ChatTurn.history] : avant d'émettre, il écarte toute phrase déjà dite
 * dans le fil et descend d'un cran plutôt que de se répéter. Il reste donc une
 * valeur déterministe — le même tour rend toujours la même réponse, ce qui le
 * rend testable ligne à ligne.
 *
 * **Le rythme est une donnée.** [MemoBeat.pauseMilliseconds] se calcule sur la
 * matière du message : plus il y a à lire, plus MEMO met de temps à répondre.
 * Une latence nulle, ou constante, est le premier signe qu'il n'y a personne en
 * face.
 *
 * Le ton, les règles de conduite et les exemples de relance viennent de
 * `agents/agent-conversation.md`, qui est le contrat de cet agent.
 *
 * @param voice ce que le moteur fait d'un vocal. Par défaut
 *   [VoiceMode.forCurrentBuild].
 */
class LocalMemoResponder(private val voice: VoiceMode = VoiceMode.forCurrentBuild) : MemoResponder {

    /** Ce que le moteur fait d'un vocal qu'il ne peut pas écouter. */
    enum class VoiceMode {
        /**
         * La fiche ne porte **que du réel** : date d'enregistrement, durée,
         * lieu, plus une ligne qui dit ce qui manque.
         *
         * C'est le défaut en release, et ce n'est pas un choix de confort :
         * `agents/agent-transcription.md` interdit d'inventer un fait, et une
         * fiche « Retranscription du contexte » remplie d'un texte que personne
         * n'a écouté en est un — d'autant qu'il finirait imprimé.
         */
        Unavailable,

        /**
         * La fiche porte un texte tiré d'une petite banque, choisi par la durée
         * du vocal. Déterministe, et marqué [TranscriptCard.isSimulated].
         *
         * Réservé aux aperçus, aux captures de PR et à l'émulateur — d'où le
         * défaut en debug seulement.
         */
        Simulated,
        ;

        companion object {
            /** Simulé en debug, honnête en release. */
            fun forBuild(isDebug: Boolean): VoiceMode = if (isDebug) Simulated else Unavailable

            /**
             * Le `#if DEBUG` d'iOS. `:core` est une bibliothèque JVM sans
             * `BuildConfig` : elle ne sait pas dans quel build elle tourne, et
             * prend donc le parti honnête. L'app, qui le sait, passe
             * `forBuild(BuildConfig.DEBUG)`.
             */
            val forCurrentBuild: VoiceMode get() = Unavailable
        }
    }

    // MARK: - L'ouverture

    override fun opening(context: ChatContext): MemoReply {
        // La maquette dessine cette bulle en entier : c'est elle, et pas une
        // paraphrase. **Et elle seule** : elle se termine déjà sur une
        // question — le contexte du voyage —, et rien ne doit venir la
        // recouvrir. La relance du voyage (« Comment ça se passe à
        // Testaccio ? ») n'est pas une bulle : c'est ce que l'accueil du voyage
        // affiche, et ce qu'une notification rappellera à qui n'a pas raconté
        // sa journée (Hugo, 17/09/2026).
        return MemoReply(
            beats = listOf(beat(ChatCopy.opening, id = "memo-opening", pause = 700)),
            suggestions = Suggestions.opening,
        )
    }

    // MARK: - Le tour de parole

    override suspend fun reply(turn: ChatTurn): MemoReply =
        when (val body = turn.message.body) {
            is ChatMessageBody.Voice -> transcriptReply(body.note, turn)
            is ChatMessageBody.Text -> textReply(body.value, turn)
            is ChatMessageBody.Photos -> photosReply(body.attachments, turn)
            // Une fiche est une bulle de MEMO : elle ne lui revient jamais comme
            // un tour de parole. Le cas existe pour que l'énumération reste
            // exhaustive, pas parce qu'il arrive.
            is ChatMessageBody.Transcript -> MemoReply(beats = emptyList(), suggestions = Suggestions.neutral)
        }

    // MARK: - Un vocal : la fiche, puis la relance

    /**
     * Deux temps, et non un seul : la fiche tombe d'abord, l'indicateur se
     * rallume, puis MEMO demande quoi en faire. Un bloc unique qui arrive d'un
     * coup ne ressemble à rien de vivant.
     */
    private fun transcriptReply(note: VoiceNote, turn: ChatTurn): MemoReply {
        val text = simulatedTranscript(note, turn.context)

        val card = TranscriptCard(
            title = ChatCopy.transcriptTitle,
            capturedAt = turn.message.sentAt,
            placeLabel = turn.context.placeName,
            duration = note.duration,
            text = text,
            isSimulated = text != null,
            entryId = null,
            footnote = if (text == null) null else ChatCopy.transcriptFootnote,
        )

        val index = turn.history.size
        val beats = mutableListOf(
            MemoBeat(
                message = ChatMessage(
                    id = "memo-$index-transcript",
                    author = ChatAuthor.Memo,
                    body = ChatMessageBody.Transcript(card),
                    sentAt = turn.message.sentAt,
                ),
                pauseMilliseconds = minOf(4_000, 1_200 + rounded(note.duration) * 45),
            ),
        )

        val follow = if (text == null) ChatCopy.transcriptUnavailable else ChatCopy.afterTranscript
        beats.add(beat(follow, id = "memo-$index-after-transcript", pause = 900))

        return MemoReply(
            beats = beats,
            suggestions = if (text == null) Suggestions.withoutTranscript else Suggestions.trio,
            preview = preview(turn),
        )
    }

    /**
     * Des photos : on accuse réception du **nombre**, et on demande ce qu'on y
     * voit. MEMO ne les a pas regardées — décrire une image qu'on n'a pas vue
     * serait exactement le fait inventé qu'interdit
     * `agents/agent-transcription.md`.
     */
    private fun photosReply(attachments: List<PhotoAttachment>, turn: ChatTurn): MemoReply {
        val text = ChatCopy.photosReceived(count = attachments.size)
        return MemoReply(
            beats = listOf(
                beat(
                    text,
                    id = "memo-${turn.history.size}-photos",
                    pause = minOf(2_600, 800 + attachments.size * 250),
                ),
            ),
            suggestions = Suggestions.neutral,
            preview = preview(turn),
        )
    }

    /**
     * Le texte de la fiche, ou `null` quand le moteur refuse d'en inventer un.
     *
     * Le choix dans la banque est fait par la durée et le lieu : deux vocaux
     * différents donnent deux récits différents, et le même vocal donne toujours
     * le même — aucun aléatoire.
     */
    private fun simulatedTranscript(note: VoiceNote, context: ChatContext): String? {
        if (voice != VoiceMode.Simulated || transcriptBank.isEmpty()) return null
        val seed = rounded(note.duration) + (context.placeName?.let(ChatGraphemes::count) ?: 0)
        return transcriptBank[abs(seed) % transcriptBank.size]
    }

    // MARK: - Un texte : une famille, choisie par priorité

    private fun textReply(text: String, turn: ChatTurn): MemoReply {
        // Une puce de suggestion revient ici comme n'importe quel message : elle
        // a été postée en bulle bleue. On la reconnaît à son libellé exact —
        // c'est la même constante des deux côtés.
        val scripted = scriptedAnswers[text]
        if (scripted != null) {
            return MemoReply(
                beats = listOf(
                    beat(
                        scripted.first,
                        id = "memo-${turn.history.size}-scripted",
                        pause = pauseForReading(text),
                    ),
                ),
                suggestions = scripted.second,
                preview = preview(turn),
            )
        }

        val signals = ChatSignals.read(text)
        val alreadySaid = turn.thingsMemoAlreadySaid

        // Les candidats, dans l'ordre de priorité. Le premier qui n'a pas déjà
        // été dit gagne : c'est ça, et rien d'autre, l'anti-répétition.
        val candidates = candidates(signals, turn)
        val chosen = candidates.firstOrNull { it.text !in alreadySaid } ?: candidates[0]

        return MemoReply(
            beats = listOf(
                beat(
                    chosen.text,
                    id = "memo-${turn.history.size}-${chosen.family}",
                    pause = pauseForReading(text),
                    callToAction = chosen.callToAction,
                ),
            ),
            suggestions = chosen.suggestions,
            preview = preview(turn),
        )
    }

    /**
     * Un candidat de réponse : la phrase, la famille qui l'a produite, et les
     * puces qui vont avec.
     */
    private data class Candidate(
        val family: String,
        val text: String,
        val suggestions: List<ChatSuggestion>,
        /**
         * Le bouton sous la bulle — [ChatCallToAction]. `null` presque
         * toujours : un bouton se mérite.
         */
        val callToAction: ChatCallToAction? = null,
    )

    /**
     * **La priorité.** C'est le cœur du moteur, et le seul endroit où l'ordre
     * compte : chaque cran est là parce que l'ignorer produit une réponse à
     * côté.
     */
    private fun candidates(signals: ChatSignals, turn: ChatTurn): List<Candidate> {
        val candidates = mutableListOf<Candidate>()

        // 1. Le refus gagne sur tout. « Ne jamais insister » est la règle la plus
        //    dure du contrat de l'agent.
        if (signals.isRefusal) {
            return listOf(Candidate(family = "refusal", text = ChatCopy.refusal, suggestions = Suggestions.afterRefusal))
        }

        // 2. Une question obtient une réponse. Relancer par-dessus une question
        //    est le pire aveu : il prouve que rien n'a été lu.
        if (signals.isQuestion) {
            return listOf(
                Candidate(
                    family = "answer",
                    text = answer(signals.subject),
                    suggestions = Suggestions.afterAnswer,
                    callToAction = if (signals.subject == ChatSignals.Subject.Subscription) subscribeCallToAction else null,
                ),
            )
        }

        // 3. Une émotion difficile s'accuse **avant** toute demande, et la
        //    demande reste optionnelle.
        if (signals.mood == ChatSignals.Mood.Negative) {
            for ((index, text) in ChatCopy.negativeMood.withIndex()) {
                candidates.add(Candidate(family = "negative-$index", text = text, suggestions = Suggestions.neutral))
            }
        }

        // 4. Deux mots ne font pas une page — et MEMO **le dit** (Hugo,
        //    08/10/2026) au lieu d'enchaîner sur un lieu ou une date qu'il
        //    aurait supposés : rien ne vient après.
        if (signals.length == ChatSignals.Length.TooShort) {
            return ChatCopy.tooShort(turn.message.spokenText ?: "").mapIndexed { index, text ->
                Candidate(family = "short-$index", text = text, suggestions = Suggestions.neutral)
            }
        }

        // 5. Le lieu ancre une page du carnet ; il passe avant la date, qui se
        //    déduit de l'horodatage du message.
        if (signals.places.isEmpty() && turn.context.placeName == null) {
            candidates.add(
                Candidate(family = "missing-place", text = ChatCopy.missingPlace, suggestions = Suggestions.neutral),
            )
        }

        // 6. Un lieu trouvé se répète **verbatim**. C'est l'écho que demande le
        //    contrat de l'agent, et le seul qui ne risque rien : un fragment
        //    reformulé de travers trahit plus vite que pas d'écho du tout.
        for (place in signals.places) {
            candidates.add(
                Candidate(family = "place", text = ChatCopy.foundPlace(place), suggestions = Suggestions.neutral),
            )
        }

        // 7. La date, une fois le lieu connu.
        if (!signals.hasWhen && (signals.places.isNotEmpty() || turn.context.placeName != null)) {
            candidates.add(
                Candidate(family = "missing-date", text = ChatCopy.missingDate, suggestions = Suggestions.neutral),
            )
        }

        // 8. Un prénom qui apparaît pour la première fois : la fiche de
        //    cohérence du carnet en a besoin, et c'est vrai — donc on le demande.
        val known = peopleAlreadyMentioned(turn)
        for (name in signals.people) {
            val text = if (name in known) ChatCopy.knownPerson(name) else ChatCopy.newPerson(name)
            candidates.add(Candidate(family = "person", text = text, suggestions = Suggestions.neutral))
        }

        // 9. Un chiffre se recopie. Jamais converti, jamais additionné.
        for (figure in signals.figures) {
            candidates.add(
                Candidate(family = "figure", text = ChatCopy.figure(figure), suggestions = Suggestions.neutral),
            )
        }

        // 10. Un message très long n'appelle pas plus de matière, mais un
        //     découpage.
        if (signals.length == ChatSignals.Length.Long) {
            candidates.add(Candidate(family = "long", text = ChatCopy.longMessage, suggestions = Suggestions.split))
        }

        // 11. Une émotion heureuse s'amplifie, et on demande le détail qui
        //     rendra bien à l'impression.
        if (signals.mood == ChatSignals.Mood.Positive) {
            candidates.add(
                Candidate(family = "positive", text = ChatCopy.positiveMood, suggestions = Suggestions.neutral),
            )
        }

        // 12. Rien de saillant : la rotation neutre. Elle **démarre** à un rang
        //     qui dépend du nombre de bulles déjà posées, pour que deux tours
        //     ternes de suite ne posent pas la même question.
        val offset = turn.history.size
        for (step in ChatCopy.rotation.indices) {
            val text = ChatCopy.rotation[(offset + step) % ChatCopy.rotation.size]
            candidates.add(Candidate(family = "rotation-$step", text = text, suggestions = Suggestions.neutral))
        }

        return candidates
    }

    // MARK: - Le rythme

    /**
     * La pause avant la première bulle : le temps de **lire** ce qu'on vient de
     * recevoir.
     */
    private fun pauseForReading(message: String): Int = minOf(2_600, 900 + ChatGraphemes.count(message) * 22)

    /**
     * La pause avant une bulle que MEMO **écrit** : plus sa phrase est longue,
     * plus elle met de temps à venir.
     */
    @Suppress("unused")
    private fun pauseForSaying(text: String): Int = minOf(1_800, 700 + ChatGraphemes.count(text) * 14)

    private fun beat(
        text: String,
        id: String,
        pause: Int,
        callToAction: ChatCallToAction? = null,
    ): MemoBeat =
        // `sentAt` reste celui du répondeur distant le jour venu ; ici c'est le
        // modèle qui l'horodate en posant la bulle, parce qu'un moteur
        // déterministe n'a pas le droit de lire l'horloge.
        MemoBeat(
            message = ChatMessage(
                id = id,
                author = ChatAuthor.Memo,
                body = ChatMessageBody.Text(text),
                sentAt = distantPast,
                callToAction = callToAction,
            ),
            pauseMilliseconds = pause,
        )

    // MARK: - La bannière

    /**
     * Les compteurs de l'aperçu.
     *
     * ⚠️ **Le nombre de pages est déduit, pas mesuré.** Le serveur ne le rend
     * pas : `serializeRender` retient volontairement le payload de mise en
     * page. Deux pages par souvenir est la moyenne des gabarits — c'est un
     * ordre de grandeur honnête, et c'est signalé dans la fiche écran.
     */
    private fun preview(turn: ChatTurn): ChatBookPreview {
        val memories = turn.history.count { it.author.isTraveller } + 1
        return ChatBookPreview(memoryCount = memories, pageCount = memories * 2)
    }

    companion object {
        /**
         * Le `Date.distantPast` de Swift — le 1er janvier de l'an 1, UTC —,
         * l'horodatage d'une bulle que le moteur pose sans lire l'horloge.
         */
        internal val distantPast: Instant = Instant.parse("0001-01-01T00:00:00Z")

        /** `Double.rounded()` de Swift : au plus proche, la moitié loin de zéro. */
        private fun rounded(value: Double): Int =
            (if (value < 0) -Math.round(-value) else Math.round(value)).toInt()

        /**
         * Le bouton que le serveur pose sous la réponse à une question de prix
         * ou de limite (`subscribe`, `services/callsToAction.ts`) — recopié pour
         * que l'aperçu montre la même carte. Le serveur le tait à un abonné ; le
         * moteur local, qui ne sait pas qui lit, le pose toujours.
         */
        internal val subscribeCallToAction = ChatCallToAction(
            id = "subscribe",
            kind = ChatCallToAction.Kind.Subscribe,
            label = "Découvrir l’abonnement",
            eyebrow = "Raconter sans limite",
        )

        // MARK: - Les réponses écrites d'avance

        /**
         * Ce que MEMO répond à ses propres puces. Le libellé est la clé : c'est la
         * même constante que celle affichée, donc rien à synchroniser à la main.
         */
        private val scriptedAnswers: Map<String, Pair<String, List<ChatSuggestion>>> by lazy {
            mapOf(
                ChatCopy.Suggest.accept to (ChatCopy.acknowledged to Suggestions.afterAccept),
                ChatCopy.Suggest.editByHand to (ChatCopy.handingOver to emptyList()),
                ChatCopy.Suggest.rewrite to (ChatCopy.handingOver to emptyList()),
                ChatCopy.Suggest.editByVoice to (ChatCopy.listening to emptyList()),
                ChatCopy.Suggest.recordAgain to (ChatCopy.listening to emptyList()),
                ChatCopy.Suggest.preferWriting to (ChatCopy.handingOver to emptyList()),
                ChatCopy.Suggest.tellByVoice to (ChatCopy.listening to emptyList()),
                ChatCopy.Suggest.later to (ChatCopy.refusal to Suggestions.afterRefusal),
                ChatCopy.Suggest.tomorrow to (ChatCopy.refusal to Suggestions.afterRefusal),
                // Pas `Suggestions.opening` : reproposer « Commencer mon carnet » à
                // quelqu'un qui vient de commencer son carnet est le genre de détail
                // qui dit qu'il n'y a personne en face.
                ChatCopy.Suggest.start to (ChatCopy.openingWithoutPrompt to Suggestions.afterAccept),
                ChatCopy.Suggest.dictate to (ChatCopy.listening to emptyList()),
                ChatCopy.Suggest.tellContext to (ChatCopy.contextInvitation to emptyList()),
            )
        }

        private fun answer(subject: ChatSignals.Subject?): String = when (subject) {
            ChatSignals.Subject.Book -> ChatCopy.Answer.book
            ChatSignals.Subject.Subscription -> ChatCopy.Answer.subscription
            ChatSignals.Subject.Photos -> ChatCopy.Answer.photos
            ChatSignals.Subject.Corrections -> ChatCopy.Answer.corrections
            ChatSignals.Subject.Pace -> ChatCopy.Answer.pace
            null -> ChatCopy.Answer.unknown
        }

        /**
         * Les prénoms déjà passés dans le fil. C'est ce qui fait la différence entre
         * « qui est-ce ? » et « et Camille ? ».
         */
        private fun peopleAlreadyMentioned(turn: ChatTurn): Set<String> {
            val names = mutableSetOf<String>()
            for (message in turn.history) {
                if (!message.author.isTraveller) continue
                val body = message.body
                if (body is ChatMessageBody.Text) names.addAll(ChatSignals.read(body.value).people)
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

        private val transcriptBank: List<String> = listOf(
            "alors ce matin on est partis tôt pour éviter la chaleur, euh on a marché " +
                "jusqu’au marché et là on a pris un café debout au comptoir comme tout le " +
                "monde, c’était le meilleur moment de la journée franchement",
            "bon là on vient de rentrer, on a fait le tour du quartier à pied, il y " +
                "avait une fête dans la rue avec de la musique jusqu’à tard, du coup on a " +
                "mangé sur le pouce et on a regardé les gens danser",
            "journée compliquée, euh le train avait deux heures de retard et on a raté " +
                "la visite qu’on avait réservée, enfin on a fini par trouver une terrasse " +
                "et ça s’est arrangé",
            "ce soir on est montés voir le coucher de soleil depuis les hauteurs, il y " +
                "avait un vent fou mais la vue valait le coup, Camille a pris une " +
                "cinquantaine de photos",
        )
    }

    // MARK: - Les jeux de suggestions
    //
    // Un jeu par famille de réponse. Le trio de validation de la maquette ne
    // suit qu'une fiche qui porte du **vrai** texte : trois puces « Ça me
    // convient / à la main / à l'oral » sous une question ouverte ne répondent à
    // rien, et ça se voit immédiatement.

    private object Suggestions {
        val trio = listOf(
            ChatSuggestion(id = "accept", label = ChatCopy.Suggest.accept, symbol = ChatCopy.Suggest.acceptSymbol, intent = ChatSuggestion.Intent.Send),
            ChatSuggestion(id = "edit-hand", label = ChatCopy.Suggest.editByHand, symbol = ChatCopy.Suggest.editByHandSymbol, intent = ChatSuggestion.Intent.SendThenEditTranscript),
            ChatSuggestion(id = "edit-voice", label = ChatCopy.Suggest.editByVoice, symbol = ChatCopy.Suggest.editByVoiceSymbol, intent = ChatSuggestion.Intent.SendThenSpeak),
        )

        val withoutTranscript = listOf(
            ChatSuggestion(id = "rewrite", label = ChatCopy.Suggest.rewrite, symbol = ChatCopy.Suggest.rewriteSymbol, intent = ChatSuggestion.Intent.SendThenWrite),
            ChatSuggestion(id = "record-again", label = ChatCopy.Suggest.recordAgain, symbol = ChatCopy.Suggest.recordAgainSymbol, intent = ChatSuggestion.Intent.SendThenSpeak),
            ChatSuggestion(id = "later", label = ChatCopy.Suggest.later, symbol = ChatCopy.Suggest.laterSymbol, intent = ChatSuggestion.Intent.Send),
        )

        /**
         * Une seule puce tant que le contexte du voyage n'est pas posé — le
         * serveur décide, ceci n'en est que le reflet pour les aperçus.
         */
        val opening = listOf(
            ChatSuggestion(
                id = "context",
                label = ChatCopy.Suggest.tellContext,
                symbol = ChatCopy.Suggest.tellContextSymbol,
                intent = ChatSuggestion.Intent.Send,
            ),
        )

        val neutral = listOf(
            ChatSuggestion(id = "voice", label = ChatCopy.Suggest.tellByVoice, symbol = ChatCopy.Suggest.tellByVoiceSymbol, intent = ChatSuggestion.Intent.SendThenSpeak),
            ChatSuggestion(id = "write", label = ChatCopy.Suggest.preferWriting, symbol = ChatCopy.Suggest.preferWritingSymbol, intent = ChatSuggestion.Intent.SendThenWrite),
            ChatSuggestion(id = "later", label = ChatCopy.Suggest.later, symbol = ChatCopy.Suggest.laterSymbol, intent = ChatSuggestion.Intent.Send),
        )

        val afterAnswer = listOf(
            ChatSuggestion(id = "clear", label = ChatCopy.Suggest.clear, symbol = ChatCopy.Suggest.clearSymbol, intent = ChatSuggestion.Intent.Send),
            ChatSuggestion(id = "another", label = ChatCopy.Suggest.anotherQuestion, symbol = ChatCopy.Suggest.anotherQuestionSymbol, intent = ChatSuggestion.Intent.SendThenWrite),
            ChatSuggestion(id = "resume", label = ChatCopy.Suggest.resume, symbol = ChatCopy.Suggest.resumeSymbol, intent = ChatSuggestion.Intent.SendThenSpeak),
        )

        val afterRefusal = listOf(
            ChatSuggestion(id = "tomorrow", label = ChatCopy.Suggest.tomorrow, symbol = ChatCopy.Suggest.tomorrowSymbol, intent = ChatSuggestion.Intent.Send),
            ChatSuggestion(id = "else", label = ChatCopy.Suggest.somethingElse, symbol = ChatCopy.Suggest.somethingElseSymbol, intent = ChatSuggestion.Intent.SendThenSpeak),
        )

        val afterAccept = listOf(
            ChatSuggestion(
                id = "dictate",
                label = ChatCopy.Suggest.dictate,
                symbol = ChatCopy.Suggest.dictateSymbol,
                intent = ChatSuggestion.Intent.SendThenSpeak,
            ),
            ChatSuggestion(
                id = "photos",
                label = ChatCopy.Suggest.importPhotos,
                symbol = ChatCopy.Suggest.importPhotosSymbol,
                intent = ChatSuggestion.Intent.ImportPhotos,
            ),
            ChatSuggestion(id = "later", label = ChatCopy.Suggest.later, symbol = ChatCopy.Suggest.laterSymbol, intent = ChatSuggestion.Intent.Send),
        )

        val split = listOf(
            ChatSuggestion(id = "split", label = ChatCopy.Suggest.splitInTwo, symbol = ChatCopy.Suggest.splitInTwoSymbol, intent = ChatSuggestion.Intent.Send),
            ChatSuggestion(id = "keep", label = ChatCopy.Suggest.keepAsOne, symbol = ChatCopy.Suggest.keepAsOneSymbol, intent = ChatSuggestion.Intent.Send),
        )
    }
}
