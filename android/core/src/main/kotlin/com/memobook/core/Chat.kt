package com.memobook.core

import kotlinx.serialization.EncodeDefault
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Required
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.net.URI
import java.time.Instant
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds

// La conversation avec MEMO : ce que le voyageur raconte, et ce que l'assistant
// en fait. Le jumeau de `MemoBookCore/Chat.swift`. Modélisé comme le back-end le
// rendra, et pour la même raison que `HomeFeed` et `TripDetail` : l'écran ne
// sait rien du contenu, il ne sait que le dessiner. Le jour où la route existe,
// seule la source change.
//
// **Deux couleurs, deux auteurs, et c'est toute la lecture de l'écran** : le
// bleu à droite est ce que le voyageur a dit, le blanc à gauche est ce que MEMO
// en a compris. Aucune bulle blanche ne s'écrit à la main — chacune est produite
// par l'analyse d'un message du voyageur, voir [MemoResponder].

/**
 * Qui parle.
 *
 * @property rawValue la valeur que le serveur écrit — le `rawValue` de l'énum Swift.
 */
@Serializable
enum class ChatAuthor(val rawValue: String) {
    /** L'assistant. Bulle blanche, alignée à gauche. */
    @SerialName("memo")
    Memo("memo"),

    /** Le voyageur. Bulle bleue, alignée à droite. */
    @SerialName("traveller")
    Traveller("traveller"),
    ;

    /**
     * `true` quand c'est le voyageur : c'est cette seule question que l'écran
     * pose pour décider du côté, de la couleur et du sens de la queue.
     */
    val isTraveller: Boolean get() = this == Traveller
}

/** Un vocal, tel qu'il s'affiche dans une bulle. */
@Serializable(with = VoiceNote.Serializer::class)
data class VoiceNote(
    val id: String,
    /** En secondes, comme le `TimeInterval` d'iOS. */
    val duration: Double,
    /**
     * Les niveaux relevés pendant l'enregistrement, de 0 à 1, dans l'ordre du
     * temps. C'est **la** waveform : elle dessine ce qui a vraiment été dit, et
     * non un motif décoratif qui serait le même pour tous les vocaux.
     *
     * `AudioRecorder` n'expose qu'un niveau **instantané**, sans historique :
     * c'est donc au modèle de l'écran d'échantillonner pendant qu'on parle.
     * Peut être vide — un vocal importé n'a pas de relevé —, et la vue dessine
     * alors une ligne plate plutôt que rien.
     */
    val levels: List<Double> = emptyList(),
    /**
     * Où trouver l'audio côté serveur. `null` tant que le vocal n'a pas quitté
     * l'appareil : il est alors lisible depuis [localUrl].
     */
    val remoteUrl: URI? = null,
    /**
     * Le fichier sur l'appareil, le temps que l'envoi se fasse.
     *
     * Hors sérialisation : un chemin local n'a aucun sens pour le serveur, et en
     * recevoir un d'une réponse serait un bug qu'on préfère ne pas pouvoir
     * écrire.
     *
     * ⚠️ `AudioRecorder.stop()` **efface** son fichier temporaire et ne rend que
     * des octets : c'est au modèle de l'écran de les réécrire quelque part s'il
     * veut que le vocal soit réécoutable. Sans ça, le triangle de lecture n'a
     * rien à jouer.
     */
    val localUrl: URI? = null,
) {
    /**
     * L'audio à jouer : le fichier local s'il est encore là, sinon le distant.
     * Le local d'abord, pour qu'un vocal soit réécoutable avant même d'être
     * parti.
     */
    val playbackUrl: URI? get() = localUrl ?: remoteUrl

    @Serializable
    @SerialName("com.memobook.core.VoiceNote")
    internal class Surrogate(
        val id: String,
        val duration: Double,
        @Required val levels: List<Double> = emptyList(),
        @Serializable(with = UriSerializer::class) val remoteUrl: URI? = null,
    )

    internal object Serializer : ChatSurrogateSerializer<VoiceNote, Surrogate>(
        Surrogate.serializer(),
        { Surrogate(it.id, it.duration, it.levels, it.remoteUrl) },
        { VoiceNote(it.id, it.duration, it.levels, it.remoteUrl) },
    )
}

/**
 * Ce que MEMO a retenu d'un vocal : le récit, daté et titré.
 *
 * C'est la première réponse à un vocal, et elle est d'une autre nature qu'une
 * phrase : on la relit, on la corrige, elle finira dans le carnet. D'où sa
 * forme de fiche plutôt que de bulle de conversation.
 */
