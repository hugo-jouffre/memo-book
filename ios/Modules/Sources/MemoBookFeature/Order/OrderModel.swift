import Foundation
import MemoBookCore
import Observation

/// Ce que le tunnel de commande sait faire : porter les sept étapes, tenir le
/// brouillon, et demander au serveur ce qu'il est le seul à savoir — les prix.
///
/// Comme ``HomeModel`` et ``ProfileModel``, il ne connaît pas `MemoBookAPI` :
/// il reçoit trois fonctions. L'app y branche les routes, les aperçus n'en
/// fournissent aucune et tombent sur le jeu d'essai — c'est ce qui montre les
/// sept étapes sans serveur.
@MainActor
@Observable
public final class OrderModel {
    /// Où en est le chargement de ce que les sept étapes lisent.
    public enum Phase: Equatable {
        /// La page est dessinée, ses valeurs ne sont pas encore arrivées : les
        /// squelettes tiennent leur place. **L'écran ne disparaît jamais.**
        case loading
        case ready
        /// Le contexte n'est pas venu. L'écran garde son en-tête et propose de
        /// réessayer — jamais un mur d'erreur.
        case failed(String)
    }

    public private(set) var phase: Phase = .loading
    public private(set) var context: OrderContext?

    public private(set) var step: OrderStep = .start

    /// Le sens du dernier changement d'étape. C'est lui qui décide du côté par
    /// lequel la nouvelle étape entre — sans quoi un retour se jouerait comme
    /// une avance, et le geste ne raconterait plus rien.
    public private(set) var isAdvancing = true

    public var draft: PrintOrderDraft

    /// Le récapitulatif, par couple (exemplaires, rapidité).
    ///
    /// **Un cache et non une valeur** : revenir de l'étape 5 à l'étape 3 puis
    /// repartir en avant ne doit pas rappeler le serveur pour la même réponse.
    /// La clé porte les deux seuls choix dont le montant dépend.
    private var quotes: [QuoteKey: OrderQuote] = [:]
    public private(set) var isQuoting = false
    public private(set) var quoteError: String?

    /// La commande passée. C'est elle qui remplit l'écran de confirmation.
    public private(set) var order: PrintOrder?
    public private(set) var isSubmitting = false

    /// Ce qui a empêché de payer. Affiché **dans la feuille de paiement**, là
    /// où se corrige le choix — pas en haut d'un écran qu'on vient de quitter.
    public private(set) var paymentError: String?

    /// L'erreur d'une étape, posée en bandeau sous son en-tête.
    public private(set) var errorMessage: String?

    private let memoId: String
    private let email: String?
    private let loadContext: (String) async throws -> OrderContext
    private let loadQuote: (String, Int, ShippingSpeed) async throws -> OrderQuote
    private let submit: (String, NewPrintOrderRequest) async throws -> PrintOrder
    private let requestShareLink: (String) async throws -> URL

    /// Le lien de prévisualisation, une fois demandé. Gardé : la route est
    /// idempotente côté serveur, mais un aller-retour de moins est un
    /// aller-retour de moins.
    public private(set) var shareLink: URL?
    public private(set) var isPreparingLink = false

    /// La tâche de devis en cours. Gardée pour l'annuler : taper cinq fois sur
    /// « + » ne doit pas laisser cinq réponses se courir après.
    private var quoteTask: Task<Void, Never>?

    private struct QuoteKey: Hashable {
        let copies: Int
        let speed: ShippingSpeed
    }

    public init(
        memoId: String,
        email: String? = nil,
        context: @escaping (String) async throws -> OrderContext = { _ in .fixture },
        quote: @escaping (String, Int, ShippingSpeed) async throws -> OrderQuote = {
            _, copies, speed in .fixture(copies: copies, speed: speed)
        },
        submit: @escaping (String, NewPrintOrderRequest) async throws -> PrintOrder = {
            memoId, request in .fixture(memoId: memoId, request: request)
        },
        shareLink: @escaping (String) async throws -> URL = { memoId in
            URL(string: "https://memo-book.com/c/\(memoId)")!
        }
    ) {
        self.memoId = memoId
        self.email = email
        self.loadContext = context
        self.loadQuote = quote
        self.submit = submit
        self.requestShareLink = shareLink
        self.draft = PrintOrderDraft(shipping: .empty)
    }

