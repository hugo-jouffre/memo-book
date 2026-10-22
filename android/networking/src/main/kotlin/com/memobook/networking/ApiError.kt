package com.memobook.networking

import com.memobook.core.DailyCredit
import com.memobook.core.MemoBookJson
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import java.io.EOFException
import java.io.IOException
import java.io.InterruptedIOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketException
import java.net.URI
import java.net.UnknownHostException
import java.net.UnknownServiceException

/**
 * Erreur remontée par le client d'API. Le jumeau de
 * `MemoBookNetworking/APIError.swift`, aux mêmes cas.
 *
 * Les messages sont destinés à l'utilisateur : le back-end renvoie déjà des
 * libellés en français dans son champ `message`, on les réutilise plutôt que
 * d'afficher un code HTTP.
 *
 * [message] vaut [errorDescription] — la phrase à montrer —, sauf pour
 * [Server] et [DailyCreditExhausted], où il est le message **brut** du serveur,
 * comme la valeur associée du cas Swift.
 */
sealed class ApiError(cause: Throwable? = null) : Exception(cause) {

    data object NotAuthenticated : ApiError()

    data class Server(
        override val statusCode: Int,
        override val code: String?,
        override val message: String,
    ) : ApiError()

    /**
     * L'appel n'a pas abouti du tout. L'URL visée est gardée avec l'erreur :
     * elle ne sert à rien à l'utilisateur, mais elle est **l'essentiel du
     * diagnostic** en développement — voir [developerDiagnosis].
     */
    data class Transport(val error: Throwable, val url: URI?) : ApiError(error)

    data class Decoding(val error: Throwable) : ApiError(error)

    /**
     * **Le crédit du jour du voyage est épuisé** — `429
     * daily_credit_exhausted` (Hugo, 03/10/2026), avec le solde que le corps
     * porte ([DailyCredit], dont `resetsAt` : l'heure à laquelle réessayer).
     *
     * Un cas à part et non un `Server(429, …)` : le solde doit **traverser**
     * jusqu'à la file et jusqu'à la bulle (« Partira demain »), et [Server]
     * n'a pas de place pour lui — lui ajouter un champ aurait cassé chacun des
     * endroits de l'app qui le décompose. Le code et le statut restent lisibles
     * par [code] et [statusCode], comme pour un refus ordinaire.
     */
    data class DailyCreditExhausted(
        override val message: String,
        val credit: DailyCredit?,
    ) : ApiError()

    override val message: String? get() = errorDescription

    /**
     * Le code d'erreur du serveur (`error` dans le corps), quel que soit le cas
     * qui le porte. `null` pour ce qui n'est pas une réponse du serveur.
     */
    open val code: String?
        get() = when (this) {
            is Server -> code
            is DailyCreditExhausted -> DAILY_CREDIT_EXHAUSTED_CODE
            NotAuthenticated, is Transport, is Decoding -> null
        }

    /** Le statut HTTP de la réponse, quand il y en a eu une. */
    open val statusCode: Int?
        get() = when (this) {
            is Server -> statusCode
            is DailyCreditExhausted -> 429
            NotAuthenticated, is Transport, is Decoding -> null
        }

    /** Le solde du jour qu'un refus de crédit a rendu. `null` partout ailleurs. */
    val dailyCredit: DailyCredit?
        get() = (this as? DailyCreditExhausted)?.credit

