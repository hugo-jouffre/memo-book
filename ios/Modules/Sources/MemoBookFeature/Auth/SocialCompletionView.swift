import MemoBookCore
import MemoBookDesign
import SwiftUI

/// La page qui suit une entrée par Apple ou Google : **vérifier ce que le
/// fournisseur a donné** — prénom, nom, adresse — avant d'entrer dans l'app.
///
/// Maquette `Social login - compléments` (`2707:9456`) : le titre, une ligne qui
/// dit d'où viennent les valeurs, le prénom et le nom côte à côte, l'adresse,
/// et « Continuer ». Elle manquait, et un compte ouvert par Google entrait sans
/// qu'on ait pu corriger un prénom en minuscules ou un nom de famille tronqué —
/// Hugo, 14/09/2026.
///
/// **L'adresse se lit, elle ne se corrige pas**, pour la même raison que sur le
/// profil : c'est l'identifiant du compte, et la changer est un écran à part.
/// Quand le fournisseur ne l'a pas donnée — une adresse Apple masquée et
/// refusée —, la ligne n'apparaît pas : un champ vide et verrouillé ne dirait
/// rien.
struct SocialCompletionView: View {
    @Bindable var model: AuthModel
    let focus: FocusState<AuthField?>.Binding
    let onAuthenticated: (Account) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Largeur du cadre de la maquette : au-delà, la colonne se centre au lieu
    /// de s'étirer. Même règle que l'écran d'entrée.
    private static let contentWidth: CGFloat = 390

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                header

                VStack(spacing: 12) {
                    nameFields
                        .textInputAutocapitalization(.words)

                    if model.completing?.email != nil {
                        BrandTextField("Email", text: $model.email, field: .email, focus: focus)
                            .textContentType(.emailAddress)
                            .disabled(true)
                    }
                }

                BrandButton(
                    "Continuer",
                    isLoading: model.isWorking,
                    fillsWidth: true,
                    action: submit
                )
                .disabled(!model.canCompleteProfile)
                .padding(.top, MemoBookSpacing.xs)

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(MemoBookFont.notification)
                        .foregroundStyle(MemoBookColor.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.vertical, MemoBookSpacing.m)
            .frame(maxWidth: Self.contentWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .brandKeyboardDismissBar()
        .background(BrandBackdrop())
        .environment(\.colorScheme, .light)
        .animation(.snappy(duration: 0.2), value: model.errorMessage)
        .onSubmit(submit)
        .submitLabel(.done)
        .onAppear {
            // Le clavier s'ouvre sur ce qu'il y a le plus souvent à corriger.
            if model.firstName.isEmpty { focus.wrappedValue = .firstName }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            Text("Complète tes informations")
                .font(MemoBookFont.h1)
                .tracking(-0.41)
                .foregroundStyle(MemoBookColor.ink)
            // La minuscule initiale est celle de la maquette, comme le
            // sous-titre de l'écran d'entrée : la phrase continue le titre.
            Text("nous avons récupéré les informations suivantes, vérifie leur validité")
                .font(MemoBookFont.body)
                .tracking(MemoBookFont.tracking(16))
                .foregroundStyle(MemoBookColor.inkMuted)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }

    /// Prénom et nom côte à côte, comme à l'inscription — et l'un sous l'autre
    /// aux tailles de texte accessibles, où deux champs ne laissent plus la
    /// place à leur intitulé.
    @ViewBuilder
    private var nameFields: some View {
        let firstName = BrandTextField("Prénom", text: $model.firstName, field: .firstName, focus: focus)
            .textContentType(.givenName)
        let lastName = BrandTextField("Nom", text: $model.lastName, field: .lastName, focus: focus)
            .textContentType(.familyName)

        if typeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                firstName
                lastName
            }
        } else {
            HStack(spacing: 12) {
                firstName
                lastName
            }
        }
    }

    private func submit() {
        guard model.canCompleteProfile, !model.isWorking else { return }
        focus.wrappedValue = nil
        Task {
            guard let account = await model.completeProfile() else { return }
            onAuthenticated(account)
        }
    }
}
