import MemoBookCore
import MemoBookDesign
import SwiftUI

// Les quatre premières étapes : de quoi on part, où ça va, en combien
// d'exemplaires, et à quelle vitesse.

// MARK: - Étape 1 — Démarrage

/// Ce qu'on s'apprête à commander, et avec quel argent.
///
/// Les deux cartes se dessinent **tout de suite**, squelettes compris : on sait
/// à quoi ressemble l'écran avant de savoir ce qu'il y a dessus. Voir
/// ``BrandSkeleton``.
struct OrderStartStep: View {
    let model: OrderModel
    let onHelp: () -> Void

    private var isLoading: Bool { model.phase == .loading }

    var body: some View {
        OrderStepLayout(help: onHelp) {
            OrderHeroCard(wallet: model.context?.wallet, isLoading: isLoading)

            OrderTripCard(trip: model.context?.trip, isLoading: isLoading)

            // Le carnet n'a jamais été composé : il n'y a rien à imprimer, et
            // c'est dit ici plutôt que découvert au moment de payer.
            if case .ready = model.phase, model.context?.renderId == nil {
                BrandNotice(
                    "**\(BookCopy.Order.Start.notComposed)** "
                        + BookCopy.Order.Start.notComposedDetail
                )
            }

            if case .failed(let message) = model.phase {
                ErrorBanner(message: message) {
                    Task { await model.retry() }
                }
            }
        } actions: {
            BrandButton(
                BookCopy.Order.Start.cta,
                fillsWidth: true,
                action: model.advance
            )
            .disabled(!model.canContinue)
        }
        // Les deux cartes se remplissent ensemble et en douceur : c'est la même
        // réponse, elle ne doit pas se poser en deux temps.
        .animation(.snappy(duration: 0.3), value: model.context)
    }
}

// MARK: - Étape 2 — Livraison

/// Où le carnet doit arriver.
///
/// Les champs sont **préremplis avec l'adresse du profil** : personne ne
/// ressaisit ce qu'on sait déjà. C'est une amorce, pas un verrou — tout reste
/// corrigeable, et l'adresse de la commande se fige à la commande.
struct OrderShippingStep: View {
    @Bindable var model: OrderModel
    var focus: FocusState<OrderField?>.Binding

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        OrderStepLayout {
            OrderSectionHeader(title: BookCopy.Order.Shipping.title)

            if model.phase == .loading {
                skeleton
            } else {
                fields
            }
        } actions: {
            BrandButton(
                BookCopy.Order.next,
                fillsWidth: true,
                action: model.advance
            )
            .disabled(!model.canContinue)
        }
    }

    private var fields: some View {
        VStack(spacing: MemoBookSpacing.s) {
            BrandTextField(
                BookCopy.Order.Shipping.name,
                text: $model.draft.shipping.name,
                field: OrderField.name,
                focus: focus,
                labelPlacement: .above,
                placeholder: BookCopy.Order.Shipping.placeholder
            )
            .textContentType(.name)
            .submitLabel(.next)
            .onSubmit { focus.wrappedValue = .line1 }

            BrandTextField(
                BookCopy.Order.Shipping.line1,
                text: $model.draft.shipping.line1,
                field: OrderField.line1,
                focus: focus,
                labelPlacement: .above,
                placeholder: BookCopy.Order.Shipping.placeholder
            )
            .textContentType(.fullStreetAddress)
            .submitLabel(.next)
            .onSubmit { focus.wrappedValue = .line2 }

            BrandTextField(
                BookCopy.Order.Shipping.line2,
                text: line2,
                field: OrderField.line2,
                focus: focus,
                labelPlacement: .above,
                placeholder: "Bâtiment, étage…"
            )
            .textContentType(.streetAddressLine2)
            .submitLabel(.next)
            .onSubmit { focus.wrappedValue = .postalCode }

            postalCodeAndCity

            BrandCountryField(
                BookCopy.Order.Shipping.country,
                countries: model.context?.countries ?? [],
                code: $model.draft.shipping.country
            )
        }
    }

    /// Code postal et ville côte à côte, comme la maquette — et **empilés** dès
    /// que le texte grandit : à deux colonnes, « Code postal » n'y tient plus.
    @ViewBuilder
    private var postalCodeAndCity: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: MemoBookSpacing.s) {
                postalCodeField
                cityField
            }
        } else {
            HStack(alignment: .top, spacing: MemoBookSpacing.s) {
                postalCodeField
                cityField
            }
        }
    }

    private var postalCodeField: some View {
        BrandTextField(
            BookCopy.Order.Shipping.postalCode,
            text: $model.draft.shipping.postalCode,
            field: OrderField.postalCode,
            focus: focus,
            labelPlacement: .above,
            placeholder: "75015"
        )
        .textContentType(.postalCode)
        .keyboardType(.numbersAndPunctuation)
        .submitLabel(.next)
        .onSubmit { focus.wrappedValue = .city }
    }

    private var cityField: some View {
        BrandTextField(
            BookCopy.Order.Shipping.city,
            text: $model.draft.shipping.city,
            field: OrderField.city,
            focus: focus,
            labelPlacement: .above,
            placeholder: "Paris"
        )
        .textContentType(.addressCity)
        .submitLabel(.done)
        .onSubmit { focus.wrappedValue = nil }
    }

    /// La deuxième ligne d'adresse est optionnelle côté modèle, obligatoire
    /// côté champ de texte : ce pont traduit « rien » en chaîne vide et
    /// l'inverse, pour qu'une ligne effacée reparte bien à `nil`.
    private var line2: Binding<String> {
        Binding(
            get: { model.draft.shipping.line2 ?? "" },
            set: { model.draft.shipping.line2 = $0.isEmpty ? nil : $0 }
        )
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                    BrandSkeleton(width: 110)
                    BrandSkeleton(
                        height: MemoBookSpacing.fieldHeight,
                        cornerRadius: MemoBookSpacing.controlCornerRadius
                    )
                }
            }
        }
    }
}