@Serializable(with = TranscriptCard.Serializer::class)
data class TranscriptCard(
    /**
     * L'intitulé manuscrit de la fiche — « Retranscription du contexte ».
     * Il vient de la réponse et non de l'interface parce qu'il dit **ce qui** a
     * été retranscrit, et que ça change d'un tour à l'autre.
     */
    val title: String,
    /**
     * Le titre du récit, donné par la rédaction — celui de l'étape dans le
     * carnet (« Dernier brunch à Paros »). `null` tant que le texte n'est pas
     * rédigé (Hugo, 01/10/2026).
     */
    val heading: String? = null,
    /**
     * Le jour dont on parle, pas celui de l'envoi : quelqu'un raconte souvent
     * sa journée le soir, ou trois jours plus tard. C'est
     * `RecordedAudio.recordedAt` qui le porte, comme
     * `MemoDetailModel.finishRecording()` le fait déjà pour `capturedAt`.
     */
    val capturedAt: Instant,
    val placeLabel: String? = null,
    /**
     * La durée du vocal d'origine, en secondes, pour que la fiche dise de quoi
     * elle est tirée. `null` pour une fiche qui ne vient pas d'un vocal.
     */
    val duration: Double? = null,
    /**
     * Le récit. **`null` est un état normal**, pas une erreur : la vraie
     * transcription est un job asynchrone côté serveur, et la fiche s'affiche
     * avant lui avec ce qu'on sait déjà — la date, le lieu, la durée. Voir
     * [MemoResponder.awaitTranscript].
     */
    val text: String? = null,
    /**
     * Le texte est fabriqué par le moteur local, pas transcrit.
     *
     * **Ce drapeau est un garde-fou, pas une information d'affichage.** Un
     * texte simulé ne doit jamais partir vers le carnet : `agents/agent-
     * transcription.md` interdit d'inventer un fait, et une fiche qui prétend
     * restituer un vocal que personne n'a écouté en est un.
     */
    val isSimulated: Boolean = false,
    /**
     * L'entrée créée par ce tour, côté serveur. C'est elle que « à la main »
     * corrigera. `null` tant qu'aucune route ne l'a créée.
     */
    val entryId: String? = null,
    /**
     * La mention « généré par IA », exigée par `docs/reglages-utilisateur.md`
     * dès qu'un texte vient de la machine.
     */
    val footnote: String? = null,
    val phase: Phase = Phase.Ready,
    /** « Ça me convient » a été dit sur ce souvenir. */
    val isValidated: Boolean = false,
    /**
     * Ce qui reste des 200 caractères de correction offerts à cette fiche
     * (Hugo, 19/10/2026, QA D8) — `DailyCredit.cost(ofCorrection:replacing:freeLeft:)`.
     * `null` : un serveur d'avant, ou une fiche du jeu d'essai.
     */
    val freeCorrectionCharactersLeft: Int? = null,
) {
    /**
     * Où en est la fiche — `docs/conversation.md` § 5. Trois temps que la
     * bulle dessine différemment : on écoute, on rédige (le brut est là, en
     * gris), c'est prêt. Le serveur le calcule depuis le souvenir ; le jeu
     * d'essai, qui ne le porte pas, décode `ready`.
     */
    @Serializable(with = Phase.Serializer::class)
    sealed interface Phase {
        val rawValue: String

        /** La transcription est en cours : la fiche n'a que sa date, son lieu et sa durée. */
        data object Listening : Phase { override val rawValue = "listening" }

        /** Le brut est arrivé, la rédaction écrit : `text` est la transcription, en gris. */
        data object Writing : Phase { override val rawValue = "writing" }

        /** Le texte rédigé — ce qui ira dans le carnet. */
        data object Ready : Phase { override val rawValue = "ready" }

        /** La transcription ou la rédaction a échoué ; `text` garde le brut s'il existe. */
        data object Failed : Phase { override val rawValue = "failed" }

        /** Un temps que le serveur connaît et pas cette version de l'app. */
        data class Unknown(override val rawValue: String) : Phase

        companion object {
            fun from(raw: String): Phase = when (raw) {
                "listening" -> Listening
                "writing" -> Writing
                "ready" -> Ready
                "failed" -> Failed
                else -> Unknown(raw)
            }
        }

        object Serializer : RawValueSerializer<Phase>("com.memobook.core.TranscriptCard.Phase", { it.rawValue }, ::from)
    }

    /** La même fiche, une fois le récit revenu. */
    fun filled(text: String, isSimulated: Boolean): TranscriptCard =
        copy(text = text, isSimulated = isSimulated, phase = Phase.Ready)

    /**
     * La fiche attend encore quelque chose du serveur : c'est ce qui décide
     * si l'écran continue de sonder le fil.
     */
    val isSettling: Boolean
        get() = when (phase) {
            Phase.Listening, Phase.Writing -> true
            Phase.Ready, Phase.Failed, is Phase.Unknown -> false
        }

    /**
     * Le décodage d'iOS : `isSimulated`, `phase` et `isValidated` absents (ou
     * `null`) prennent leur valeur par défaut ; les trois sont toujours écrits.
     */
    @Serializable
    @SerialName("com.memobook.core.TranscriptCard")
    internal class Surrogate(
        val title: String,
        val heading: String? = null,
        @Serializable(with = InstantSerializer::class) val capturedAt: Instant,
        val placeLabel: String? = null,
        val duration: Double? = null,
        val text: String? = null,
        val isSimulated: Boolean? = null,
        val entryId: String? = null,
        val footnote: String? = null,
        val phase: Phase? = null,
        val isValidated: Boolean? = null,
        val freeCorrectionCharactersLeft: Int? = null,
    )

    internal object Serializer : ChatSurrogateSerializer<TranscriptCard, Surrogate>(
        Surrogate.serializer(),
        {
            Surrogate(
                it.title, it.heading, it.capturedAt, it.placeLabel, it.duration, it.text, it.isSimulated,
                it.entryId, it.footnote, it.phase, it.isValidated, it.freeCorrectionCharactersLeft,
            )
        },
        {
            TranscriptCard(
                title = it.title,
                heading = it.heading,
                capturedAt = it.capturedAt,
                placeLabel = it.placeLabel,
                duration = it.duration,
                text = it.text,
                isSimulated = it.isSimulated ?: false,
                entryId = it.entryId,
                footnote = it.footnote,
                phase = it.phase ?: Phase.Ready,
                isValidated = it.isValidated ?: false,
                freeCorrectionCharactersLeft = it.freeCorrectionCharactersLeft,
            )
        },
    )
}

/**
 * Une photo jointe à la conversation.
 *
 * Même partage que [VoiceNote] entre le local et le distant : le fichier vit
 * dans les caches le temps de l'envoi, et l'URL distante prend la relève.
 * [localUrl] est hors sérialisation pour la même raison — un chemin d'appareil
 * n'a aucun sens pour le serveur.
 */
@Serializable(with = PhotoAttachment.Serializer::class)
data class PhotoAttachment(
    val id: String,
    val remoteUrl: URI? = null,
    val localUrl: URI? = null,
) {
    val displayUrl: URI? get() = localUrl ?: remoteUrl

    @Serializable
    @SerialName("com.memobook.core.PhotoAttachment")
    internal class Surrogate(
        val id: String,
        @Serializable(with = UriSerializer::class) val remoteUrl: URI? = null,
    )

    internal object Serializer : ChatSurrogateSerializer<PhotoAttachment, Surrogate>(
        Surrogate.serializer(),
        { Surrogate(it.id, it.remoteUrl) },
        { PhotoAttachment(it.id, it.remoteUrl) },
    )
}

/**
 * Ce que porte un message. Quatre formes, et quatre dessins de bulle.
 *
 * Sur le fil : `{ "kind": "text", "text": … }`, `{ "kind": "voice", "voice": … }`,
 * `{ "kind": "transcript", "transcript": … }`, `{ "kind": "photos", "photos": [ … ] }`.
 * Un `kind` inconnu fait échouer le décodage, comme sur iOS.
 */
@Serializable(with = ChatMessageBody.Serializer::class)
sealed interface ChatMessageBody {
    data class Text(val value: String) : ChatMessageBody
    data class Voice(val note: VoiceNote) : ChatMessageBody
    data class Transcript(val card: TranscriptCard) : ChatMessageBody

    /**
     * Des photos, une à quatre. Au-delà, `agents/agent-conversation.md`
     * demande de n'en garder « 2 à 4 par souvenir maximum » : la bulle en
     * montre donc quatre et compte le reste.
     */
    data class Photos(val attachments: List<PhotoAttachment>) : ChatMessageBody

    object Serializer : KSerializer<ChatMessageBody> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("com.memobook.core.ChatMessageBody")

        override fun deserialize(decoder: Decoder): ChatMessageBody {
            val json = decoder.asJson()
            val container = json.decodeJsonElement().jsonObject
            fun field(key: String): JsonElement =
                container[key] ?: throw SerializationException("ChatMessageBody : clé « $key » absente")
            return when (val kind = container.requiredString("kind")) {
                "text" -> Text(json.json.decodeFromJsonElement(String.serializer(), field("text")))
                "voice" -> Voice(json.json.decodeFromJsonElement(VoiceNote.serializer(), field("voice")))
                "transcript" -> Transcript(json.json.decodeFromJsonElement(TranscriptCard.serializer(), field("transcript")))
                "photos" -> Photos(
                    json.json.decodeFromJsonElement(
                        ListSerializer(PhotoAttachment.serializer()),
                        field("photos"),
                    ),
                )
                else -> throw SerializationException("ChatMessageBody : kind inconnu « $kind »")
            }
        }

