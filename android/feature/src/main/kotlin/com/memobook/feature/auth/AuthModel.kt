package com.memobook.feature.auth

import androidx.lifecycle.ViewModel
import com.memobook.core.Account
import com.memobook.core.AuthProvider
import com.memobook.core.AuthSession
import com.memobook.core.EmailAddress
import com.memobook.core.PasswordRule
import com.memobook.core.ProfileEdit
import com.memobook.core.Some
import com.memobook.feature.AppSettings
import com.memobook.networking.ApiError
import com.memobook.networking.MemoBookApi
import com.memobook.networking.SocialSignIn
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.time.Duration
import java.time.Instant

/**
 * L'état du formulaire d'entrée, et les règles qui décident si « Continuer »
 * est actif. Jumeau de `AuthModel.swift`.
 *
 * La validation vit ici plutôt que dans la vue pour être testable sans
 * émulateur — c'est la seule partie de cet écran qui porte des règles.
 *
 * L'appel réseau vit ici aussi : c'est ce qui permet à la vue de ne connaître
 * que trois choses — un état en cours, un message d'erreur, et une réussite.
 *
 * Les champs s'écrivent par leurs propriétés (`model.email = …`), l'écran lit
 * tout par [state]. Les appels sont des fonctions `suspend` qui rendent le
 * compte, comme les `async` d'iOS : la vue les lance et entre quand ils rendent
 * autre chose que `null`.
 *
 * @param settings là où [SocialIdentityStore] garde ce qu'Apple ne dit qu'une
 *   fois — l'`UserDefaults.standard` d'iOS.
 */
