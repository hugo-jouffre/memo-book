import MemoBookCore
import MemoBookDesign
import SwiftUI

/// « Ajouter à ma cagnotte » (`3551:26486`) : combien, et comment on paie.
///
/// On y arrive par « Ajouter », sur la carte de solde de la cagnotte (Clara,
/// 26/09/2026) — le bouton ne menait nulle part.
///
/// **Trois écarts à la maquette, voulus et signalés** (§ 31) :
///
/// - **La carte ne se saisit pas ici.** La maquette pose trois champs —
///   numéro, expiration, CVV. Un numéro de carte ne transite jamais par un
///   champ de l'app : il se tape dans la fenêtre de Stripe, qui s'ouvre au
///   bouton du bas (``WalletModel/addFunds(_:)``). La section « Paiement » dit
///   donc où la carte se saisira, et quelles cartes passent.
/// - **Le don récurrent pâlit.** Le serveur ne sait pas encore prélever chaque
///   mois : l'interrupteur se touche et explique, il ne ment pas.
/// - **L'objectif est l'estimation de ce carnet**, et non « le prix moyen d'un
///   carnet de voyage » : l'app le connaît mieux. Sans estimation, pas de
///   barre — on n'annonce pas un chiffre inventé.
public struct WalletTopUpView: View {
    @State private var model: WalletModel
    private let onFinished: () -> Void