        override fun serialize(encoder: Encoder, value: ChatMessageBody) {
            val json = encoder.asJson()
            val element = buildJsonObject {
                when (value) {
                    is Text -> {
                        put("kind", JsonPrimitive("text"))
                        put("text", JsonPrimitive(value.value))
                    }
                    is Voice -> {
                        put("kind", JsonPrimitive("voice"))
                        put("voice", json.json.encodeToJsonElement(VoiceNote.serializer(), value.note))
                    }
                    is Transcript -> {
                        put("kind", JsonPrimitive("transcript"))
                        put("transcript", json.json.encodeToJsonElement(TranscriptCard.serializer(), value.card))
                    }
                    is Photos -> {
                        put("kind", JsonPrimitive("photos"))
                        put(
                            "photos",
                            json.json.encodeToJsonElement(
                                ListSerializer(PhotoAttachment.serializer()),
                                value.attachments,
                            ),
                        )
                    }
                }
            }
            json.encodeJsonElement(element)
        }
    }
}

/**
 * Où en est un message qu'on vient d'envoyer.
 *
 * Un message du voyageur apparaît **avant** d'être parti : c'est ce qui fait
 * qu'une conversation répond au doigt. Cet état est donc le seul endroit où se
 * lit la différence entre « affiché » et « arrivé ».
 */
sealed interface ChatDelivery {
    data object Sending : ChatDelivery
    data object Sent : ChatDelivery

    /**
     * L'envoi a échoué, avec de quoi le dire à l'utilisateur. Le message reste
     * dans la conversation et se renvoie d'une tape : le perdre serait perdre
     * ce qu'il a raconté.
     */
    data class Failed(val message: String) : ChatDelivery

    /**
     * Le serveur l'a refusé **faute de crédit du jour** (`429
     * daily_credit_exhausted`) : ce n'est pas un échec, c'est un rendez-vous.
     * Le tour attend sur le disque et repart tout seul quand le crédit se
     * recharge (`until`, le `resetsAt` du serveur — à défaut, le minuit local
     * suivant). La bulle dit « Partira demain », en gris : un « Non envoyé ·
     * Réessayer » rouge ferait renvoyer en boucle vers le même refus (Hugo,
     * 03/10/2026).
     */
    data class WaitingForCredit(val until: Instant?) : ChatDelivery

    /**
     * Le tour coûte **plus qu'une journée entière** de crédit — un vocal de
     * plus de 5:03, un texte de plus de 4 000 caractères —, ou le serveur l'a
     * dit (`daily_credit_too_long`). Attendre demain n'y changerait rien : le
     * pot plein le refuserait encore. Il reste sur le téléphone, la bulle dit
     * « Trop long pour une journée · Passer en illimité », et il repart dès
     * que le compte raconte sans limite (03/10/2026).
     */
    data object WaitingForUnlimited : ChatDelivery

    val hasFailed: Boolean get() = this is Failed

    /** Le tour attend le crédit de demain — voir [WaitingForCredit]. */
    val isWaitingForCredit: Boolean get() = this is WaitingForCredit

    /** Le tour attend l'illimité — voir [WaitingForUnlimited]. */
    val isWaitingForUnlimited: Boolean get() = this == WaitingForUnlimited
}

