import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Le numéro à prévenir, demandé depuis l'écran de confirmation.
///
/// Elle n'existe que pour les comptes qui n'ont pas encore de numéro : les
/// autres acceptent le suivi d'un seul geste. Le numéro saisi ici **remonte sur
/// le compte** — c'est aujourd'hui le seul endroit qui le demande, et le
/// redemander à la commande suivante serait une question déjà posée.
struct OrderWhatsAppSheet: View {
    let suggested: String?
    let onConfirm: (String) -> Void

    @State private var phone: String
    /// Une énumération à un seul cas plutôt qu'un booléen : ``BrandTextField``
    /// attend un focus **optionnel**, parce que « aucun champ » est un état.
    @FocusState private var focus: Field?

    private enum Field: Hashable { case phone }

    init(suggested: String?, onConfirm: @escaping (String) -> Void) {
        self.suggested = suggested
        self.onConfirm = onConfirm
        _phone = State(initialValue: suggested ?? "")
    }

    /// Volontairement permissif : les formats internationaux sont nombreux, et
    /// c'est l'envoi qui validera vraiment. Assez pour écarter un champ à
    /// moitié rempli, pas assez pour refuser un numéro valide qu'on n'a pas su
    /// lire.
    private var canConfirm: Bool {
        phone.filter(\.isNumber).count >= 6
    }

    var body: some View {
        BrandSheet(
            BookCopy.Order.Confirmation.whatsappSheetTitle,
            subtitle: BookCopy.Order.Confirmation.whatsappSheetSubtitle
        ) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                BrandTextField(
                    BookCopy.Order.Confirmation.whatsappField,
                    text: $phone,
                    field: Field.phone,
                    focus: $focus,
                    labelPlacement: .above,
                    placeholder: BookCopy.Order.Confirmation.whatsappPlaceholder
                )
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .submitLabel(.done)

                BrandButton(
                    BookCopy.Order.Confirmation.whatsappConfirm,
                    fillsWidth: true
                ) {
                    onConfirm(phone.trimmingCharacters(in: .whitespaces))
                }
                .disabled(!canConfirm)
            }
        }
        .task {
            // Le champ est le seul de la feuille : le clavier arrive avec elle
            // plutôt que d'attendre une touche de plus.
            try? await Task.sleep(for: .milliseconds(250))
            focus = .phone
        }
    }
}

#Preview("Numéro WhatsApp") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            OrderWhatsAppSheet(suggested: nil) { _ in }
        }
}