    @Environment(\.travellerFirstName) private var travellerFirstName
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Le montant choisi parmi les quatre pastilles, ou `nil` quand on tape
    /// le sien.
    @State private var preset: Decimal? = 10
    @State private var freeAmount = ""
    @State private var showsRecurringNotice = false
    @State private var isPaying = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case freeAmount }

    /// Les pastilles de la maquette.
    private static let presets: [Decimal] = [5, 10, 20, 60]

    /// Les bornes du serveur (`TOPUP_MIN_CENTS`, `TOPUP_MAX_CENTS`) : en deçà,
    /// les frais Stripe mangent la recharge ; au-delà, c'est plus sûrement une
    /// faute de frappe qu'une intention.
    private static let minimum: Decimal = 5
    private static let maximum: Decimal = 500

    public init(model: WalletModel, onFinished: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onFinished = onFinished
    }

    /// Ce que le bouton encaissera.
    private var amount: Decimal? {
        if let preset { return preset }
        let typed = freeAmount
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "€", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty, let value = Decimal(string: typed, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        return value
    }

    private var isAmountValid: Bool {
        guard let amount else { return false }
        return amount >= Self.minimum && amount <= Self.maximum
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                BrandScreenHeader(title: BookCopy.Wallet.topUpTitle)

                contextCard
                amountSection
                recurringCard
                paymentSection

                if let message = model.errorMessage {
                    ErrorBanner(message: message)
                }
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.top, MemoBookSpacing.xs)
            .padding(.bottom, MemoBookSpacing.l)
            .animation(.snappy(duration: 0.2), value: showsRecurringNotice)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { callToAction }
        .background(MemoBookColor.background.ignoresSafeArea())
        .brandHiddenNavigationBar()
        .brandKeyboardDismissBar()
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
        .task { if model.wallet == nil { await model.load() } }
    }

    // MARK: - La cagnotte, en tête

    /// L'avatar, le carnet financé, ce qui est déjà collecté et l'objectif.
    private var contextCard: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)

        return VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            HStack(spacing: MemoBookSpacing.snug) {
                BrandAvatar(url: nil, initials: initial)

                VStack(alignment: .leading, spacing: 2) {
                    Text(BookCopy.Wallet.topUpCardTitle)
                        .font(MemoBookFont.bodySemibold)
                        .foregroundStyle(MemoBookColor.ink)
                    if let trip = model.wallet?.tripTitle, !trip.isEmpty {
                        Text(BookCopy.Wallet.topUpCardSubtitle(trip: trip))
                            .font(MemoBookFont.taglineRegular)
                            .foregroundStyle(MemoBookColor.inkMuted)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle()
                .fill(MemoBookColor.hairline)
                .frame(height: 1)
                .accessibilityHidden(true)

            progress
        }
        .padding(MemoBookSpacing.sectionGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MemoBookColor.surface, in: shape)
        .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
    }

    /// L'initiale du prénom, comme sur la maquette. La photo du compte n'est
    /// pas lue ici : elle vit dans le profil, et un second appel pour un rond
    /// de 40 pt ne se justifie pas.
    private var initial: String {
        travellerFirstName?.first.map { String($0).uppercased() } ?? ""
    }

    @ViewBuilder
    private var progress: some View {
        if let wallet = model.wallet {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(BookCopy.Wallet.topUpCollected)
                        .font(MemoBookFont.label)
                        .foregroundStyle(MemoBookColor.inkMuted)
                    Spacer(minLength: MemoBookSpacing.xs)
                    Text(wallet.balance.euros)
                        .font(MemoBookFont.bodySemibold)
                        .foregroundStyle(MemoBookColor.ink)
                        .monospacedDigit()
                }

                if let estimate = wallet.estimate {
                    BrandProgressTrack(fraction: estimate.coverage(of: wallet.balance), tone: .tinted)

                    HStack(alignment: .firstTextBaseline) {
                        Text(BookCopy.Wallet.topUpGoalCaption)
                        Spacer(minLength: MemoBookSpacing.xs)
                        Text(BookCopy.Wallet.topUpGoal(estimate.cost.euros))
                            .fontWeight(.semibold)
                    }
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.action)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                BrandSkeleton()
                BrandSkeleton(
                    height: MemoBookSpacing.progressBarHeight,
                    cornerRadius: MemoBookSpacing.progressBarHeight / 2
                )
            }
        }
    }

    // MARK: - Combien

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            VStack(spacing: MemoBookSpacing.xs / 2) {
                Text((amount ?? 0).euros)
                    .font(MemoBookFont.balance)
                    .foregroundStyle(isAmountValid ? MemoBookColor.action : MemoBookColor.inkMuted)
                    .contentTransition(.numericText())
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .animation(.snappy(duration: 0.2), value: amount)

                Text(BookCopy.Wallet.topUpAmountCaption)
                    .font(MemoBookFont.taglineRegular)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            presets

            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                BrandTextField(
                    BookCopy.Wallet.topUpFreeAmount,
                    text: $freeAmount,
                    field: Field.freeAmount,
                    focus: $focus,
                    labelPlacement: .above,
                    placeholder: BookCopy.Wallet.topUpFreeAmountPlaceholder
                )
                .keyboardType(.decimalPad)
                .onChange(of: freeAmount) { _, typed in
                    // Taper un montant retire la pastille : il n'y a qu'un
                    // montant à la fois.
                    if !typed.isEmpty { preset = nil }
                }

                if amount != nil, !isAmountValid {
                    Text(BookCopy.Wallet.topUpBounds(min: Self.minimum.euros, max: Self.maximum.euros))
                        .font(MemoBookFont.caption)
                        .foregroundStyle(MemoBookColor.error)
                }
            }
        }
    }

    /// Les quatre pastilles, sur une ligne — sur deux en taille accessible,
    /// où « 60 € » ne tiendrait plus dans un quart de largeur.
    @ViewBuilder
    private var presets: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: MemoBookSpacing.xs),
            count: typeSize.isAccessibilitySize ? 2 : 4
        )
        LazyVGrid(columns: columns, spacing: MemoBookSpacing.xs) {
            ForEach(Self.presets, id: \.self) { value in
                presetPill(value)
            }
        }
    }

    private func presetPill(_ value: Decimal) -> some View {
        let isSelected = preset == value
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.controlCornerRadius)

        return Button {
            preset = value
            freeAmount = ""
            focus = nil
        } label: {
            Text(value.roundedEuros)
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(isSelected ? MemoBookColor.action : MemoBookColor.ink)
                .frame(maxWidth: .infinity, minHeight: MemoBookSpacing.minimumTapTarget)
                .background(isSelected ? MemoBookColor.action.opacity(0.08) : MemoBookColor.surface, in: shape)
                .overlay {
                    shape.strokeBorder(
                        isSelected ? MemoBookColor.action : MemoBookColor.hairline,
                        lineWidth: isSelected ? 1.5 : 1
                    )
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Le don récurrent

    /// Pâli et toujours tapable : le serveur ne sait pas encore prélever
    /// chaque mois, et l'appui le dit au lieu d'avaler le geste.
    private var recurringCard: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)

        return VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            Button {
                showsRecurringNotice.toggle()
            } label: {
                HStack(spacing: MemoBookSpacing.s) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(BookCopy.Wallet.topUpRecurringTitle)
                            .font(MemoBookFont.bodySemibold)
                            .foregroundStyle(MemoBookColor.ink)
                        Text(BookCopy.Wallet.topUpRecurringDetail)
                            .font(MemoBookFont.caption)
                            .foregroundStyle(MemoBookColor.inkMuted)
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Toggle("", isOn: .constant(false))
                        .labelsHidden()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .padding(MemoBookSpacing.s)
                .background(MemoBookColor.surface, in: shape)
                .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
                .contentShape(shape)
                .opacity(0.45)
            }
            .buttonStyle(.plain)
            .accessibilityHint(BookCopy.Wallet.topUpRecurringUnavailable)

            if showsRecurringNotice {
                BrandNotice(BookCopy.Wallet.topUpRecurringUnavailable, tone: .information)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Le paiement

    private var paymentSection: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            Text(BookCopy.Wallet.topUpPaymentSection)
                .font(MemoBookFont.sectionOverline)
                .foregroundStyle(MemoBookColor.inkMuted)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)

            Text(BookCopy.Wallet.topUpPaymentNote)
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: MemoBookSpacing.xs) {
                Text(BookCopy.Wallet.topUpAcceptedCards)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
                ForEach(["VISA", "MC", "CB"], id: \.self) { brand in
                    Text(brand)
                        .font(MemoBookFont.microBadge)
                        .foregroundStyle(MemoBookColor.ink)
                        .padding(.horizontal, MemoBookSpacing.xs)
                        .padding(.vertical, 4)
                        .background(MemoBookColor.surface, in: .rect(cornerRadius: 4))
                        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
                }
            }
            .padding(.top, MemoBookSpacing.xs / 2)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Contribuer

    /// « Contribuer 10,00 € », posé en bas et toujours visible, comme
    /// « Prévisualiser mon carnet » sur la cagnotte.
    private var callToAction: some View {
        BrandButton(
            BookCopy.Wallet.topUpCta((amount ?? 0).euros),
            isLoading: isPaying,
            fillsWidth: true,
            action: pay
        )
        .disabled(!isAmountValid)
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        .padding(.vertical, MemoBookSpacing.snug)
        .background(.thinMaterial)
    }

    private func pay() {
        guard let amount, isAmountValid, !isPaying else { return }
        focus = nil
        isPaying = true
        Task {
            let credited = await model.addFunds(amount)
            isPaying = false
            // L'argent est arrivé : on revient à la cagnotte, qui se relit.
            // Une feuille refermée sans payer laisse la page telle quelle.
            if credited { onFinished() }
        }
    }
}

#Preview("Ajouter à ma cagnotte") {
    NavigationStack {
        WalletTopUpView(model: WalletModel(), onFinished: {})
    }
    .environment(\.travellerFirstName, "Camille")
}

#Preview("Ajouter à ma cagnotte — AX3") {
    NavigationStack {
        WalletTopUpView(model: WalletModel(), onFinished: {})
    }
    .environment(\.travellerFirstName, "Camille")
    .environment(\.dynamicTypeSize, .accessibility3)
}