/** Un message de la conversation. */
@Serializable(with = ChatMessage.Serializer::class)
data class ChatMessage(
    val id: String,
    val author: ChatAuthor,
    val body: ChatMessageBody,
    val sentAt: Instant,
    /**
     * L'étape du voyage dont ce message parle.
     *
     * **Un seul fil par voyage**, et non un fil par étape : une conversation
     * se lit d'un bout à l'autre, et couper le récit en autant de fils que
     * d'étapes obligerait à en changer pour relire ce qu'on a dit la veille.
     * C'est cet identifiant qui permet malgré tout d'ouvrir le fil **sur** une
     * étape — voir [ChatThread.lastMessage].
     *
     * `null` pour ce qui ne parle d'aucune étape en particulier : l'ouverture de
     * MEMO, une question sur l'abonnement.
     */
    val stepId: String? = null,
    val delivery: ChatDelivery = ChatDelivery.Sent,
    /**
     * Le prénom de **l'autre** voyageur qui a dit cette bulle, dans un fil à
     * plusieurs. Le serveur a déjà décidé : `null` pour soi-même, pour MEMO, et
     * quand on est seul sur le voyage — la vue affiche, elle ne raisonne pas.
     */
    val authorName: String? = null,
    /**
     * Le portrait de celui qui a parlé : ses initiales, et sa photo s'il en a
     * posé une. Sur **toutes** les bulles du voyageur — les siennes comme
     * celles des autres —, `null` pour MEMO. C'est lui que la bulle d'un vocal
     * montre (Clara, 26/09/2026).
     */
    val authorInitials: String? = null,
    val authorAvatarUrl: URI? = null,
    /**
     * Le rang dans le fil, tel que le serveur le tient : **la seule vérité sur
     * l'ordre**. `null` pour une bulle posée par l'app avant sa réponse.
     */
    val seq: Int? = null,
    /**
     * Le silence avant cette bulle de MEMO, décidé par le serveur et joué par
     * l'app — la donnée de rythme de [MemoBeat]. `null` pour une bulle du
     * voyageur.
     */
    val pauseMilliseconds: Int? = null,
    /**
     * Ce que MEMO a fait de ce tour — `docs/conversation.md` § 4. `null` pour
     * une bulle de MEMO, ou tant qu'il n'a pas répondu.
     */
    val disposition: ChatDisposition? = null,
    /**
     * Le bouton posé sous une bulle de MEMO — [ChatCallToAction] : « Raconter
     * sans limite » sous la bulle « reviens demain », « Modifier
     * l’autorisation » sous celle des photos… `null` le plus souvent.
     *
     * Une **clé optionnelle du message**, et non un nouveau `body.kind` ni une
     * puce (03/10/2026) : un `kind` inconnu ferait tomber tout le fil sur les
     * versions déjà installées, et une puce s'envoie comme un message — un
     * bouton, lui, ouvre un écran. Le serveur le résout pour **celui qui lit** :
     * un abonné ne reçoit jamais « Raconter sans limite ».
     */
    val callToAction: ChatCallToAction? = null,
    /**
     * Le souvenir dont parle cette bulle : celui du voyageur, la fiche dont
     * MEMO attend la validation, le récit dont il demande les photos (Hugo,
     * 12/10/2026). C'est ce qui fait viser la bonne fiche à « J'aimerais
     * faire des modifications à la main » quand MEMO revient à une étape
     * sautée, et ce qui retrouve le récit d'une étape depuis sa carte. `null`
     * d'un serveur d'avant, et pour ce qui ne parle d'aucun souvenir.
     */
    val entryId: String? = null,
) {
    /**
     * Le texte qu'on peut copier ou faire lire à voix haute. `null` pour un
     * vocal — il n'a rien à copier, il a un bouton pour se jouer — et pour une
     * fiche qui attend encore son récit.
     */
    val spokenText: String?
        get() = when (body) {
            is ChatMessageBody.Text -> body.value
            is ChatMessageBody.Transcript -> body.card.text
            is ChatMessageBody.Voice, is ChatMessageBody.Photos -> null
        }

    /**
     * La même bulle, avec ce que l'app sait et que le serveur ne rend pas : le
     * fichier local d'un vocal ou d'une photo, le temps qu'il soit parti.
     *
     * Une photo se retrouve par son identifiant, **sinon par son rang**. La
     * bulle posée avant l'envoi numérote ses photos (`<tour>-0`, `<tour>-1`…),
     * le serveur les rend sous l'identifiant de leur souvenir : rapprochées
     * par identifiant seulement, elles perdaient leur fichier dès le reçu, et
     * la bulle allait chercher une adresse distante qui demande la session
     * (deux `401` le 30/09/2026, une seconde après l'envoi). Le serveur écrit
     * les souvenirs dans l'ordre des fichiers reçus : le rang est sûr quand
     * les deux listes ont la même longueur.
     */
    fun keepingLocalFiles(previous: ChatMessage): ChatMessage {
        val current = body
        val known = previous.body
        return when {
            current is ChatMessageBody.Voice && known is ChatMessageBody.Voice -> copy(
                body = ChatMessageBody.Voice(
                    current.note.copy(localUrl = known.note.localUrl ?: current.note.localUrl),
                ),
            )
            current is ChatMessageBody.Photos && known is ChatMessageBody.Photos -> {
                val sameCount = current.attachments.size == known.attachments.size
                copy(
                    body = ChatMessageBody.Photos(
                        current.attachments.mapIndexed { rank, attachment ->
                            val byId = known.attachments.firstOrNull { it.id == attachment.id }?.localUrl
                            val byRank = if (sameCount) known.attachments[rank].localUrl else null
                            attachment.copy(localUrl = byId ?: byRank ?: attachment.localUrl)
                        },
                    ),
                )
            }
            else -> this
        }
    }

    /**
     * L'acheminement n'est **pas** décodé : un message qui arrive du serveur
     * est arrivé, par définition. `sending` et `failed` n'existent que le temps
     * d'un aller-retour, côté app.
     *
     * L'avatar et le bouton sont lus avec tolérance : une adresse illisible ne
     * doit pas faire tomber la bulle — les initiales prennent la place —, et un
     * bouton illisible non plus — son texte se suffit à lui-même, le bouton
     * n'est qu'un raccourci.
     */
    @Serializable
    @SerialName("com.memobook.core.ChatMessage")
    internal class Surrogate(
        val id: String,
        val author: ChatAuthor,
        val body: ChatMessageBody,
        @Serializable(with = InstantSerializer::class) val sentAt: Instant,
        val stepId: String? = null,
        val authorName: String? = null,
        val authorInitials: String? = null,
        val authorAvatarUrl: JsonElement? = null,
        val seq: Int? = null,
        val pauseMilliseconds: Int? = null,
        val disposition: ChatDisposition? = null,
        val callToAction: JsonElement? = null,
        val entryId: String? = null,
    )

    internal object Serializer : ChatSurrogateSerializer<ChatMessage, Surrogate>(
        Surrogate.serializer(),
        {
            Surrogate(
                id = it.id,
                author = it.author,
                body = it.body,
                sentAt = it.sentAt,
                stepId = it.stepId,
                authorName = it.authorName,
                authorInitials = it.authorInitials,
                authorAvatarUrl = it.authorAvatarUrl?.let { url -> JsonPrimitive(url.toString()) },
                seq = it.seq,
                pauseMilliseconds = it.pauseMilliseconds,
                disposition = it.disposition,
                callToAction = it.callToAction?.let { cta -> MemoBookJson.encodeToJsonElement(ChatCallToAction.serializer(), cta) },
                entryId = it.entryId,
            )
        },
        {
            ChatMessage(
                id = it.id,
                author = it.author,
                body = it.body,
                sentAt = it.sentAt,
                stepId = it.stepId,
                authorName = it.authorName,
                authorInitials = it.authorInitials,
                authorAvatarUrl = it.authorAvatarUrl.decodeOrNull(UriSerializer),
                seq = it.seq,
                pauseMilliseconds = it.pauseMilliseconds,
                disposition = it.disposition,
                callToAction = it.callToAction.decodeOrNull(ChatCallToAction.serializer()),
                entryId = it.entryId,
            )
        },
    )
}

/** Ce que MEMO a fait d'un tour du voyageur — `docs/conversation.md` § 4. */
@Serializable(with = ChatDisposition.Serializer::class)
sealed interface ChatDisposition {
    val rawValue: String

    /** Un souvenir : une entrée existe pour lui, la rédaction l'écrit. */
    data object Memory : ChatDisposition { override val rawValue = "memory" }

    /** Une précision, rattachée au souvenir en cours. */
    data object Context : ChatDisposition { override val rawValue = "context" }

    /** Une puce, un refus, une question sur l'app : rien n'entre dans le carnet. */
    data object Command : ChatDisposition { override val rawValue = "command" }

    data class Unknown(override val rawValue: String) : ChatDisposition

    companion object {
        fun from(raw: String): ChatDisposition = when (raw) {
            "memory" -> Memory
            "context" -> Context
            "command" -> Command
            else -> Unknown(raw)
        }
    }

    object Serializer : RawValueSerializer<ChatDisposition>("com.memobook.core.ChatDisposition", { it.rawValue }, ::from)
}

/**
 * Une réponse toute prête, proposée par MEMO sous la conversation.
 *
 * Ce n'est pas un raccourci d'interface : c'est **MEMO qui prend la main** en
 * proposant la suite. Les libellés viennent donc du même endroit que ses
 * phrases, et changent à chaque tour.
 */
