package com.memobook.feature.auth

import com.memobook.core.Account
import com.memobook.core.EmailAddress
import com.memobook.core.PasswordRule
import com.memobook.networking.ApiError
import com.memobook.networking.MemoBookApi
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.util.UUID

/**
 * L'état de la feuille « Mot de passe oublié », et l'appel qui envoie
 * l'e-mail. Jumeau de `PasswordRecoveryModel.swift`.
 *
 * Un seul modèle pour toutes les étapes du parcours : la feuille change de
 * contenu, elle ne s'empile pas (voir `BrandSheet`). Chaque étape est un cas
 * de [Step], et c'est lui que la vue dessine.
 *
 * **Un objet par ouverture**, que l'écran d'entrée tient et jette avec la
 * feuille — pas un `ViewModel` : il ne vit que le temps d'un parcours, et ses
 * appels partent de la vue, comme les `Task` d'iOS.
 */
class PasswordRecoveryModel private constructor(
    private val api: MemoBookApi,
    initial: State,
) {
    /**
     * La feuille s'ouvre sur ce que le formulaire de connexion contenait déjà :
     * on ne fait pas retaper une adresse qu'on vient d'écrire.
     */
    constructor(api: MemoBookApi, email: String) : this(api, State(step = Step.Request, email = email))

    companion object {
        /**
         * La page ouverte **par le lien de l'e-mail**, directement sur le
         * nouveau mot de passe. L'adresse n'est pas connue ici — le lien ne la
         * porte pas, et n'a pas à la porter : le secret suffit.
         */
        fun forReset(api: MemoBookApi, resetToken: String): PasswordRecoveryModel =
            PasswordRecoveryModel(api, State(step = Step.Reset(resetToken), email = ""))

        /** Le code du serveur pour « aucun compte à cette adresse » — voir `backend/src/services/passwordReset.ts`. */
        const val unknownAccountCode = "unknown_account"

        /**
         * Un serveur muet ou en panne se dit avec les mots de la maquette ; tout
         * le reste garde le libellé qu'il porte, déjà en français.
         */
        private fun message(error: Throwable): String {
            if (error is ApiError) {
                if (error is ApiError.Server && error.statusCode >= 500) return AuthModel.unavailableMessage
                if (error.isTransport && ApiError.developerDiagnostics == null) return AuthModel.unavailableMessage
            }
            return authErrorMessage(error)
        }
    }

    /**
     * Une identité par ouverture de la feuille : c'est ce qui la présente
     * (`BrandSheetHost(item:)`), et ce qui garantit qu'une seconde ouverture
     * repart d'un modèle neuf.
     */
    val id: UUID = UUID.randomUUID()

    /** Où en est le parcours. */
    sealed interface Step {
        /** L'adresse, à confirmer ou corriger, et « Continuer ». */
        data object Request : Step

        /** L'e-mail est parti pour `email` : il n'y a plus qu'à l'ouvrir. */
        data object Sent : Step

        /** Le lien de l'e-mail a été ouvert : le nouveau mot de passe, deux fois, et le secret qui l'accompagnera. */
        data class Reset(val token: String) : Step
    }

    data class State(
        val step: Step,
        val email: String,
        val password: String = "",
        val passwordConfirmation: String = "",
        /** Message d'échec, sous le bouton. Nul quand tout va bien. */
        val errorMessage: String? = null,
        /**
         * L'adresse que le serveur a refusée parce qu'aucun compte n'y répond,
         * telle qu'il l'a cherchée (normalisée). C'est elle que la feuille écrit
         * en rouge, avec la porte vers l'inscription. Nul le reste du temps.
         */
        val unknownEmail: String? = null,
        /**
         * L'appel est parti : le bouton tourne, et la feuille ne se referme plus
         * au glissé — une demande envoyée à moitié n'a pas de sens.
         */
        val isWorking: Boolean = false,
    ) {
        /** La règle vit dans [PasswordRule] : l'inscription pose la même. */
        val isPasswordValid: Boolean get() = PasswordRule.isValid(password)

        val passwordsMatch: Boolean get() = password == passwordConfirmation

        /** Même phrase que l'inscription, une fois qu'il y a de quoi juger. */
        val passwordConfirmationError: String?
            get() = if (passwordConfirmation.isEmpty() || passwordsMatch) null else AuthModel.passwordMismatchMessage

        val canSave: Boolean get() = isPasswordValid && passwordsMatch && !isWorking

        val isUnknownAccount: Boolean get() = unknownEmail != null

        /** La règle vit dans [EmailAddress] : une seule copie pour toute l'app. */
        val canSubmit: Boolean get() = EmailAddress.isValid(email) && !isWorking && !isUnknownAccount
    }

    private val _state = MutableStateFlow(initial)
    val state: StateFlow<State> = _state.asStateFlow()

    // MARK: - Nouveau mot de passe

    var password: String
        get() = _state.value.password
        set(value) = _state.update { if (it.password == value) it else it.copy(password = value, errorMessage = null) }

    var passwordConfirmation: String
        get() = _state.value.passwordConfirmation
        set(value) = _state.update {
            if (it.passwordConfirmation == value) it else it.copy(passwordConfirmation = value, errorMessage = null)
        }

    /**
     * Enregistre le nouveau mot de passe. Réussite : la session est ouverte,
     * le compte est rendu et l'app entre. Échec : le message est posé — dont
     * « ce lien n'est plus valable », qui renvoie à l'étape de l'adresse.
     */
    suspend fun resetPassword(): Account? {
        val current = _state.value
        val step = current.step as? Step.Reset ?: return null
        if (!current.canSave) return null
        _state.update { it.copy(isWorking = true, errorMessage = null) }
        return try {
            api.resetPassword(token = step.token, password = current.password).account
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            _state.update { it.copy(errorMessage = message(error)) }
            null
        } finally {
            _state.update { it.copy(isWorking = false) }
        }
    }

    /**
     * « Ce lien n'est plus valable » : la seule issue est d'en redemander un.
     * On repart de l'adresse, champs et message effacés — l'étape est neuve.
     */
    fun startOver() {
        _state.update { it.copy(password = "", passwordConfirmation = "", errorMessage = null, step = Step.Request) }
    }

    // MARK: - L'adresse

    /**
     * Corriger l'adresse efface ce qu'on lui reprochait — même règle que le
     * formulaire d'entrée. Le refus « aucun compte » aussi : la feuille
     * redevient alors celle du départ, avec « Continuer ».
     */
    var email: String
        get() = _state.value.email
        set(value) = _state.update {
            if (it.email == value) it else it.copy(email = value, errorMessage = null, unknownEmail = null)
        }

    /**
     * Demande l'e-mail. Réussite : la feuille passe à [Step.Sent]. Échec : le
     * message est posé, l'étape ne bouge pas.
     */
    suspend fun submit() {
        val current = _state.value
        if (!current.canSubmit) return
        _state.update { it.copy(isWorking = true, errorMessage = null) }
        try {
            api.requestPasswordReset(email = current.email.trim())
            _state.update { it.copy(step = Step.Sent) }
        } catch (error: CancellationException) {
            throw error
        } catch (error: ApiError.Server) {
            if (error.statusCode == 404 && error.code == unknownAccountCode) {
                // Le serveur a normalisé l'adresse ; on garde la nôtre, telle
                // qu'elle est écrite dans le champ, pour que la phrase rouge et
                // le champ disent la même chose.
                _state.update { it.copy(unknownEmail = current.email.trim()) }
            } else {
                _state.update { it.copy(errorMessage = message(error)) }
            }
        } catch (error: Exception) {
            _state.update { it.copy(errorMessage = message(error)) }
        } finally {
            _state.update { it.copy(isWorking = false) }
        }
    }
}
