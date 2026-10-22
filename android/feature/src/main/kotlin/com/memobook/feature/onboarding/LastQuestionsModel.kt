package com.memobook.feature.onboarding

import androidx.lifecycle.ViewModel
import com.memobook.core.Account
import com.memobook.core.CalendarDay
import com.memobook.core.ProfileEdit
import com.memobook.core.Some
import com.memobook.feature.AppSettings
import com.memobook.networking.ApiError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.time.Duration
import java.time.Instant

/**
 * Les « Dernières questions » : ce qu'on demande à quelqu'un qui entre pour
 * la première fois — son nom, sa date de naissance, son numéro WhatsApp —
 * avant l'accueil (Clara, 26/09/2026). Jumeau de `LastQuestionsModel.swift`.
 *
 * **Trois écrans, un seul modèle**, parce que c'est un seul geste : chaque
 * écran se valide ou se passe, et l'on avance. Ce qui est validé part tout de
 * suite au profil (`PATCH /v1/profile`) plutôt qu'à la fin : quelqu'un qui
 * referme l'app au deuxième écran a quand même donné son nom.
 *
 * Le modèle ne connaît pas l'API : il reçoit une fonction qui écrit le profil,
 * comme `ProfileModel`. Les aperçus n'en donnent aucune.
 */
class LastQuestionsModel(
    private val account: Account,
    private val save: (suspend (ProfileEdit) -> Unit)? = null,
) : ViewModel() {
    enum class Step {
        Name,
        BirthDate,
        Phone,
        ;

        val previous: Step? get() = entries.getOrNull(ordinal - 1)
        val next: Step? get() = entries.getOrNull(ordinal + 1)
    }

    data class State(
        val step: Step = Step.Name,
        val lastName: String = "",
        val firstName: String = "",
        /** Ce qu'on tape, `JJ/MM/AAAA` — les barres se posent toutes seules. */
        val birthDateText: String = "",
        val phoneNumber: String = "",
        val isSaving: Boolean = false,
        val errorMessage: String? = null,
    ) {
        // MARK: Ce que « Valider » attend

        val canValidate: Boolean
            get() = when (step) {
                Step.Name -> lastName.trim().isNotEmpty() && firstName.trim().isNotEmpty()
                Step.BirthDate -> birthDate?.isPlausibleBirthDate() == true
                Step.Phone -> phoneNumber.count { it.isDigit() } in 7..15
            }

        /** La date tapée, quand elle est complète et qu'elle existe. */
        val birthDate: CalendarDay? get() = CalendarDay.fromSlashed(birthDateText)

        /**
         * Ce qu'on dit sous le champ de la date, quand elle est complète mais
         * impossible — le 31 juin, une naissance dans le futur.
         */
        val birthDateProblem: String?
            get() {
                if (step != Step.BirthDate || birthDateText.length != 10) return null
                return if (canValidate) null else LastQuestionsCopy.invalidBirthDate
            }

        /**
         * Il y a un écran avant celui-ci : la flèche s'affiche, le glissé vers
         * la droite y ramène.
         */
        val canGoBack: Boolean get() = step.ordinal > 0

        /**
         * Rien n'a été tapé sur cet écran. Un prénom venu d'Apple ou de Google
         * compte comme tapé : il est dans le champ, sous les yeux.
         */
        val isStepUntouched: Boolean
            get() = when (step) {
                Step.Name -> lastName.trim().isEmpty() && firstName.trim().isEmpty()
                Step.BirthDate -> birthDateText.isEmpty()
                Step.Phone -> phoneNumber.trim().isEmpty()
            }
    }

    private val _state = MutableStateFlow(State(lastName = account.lastName.orEmpty(), firstName = account.firstName.orEmpty()))
    val state: StateFlow<State> = _state.asStateFlow()

    var lastName: String
        get() = _state.value.lastName
        set(value) = _state.update { it.copy(lastName = value) }

    var firstName: String
        get() = _state.value.firstName
        set(value) = _state.update { it.copy(firstName = value) }

    /** Ce qu'on tape, `JJ/MM/AAAA` — les barres se posent toutes seules. */
    var birthDateText: String
        get() = _state.value.birthDateText
        set(value) = _state.update { it.copy(birthDateText = maskedBirthDate(value)) }

    var phoneNumber: String
        get() = _state.value.phoneNumber
        set(value) = _state.update { it.copy(phoneNumber = value) }

    // MARK: - Avancer

    /**
     * Enregistre ce que l'écran demande, puis avance.
     *
     * @return le compte à jour quand c'était le dernier écran — l'app entre
     *   alors dans l'accueil —, `null` sinon, ou si l'enregistrement a échoué
     *   (le message est dans [State.errorMessage], et l'écran reste).
     */
    suspend fun validate(): Account? {
        val current = _state.value
        if (!current.canValidate || current.isSaving) return null
        _state.update { it.copy(isSaving = true, errorMessage = null) }
        try {
            save?.invoke(edit(current))
        } catch (error: CancellationException) {
            _state.update { it.copy(isSaving = false) }
            throw error
        } catch (error: Exception) {
            _state.update { it.copy(isSaving = false, errorMessage = describe(error)) }
            return null
        }
        _state.update { it.copy(isSaving = false) }
        return advance()
    }

    /** « Passer » : rien n'est enregistré, et l'on avance. */
    fun skip(): Account? {
        _state.update { it.copy(errorMessage = null) }
        return advance()
    }

    /**
     * La flèche de retour, et le glissé vers la droite. `false` depuis le
     * premier écran : il n'y a pas d'écran avant — et l'écran n'y montre plus
     * de flèche (T192, Hugo, 06/10/2026) : elle ramenait à l'entrée, donc
     * refermait la session qu'on venait d'ouvrir.
     */
    fun goBack(): Boolean {
        val previous = _state.value.step.previous ?: return false
        _state.update { it.copy(errorMessage = null, step = previous) }
        return true
    }

    /**
     * Le glissé vers la gauche — l'illustration qu'on feuillette, comme à la
     * création d'un voyage (Hugo, 06/10/2026).
     *
     * Il vaut « Valider » quand l'écran est rempli, et « Passer » quand on n'y
     * a rien tapé : chaque question se passe, et un doigt qui glisse sur un
     * écran vide veut aller plus loin. **Un écran à moitié rempli ne bouge
     * pas** : le passer jetterait en silence ce qu'on vient de taper — le
     * bouton gris dit déjà ce qui manque.
     *
     * @return comme [validate] — le compte à jour après le dernier écran, `null` sinon.
     */
    suspend fun swipeForward(): Account? {
        val current = _state.value
        if (current.isSaving) return null
        if (current.canValidate) return validate()
        if (current.isStepUntouched) return skip()
        return null
    }

    private fun advance(): Account? {
        val next = _state.value.step.next
        if (next != null) {
            _state.update { it.copy(step = next) }
            return null
        }
        return updatedAccount
    }

    private fun edit(state: State): ProfileEdit = when (state.step) {
        Step.Name -> ProfileEdit(firstName = Some(state.firstName.trim()), lastName = Some(state.lastName.trim()))
        Step.BirthDate -> ProfileEdit(birthDate = Some(state.birthDate))
        Step.Phone -> ProfileEdit(phoneNumber = Some(state.phoneNumber.trim()))
    }

    /** Le compte tel que l'accueil doit le connaître : avec le prénom qu'on vient de confirmer. */
    private val updatedAccount: Account
        get() {
            val current = _state.value
            return account.copy(
                firstName = current.firstName.trim().ifEmpty { null } ?: account.firstName,
                lastName = current.lastName.trim().ifEmpty { null } ?: account.lastName,
            )
        }

    /** Le `localizedDescription` d'iOS : la phrase de l'API, déjà en français. */
    private fun describe(error: Throwable): String =
        (error as? ApiError)?.errorDescription ?: error.localizedMessage ?: error.toString()

    companion object {
        private const val ANSWERED_KEY_PREFIX = "lastQuestionsAnswered."

        // MARK: - Qui les voit

        /**
         * Faut-il poser ces questions à ce compte ?
         *
         * Oui pour un compte **qui vient d'être ouvert** — le serveur ne le dit
         * pas autrement que par sa date — et une seule fois par compte sur cet
         * appareil : passer les trois écrans, c'est avoir répondu. Dix minutes et
         * non deux : l'horloge du téléphone et celle du serveur ne sont pas
         * toujours d'accord.
         */
        fun shouldAsk(account: Account, settings: AppSettings, now: Instant = Instant.now()): Boolean {
            if (settings.getBoolean(ANSWERED_KEY_PREFIX + account.id)) return false
            return Duration.between(account.createdAt, now) < Duration.ofMinutes(10)
        }

        /** Ne plus jamais les poser à ce compte, sur cet appareil. */
        fun markAnswered(account: Account, settings: AppSettings) {
            settings.putBoolean(ANSWERED_KEY_PREFIX + account.id, true)
        }

        // MARK: - La date, à la frappe

        /**
         * `JJ/MM/AAAA`, à partir de ce qui a été tapé : seuls les chiffres
         * comptent, huit au plus, et les barres se posent derrière le jour et le
         * mois. On corrige en effaçant, on ne bute jamais sur une barre.
         */
        fun maskedBirthDate(raw: String): String {
            val digits = raw.filter { it.isDigit() }.take(8)
            return buildString {
                digits.forEachIndexed { index, digit ->
                    if (index == 2 || index == 4) append('/')
                    append(digit)
                }
            }
        }
    }
}