@Serializable
data class ChatSuggestion(
    val id: String,
    /** Le libellé, au caractère près : c'est lui qui part comme message. */
    val label: String,
    /**
     * L'emoji de tête, quand la maquette en montre un. Séparé du libellé pour
     * qu'il ne se retrouve pas dans le message envoyé, ni lu par TalkBack.
     */
    val symbol: String? = null,
    @Required val intent: Intent = Intent.Send,
) {
    /**
     * Ce que la puce déclenche **en plus** d'envoyer son libellé.
     *
     * La maquette montre « J'aimerais faire des modifications à la main » posée
     * en bulle bleue dans le fil : une puce **dit** quelque chose, elle n'est
     * pas un bouton d'interface déguisé. Ce qui change d'une intention à
     * l'autre, c'est l'outil qu'elle ouvre derrière.
     */
    @Serializable(with = Intent.Serializer::class)
    sealed interface Intent {
        val rawValue: String

        /** Envoyer le libellé, et rien de plus. */
        data object Send : Intent { override val rawValue = "send" }

        /** Envoyer le libellé, puis ouvrir le clavier : « à la main ». */
        data object SendThenWrite : Intent { override val rawValue = "send_then_write" }

        /**
         * Envoyer le libellé, puis ouvrir le clavier **avec la retranscription
         * déjà dedans** : « J'aimerais faire des modifications à la main »
         * sous une fiche remplie. On ne retape pas cinquante mots pour en
         * changer trois — le texte de MEMO est posé dans le champ, prêt à
         * être corrigé (Hugo, 17/09/2026).
         */
        data object SendThenEditTranscript : Intent { override val rawValue = "send_then_edit_transcript" }

        /** Envoyer le libellé, puis armer le micro : « à l'oral ». */
        data object SendThenSpeak : Intent { override val rawValue = "send_then_speak" }

        /**
         * Ouvrir le sélecteur de photos. La seule qui n'envoie rien : on ne
         * dit pas « j'importe des photos », on les importe.
         */
        data object ImportPhotos : Intent { override val rawValue = "import_photos" }

        /**
         * Ouvrir l'aperçu du carnet. N'envoie rien non plus : « Voir ma
         * page », une fois les photos d'une étape validées (Hugo, 01/10/2026).
         */
        data object OpenPreview : Intent { override val rawValue = "open_preview" }

        /**
         * Une intention que le serveur connaît et pas cette version de l'app.
         * Elle se comporte alors comme `send` — la puce marche, elle en fait
         * juste un peu moins. Même parti pris que [Status.Unknown].
         */
        data class Unknown(override val rawValue: String) : Intent

        companion object {
            fun from(raw: String): Intent = when (raw) {
                "send" -> Send
                "send_then_write" -> SendThenWrite
                "send_then_edit_transcript" -> SendThenEditTranscript
                "send_then_speak" -> SendThenSpeak
                "import_photos" -> ImportPhotos
                "open_preview" -> OpenPreview
                else -> Unknown(raw)
            }
        }

        object Serializer : RawValueSerializer<Intent>("com.memobook.core.ChatSuggestion.Intent", { it.rawValue }, ::from)
    }
}

/**
 * La bannière « Aperçu en direct » en haut de la conversation : ce que la
 * conversation a déjà produit.
 *
 * Elle est là pour une seule raison — raconter dans le vide est décourageant.
 * Deux compteurs suffisent à montrer que le carnet monte pendant qu'on parle.
 */
@Serializable
data class ChatBookPreview(
    val memoryCount: Int,
    val pageCount: Int,
    /**
     * Un PDF composé existe. La capsule ne s'en sert plus pour se
     * désactiver (30/09/2026) : elle mène à l'aperçu dans tous les cas, et
     * c'est lui qui dit si le carnet se compose encore.
     */
    @Required val isOpenable: Boolean = true,
)

/**
 * L'accueil d'une conversation qui n'a rien dedans : le signe de la marque, une
 * phrase qui nomme le voyage, et ce que MEMO propose d'en faire.
 *
 * C'est du **contenu** et non de l'interface : « Nouveau voyage à Rome ! »
 * dépend du voyage, et la relance de ce que le serveur sait déjà.
 */
@Serializable
data class ChatGreeting(
    val title: String,
    val message: String,
)

/**
 * Ce que MEMO sait du voyage quand il répond. C'est **tout** son contexte : il
 * n'a accès à rien d'autre, ce qui rend ses réponses testables une par une.
 */
@Serializable(with = ChatContext.Serializer::class)
data class ChatContext(
    val tripId: String,
    val tripTitle: String? = null,
    val travellerFirstName: String? = null,
    /**
     * Le portrait de celui qui lit, pour ses bulles qui ne sont pas encore
     * parties : elles n'ont pas de réponse du serveur où le trouver.
     */
    val travellerInitials: String? = null,
    val travellerAvatarUrl: URI? = null,
    /**
     * Le lieu de la dernière étape connue. Il complète l'analyse quand le
     * message du voyageur n'en nomme aucun.
     */
    val placeName: String? = null,
    val stepNumber: Int? = null,
    /**
     * L'étape à laquelle rattacher ce qu'on raconte maintenant.
     *
     * C'est l'étape ouverte, ou à défaut la dernière du voyage : dans un carnet
     * de voyage, ce qu'on dit le soir parle de la journée en cours. C'est elle
     * qui se retrouve sur [ChatMessage.stepId], et qui permet plus tard de
     * rouvrir le fil sur cette journée-là.
     */
    val stepId: String? = null,
    /**
     * `TripDetail.prompt` — la relance que le voyageur a déjà vue au-dessus
     * du micro, sur l'accueil du voyage.
     *
     * **Le chat n'ouvre plus dessus** (Hugo, 17/09/2026) : la bulle
     * d'ouverture pose déjà sa question — le contexte du voyage — et la
     * relance ne doit pas venir par-dessus. Elle reste dans le contexte pour
     * que le répondeur sache de quelle journée on parle, et pour la
     * notification qui la portera.
     */
    val prompt: String? = null,
    /**
     * Combien de personnes sont sur ce voyage, propriétaire compris. Au-delà
     * de un, le fil est **commun** et les bulles portent un prénom. Un jeu
     * d'essai qui ne le dit pas décode `1`.
     */
    val memberCount: Int = 1,
) {
    /** L'avatar se lit avec tolérance : une adresse illisible vaut `null`. */
    @Serializable
    @SerialName("com.memobook.core.ChatContext")
    internal class Surrogate(
        val tripId: String,
        val tripTitle: String? = null,
        val travellerFirstName: String? = null,
        val travellerInitials: String? = null,
        val travellerAvatarUrl: JsonElement? = null,
        val placeName: String? = null,
        val stepNumber: Int? = null,
        val stepId: String? = null,
        val prompt: String? = null,
        val memberCount: Int? = null,
    )

    internal object Serializer : ChatSurrogateSerializer<ChatContext, Surrogate>(
        Surrogate.serializer(),
        {
            Surrogate(
                it.tripId, it.tripTitle, it.travellerFirstName, it.travellerInitials,
                it.travellerAvatarUrl?.let { url -> JsonPrimitive(url.toString()) },
                it.placeName, it.stepNumber, it.stepId, it.prompt, it.memberCount,
            )
        },
        {
            ChatContext(
                tripId = it.tripId,
                tripTitle = it.tripTitle,
                travellerFirstName = it.travellerFirstName,
                travellerInitials = it.travellerInitials,
                travellerAvatarUrl = it.travellerAvatarUrl.decodeOrNull(UriSerializer),
                placeName = it.placeName,
                stepNumber = it.stepNumber,
                stepId = it.stepId,
                prompt = it.prompt,
                memberCount = it.memberCount ?: 1,
            )
        },
    )
}