    // MARK: - Ouvrir

    /// Charge ce que les sept étapes lisent. Idempotent : revenir sur l'écran
    /// ne relance rien si la réponse est déjà là.
    public func load() async {
        if case .ready = phase { return }

        do {
            let loaded = try await loadContext(memoId)
            context = loaded

            // Le brouillon part de ce que le serveur propose : l'adresse du
            // profil, la carte par défaut, le style du carnet. Personne ne
            // ressaisit ce qu'on sait déjà.
            draft = PrintOrderDraft(
                copies: 1,
                shippingSpeed: .standard,
                shipping: loaded.shipping,
                copyOptions: [loaded.options.moved(to: 1)],
                paymentCardId: loaded.selectedCardId,
                usesApplePay: false
            )
            phase = .ready

            // Le premier devis part tout de suite : il sera là bien avant que
            // quiconque ait rempli son adresse, et l'étape 5 s'ouvrira sans
            // attente.
            refreshQuote()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    public func retry() async {
        phase = .loading
        await load()
    }

    // MARK: - Avancer, reculer

    /// L'étape courante laisse-t-elle passer ?
    public var canContinue: Bool {
        switch step {
        case .start: context?.renderId != nil
        case .shipping: draft.hasCompleteAddress
        case .copies: draft.copies >= 1
        case .speed: true
        case .summary: quote != nil
        case .payment: draft.hasPaymentMethod || quote?.isFullyCovered == true
        case .confirmation: false
        }
    }

    public func advance() {
        guard canContinue, let next = OrderStep(rawValue: step.rawValue + 1) else { return }
        errorMessage = nil
        isAdvancing = true
        step = next
    }

    /// Recule d'une étape. Rend `false` quand il n'y a plus d'étape derrière —
    /// c'est alors à l'écran de quitter le tunnel.
    @discardableResult
    public func goBack() -> Bool {
        guard step.allowsGoingBack, let previous = OrderStep(rawValue: step.rawValue - 1) else {
            return false
        }
        errorMessage = nil
        isAdvancing = false
        step = previous
        return true
    }

    // MARK: - Étape 3 — les exemplaires

    public static let maximumCopies = 20

    public func addCopy() {
        guard draft.copies < Self.maximumCopies else {
            errorMessage = BookCopy.Order.Copies.maximumReached
            return
        }
        errorMessage = nil
        setCopies(draft.copies + 1)
    }

    public func removeCopy() {
        guard draft.copies > 1 else {
            errorMessage = BookCopy.Order.Copies.minimumReached
            return
        }
        errorMessage = nil
        setCopies(draft.copies - 1)
    }

    private func setCopies(_ count: Int) {
        draft.copies = count
        draft.alignCopyOptions(defaults: context?.options ?? PrintedCopyOptions(position: 1))
        refreshQuote()
    }

    /// Les trois gestes de l'étape 3 appartiennent au **brouillon** : ce sont
    /// des règles sur des données, pas des règles d'écran, et elles se testent
    /// donc sans simulateur. Voir ``PrintOrderDraft``.
    public func setOption(
        _ option: PrintedCopyOption,
        to isOn: Bool,
        forCopyAt position: Int
    ) {
        draft.setOption(option, to: isOn, forCopyAt: position)
    }

    public func followsFirstCopy(_ position: Int) -> Bool {
        draft.followsFirstCopy(position)
    }

    public func setFollowsFirstCopy(_ follows: Bool, forCopyAt position: Int) {
        draft.setFollowsFirstCopy(follows, forCopyAt: position)
    }

    // MARK: - Étape 4 — la rapidité

    public func select(speed: ShippingSpeed) {
        guard draft.shippingSpeed != speed else { return }
        draft.shippingSpeed = speed
        refreshQuote()
    }

    // MARK: - Étape 5 — le récapitulatif

    /// Le devis du couple choisi, s'il est déjà arrivé.
    public var quote: OrderQuote? {
        quotes[QuoteKey(copies: draft.copies, speed: draft.shippingSpeed)]
    }

    /// Demande le récapitulatif du couple courant, sauf s'il est déjà en cache.
    ///
    /// Appelé à **chaque** changement d'exemplaires ou de rapidité, donc bien
    /// avant l'étape 5 : quand on y arrive, la réponse est là.
    public func refreshQuote() {
        let key = QuoteKey(copies: draft.copies, speed: draft.shippingSpeed)
        quoteTask?.cancel()
        guard quotes[key] == nil else {
            quoteError = nil
            isQuoting = false
            return
        }

        isQuoting = true
        quoteError = nil
        quoteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await loadQuote(memoId, key.copies, key.speed)
                guard !Task.isCancelled else { return }
                quotes[key] = loaded
                quoteError = nil
            } catch {
                guard !Task.isCancelled else { return }
                quoteError = error.localizedDescription
            }
            if !Task.isCancelled { isQuoting = false }
        }
    }

