package com.memobook.feature.order

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.memobook.core.BookPreview
import com.memobook.core.DayRange
import com.memobook.core.NewPrintOrderRequest
import com.memobook.core.OrderContext
import com.memobook.core.OrderCopy
import com.memobook.core.OrderPayment
import com.memobook.core.OrderQuote
import com.memobook.core.OrderSettlement
import com.memobook.core.OrderStep
import com.memobook.core.PaymentIntentTicket
import com.memobook.core.PlacedPrintOrder
import com.memobook.core.PrintOrder
import com.memobook.core.PrintOrderDraft
import com.memobook.core.PrintOrderStatus
import com.memobook.core.PrintedCopyOption
import com.memobook.core.PrintedCopyOptions
import com.memobook.core.ResumedOrderPayment
import com.memobook.core.ShippingAddress
import com.memobook.core.ShippingSpeed
import com.memobook.networking.ApiError
import com.memobook.payments.PaymentOutcome
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.net.URI
import kotlin.time.Duration.Companion.seconds

/**
 * Ce que le tunnel de commande sait faire : porter les sept étapes, tenir le
 * brouillon, et demander au serveur ce qu'il est le seul à savoir — les prix.
 * Jumeau de `Order/OrderModel.swift`.
 *
 * Comme `HomeModel` et `ProfileModel`, il ne connaît pas `MemoBookApi` : il
 * reçoit des fonctions. L'app y branche les routes ([orderModel]), les aperçus
 * n'en fournissent aucune et tombent sur le jeu d'essai — c'est ce qui montre
 * les sept étapes sans serveur.
 *
 * @param email l'adresse à laquelle la confirmation partira, pour la dernière
 *   phrase de l'écran de confirmation. `null` quand le compte n'en a pas.
 * @param presentPayment qui ouvre la feuille de paiement. Une fonction et non le
 *   SDK : les aperçus en passent une qui n'appelle personne.
 * @param reloadOrder relit la commande auprès du serveur. `null` dans les
 *   aperçus, qui n'ont pas de serveur à qui demander — la commande y est réglée
 *   d'avance.
 * @param resumePayment rouvre la feuille sur **la même** intention, et
 *   [cancelOrder] abandonne un brouillon qui ne correspond plus — voir [pay].
 *   `null` en aperçu.
 */