/**
 * Où en est le tour de parole, vu du serveur : un message du voyageur attend
 * encore la réponse de MEMO, ou non. C'est ce que l'app sonde.
 *
 * Sur le fil : `{ "status": "idle" }` ou `{ "status": "replying", "messageId": … }`.
 * Un `replying` sans `messageId`, ou un statut inconnu, se lit `idle`.
 */
@Serializable(with = ChatTurnStatus.Serializer::class)
sealed interface ChatTurnStatus {
    data object Idle : ChatTurnStatus
    data class Replying(val messageId: String) : ChatTurnStatus

    val isReplying: Boolean get() = this is Replying

    object Serializer : KSerializer<ChatTurnStatus> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("com.memobook.core.ChatTurnStatus")

        override fun deserialize(decoder: Decoder): ChatTurnStatus {
            val container = decoder.asJson().decodeJsonElement().jsonObject
            val status = container.requiredString("status")
            val messageId = container.optionalString("messageId")
            return if (status == "replying" && messageId != null) Replying(messageId) else Idle
        }

        override fun serialize(encoder: Encoder, value: ChatTurnStatus) {
            encoder.asJson().encodeJsonElement(
                buildJsonObject {
                    when (value) {
                        Idle -> put("status", JsonPrimitive("idle"))
                        is Replying -> {
                            put("status", JsonPrimitive("replying"))
                            put("messageId", JsonPrimitive(value.messageId))
                        }
                    }
                },
            )
        }
    }
}

/**
 * La suite du fil depuis un instant — ce que `GET /v1/trips/:id/chat?since=`
 * rend, et que le modèle fusionne dans ce qu'il a : on insère ou on remplace
 * par `id`, on trie par `seq`.
 */
@Serializable(with = ChatThreadUpdate.Serializer::class)
data class ChatThreadUpdate(
    val messages: List<ChatMessage>,
    val suggestions: List<ChatSuggestion> = emptyList(),
    val preview: ChatBookPreview? = null,
    /**
     * Toujours servi, pas seulement quand il change : la pastille se remplit
     * à chaque réponse de MEMO.
     */
    val tripContext: ChatTripContext? = null,
    val turn: ChatTurnStatus = ChatTurnStatus.Idle,
    /** L'heure du serveur à la lecture : le curseur de la lecture suivante. */
    val now: Instant,
    /**
     * Le crédit du jour du voyage, à jour de ce qu'un co-voyageur vient de
     * raconter — voir [ChatThread.dailyCredit]. `null` d'un serveur qui ne
     * le sert pas encore : l'app garde alors celui qu'elle tenait.
     */
    val dailyCredit: DailyCredit? = null,
) {
    /**
     * `messages`, `suggestions`, `turn` et `now` sont exigés ; un crédit
     * illisible ne fait pas tomber la suite du fil : la barre garde le dernier
     * connu, le serveur tranche de toute façon.
     */
    @Serializable
    @SerialName("com.memobook.core.ChatThreadUpdate")
    internal class Surrogate(
        val messages: List<ChatMessage>,
        val suggestions: List<ChatSuggestion>,
        val preview: ChatBookPreview? = null,
        val tripContext: ChatTripContext? = null,
        val turn: ChatTurnStatus,
        @Serializable(with = InstantSerializer::class) val now: Instant,
        val dailyCredit: JsonElement? = null,
    )

    internal object Serializer : ChatSurrogateSerializer<ChatThreadUpdate, Surrogate>(
        Surrogate.serializer(),
        {
            Surrogate(
                it.messages, it.suggestions, it.preview, it.tripContext, it.turn, it.now,
                it.dailyCredit?.let { credit -> MemoBookJson.encodeToJsonElement(DailyCredit.serializer(), credit) },
            )
        },
        {
            ChatThreadUpdate(
                messages = it.messages,
                suggestions = it.suggestions,
                preview = it.preview,
                tripContext = it.tripContext,
                turn = it.turn,
                now = it.now,
                dailyCredit = it.dailyCredit.decodeOrNull(DailyCredit.serializer()),
            )
        },
    )
}

/**
 * Ce que `POST /v1/trips/:id/chat` rend : les bulles qu'il vient d'écrire —
 * l'ouverture si elle vient d'être posée, le message du voyageur avec son
 * `seq`, la fiche pour un vocal — et l'état du tour.
 *
 * Il porte aussi le crédit du jour **après** décompte de ce tour, et, quand
 * ce tour l'a épuisé, la bulle « reviens demain » de MEMO parmi ses messages.
 */
@Serializable(with = ChatTurnReceipt.Serializer::class)
data class ChatTurnReceipt(
    val messages: List<ChatMessage>,
    val turn: ChatTurnStatus,
    val now: Instant,
    /**
     * Le crédit du jour du voyage, ce tour compté. `null` d'un serveur qui ne
     * le sert pas encore.
     */
    val dailyCredit: DailyCredit? = null,
) {
    @Serializable
    @SerialName("com.memobook.core.ChatTurnReceipt")
    internal class Surrogate(
        val messages: List<ChatMessage>,
        val turn: ChatTurnStatus,
        @Serializable(with = InstantSerializer::class) val now: Instant,
        val dailyCredit: JsonElement? = null,
    )

    internal object Serializer : ChatSurrogateSerializer<ChatTurnReceipt, Surrogate>(
        Surrogate.serializer(),
        {
            Surrogate(
                it.messages, it.turn, it.now,
                it.dailyCredit?.let { credit -> MemoBookJson.encodeToJsonElement(DailyCredit.serializer(), credit) },
            )
        },
        { ChatTurnReceipt(it.messages, it.turn, it.now, it.dailyCredit.decodeOrNull(DailyCredit.serializer())) },
    )
}

/**
 * Ce que « Ça me convient » rend : le souvenir validé, et rien d'autre
 * (03/10/2026). Un champ de plus servi par un ancien serveur est ignoré.
 */
@Serializable
data class EntryValidation(
    val entry: Entry,
)

/**
 * Le tour de parole soumis au répondeur : ce qui vient d'être dit, ce qui l'a
 * précédé, et ce qu'on sait du voyage.
 *
 * Pas une `data class` : l'historique est **borné** à la construction, comme
 * l'`init` d'iOS, et une `copy` le contournerait.
 */