    /** La phrase à montrer à l'utilisateur — le `errorDescription` d'iOS. */
    val errorDescription: String
        get() = when (this) {
            NotAuthenticated -> "Cet appareil n’est pas encore enregistré."
            is DailyCreditExhausted -> message
            // Un serveur déployé avant le 15/09/2026 répond encore « Erreur
            // interne du serveur. » : une phrase qui accuse sans dire à qui est
            // la panne. On la remplace par la sienne — le conseil, lui, vient de
            // `recoveryAdvice`.
            is Server ->
                if (statusCode >= 500 && message == "Erreur interne du serveur.") {
                    "Notre serveur a rencontré un problème inattendu."
                } else {
                    message
                }
            is Transport -> {
                val diagnostics = developerDiagnostics
                if (diagnostics != null) {
                    developerDiagnosis(error, url, diagnostics.runsInEmulator)
                } else {
                    "Connexion impossible. Vérifie ton réseau et réessaie."
                }
            }
            is Decoding ->
                if (developerDiagnostics != null) {
                    "Réponse inattendue du serveur.\n\n$error\n\n" +
                        "Le modèle Kotlin et `appSerializers.ts` ne disent plus la même " +
                        "chose. Compare le champ nommé ci-dessus avec ce que rend la " +
                        "route."
                } else {
                    "Réponse inattendue du serveur."
                }
        }

    /**
     * L'appel n'a **pas quitté l'appareil** — ou n'est jamais revenu. C'est la
     * seule erreur qui vaille un repli sur ce qu'on avait déjà : un 500 ou un
     * 404 sont des réponses, et une réponse mérite qu'on la montre.
     */
    val isTransport: Boolean get() = this is Transport

    /**
     * La panne est **du côté du serveur** — un 5xx —, pas de l'appareil ni de
     * la requête. C'est ce qui décide de proposer le support à côté de
     * « Réessayer » : contre un bogue de notre côté, réessayer ne suffit pas.
     */
    val isServerSide: Boolean get() = this is Server && statusCode >= 500

    /**
     * Le serveur a refusé faute de crédit du jour : ce n'est pas un échec,
     * c'est « demain ». Voir [DailyCreditExhausted].
     */
    val isDailyCreditExhausted: Boolean get() = this is DailyCreditExhausted

    /**
     * Le serveur a refusé un tour qu'aucune journée de crédit ne laissera
     * passer : ni un échec à réessayer, ni « demain » — l'illimité. Voir
     * [DAILY_CREDIT_TOO_LONG_CODE].
     */
    val isDailyCreditTooLong: Boolean get() = code == DAILY_CREDIT_TOO_LONG_CODE

    /**
     * Ce qu'on peut **faire**, sous la phrase qui dit ce qui s'est passé.
     *
     * Une erreur qui ne propose rien laisse chercher ce qu'on a mal fait — et
     * devant un 500, on n'a rien fait de mal. Chaque cas nomme donc à qui est
     * la panne et le geste qui a une chance : réessayer, se reconnecter,
     * revenir à l'accueil, nous écrire. `null` pour un refus du serveur qui
     * porte déjà son propre message (un 400, un 409). Hugo, 15/09/2026.
     *
     * L'ordre des branches est celui du `switch` d'iOS, et il compte.
     */
    val recoveryAdvice: String?
        get() = when {
            this is Server && statusCode >= 500 ->
                "Le problème vient de notre côté, pas du tien. Réessaie dans un instant ; si ça continue, écris-nous depuis « Besoin d’aide ? » et on répare."
            this is Server && statusCode == 404 ->
                "Ce voyage n’est plus sur ton compte, ou il a été supprimé : reviens à l’accueil pour le vérifier."
            // Le crédit du jour : ce qui a été raconté attend sur le téléphone,
            // et il n'y a rien d'autre à faire qu'attendre minuit — ou passer en
            // illimité.
            this is DailyCreditExhausted ->
                "Ce que tu as raconté est gardé sur ton téléphone et partira demain. Pour continuer tout de suite, passe en illimité depuis ton profil."
            // Plus long qu'une journée de crédit : demain ne suffira pas.
            this is Server && code == DAILY_CREDIT_TOO_LONG_CODE ->
                "Ce que tu as raconté est gardé sur ton téléphone. C’est plus long que le crédit d’une journée : passe en illimité pour l’envoyer."
            this is Server && statusCode == 429 && code == "chat_daily_cap" ->
                "Reviens demain, ou raconte la suite au clavier dans un autre carnet."
            // **Avant le cas générique des 403** : un 403 se traite d'ordinaire
            // par « reconnecte-toi », et celui-ci n'a rien à voir avec la
            // session. Le placer après ferait dire à l'app exactement le
            // contraire de ce qu'il faut faire.
            this is Server && statusCode == 403 && code == "owner_only" ->
                "Seul le propriétaire du voyage peut faire ça. Demande-lui, ou continue à raconter."
            (this is Server && (statusCode == 401 || statusCode == 403)) || this == NotAuthenticated ->
                "Reconnecte-toi pour continuer."
            this is Server -> null
            this is Transport -> "Vérifie ta connexion, puis réessaie."
            // Le Play Store et non l'App Store : la seule copie qui nomme la
            // boutique de la plateforme.
            else -> "Mets MemoBook à jour depuis le Play Store ; si ça continue, écris-nous depuis « Besoin d’aide ? »."
        }