// MARK: - Étape 3 — Exemplaires

/// Combien de carnets, et dans quelle version chacun.
struct OrderCopiesStep: View {
    @Bindable var model: OrderModel
    let onHelp: () -> Void

    /// Le rang qu'on vient de déplier, à amener sous les yeux.
    @State private var expanded: Int?

    var body: some View {
        OrderStepLayout(scrollTarget: $expanded, help: onHelp) {
            counter
            customisation
        } actions: {
            BrandButton(
                BookCopy.Order.next,
                fillsWidth: true,
                action: model.advance
            )
            .disabled(!model.canContinue)
        }
    }

    private var counter: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            OrderSectionHeader(
                title: BookCopy.Order.Copies.title,
                subtitle: BookCopy.Order.Copies.subtitle
            )

            BrandStepper(
                value: model.draft.copies,
                canDecrement: model.draft.copies > 1,
                canIncrement: model.draft.copies < OrderModel.maximumCopies,
                onDecrement: model.removeCopy,
                onIncrement: model.addCopy
            )
            .frame(maxWidth: .infinity)

            if let message = model.errorMessage {
                Text(message)
                    .font(MemoBookFont.h3)
                    .foregroundStyle(MemoBookColor.warning)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            OrderPriceRow(
                label: BookCopy.Order.Copies.unitPrice,
                amount: model.context?.unitPrice
            )
            .padding(.horizontal, MemoBookSpacing.s)
            .padding(.vertical, MemoBookSpacing.snug)
            .background(
                MemoBookColor.surface,
                in: .rect(cornerRadius: MemoBookSpacing.controlCornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MemoBookSpacing.controlCornerRadius)
                    .strokeBorder(MemoBookColor.hairline, lineWidth: 1)
            }
        }
        .animation(.snappy(duration: 0.25), value: model.errorMessage)
    }

    private var customisation: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            OrderSectionHeader(
                title: BookCopy.Order.Copies.customiseTitle,
                subtitle: BookCopy.Order.Copies.customiseSubtitle
            )

            ForEach(model.draft.copyOptions) { copy in
                OrderCopyDisclosure(model: model, position: copy.position) { expanded = $0 }
                    .id(copy.position)
            }
        }
        // Les exemplaires apparaissent et disparaissent avec le compteur : ils
        // glissent au lieu de surgir.
        .animation(.snappy(duration: 0.3), value: model.draft.copyOptions.count)
    }
}