class ChatTurn(
    val message: ChatMessage,
    history: List<ChatMessage>,
    val context: ChatContext,
) {
    /** Le fil, sans [message], et **borné** : voir [historyLimit]. */
    val history: List<ChatMessage> = history.takeLast(historyLimit)

    /**
     * Tout ce que MEMO a déjà dit dans ce fil. C'est là — et nulle part
     * ailleurs — que le répondeur va chercher de quoi ne pas se répéter : il
     * reste donc une valeur sans état mutable.
     */
    val thingsMemoAlreadySaid: Set<String>
        get() = history
            .filter { it.author == ChatAuthor.Memo }
            .mapNotNull { (it.body as? ChatMessageBody.Text)?.value }
            .toSet()

    override fun equals(other: Any?): Boolean =
        other is ChatTurn && message == other.message && history == other.history && context == other.context

    override fun hashCode(): Int = (message.hashCode() * 31 + history.hashCode()) * 31 + context.hashCode()

    override fun toString(): String = "ChatTurn(message=$message, history=$history, context=$context)"

    companion object {
        /**
         * Combien de bulles le répondeur relit pour ne pas se répéter.
         *
         * Vingt, et pas tout le fil : c'est la mémoire d'une conversation, pas une
         * archive, et rescanner quatre cents bulles à chaque tour coûterait de plus
         * en plus cher pour une information de moins en moins utile. La rédaction
         * borne déjà son contexte de la même façon, à trois étapes.
         */
        const val historyLimit = 20
    }
}

/**
 * Une bulle de MEMO, et le silence qu'il prend avant de la poser.
 *
 * **Le répondeur ne dort jamais, il décrit.** Le rythme est une donnée et non
 * un effet de bord : c'est ce qui laisse le moteur testable — on vérifie
 * qu'aucune pause n'est nulle — et le modèle maître du minutage.
 */
@Serializable
data class MemoBeat(
    val message: ChatMessage,
    /**
     * En millisecondes, et non en `Duration` : une durée s'encode mal dans un
     * contrat JSON.
     */
    val pauseMilliseconds: Int,
) {
    val pause: Duration get() = pauseMilliseconds.milliseconds
}

/**
 * Ce que MEMO répond à un tour de parole.
 *
 * Un tour peut valoir **plusieurs** bulles — une fiche de retranscription puis
 * une relance —, et il remplace toujours les suggestions : celles du tour
 * précédent ne veulent plus rien dire.
 */
@Serializable
data class MemoReply(
    val beats: List<MemoBeat>,
    @Required val suggestions: List<ChatSuggestion> = emptyList(),
    /**
     * Les compteurs de la bannière, quand ce tour les a fait bouger. `null`
     * laisse en place ceux qui sont affichés.
     */
    val preview: ChatBookPreview? = null,
)

/** Une conversation ouverte : tout ce qu'il faut pour dessiner l'écran de chat. */
@Serializable(with = ChatThread.Serializer::class)
data class ChatThread(
    val id: String,
    /**
     * Le titre de l'en-tête — le nom du voyage, ou celui de l'étape dont on
     * parle.
     */
    val title: String,
    /** La vignette ronde posée devant le titre : la couverture du voyage. */
    val avatarUrl: URI? = null,
    /** Le pays, pour le drapeau de l'accueil de conversation. */
    val destination: Destination? = null,
    val greeting: ChatGreeting? = null,
    val preview: ChatBookPreview? = null,
    val context: ChatContext,
    val messages: List<ChatMessage> = emptyList(),
    val suggestions: List<ChatSuggestion> = emptyList(),
    /**
     * Le contexte du voyage — [ChatTripContext]. `null` tant que le voyageur
     * n'a pas commencé à le raconter.
     */
    val tripContext: ChatTripContext? = null,
    /**
     * Un tour du voyageur attend encore MEMO — le serveur le sait, l'app le
     * sonde. `idle` pour un jeu d'essai.
     */
    val turn: ChatTurnStatus = ChatTurnStatus.Idle,
    /**
     * « Supprimer la conversation » est ouvert à ce compte : le propriétaire
     * du voyage. Un co-voyageur voit le lien pâli.
     */
    val canClear: Boolean = true,
    /**
     * L'heure du serveur à la lecture — le curseur du sondage. `null` pour un
     * jeu d'essai.
     */
    val now: Instant? = null,
    /**
     * **Le crédit du jour du voyage** (Hugo, 03/10/2026) — [DailyCredit] :
     * ce que la barre d'enregistrement compte pendant qu'on parle, ce qui
     * pâlit le micro et l'envoi quand il n'y a plus rien. `null` pour un fil
     * local, ou d'un serveur qui ne le sert pas encore : l'app ne prévient
     * alors de rien, et le serveur tranche seul.
     */
    val dailyCredit: DailyCredit? = null,
) {
    /**
     * Rien n'a encore été dit. C'est cet état, et lui seul, qui montre
     * [greeting] à la place de la conversation.
     */
    val isEmpty: Boolean get() = messages.isEmpty()

    /**
     * Le même fil, **sans un mot** : ce qu'on obtient après « Supprimer la
     * conversation ». Le voyage, son en-tête et son mot d'accueil restent ;
     * les messages et les puces s'en vont — les puces d'ouverture reviennent
     * d'elles-mêmes, elles appartiennent au répondeur.
     */
    fun cleared(): ChatThread = copy(messages = emptyList(), suggestions = emptyList())

    /**
     * Le dernier message qui parle de cette étape.
     *
     * C'est **la** cible d'une ouverture depuis une carte d'étape : on ne veut
     * pas le début de ce qu'on a raconté ce jour-là, on veut où on en était.
     * `null` quand l'étape n'a encore rien — le fil s'ouvre alors sur sa fin,
     * comme d'habitude.
     */
    fun lastMessage(about: String): ChatMessage? = messages.lastOrNull { it.stepId == about }

    /**
     * **Le récit d'une étape** : la bulle du voyageur qui l'a racontée — son
     * vocal ou son texte —, que la carte de l'étape ouvre (Hugo, 12/10/2026).
     * À défaut, sa fiche, puis le premier message qui en parle.
     *
     * Le premier et non le dernier : une étape se relit depuis son début, et
     * sa fiche suit juste dessous.
     */
    fun storyMessage(about: String): ChatMessage? {
        val aboutStep = messages.filter { it.stepId == about }
        return aboutStep.firstOrNull { message ->
            if (!message.author.isTraveller) return@firstOrNull false
            when (message.body) {
                is ChatMessageBody.Voice, is ChatMessageBody.Text ->
                    message.disposition == ChatDisposition.Memory || message.disposition == null
                is ChatMessageBody.Transcript, is ChatMessageBody.Photos -> false
            }
        }
            ?: aboutStep.firstOrNull { it.body is ChatMessageBody.Transcript }
            ?: aboutStep.firstOrNull()
    }

    /**
     * Le jeu d'essai ne porte pas les champs ajoutés : `messages`,
     * `suggestions`, `turn` et `canClear` ont leur défaut. Un crédit illisible
     * ne doit pas coûter le fil entier.
     */
    @Serializable
    @SerialName("com.memobook.core.ChatThread")
    internal class Surrogate(
        val id: String,
        val title: String,
        @Serializable(with = UriSerializer::class) val avatarUrl: URI? = null,
        val destination: Destination? = null,
        val greeting: ChatGreeting? = null,
        val preview: ChatBookPreview? = null,
        val context: ChatContext,
        val messages: List<ChatMessage>? = null,
        val suggestions: List<ChatSuggestion>? = null,
        val tripContext: ChatTripContext? = null,
        val turn: ChatTurnStatus? = null,
        val canClear: Boolean? = null,
        @Serializable(with = InstantSerializer::class) val now: Instant? = null,
        val dailyCredit: JsonElement? = null,
    )

    internal object Serializer : ChatSurrogateSerializer<ChatThread, Surrogate>(
        Surrogate.serializer(),
        {
            Surrogate(
                it.id, it.title, it.avatarUrl, it.destination, it.greeting, it.preview, it.context,
                it.messages, it.suggestions, it.tripContext, it.turn, it.canClear, it.now,
                it.dailyCredit?.let { credit -> MemoBookJson.encodeToJsonElement(DailyCredit.serializer(), credit) },
            )
        },
        {
            ChatThread(
                id = it.id,
                title = it.title,
                avatarUrl = it.avatarUrl,
                destination = it.destination,
                greeting = it.greeting,
                preview = it.preview,
                context = it.context,
                messages = it.messages ?: emptyList(),
                suggestions = it.suggestions ?: emptyList(),
                tripContext = it.tripContext,
                turn = it.turn ?: ChatTurnStatus.Idle,
                canClear = it.canClear ?: true,
                now = it.now,
                dailyCredit = it.dailyCredit.decodeOrNull(DailyCredit.serializer()),
            )
        },
    )
}