class OrderModel(
    private val memoId: String,
    email: String? = null,
    context: suspend (String) -> OrderContext = { OrderContext.fixture },
    quote: suspend (String, Int, ShippingSpeed) -> OrderQuote = { _, copies, speed ->
        OrderQuote.fixture(copies = copies, speed = speed)
    },
    submit: suspend (String, NewPrintOrderRequest) -> PlacedPrintOrder = { memoId, request ->
        // Le jeu d'essai répond comme le serveur à une commande sans rendu :
        // c'est ce qui montre la notice dans le bac à sable.
        if (request.renderId == null) {
            throw ApiError.Server(statusCode = 409, code = MISSING_RENDER_CODE, message = OrderCopy.Payment.noRender)
        }
        PlacedPrintOrder.fixture(memoId = memoId, request = request)
    },
    shareLink: suspend (String) -> URI = { memoId -> URI(BookPreview.sampleShareLink(memoId)) },
    setWhatsApp: suspend (String, String?) -> PrintOrder = { _, _ ->
        PrintOrder.fixture(memoId = "preview", request = NewPrintOrderRequest.previewRequest)
    },
    presentPayment: suspend (PaymentIntentTicket) -> PaymentOutcome = { PaymentOutcome.Succeeded },
    private val reloadOrder: (suspend (String) -> PrintOrder)? = null,
    private val resumePayment: (suspend (String) -> ResumedOrderPayment)? = null,
    private val cancelOrder: (suspend (String) -> PrintOrder)? = null,
) : ViewModel() {
    private val loadContext = context
    private val loadQuote = quote
    private val submitOrder = submit
    private val requestShareLink = shareLink
    private val saveWhatsApp = setWhatsApp
    private val openPayment = presentPayment

    /** Où en est le chargement de ce que les sept étapes lisent. */
    sealed interface Phase {
        /**
         * La page est dessinée, ses valeurs ne sont pas encore arrivées : les
         * squelettes tiennent leur place. **L'écran ne disparaît jamais.**
         */
        data object Loading : Phase

        data object Ready : Phase

        /**
         * Le contexte n'est pas venu. L'écran garde son en-tête et propose de
         * réessayer — jamais un mur d'erreur.
         */
        data class Failed(val message: String) : Phase
    }

    /** Le couple dont le montant dépend : les exemplaires et la rapidité. */
    data class QuoteKey(val copies: Int, val speed: ShippingSpeed)

    /**
     * @property isAdvancing le sens du dernier changement d'étape. C'est lui qui
     *   décide du côté par lequel la nouvelle étape entre — sans quoi un retour
     *   se jouerait comme une avance, et le geste ne raconterait plus rien.
     * @property quotes le récapitulatif, par couple (exemplaires, rapidité).
     *   **Un cache et non une valeur** : revenir de l'étape 5 à l'étape 3 puis
     *   repartir en avant ne doit pas rappeler le serveur pour la même réponse.
     *   La clé porte les deux seuls choix dont le montant dépend.
     * @property order la commande passée. C'est elle qui remplit l'écran de
     *   confirmation.
     * @property paymentError ce qui a empêché de payer. Affiché **dans l'étape
     *   du paiement**, là où se corrige le choix — pas en haut d'un écran qu'on
     *   vient de quitter.
     * @property isMissingRender « Payer » a été touché sur un carnet qu'aucune
     *   composition n'a rendu — voir `OrderCopy.Payment.noRender`. Ce n'est pas
     *   une panne : rien n'a raté, il manque le carnet. L'étape le dit donc en
     *   notice d'information, sous le geste, et non en bandeau d'erreur.
     * @property errorMessage l'erreur d'une étape, posée en bandeau sous son en-tête.
     * @property ordersWithoutRender on commande un carnet que le serveur n'a pas
     *   encore composé — voir [orderWithoutRender].
     * @property isSavingWhatsApp l'accord de suivi est en train de partir. Le
     *   bouton tourne plutôt que de basculer avant que le serveur ait confirmé.
     * @property shareLink le lien de prévisualisation, une fois demandé. Gardé :
     *   la route est idempotente côté serveur, mais un aller-retour de moins est
     *   un aller-retour de moins.
     */
    data class State(
        val phase: Phase = Phase.Loading,
        val context: OrderContext? = null,
        val step: OrderStep = OrderStep.Start,
        val isAdvancing: Boolean = true,
        val draft: PrintOrderDraft = PrintOrderDraft(shipping = emptyShipping),
        val quotes: Map<QuoteKey, OrderQuote> = emptyMap(),
        val isQuoting: Boolean = false,
        val quoteError: String? = null,
        val order: PrintOrder? = null,
        val isSubmitting: Boolean = false,
        val paymentError: String? = null,
        val isMissingRender: Boolean = false,
        val errorMessage: String? = null,
        val ordersWithoutRender: Boolean = false,
        val isSavingWhatsApp: Boolean = false,
        val shareLink: URI? = null,
        val isPreparingLink: Boolean = false,
        val email: String? = null,
    ) {
        /** Le devis du couple choisi, s'il est déjà arrivé. */
        val quote: OrderQuote? get() = quotes[QuoteKey(draft.copies, draft.shippingSpeed)]

        /** L'étape courante laisse-t-elle passer ? */
        val canContinue: Boolean
            get() = when (step) {
                OrderStep.Start -> context?.renderId != null || ordersWithoutRender
                OrderStep.Shipping -> draft.hasCompleteAddress
                OrderStep.Copies -> draft.copies >= 1
                OrderStep.Speed -> true
                OrderStep.Summary -> quote != null
                // Rien à choisir avant « Payer » : la feuille de Stripe porte le
                // moyen de paiement, cartes enregistrées comprises.
                OrderStep.Payment -> true
                OrderStep.Confirmation -> false
            }

        // MARK: Étape 7 — la confirmation

        /**
         * Ce que l'écran de confirmation raconte. Il lit la **commande** et non le
         * brouillon : c'est le serveur qui a le dernier mot sur ce qui a été
         * enregistré, y compris le délai.
         */
        val confirmationDetail: String
            get() = OrderCopy.Confirmation.detail(book = context?.bookTitle ?: "ton carnet", email = email)

        val confirmationDays: DayRange?
            get() = order?.estimatedDays ?: context?.days(draft.shippingSpeed)

        /**
         * Le numéro qu'on proposera : celui déjà connu du compte. `null` quand il
         * n'y en a pas — l'écran le demande alors au lieu de le supposer.
         */
        val suggestedPhoneNumber: String? get() = context?.phoneNumber

        /**
         * Le suivi est-il accepté ? C'est **la commande** qui le dit, pas un état
         * d'écran : ce qui compte est ce que le serveur a enregistré.
         */
        val wantsWhatsApp: Boolean get() = order?.notifyByWhatsApp ?: false

        val confirmationSummary: String
            get() = OrderCopy.Confirmation.summary(
                copies = order?.copies ?: draft.copies,
                pages = order?.pageCount ?: context?.pageCount,
            )

        /** L'étape 3 : l'exemplaire suit-il encore la version du premier ? */
        fun followsFirstCopy(position: Int): Boolean = draft.followsFirstCopy(position)
    }

    private val _state = MutableStateFlow(State(email = email))
    val state: StateFlow<State> = _state.asStateFlow()

    /**
     * Le brouillon, que les champs de l'étape 2 écrivent. Une valeur : on le
     * remplace, on ne le modifie pas sur place.
     */
    var draft: PrintOrderDraft
        get() = _state.value.draft
        set(value) = _state.update { it.copy(draft = value) }

    /** Corrige l'adresse du brouillon — un champ de l'étape 2. */
    fun editShipping(edit: (ShippingAddress) -> ShippingAddress) {
        _state.update { it.copy(draft = it.draft.copy(shipping = edit(it.draft.shipping))) }
    }

    /**
     * Ce que la commande en cours a été passée avec. C'est ce qui dit si
     * « Payer » peut la reprendre, ou si l'adresse, les exemplaires ou la
     * rapidité ont changé depuis.
     */
    private var placedRequest: NewPrintOrderRequest? = null

    /**
     * La tâche de devis en cours. Gardée pour l'annuler : taper cinq fois sur
     * « + » ne doit pas laisser cinq réponses se courir après.
     */
    private var quoteTask: Job? = null

    // MARK: - Ouvrir

    /**
     * Charge ce que les sept étapes lisent. Idempotent : revenir sur l'écran
     * ne relance rien si la réponse est déjà là.
     */
    suspend fun load() {
        if (_state.value.phase == Phase.Ready) return

        try {
            val loaded = loadContext(memoId)
            // Le brouillon part de ce que le serveur propose : l'adresse du
            // profil et le style du carnet. Personne ne ressaisit ce qu'on sait
            // déjà. La carte, elle, se choisit dans la feuille de Stripe.
            _state.update {
                it.copy(
                    context = loaded,
                    draft = PrintOrderDraft(
                        copies = 1,
                        shippingSpeed = ShippingSpeed.Standard,
                        shipping = loaded.shipping,
                        copyOptions = listOf(loaded.options.moved(to = 1)),
                    ),
                    phase = Phase.Ready,
                )
            }

            // Le premier devis part tout de suite : il sera là bien avant que
            // quiconque ait rempli son adresse, et l'étape 5 s'ouvrira sans
            // attente.
            refreshQuote()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            _state.update { it.copy(phase = Phase.Failed(describe(error))) }
        }
    }

    suspend fun retry() {
        _state.update { it.copy(phase = Phase.Loading) }
        load()
    }

    // MARK: - Avancer, reculer

    /**
     * On commande un carnet que le serveur n'a pas encore composé.
     *
     * **La porte de service de la première étape** (Hugo, 19/09/2026). Le
     * tunnel refuse de s'ouvrir sans rendu — c'est le bon défaut, on ne fait
     * pas imprimer ce qui n'existe pas —, mais il n'y avait alors aucun moyen
     * de voir les six étapes suivantes sur un compte dont aucun carnet n'est
     * composé. Le lien de la boîte lève le verrou, et il est **dans l'app
     * livrée** : un carnet se compose pendant qu'on remplit son adresse, et
     * refuser la commande pour ça ferait perdre la vente.
     */
    fun orderWithoutRender() {
        _state.update { it.copy(ordersWithoutRender = true) }
    }

    fun advance() {
        val current = _state.value
        if (!current.canContinue) return
        val next = OrderStep.entries.getOrNull(current.step.rawValue + 1) ?: return
        _state.update { it.copy(errorMessage = null, isAdvancing = true, step = next) }
    }

    /**
     * Recule d'une étape. Rend `false` quand il n'y a plus d'étape derrière —
     * c'est alors à l'écran de quitter le tunnel.
     */
    fun goBack(): Boolean {
        val current = _state.value.step
        if (!current.allowsGoingBack) return false
        val previous = OrderStep.entries.getOrNull(current.rawValue - 1) ?: return false
        _state.update { it.copy(errorMessage = null, isAdvancing = false, step = previous) }
        return true
    }

    // MARK: - Étape 3 — les exemplaires

    fun addCopy() {
        if (_state.value.draft.copies >= MAXIMUM_COPIES) {
            _state.update { it.copy(errorMessage = OrderCopy.Copies.maximumReached) }
            return
        }
        _state.update { it.copy(errorMessage = null) }
        setCopies(_state.value.draft.copies + 1)
    }

    fun removeCopy() {
        if (_state.value.draft.copies <= 1) {
            _state.update { it.copy(errorMessage = OrderCopy.Copies.minimumReached) }
            return
        }
        _state.update { it.copy(errorMessage = null) }
        setCopies(_state.value.draft.copies - 1)
    }

    private fun setCopies(count: Int) {
        _state.update {
            val defaults = it.context?.options ?: PrintedCopyOptions(position = 1)
            it.copy(draft = it.draft.copy(copies = count).alignCopyOptions(defaults))
        }
        refreshQuote()
    }

    /**
     * Les trois gestes de l'étape 3 appartiennent au **brouillon** : ce sont
     * des règles sur des données, pas des règles d'écran, et elles se testent
     * donc sans émulateur. Voir [PrintOrderDraft].
     */
    fun setOption(option: PrintedCopyOption, isOn: Boolean, forCopyAt: Int) {
        _state.update { it.copy(draft = it.draft.setOption(option, isOn, forCopyAt)) }
    }

    fun followsFirstCopy(position: Int): Boolean = _state.value.followsFirstCopy(position)

    fun setFollowsFirstCopy(follows: Boolean, forCopyAt: Int) {
        _state.update { it.copy(draft = it.draft.setFollowsFirstCopy(follows, forCopyAt)) }
    }

    // MARK: - Étape 4 — la rapidité

    fun select(speed: ShippingSpeed) {
        if (_state.value.draft.shippingSpeed == speed) return
        _state.update { it.copy(draft = it.draft.copy(shippingSpeed = speed)) }
        refreshQuote()
    }

    // MARK: - Étape 5 — le récapitulatif

    /**
     * Demande le récapitulatif du couple courant, sauf s'il est déjà en cache.
     *
     * Appelé à **chaque** changement d'exemplaires ou de rapidité, donc bien
     * avant l'étape 5 : quand on y arrive, la réponse est là.
     */
    fun refreshQuote() {
        val draft = _state.value.draft
        val key = QuoteKey(draft.copies, draft.shippingSpeed)
        quoteTask?.cancel()
        if (_state.value.quotes[key] != null) {
            _state.update { it.copy(quoteError = null, isQuoting = false) }
            return
        }

        _state.update { it.copy(isQuoting = true, quoteError = null) }
        quoteTask = viewModelScope.launch {
            try {
                val loaded = loadQuote(memoId, key.copies, key.speed)
                ensureActive()
                _state.update { it.copy(quotes = it.quotes + (key to loaded), quoteError = null) }
            } catch (error: CancellationException) {
                // Une réponse dépassée par un autre « + » : la tâche suivante
                // tient l'état, celle-ci ne touche plus à rien.
                throw error
            } catch (error: Exception) {
                ensureActive()
                _state.update { it.copy(quoteError = describe(error)) }
            }
            _state.update { it.copy(isQuoting = false) }
        }
    }

    // MARK: - Étape 6 — payer

    /**
     * Enregistre la commande, l'encaisse, puis ouvre la confirmation.
     *
     * Le montant n'est **pas** envoyé : le serveur le recalcule. Ce que l'app a
     * affiché ne l'engage pas, sans quoi un total deviendrait réécrivable.
     *
     * Deux chemins :
     *
     * - feuille Stripe, puis relecture de la commande ;
     * - le serveur n'a pas donné de quoi ouvrir la feuille → on le dit. C'est
     *   une panne de configuration, et afficher la confirmation annoncerait une
     *   commande payée qui ne l'est pas.
     *
     * Le troisième — la cagnotte qui couvrait tout, sans feuille — est parti
     * avec elle (Hugo, 06/10/2026, T230).
     *
     * **Une commande déjà passée se reprend** (01/10/2026). « Payer » après une
     * feuille refermée ou une carte refusée créait une seconde commande. Si
     * rien n'a changé depuis, on rouvre la feuille sur **la même** intention ;
     * si l'adresse, les exemplaires ou la rapidité ont changé, l'ancienne
     * commande est abandonnée avant d'en passer une neuve.
     *
     * **Sans rendu, le serveur choisit** (06/10/2026). Le tunnel peut s'ouvrir
     * sur un carnet pas encore composé ; la commande part alors sans
     * `renderId`, et le serveur prend le dernier rendu prêt — celui d'une
     * composition qui a pu aboutir pendant qu'on remplissait son adresse. S'il
     * n'y en a aucun (`409 no_render`), l'étape le dit au lieu de ne rien faire,
     * ce qu'elle faisait.
     *
     * ⚠️ Sur Android, la vue le lance dans `viewModelScope` et non dans la
     * portée de la composition (le `Task {}` d'iOS, qui ne meurt pas avec la
     * vue) : une rotation pendant la feuille de Stripe recrée l'écran, et
     * l'attente de son issue — puis la relecture de la commande — doivent
     * survivre à cette recréation.
     */
    suspend fun pay() {
        val current = _state.value
        val context = current.context
        if (current.isSubmitting || context == null) return

        _state.update { it.copy(isSubmitting = true, paymentError = null, isMissingRender = false) }

        try {
            val request = NewPrintOrderRequest(renderId = context.renderId, draft = current.draft)

            val payment: OrderPayment
            val resumed = resumeIfUnchanged(request)
            if (resumed != null) {
                setOrder(resumed.order)
                val resumedPayment = resumed.payment
                if (resumedPayment == null) {
                    // Plus rien à régler : payée entre-temps, ou en cours.
                    setOrder(settled(resumed.order))
                    showConfirmation()
                    return
                }
                payment = resumedPayment
            } else {
                abandonPlacedOrder()
                val placed = submitOrder(memoId, request)
                setOrder(placed.order)
                placedRequest = request
                payment = placed.payment
            }

            val placedOrder = _state.value.order ?: return

            when (val settlement = payment.settlement) {
                OrderSettlement.Unavailable -> {
                    _state.update { it.copy(paymentError = OrderCopy.Payment.unavailable) }
                    return
                }

                is OrderSettlement.Card -> when (val outcome = openPayment(settlement.ticket)) {
                    // Pas une erreur, un choix — donc pas de message. La commande
                    // reste en brouillon, et « Payer » la reprendra sur la même
                    // intention : pas de second débit.
                    PaymentOutcome.Cancelled -> return

                    is PaymentOutcome.Failed -> {
                        _state.update { it.copy(paymentError = outcome.message) }
                        return
                    }

                    PaymentOutcome.Succeeded -> setOrder(settled(placedOrder))
                }
            }

            showConfirmation()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            if (isMissingRender(error)) {
                _state.update { it.copy(isMissingRender = true) }
            } else {
                _state.update { it.copy(paymentError = describe(error)) }
            }
        } finally {
            _state.update { it.copy(isSubmitting = false) }
        }
    }

    private fun setOrder(order: PrintOrder?) {
        _state.update { it.copy(order = order) }
    }

    /**
     * La commande déjà passée, rouverte — si elle existe, si elle attend encore
     * d'être payée, et si rien n'a changé depuis. `null` sinon : il faut en
     * passer une neuve.
     */
    private suspend fun resumeIfUnchanged(request: NewPrintOrderRequest): ResumedOrderPayment? {
        val order = _state.value.order ?: return null
        val resume = resumePayment ?: return null
        if (order.status != PrintOrderStatus.Draft || request != placedRequest) return null
        return try {
            resume(order.id)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            // Expirée (409) ou introuvable : on repart d'une commande neuve.
            // L'ancienne a rendu sa réservation de son côté.
            placedRequest = null
            setOrder(null)
            null
        }
    }

    /**
     * Abandonne la commande en brouillon qui ne correspond plus, avant d'en
     * passer une neuve. Sans réponse du serveur, le ménage des brouillons s'en
     * chargera.
     */
    private suspend fun abandonPlacedOrder() {
        val stale = _state.value.order ?: return
        if (stale.status != PrintOrderStatus.Draft) return
        try {
            cancelOrder?.invoke(stale.id)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            // Le ménage des brouillons s'en chargera.
        }
        setOrder(null)
        placedRequest = null
    }

    private fun showConfirmation() {
        _state.update { it.copy(isAdvancing = true, step = OrderStep.Confirmation) }
    }

    /**
     * Relit la commande jusqu'à ce que le serveur la dise payée.
     *
     * **Une feuille qui rend `Succeeded` dit que Stripe a accepté, pas que notre
     * serveur l'a appris.** Le passage en `submitted` vient du webhook, qui
     * arrive par un autre chemin — d'où cette relecture, plutôt que de conclure
     * depuis le retour de la feuille.
     *
     * Au bout du budget, on rend ce qu'on a et la confirmation s'affiche quand
     * même : l'argent est pris, la confirmation est due. Un échec ici
     * annoncerait une commande perdue sur un paiement réussi, et l'écran de
     * suivi relira l'état plus tard de toute façon.
     */
    private suspend fun settled(placed: PrintOrder): PrintOrder {
        val reload = reloadOrder ?: return placed

        repeat(SETTLEMENT_ATTEMPTS) {
            delay(1.seconds)
            val fresh = try {
                reload(placed.id)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                null
            }
            if (fresh != null && fresh.status != PrintOrderStatus.Draft) return fresh
        }

        return placed
    }

    // MARK: - Étape 7 — la confirmation

    /**
     * Le lien public du carnet, demandé au premier partage.
     *
     * Rend `null` quand le serveur refuse : l'écran n'ouvre alors pas une
     * feuille de partage vide, il ne se passe rien — et l'erreur se lit dans le
     * bandeau plutôt que dans une feuille du système à moitié remplie.
     */
    suspend fun prepareShareLink(): URI? {
        _state.value.shareLink?.let { return it }

        _state.update { it.copy(isPreparingLink = true) }
        try {
            val link = requestShareLink(memoId)
            _state.update { it.copy(shareLink = link, errorMessage = null) }
            return link
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            _state.update { it.copy(errorMessage = describe(error)) }
            return null
        } finally {
            _state.update { it.copy(isPreparingLink = false) }
        }
    }

    // MARK: Le suivi par WhatsApp

    /**
     * Accepte le suivi avec ce numéro, ou le refuse en passant `null`.
     *
     * Le numéro **remonte sur le compte** quand celui-ci n'en a pas : c'est la
     * seule fois où on le demande aujourd'hui, et le redemander à la commande
     * suivante serait une question déjà posée.
     */
    suspend fun setWhatsAppTracking(phone: String?) {
        val orderId = _state.value.order?.id ?: return
        if (_state.value.isSavingWhatsApp) return

        _state.update { it.copy(isSavingWhatsApp = true) }
        try {
            val updated = saveWhatsApp(orderId, phone)
            _state.update { it.copy(order = updated, errorMessage = null) }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            _state.update { it.copy(errorMessage = describe(error)) }
        } finally {
            _state.update { it.copy(isSavingWhatsApp = false) }
        }
    }

    companion object {
        const val MAXIMUM_COPIES = 20

        /** Le refus du serveur quand le voyage n'a aucun rendu prêt. */
        internal const val MISSING_RENDER_CODE = "no_render"

        internal fun isMissingRender(error: Throwable): Boolean = (error as? ApiError)?.code == MISSING_RENDER_CODE

        /**
         * Combien de fois relire la commande avant de passer à la confirmation.
         *
         * Une seconde entre deux lectures. Le webhook arrive en général avant la
         * deuxième ; le budget couvre un Stripe qui traîne sans faire tourner le
         * bouton pendant une demi-minute.
         */
        private const val SETTLEMENT_ATTEMPTS = 6

        /** Une adresse vide, le temps que celle du profil arrive. */
        internal val emptyShipping: ShippingAddress
            get() = ShippingAddress(name = "", line1 = "", postalCode = "", city = "", country = "FR")

        /** Le `localizedDescription` d'iOS : la phrase de l'API, déjà en français. */
        internal fun describe(error: Throwable): String =
            (error as? ApiError)?.errorDescription ?: error.localizedMessage ?: error.toString()
    }
}