/// Un exemplaire et ses quatre options, repliables.
///
/// Le premier carnet s'ouvre sur ses options ; les suivants annoncent d'abord
/// qu'ils reprennent sa version, et ne montrent leurs propres réglages que si
/// on demande à les détacher.
private struct OrderCopyDisclosure: View {
    let model: OrderModel
    let position: Int
    /// Ce qu'on vient de déplier. La liste s'en sert pour l'amener sous les
    /// yeux : sans ça, les options d'un carnet déplié en bas de page
    /// apparaissent **sous** la barre du bouton, et rien ne dit qu'elles sont
    /// là.
    let onExpand: (Int) -> Void

    @State private var isExpanded = false

    private var copy: PrintedCopyOptions? {
        model.draft.copyOptions.first { $0.position == position }
    }

    private var followsFirst: Bool { model.followsFirstCopy(position) }

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
            header

            if isExpanded {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, MemoBookSpacing.xs)
        .animation(.snappy(duration: 0.28), value: isExpanded)
        .animation(.snappy(duration: 0.28), value: followsFirst)
        .onAppear {
            // Le premier carnet s'ouvre : c'est celui qu'on règle, et les
            // autres en découlent.
            isExpanded = position == 1
        }
    }

    private var header: some View {
        Button {
            isExpanded.toggle()
            if isExpanded { onExpand(position) }
        } label: {
            HStack(spacing: MemoBookSpacing.xs) {
                Text(BookCopy.Order.Copies.copyTitle(position))
                    .font(MemoBookFont.bodySemibold)
                    .foregroundStyle(MemoBookColor.ink)

                Spacer(minLength: MemoBookSpacing.xs)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .frame(minHeight: MemoBookSpacing.minimumTapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BookCopy.Order.Copies.copyTitle(position))
        .accessibilityHint(isExpanded ? "Replier" : "Déplier")
    }

    @ViewBuilder
    private var content: some View {
        if position > 1, followsFirst {
            VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
                Text(BookCopy.Order.Copies.sameAsFirst)
                    .font(MemoBookFont.h3)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                BrandButton(
                    BookCopy.Order.Copies.differentFromFirst,
                    style: .secondary,
                    fillsWidth: true
                ) {
                    model.setFollowsFirstCopy(false, forCopyAt: position)
                    onExpand(position)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                toggles

                if position > 1 {
                    BrandButton(
                        BookCopy.Order.Copies.backToSameAsFirst,
                        style: .link,
                        fillsWidth: true
                    ) {
                        model.setFollowsFirstCopy(true, forCopyAt: position)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var toggles: some View {
        if let copy {
            ForEach(PrintedCopyOption.allCases) { option in
                OrderToggleCard(
                    title: option.title,
                    isOn: Binding(
                        get: { option.value(in: copy) },
                        set: { model.setOption(option, to: $0, forCopyAt: position) }
                    )
                )
            }
        }
    }
}

// MARK: - Étape 4 — Rapidité

/// À quelle vitesse le carnet part.
struct OrderSpeedStep: View {
    let model: OrderModel
    let onHelp: () -> Void

    var body: some View {
        OrderStepLayout(help: onHelp) {
            OrderSectionHeader(title: BookCopy.Order.Speed.title)

            BrandOptionGroup {
                ForEach(ShippingSpeed.allCases, id: \.self) { speed in
                    BrandOptionRow(
                        speed.title,
                        subtitle: model.context?.days(for: speed).label,
                        value: price(for: speed),
                        isSelected: model.draft.shippingSpeed == speed
                    ) {
                        model.select(speed: speed)
                    }
                }
            }

            if let message = model.quoteError {
                ErrorBanner(message: message) { model.refreshQuote() }
            }
        } actions: {
            BrandButton(
                BookCopy.Order.Speed.cta,
                fillsWidth: true,
                action: model.advance
            )
            .disabled(!model.canContinue)
        }
        .animation(.snappy(duration: 0.25), value: model.draft.shippingSpeed)
    }

    /// « Inclus » pour le standard, le supplément pour l'express. Rien tant que
    /// le tarif n'est pas arrivé : un prix inventé serait pire qu'un blanc.
    private func price(for speed: ShippingSpeed) -> String? {
        guard let context = model.context else { return nil }
        return switch speed {
        case .standard: BookCopy.Order.Speed.included
        case .express: context.expressPrice.euros
        }
    }
}