// MARK: - Ce que l'app envoie

/**
 * Un texte ou une puce, tel que `POST /v1/trips/:id/chat` le reçoit.
 *
 * `id` est **fourni par l'app** et devient l'identifiant du message : la bulle
 * optimiste et la bulle servie sont la même, et un renvoi après une panne de
 * transport tombe sur l'existant au lieu de créer un doublon.
 */
@OptIn(ExperimentalSerializationApi::class)
@Serializable
data class ChatTextTurn(
    val id: String,
    val text: String,
    val stepId: String? = null,
    /**
     * La puce qui a produit ce message, ou une commande silencieuse
     * (`transcript_edited`). `null` pour un texte libre.
     */
    val suggestionId: String? = null,
    /** Le souvenir visé par « Ça me convient ». */
    val entryId: String? = null,
) {
    @EncodeDefault
    val kind: String = "text"
}

/** Un vocal, tel que la route le reçoit en `multipart/form-data`. */
data class ChatVoiceTurn(
    val id: String,
    val data: ByteArray,
    val filename: String,
    val mimeType: String,
    /** Le jour raconté — `RecordedAudio.recordedAt`. */
    val capturedAt: Instant,
    /**
     * La durée capturée, pauses déduites, telle que l'app l'a mesurée, en
     * secondes.
     *
     * **Le serveur ne la croit plus** (03/10/2026) : il relit la durée dans le
     * fichier, et c'est elle qui décompte le crédit du jour et s'affiche dans
     * la bulle une fois le reçu arrivé. Elle part quand même — inoffensive, et
     * lue par un serveur d'avant.
     */
    val durationSeconds: Double,
    /** La forme d'onde relevée pendant l'enregistrement, pour la bulle. */
    val levels: List<Double> = emptyList(),
    val placeLabel: String? = null,
    val stepId: String? = null,
) {
    // Les octets se comparent par contenu, comme les `Data` d'iOS.
    override fun equals(other: Any?): Boolean =
        other is ChatVoiceTurn && id == other.id && data.contentEquals(other.data) &&
            filename == other.filename && mimeType == other.mimeType && capturedAt == other.capturedAt &&
            durationSeconds == other.durationSeconds && levels == other.levels &&
            placeLabel == other.placeLabel && stepId == other.stepId

    override fun hashCode(): Int =
        listOf(id, data.contentHashCode(), filename, mimeType, capturedAt, durationSeconds, levels, placeLabel, stepId)
            .hashCode()
}

/** Une photo à envoyer, une à quatre par tour. */
data class ChatPhotoUpload(
    val data: ByteArray,
    val filename: String,
    val mimeType: String,
) {
    // Les octets se comparent par contenu, comme les `Data` d'iOS.
    override fun equals(other: Any?): Boolean =
        other is ChatPhotoUpload && data.contentEquals(other.data) &&
            filename == other.filename && mimeType == other.mimeType

    override fun hashCode(): Int = listOf(data.contentHashCode(), filename, mimeType).hashCode()
}

data class ChatPhotosTurn(
    val id: String,
    val photos: List<ChatPhotoUpload>,
    val capturedAt: Instant,
    val stepId: String? = null,
)

// MARK: - Outils de décodage, propres à la conversation

/**
 * Le patron « surrogate » de kotlinx.serialization : le type public se lit et
 * s'écrit par une classe-miroir qui porte les règles de décodage d'iOS
 * (défauts, tolérance).
 */
internal abstract class ChatSurrogateSerializer<T, S>(
    private val surrogate: KSerializer<S>,
    private val toSurrogate: (T) -> S,
    private val fromSurrogate: (S) -> T,
) : KSerializer<T> {
    override val descriptor: SerialDescriptor get() = surrogate.descriptor
    override fun serialize(encoder: Encoder, value: T) = encoder.encodeSerializableValue(surrogate, toSurrogate(value))
    override fun deserialize(decoder: Decoder): T = fromSurrogate(decoder.decodeSerializableValue(surrogate))
}

/** Le `try? decodeIfPresent` d'iOS : absent, `null` ou illisible, c'est `null`. */
private fun <T> JsonElement?.decodeOrNull(serializer: KSerializer<T>): T? {
    if (this == null || this is JsonNull) return null
    return try {
        MemoBookJson.decodeFromJsonElement(serializer, this)
    } catch (_: Exception) {
        null
    }
}

private fun Decoder.asJson(): JsonDecoder =
    this as? JsonDecoder ?: throw SerializationException("La conversation ne se lit qu'en JSON")

private fun Encoder.asJson(): JsonEncoder =
    this as? JsonEncoder ?: throw SerializationException("La conversation ne s'écrit qu'en JSON")

private fun JsonObject.requiredString(key: String): String {
    val primitive = (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }
        ?: throw SerializationException("Clé « $key » absente")
    if (!primitive.isString) throw SerializationException("Clé « $key » : une chaîne est attendue")
    return primitive.content
}

private fun JsonObject.optionalString(key: String): String? {
    val element = this[key] ?: return null
    if (element is JsonNull) return null
    val primitive = element.jsonPrimitive
    if (!primitive.isString) throw SerializationException("Clé « $key » : une chaîne est attendue")
    return primitive.content
}