    // MARK: - Étape 6 — payer

    public func select(cardId: String) {
        draft.paymentCardId = cardId
        draft.usesApplePay = false
        paymentError = nil
    }

    public func selectApplePay() {
        draft.usesApplePay = true
        paymentError = nil
    }

    /// La carte présentée à l'étape 6.
    public var selectedCard: PaymentCard? {
        guard !draft.usesApplePay, let id = draft.paymentCardId else { return nil }
        return context?.cards.first { $0.id == id }
    }

    /// Passe la commande, puis ouvre la confirmation.
    ///
    /// Le montant n'est **pas** envoyé : le serveur le recalcule. Ce que l'app
    /// a affiché ne l'engage pas, sans quoi un total deviendrait réécrivable.
    public func pay() async {
        guard !isSubmitting, let renderId = context?.renderId else { return }

        isSubmitting = true
        paymentError = nil
        defer { isSubmitting = false }

        do {
            let placed = try await submit(memoId, NewPrintOrderRequest(renderId: renderId, draft: draft))
            order = placed
            isAdvancing = true
            step = .confirmation
        } catch {
            paymentError = error.localizedDescription
        }
    }

    // MARK: - Étape 7 — la confirmation

    /// Ce que l'écran de confirmation raconte. Il lit la **commande** et non le
    /// brouillon : c'est le serveur qui a le dernier mot sur ce qui a été
    /// enregistré, y compris le délai.
    public var confirmationDetail: String {
        BookCopy.Order.Confirmation.detail(book: context?.bookTitle ?? "ton carnet", email: email)
    }

    public var confirmationDays: DayRange? {
        order?.estimatedDays ?? context.map { $0.days(for: draft.shippingSpeed) }
    }

    /// Le lien public du carnet, demandé au premier partage.
    ///
    /// Rend `nil` quand le serveur refuse : l'écran n'ouvre alors pas une
    /// feuille de partage vide, il ne se passe rien — et l'erreur se lit dans
    /// le bandeau plutôt que dans une feuille du système à moitié remplie.
    public func prepareShareLink() async -> URL? {
        if let shareLink { return shareLink }

        isPreparingLink = true
        defer { isPreparingLink = false }

        do {
            let link = try await requestShareLink(memoId)
            shareLink = link
            errorMessage = nil
            return link
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public var confirmationSummary: String {
        BookCopy.Order.Confirmation.summary(
            copies: order?.copies ?? draft.copies,
            pages: order?.pageCount ?? context?.pageCount
        )
    }
}

extension ShippingAddress {
    /// Une adresse vide, le temps que celle du profil arrive.
    static var empty: ShippingAddress {
        ShippingAddress(name: "", line1: "", postalCode: "", city: "", country: "FR")
    }
}