    /** `true` quand réessayer a une chance d'aboutir. */
    val isRetryable: Boolean
        get() = when (this) {
            is Transport -> true
            is Server -> statusCode >= 500
            // Réessayer tout de suite retomberait sur le même refus : c'est la
            // file qui repart, d'elle-même, quand le crédit se recharge.
            NotAuthenticated, is Decoding, is DailyCreditExhausted -> false
        }

    /**
     * Le `#if DEBUG` d'iOS. Une bibliothèque Android ne sait pas si l'app est
     * en Debug — seule la cible `app` lit `BuildConfig` : c'est donc elle qui
     * pose ce réglage au lancement, en Debug seulement. `null` (le défaut, et
     * la Release) donne les phrases destinées à quelqu'un qui a l'app
     * installée.
     *
     * @property runsInEmulator Le `targetEnvironment(simulator)` d'iOS.
     */
    data class DeveloperDiagnostics(val runsInEmulator: Boolean)

    companion object {
        /** Posé par l'app en Debug, jamais en Release. Voir [DeveloperDiagnostics]. */
        @Volatile
        var developerDiagnostics: DeveloperDiagnostics? = null

        /**
         * Le code du refus faute de crédit du jour — le même que le serveur
         * (`services/dailyCredit.ts`).
         */
        const val DAILY_CREDIT_EXHAUSTED_CODE = "daily_credit_exhausted"

        /**
         * Le code du refus d'un tour **plus long qu'une journée entière** de
         * crédit — un vocal de plus de 5:03, un texte de plus de 4 000 caractères
         * (03/10/2026). Il arrive en [Server] : rien à porter d'autre que le
         * code, et la file le reconnaît par lui — voir [isDailyCreditTooLong].
         * Attendre demain n'y changerait rien : le tour attend l'illimité.
         */
        const val DAILY_CREDIT_TOO_LONG_CODE = "daily_credit_too_long"

        /**
         * Le refus d'un troisième changement de nombre de pages cible — `409`
         * (Hugo, 15/10/2026, `services/pageTarget.ts`). L'écran ne l'affiche pas
         * en erreur : il dit, à l'orange, que la cible ne bouge plus.
         */
        const val PAGE_TARGET_LIMIT_REACHED_CODE = "page_target_limit_reached"

        /**
         * La réécriture des étapes déjà écrites a déjà été faite pour ce
         * changement — `409`.
         */
        const val PAGE_TARGET_REWRITE_UNAVAILABLE_CODE = "page_target_rewrite_unavailable"

        /**
         * Ce qui a vraiment échoué, et quoi faire — **build de développement
         * seulement** (voir [developerDiagnostics]).
         *
         * « Connexion impossible. Vérifie ton réseau et réessaie. » est la bonne
         * phrase pour quelqu'un qui a l'app installée : il ne peut rien faire
         * d'autre que regarder son wifi. Sur un build branché sur le Mac, c'est
         * **la pire phrase possible** — elle envoie chercher du côté du réseau
         * un serveur qui n'est simplement pas lancé. On a déjà perdu deux fois
         * une demi-heure là-dessus.
         *
         * On nomme donc la panne, et on donne la commande qui la répare. Les
         * pannes de `java.net` remplacent les codes d'`URLError`.
         */
        fun developerDiagnosis(error: Throwable, url: URI?, runsInEmulator: Boolean): String {
            val target = url?.let { "${it.host ?: "?"}:${if (it.port == -1) 80 else it.port}" } ?: "le serveur"
            // `10.0.2.2` est le Mac vu de l'émulateur : le `localhost` du simulateur.
            val isLocal = url?.host in setOf("localhost", "127.0.0.1", "10.0.2.2")

            if (error !is IOException) {
                return "L’appel vers $target a échoué.\n\n$error"
            }

            return when (error) {
                is NoRouteToHostException -> "Pas de réseau. Là, c’est vraiment le wifi."

                // Sur un téléphone, `localhost` est le téléphone : ce n'est pas
                // le back-end qui manque, c'est l'adresse qui est fausse — et
                // relancer `npm run dev` n'y changerait rien. Le build ne doit
                // plus pouvoir l'embarquer (`ApiConfiguration.effective`) ; si
                // cette phrase s'affiche quand même, c'est le garde-fou qui a
                // sauté.
                is ConnectException, is UnknownHostException ->
                    if (isLocal && !runsInEmulator) {
                        "Ce build parle à $target depuis un téléphone — c’est-à-dire " +
                            "au téléphone lui-même.\n\n" +
                            "Un appareil doit viser la production, ou l’IP du Mac " +
                            "dans secrets.properties. Voir android/CLAUDE.md, " +
                            "§ Configurations et secrets."
                    } else if (isLocal) {
                        "Rien n’écoute sur $target.\n\n" +
                            "Le back-end n’est pas lancé :\n" +
                            "    cd backend && npm run dev\n\n" +
                            "Pour vérifier, dans un autre terminal :\n" +
                            "    curl -s -o /dev/null -w \"%{http_code}\\n\" " +
                            "localhost:3000/v1/showcases/welcome"
                    } else {
                        "Impossible de joindre $target."
                    }

                is InterruptedIOException ->
                    "$target n’a pas répondu à temps.\n\n" +
                        "Le serveur tourne mais bloque — souvent la base : vérifie que " +
                        "`DATABASE_URL` répond."

                is SocketException, is EOFException ->
                    "La connexion vers $target s’est coupée en cours de route.\n\n" +
                        "Le serveur est mort **pendant** la requête. Regarde la fin de " +
                        "sa sortie : c’est là qu’est la vraie erreur."

                is UnknownServiceException ->
                    "La politique réseau a bloqué l’appel en clair vers $target.\n\n" +
                        "`network_security_config.xml` doit couvrir cet hôte — voir " +
                        "`app/src/debug/res/xml/network_security_config.xml`."

                else -> "L’appel vers $target a échoué : ${error.localizedMessage}"
            }
        }
    }
}

