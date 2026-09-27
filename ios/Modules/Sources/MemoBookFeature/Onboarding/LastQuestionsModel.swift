import Foundation
import MemoBookCore
import Observation

/// Les « Dernières questions » : ce qu'on demande à quelqu'un qui entre pour
/// la première fois — son nom, sa date de naissance, son numéro WhatsApp —
/// avant l'accueil (Clara, 26/09/2026).
///
/// **Trois écrans, un seul modèle**, parce que c'est un seul geste : chaque
/// écran se valide ou se passe, et l'on avance. Ce qui est validé part tout de
/// suite au profil (`PATCH /v1/profile`) plutôt qu'à la fin : quelqu'un qui
/// referme l'app au deuxième écran a quand même donné son nom.
///
/// Le modèle ne connaît pas l'API : il reçoit une fonction qui écrit le profil,
/// comme ``ProfileModel``. Les aperçus n'en donnent aucune.
@MainActor
@Observable
public final class LastQuestionsModel {
    public enum Step: Int, CaseIterable, Sendable {
        case name
        case birthDate
        case phone
    }

    public private(set) var step: Step = .name
    public var lastName: String
    public var firstName: String
    /// Ce qu'on tape, `JJ/MM/AAAA` — les barres se posent toutes seules.
    public var birthDateText = "" {
        didSet {
            let formatted = Self.maskedBirthDate(birthDateText)
            if formatted != birthDateText { birthDateText = formatted }
        }
    }
    public var phoneNumber = ""

    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    private let account: Account
    private let save: ((ProfileEdit) async throws -> Void)?

    public init(account: Account, save: ((ProfileEdit) async throws -> Void)? = nil) {
        self.account = account
        self.save = save
        lastName = account.lastName ?? ""
        firstName = account.firstName ?? ""
    }

    // MARK: - Qui les voit

    /// Faut-il poser ces questions à ce compte ?
    ///
    /// Oui pour un compte **qui vient d'être ouvert** — le serveur ne le dit
    /// pas autrement que par sa date — et une seule fois par compte sur cet
    /// appareil : passer les trois écrans, c'est avoir répondu. Dix minutes et
    /// non deux : l'horloge du téléphone et celle du serveur ne sont pas
    /// toujours d'accord.
    public static func shouldAsk(_ account: Account, now: Date = .now, defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: answeredKey(account.id)) else { return false }
        return now.timeIntervalSince(account.createdAt) < 600
    }

    /// Ne plus jamais les poser à ce compte, sur cet appareil.
    public static func markAnswered(_ account: Account, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: answeredKey(account.id))
    }

    private static func answeredKey(_ accountId: String) -> String {
        "lastQuestionsAnswered.\(accountId)"
    }

    // MARK: - Ce que « Valider » attend

    public var canValidate: Bool {
        switch step {
        case .name:
            !lastName.trimmed.isEmpty && !firstName.trimmed.isEmpty
        case .birthDate:
            birthDate?.isPlausibleBirthDate() == true
        case .phone:
            (7...15).contains(phoneNumber.filter(\.isNumber).count)
        }
    }

    /// La date tapée, quand elle est complète et qu'elle existe.
    public var birthDate: CalendarDay? {
        CalendarDay(slashed: birthDateText)
    }

    /// Ce qu'on dit sous le champ de la date, quand elle est complète mais
    /// impossible — le 31 juin, une naissance dans le futur.
    public var birthDateProblem: String? {
        guard step == .birthDate, birthDateText.count == 10 else { return nil }
        return canValidate ? nil : LastQuestionsCopy.invalidBirthDate
    }

    // MARK: - Avancer

    /// Enregistre ce que l'écran demande, puis avance.
    ///
    /// - Returns: le compte à jour quand c'était le dernier écran — l'app
    ///   entre alors dans l'accueil —, `nil` sinon, ou si l'enregistrement a
    ///   échoué (le message est dans ``errorMessage``, et l'écran reste).
    public func validate() async -> Account? {
        guard canValidate, !isSaving else { return nil }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await save?(edit(for: step))
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
        return advance()
    }

    /// « Passer » : rien n'est enregistré, et l'on avance.
    public func skip() -> Account? {
        errorMessage = nil
        return advance()
    }

    /// La flèche de retour. `false` depuis le premier écran : il n'y a pas
    /// d'écran avant, c'est l'entrée — à l'appelant de décider.
    public func goBack() -> Bool {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return false }
        errorMessage = nil
        step = previous
        return true
    }

    private func advance() -> Account? {
        if let next = Step(rawValue: step.rawValue + 1) {
            step = next
            return nil
        }
        return updatedAccount
    }

    private func edit(for step: Step) -> ProfileEdit {
        switch step {
        case .name:
            ProfileEdit(firstName: .some(firstName.trimmed), lastName: .some(lastName.trimmed))
        case .birthDate:
            ProfileEdit(birthDate: .some(birthDate))
        case .phone:
            ProfileEdit(phoneNumber: .some(phoneNumber.trimmed))
        }
    }

    /// Le compte tel que l'accueil doit le connaître : avec le prénom qu'on
    /// vient de confirmer.
    private var updatedAccount: Account {
        Account(
            id: account.id,
            email: account.email,
            firstName: firstName.trimmed.isEmpty ? account.firstName : firstName.trimmed,
            lastName: lastName.trimmed.isEmpty ? account.lastName : lastName.trimmed,
            createdAt: account.createdAt
        )
    }

    // MARK: - La date, à la frappe

    /// `JJ/MM/AAAA`, à partir de ce qui a été tapé : seuls les chiffres
    /// comptent, huit au plus, et les barres se posent derrière le jour et le
    /// mois. On corrige en effaçant, on ne bute jamais sur une barre.
    static func maskedBirthDate(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(8))
        var result = ""
        for (index, digit) in digits.enumerated() {
            if index == 2 || index == 4 { result.append("/") }
            result.append(digit)
        }
        return result
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Les mots des trois écrans, recopiés des nœuds « Dernières questions »
/// (`3533:14979`, `3533:15036`, `3533:15010`) au caractère près (R8) —
/// majuscules comprises, et « Whatsapp » tel que la maquette l'écrit (signalé).
public enum LastQuestionsCopy {
    public static let skip = "Passer"
    public static let validate = "Valider"

    public static let nameTitle = "Ton Nom et Prénom"
    public static let lastNamePlaceholder = "Dupont"
    public static let firstNamePlaceholder = "Margaux"

    public static let birthDateTitle = "Ta Date de Naissance"
    public static let birthDatePlaceholder = "XX/XX/XXXX"

    public static let phoneTitle = "Ton Numéro Whatsapp"
    public static let phonePlaceholder = "+33 0 00 00 00 00"

    /// Pas dans la maquette : ce qu'on dit d'une date complète qui n'existe pas.
    public static let invalidBirthDate = "Cette date n’existe pas. Vérifie le jour, le mois et l’année."

    public enum Voice {
        public static let lastName = "Nom"
        public static let firstName = "Prénom"
        public static let birthDate = "Date de naissance, jour, mois et année"
        public static let phone = "Numéro WhatsApp"
        public static func progress(step: Int, of count: Int) -> String {
            "Question \(step) sur \(count)"
        }
    }
}