/**
 * Les mots des trois écrans, recopiés des nœuds « Dernières questions »
 * (`3533:14979`, `3533:15036`, `3533:15010`) — sauf ce que Hugo a corrigé le
 * 06/10/2026 : les majuscules à la française dans les titres (T191),
 * « WhatsApp » avec sa casse de marque, le repère « JJ/MM/AAAA » au lieu de
 * « XX/XX/XXXX », et les noms des champs au lieu de « Margaux » et « Dupont ».
 */
object LastQuestionsCopy {
    const val skip = "Passer"
    const val validate = "Valider"

    const val nameTitle = "Ton nom et prénom"

    /**
     * Les intitulés des deux champs : au repos, ils sont le texte gris du
     * cadre ; au focus, ils montent sur son contour — comme à l'inscription.
     */
    const val firstNameLabel = "Prénom"
    const val lastNameLabel = "Nom"

    const val birthDateTitle = "Ta date de naissance"
    const val birthDateLabel = "Date de naissance"
    const val birthDatePlaceholder = "JJ/MM/AAAA"

    const val phoneTitle = "Ton numéro WhatsApp"
    const val phoneLabel = "Numéro WhatsApp"
    const val phonePlaceholder = "+33 0 00 00 00 00"

    /** Pas dans la maquette : ce qu'on dit d'une date complète qui n'existe pas. */
    const val invalidBirthDate = "Cette date n’existe pas. Vérifie le jour, le mois et l’année."

    object Voice {
        /**
         * Le format de la date, que TalkBack ne peut pas lire dans le repère
         * gris (il est caché) : il l'entend en indice.
         */
        const val birthDateHint = "Jour, mois et année"

        fun progress(step: Int, count: Int): String = "Question $step sur $count"
    }
}