/**
 * Corps d'erreur normalisé du back-end.
 *
 * `dailyCredit` n'accompagne que le refus `429 daily_credit_exhausted` : le
 * serveur pose les détails d'une erreur **à plat** dans le corps, à côté du
 * code et du message (`HttpError`, 03/10/2026).
 *
 * Lu champ par champ, chacun à son propre risque : un solde illisible ne doit
 * pas coûter le message, qui est destiné à l'utilisateur — la file retombe
 * alors sur le minuit suivant.
 */
internal class ApiErrorBody(
    val error: String?,
    val message: String?,
    val dailyCredit: DailyCredit?,
) {
    companion object {
        /** `null` quand le corps n'est pas un objet JSON — un 502 de proxy en HTML. */
        fun parse(data: ByteArray): ApiErrorBody? {
            val root: JsonObject = try {
                MemoBookJson.parseToJsonElement(data.toString(Charsets.UTF_8)).jsonObject
            } catch (_: IllegalArgumentException) {
                return null
            }
            fun string(key: String): String? =
                (root[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
            val credit = root["dailyCredit"]?.let { element ->
                try {
                    MemoBookJson.decodeFromJsonElement(DailyCredit.serializer(), element)
                } catch (_: IllegalArgumentException) {
                    null
                }
            }
            return ApiErrorBody(string("error"), string("message"), credit)
        }
    }
}