class AuthModel(
    private val api: MemoBookApi,
    private val settings: AppSettings,
) : ViewModel() {
    /** Tout ce que l'écran dessine. Les règles se lisent dessus. */
    data class State(
        val mode: AuthMode = AuthMode.SignUp,
        val firstName: String = "",
        val lastName: String = "",
        val email: String = "",
        val password: String = "",
        val passwordConfirmation: String = "",
        /**
         * Ce que le serveur reproche à **l'adresse**, affiché sous son champ et
         * non sous le bouton : c'est la ligne qu'il faut changer. Aujourd'hui un
         * seul cas, l'adresse déjà prise. Voir [report].
         */
        val emailError: String? = null,
        /** Message d'échec affiché sous les boutons. Nul quand tout va bien. */
        val errorMessage: String? = null,
        /** Un appel est en cours : les boutons se figent, « Continuer » tourne. */
        val isWorking: Boolean = false,
        /**
         * Le compte qui vient d'être ouvert par Apple ou Google, et dont il reste
         * à **vérifier le prénom et le nom** avant d'entrer. `null` le reste du
         * temps. Voir [SocialCompletionView].
         */
        val completing: Account? = null,
    ) {
        /** La règle vit dans [PasswordRule] : le nouveau mot de passe après « Mot de passe oublié » la pose aussi. */
        val isPasswordValid: Boolean get() = PasswordRule.isValid(password)

        /** La règle vit dans [EmailAddress] : le profil la pose aussi, et deux copies auraient fini par diverger. */
        val isEmailValid: Boolean get() = EmailAddress.isValid(email)

        val passwordsMatch: Boolean get() = password == passwordConfirmation

        /** Ce que « Continuer » attend pour s'allumer. */
        val canSubmit: Boolean
            get() = when (mode) {
                AuthMode.SignUp ->
                    firstName.trim().isNotEmpty() &&
                        lastName.trim().isNotEmpty() &&
                        isEmailValid &&
                        isPasswordValid &&
                        passwordsMatch
                AuthMode.SignIn -> isEmailValid && password.isNotEmpty()
            }

        /**
         * Message affiché sous la confirmation, une fois qu'il y a de quoi juger.
         *
         * La phrase de la maquette (`Sign Up Filled`, `3390:10812`), au
         * tutoiement près : elle écrivait « Vérifiez votre saisie », et R9 ne
         * souffre pas d'exception — voir T9.
         */
        val passwordConfirmationError: String?
            get() = if (passwordConfirmation.isEmpty() || passwordsMatch) null else passwordMismatchMessage

        val canCompleteProfile: Boolean
            get() = firstName.trim().isNotEmpty() && lastName.trim().isNotEmpty()
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    var mode: AuthMode
        get() = _state.value.mode
        set(value) = _state.update { it.copy(mode = value) }

    var firstName: String
        get() = _state.value.firstName
        set(value) = _state.update { it.copy(firstName = value) }

    var lastName: String
        get() = _state.value.lastName
        set(value) = _state.update { it.copy(lastName = value) }

    /**
     * Corriger l'adresse efface ce qu'on lui reprochait : le message ne parle
     * plus de ce qui est écrit.
     */
    var email: String
        get() = _state.value.email
        set(value) = _state.update { if (it.email == value) it else it.copy(email = value, emailError = null) }

    var password: String
        get() = _state.value.password
        set(value) = _state.update { it.copy(password = value) }

    var passwordConfirmation: String
        get() = _state.value.passwordConfirmation
        set(value) = _state.update { it.copy(passwordConfirmation = value) }

    // MARK: - Envoyer

    /**
     * Envoie le formulaire — inscription ou connexion selon le mode.
     *
     * @return le compte, quand la session est ouverte. `null` si l'appel a
     *   échoué : le message est alors dans [State.errorMessage].
     */
    suspend fun submit(): Account? = openSession {
        val form = _state.value
        when (form.mode) {
            AuthMode.SignUp -> api.signUp(
                email = form.email.trim(),
                password = form.password,
                firstName = form.firstName.trim(),
                lastName = form.lastName.trim(),
            )
            AuthMode.SignIn -> api.signIn(email = form.email.trim(), password = form.password)
        }
    }

    // MARK: - Fournisseurs tiers

    /**
     * Un fournisseur a donné son accord ; reste à le faire vérifier.
     *
     * **Important** : à ce stade l'utilisateur n'est **pas** authentifié. Le
     * jeton n'est qu'une affirmation tant que le serveur ne l'a pas vérifié
     * contre les clés publiques du fournisseur.
     */
    suspend fun accept(credential: SocialCredential): Account? {
        // Avant toute chose, avant même le réseau : le nom et l'adresse d'Apple
        // ne repasseront jamais. Si l'appel échoue, ils sont quand même gardés
        // pour la tentative suivante.
        SocialIdentityStore.remember(credential, settings)
        val known = SocialIdentityStore.identity(credential, settings)

        val first = credential.firstName ?: known?.firstName
        val last = credential.lastName ?: known?.lastName
        val address = credential.email ?: known?.email
        _state.update { form ->
            form.copy(
                firstName = first ?: form.firstName,
                lastName = last ?: form.lastName,
                email = address ?: form.email,
            )
        }

        return openSession {
            api.signIn(
                with = SocialSignIn(
                    provider = credential.provider.apiProvider,
                    identityToken = credential.identityToken,
                    nonce = credential.nonce,
                    firstName = first,
                    lastName = last,
                ),
            )
        }
    }

    /**
     * Traduit un échec en phrase, **et la pose au bon endroit**.
     *
     * Trois cas, ceux que la maquette dessine (T9) : l'adresse déjà prise va
     * sous le champ de l'adresse ; un serveur muet ou en panne dit qu'il est
     * indisponible ; tout le reste garde le libellé qu'il porte — le
     * back-end écrit déjà les siens en français.
     */
    fun report(error: Throwable) {
        if (error is ApiError) {
            if (error is ApiError.Server && error.statusCode == 409) {
                _state.update { it.copy(emailError = emailTakenMessage) }
                return
            }
            if (error is ApiError.Server && error.statusCode >= 500) {
                _state.update { it.copy(errorMessage = unavailableMessage) }
                return
            }
            // En développement, le transport garde son diagnostic — il nomme
            // le serveur qui ne tourne pas et donne la commande. Livré, la
            // panne se dit avec les mots de la maquette. Le `#if !DEBUG`
            // d'iOS : le diagnostic n'est posé qu'en Debug (`MemoBookApplication`).
            if (error.isTransport && ApiError.developerDiagnostics == null) {
                _state.update { it.copy(errorMessage = unavailableMessage) }
                return
            }
        }
        _state.update { it.copy(errorMessage = authErrorMessage(error)) }
    }

    // MARK: - Compléter ce qu'un fournisseur a donné

    /**
     * Faut-il passer par la page de compléments ?
     *
     * Oui pour un compte **neuf** — la maquette (`2707:9456`) demande de
     * vérifier ce qu'on a récupéré, même quand tout y est —, et pour un compte
     * auquel il manque encore un prénom ou un nom. Une reconnexion sur un
     * compte complet passe tout droit. Un compte est neuf quand il vient
     * d'être créé : le serveur ne le dit pas autrement que par sa date.
     */
    fun needsCompletion(account: Account, now: Instant = Instant.now()): Boolean {
        val isFresh = Duration.between(account.createdAt, now) < Duration.ofSeconds(120)
        val isMissingName = listOf(account.firstName, account.lastName).any { it.orEmpty().trim().isEmpty() }
        return isFresh || isMissingName
    }

    /**
     * Ouvre la page de compléments, préremplie de ce que le fournisseur a
     * donné : le compte d'abord, puis ce que l'app avait retenu d'une première
     * autorisation (Apple ne redonne jamais le nom).
     */
    fun beginCompletion(account: Account) {
        _state.update { form ->
            form.copy(
                firstName = account.firstName?.takeIf { it.trim().isNotEmpty() } ?: form.firstName,
                lastName = account.lastName?.takeIf { it.trim().isNotEmpty() } ?: form.lastName,
                email = account.email ?: form.email,
                errorMessage = null,
                completing = account,
            )
        }
    }

    /**
     * Enregistre le prénom et le nom vérifiés, et rend le compte à jour.
     *
     * `null` si l'appel a échoué : le message est dans [State.errorMessage] et
     * la page reste ouverte. Le compte, lui, existe déjà — c'est le profil
     * qu'on corrige, par la route qu'emploie l'écran de profil.
     */
    suspend fun completeProfile(): Account? {
        val form = _state.value
        val account = form.completing ?: return null
        if (form.isWorking) return null
        _state.update { it.copy(isWorking = true, errorMessage = null) }
        val firstName = form.firstName.trim()
        val lastName = form.lastName.trim()
        return try {
            // Le profil renvoyé ne porte que le nom composé (`fullName`) : ce
            // qu'on vient d'envoyer est la vérité la plus fraîche.
            api.updateProfile(ProfileEdit(firstName = Some(firstName), lastName = Some(lastName)))
            _state.update { it.copy(completing = null) }
            account.copy(firstName = firstName, lastName = lastName)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            report(error)
            null
        } finally {
            _state.update { it.copy(isWorking = false) }
        }
    }

    // MARK: - Compte de test

    /**
     * Entre dans l'app par le compte de test — **une vraie connexion**, pas
     * un compte inventé.
     *
     * Le bouton fabriquait jusqu'ici un `Account` de toutes pièces. Il
     * ouvrait bien l'accueil, mais sans session : chaque écran derrière
     * tombait alors sur un 401, et on croyait à un bug d'écran. Ici, la
     * session est celle du serveur, avec les voyages et le profil du seed.
     *
     * Le `#if DEBUG` d'iOS : seul un build débogable montre le bouton qui
     * l'appelle (`WelcomeView`).
     */
    suspend fun signInAsTestAccount(): Account? = openSession {
        api.signIn(email = testAccountEmail, password = testAccountPassword)
    }

    /**
     * Le même enrobage pour les trois chemins d'entrée : un seul appel à la
     * fois, l'erreur précédente effacée, et le message traduit en cas d'échec.
     */
    private suspend fun openSession(work: suspend () -> AuthSession): Account? {
        if (_state.value.isWorking) return null
        _state.update { it.copy(isWorking = true, errorMessage = null, emailError = null) }
        return try {
            work().account
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            report(error)
            null
        } finally {
            _state.update { it.copy(isWorking = false) }
        }
    }

    // MARK: - Clavier

    /** Champ suivant dans l'enchaînement du clavier, ou `null` s'il faut valider. */
    fun fieldAfter(field: AuthField): AuthField? = when (mode) {
        AuthMode.SignUp -> when (field) {
            AuthField.FirstName -> AuthField.LastName
            AuthField.LastName -> AuthField.Email
            AuthField.Email -> AuthField.Password
            AuthField.Password -> AuthField.PasswordConfirmation
            AuthField.PasswordConfirmation -> null
        }
        AuthMode.SignIn -> when (field) {
            AuthField.Email -> AuthField.Password
            else -> null
        }
    }

    companion object {
        /** Partagé avec le nouveau mot de passe de « Mot de passe oublié ». */
        const val passwordMismatchMessage = "Les deux mots de passe sont différents. Vérifie ta saisie."

        /**
         * Un compte existe déjà avec cette adresse. La phrase de la maquette
         * (`3394:10929`), au tutoiement près — elle écrivait « Connectez-vous ou
         * utilisez » (T9).
         */
        const val emailTakenMessage =
            "Cette adresse e-mail est déjà associée à un compte. Connecte-toi ou utilise une autre adresse."

        /**
         * Le serveur ne répond pas, ou répond qu'il est en panne. La phrase de la
         * maquette (`3405:10991`), au tutoiement près — « veuillez réessayer ».
         */
        const val unavailableMessage = "MemoBook est actuellement indisponible, réessaie plus tard."

        /**
         * Le compte de test de l'app, celui que `backend/prisma/seed.ts` pose
         * et tient à jour.
         *
         * **Le mot de passe n'est pas un secret** : il n'ouvre qu'un compte de
         * démonstration, il est écrit dans le seed et dans `docs/supabase.md`.
         */
        internal const val testAccountEmail = "demo@memo-book.com"
        internal const val testAccountPassword = "memobook2026"
    }
}

private val SocialCredential.Provider.apiProvider: AuthProvider
    get() = when (this) {
        SocialCredential.Provider.Apple -> AuthProvider.Apple
        SocialCredential.Provider.Google -> AuthProvider.Google
    }
