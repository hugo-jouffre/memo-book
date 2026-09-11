import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Ma cagnotte : ce qu'il y a dessus, d'où ça vient, et ce que le carnet
/// coûtera.
///
/// **Un seul écran pour la cagnotte pleine et la cagnotte vide.** Les deux
/// maquettes ne diffèrent que par un bloc — l'historique d'un côté, une carte
/// d'invitation de l'autre — et tout le reste est identique, carte de solde
/// comprise. En faire deux écrans aurait dupliqué la partie qui compte.
///
/// On y arrive de deux endroits, et c'est la même somme : la ligne « Ma
/// cagnotte » du profil, et celle des paramètres du voyage. La cagnotte
/// appartient au compte (voir ``Wallet``) ; ce qui change, c'est le carnet
/// qu'on finance.
public struct WalletView: View {
    private let onIntent: (WalletIntent) -> Void

    @State private var model: WalletModel

    public init(
        model: WalletModel,
        onIntent: @escaping (WalletIntent) -> Void
    ) {
        _model = State(initialValue: model)
        self.onIntent = onIntent
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MemoBookSpacing.l) {
                BrandScreenHeader(
                    title: BookCopy.Wallet.title,
                    subtitle: BookCopy.Wallet.subtitle(trip: model.wallet?.tripTitle),
                    isSubtitleLoading: model.isLoading
                )

                WalletBalanceCard(
                    wallet: model.wallet,
                    isLoading: model.isLoading,
                    onAdd: addFunds,
                    onShare: { onIntent(.shareWallet) }
                )

                // C'est **le seul bloc** qui distingue les deux maquettes.
                if let wallet = model.wallet, wallet.isEmpty {
                    WalletEmptyCard { onIntent(.inviteFriends) }
                } else {
                    WalletHistory(wallet: model.wallet, isLoading: model.isLoading)
                }

                faq

                if let message = model.errorMessage {
                    ErrorBanner(message: message) {
                        Task { await model.load() }
                    }
                }

                BrandButton(
                    BookCopy.Wallet.help,
                    style: .link,
                    isSubdued: true,
                    fillsWidth: true
                ) {
                    onIntent(.openHelp)
                }

                #if DEBUG
                    WalletDebugPanel(model: model)
                #endif
            }
            // Le solde, la barre et l'historique arrivent ensemble et en
            // douceur : c'est la même donnée, elle ne doit pas se poser en
            // trois temps.
            .animation(.snappy(duration: 0.3), value: model.wallet)
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.top, MemoBookSpacing.xs)
            .padding(.bottom, MemoBookSpacing.l)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) { previewCallToAction }
        .background(MemoBookColor.background.ignoresSafeArea())
        .brandHiddenNavigationBar()
        // Le crème de la marque ne se retourne pas en sombre — voir
        // `MemoBookColor`.
        .environment(\.colorScheme, .light)
        .task { await model.load() }
    }

    /// « Si je n'utilise pas toute ma cagnotte ? »
    ///
    /// C'est **la** question que se pose quelqu'un qui va demander de l'argent
    /// à ses proches, et l'écran y répond avant qu'elle soit posée. Elle n'est
    /// pas dans une carte : ce n'est pas une action, c'est une phrase qu'on lit
    /// une fois.
    private var faq: some View {
        VStack(spacing: MemoBookSpacing.xs / 2 + 2) {
            Text(BookCopy.Wallet.faqTitle)
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.ink)

            Text(BookCopy.Wallet.faqMessage)
                .font(MemoBookFont.h3)
                .foregroundStyle(MemoBookColor.inkMuted)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    /// « Prévisualiser mon carnet », posé en bas et toujours visible.
    ///
    /// Dans un `safeAreaInset` et non au bout du défilement : la maquette le
    /// pose sur une barre fixe, et c'est juste — quelqu'un qui vient de voir sa
    /// cagnotte veut voir ce qu'elle paie, sans redescendre un historique de
    /// vingt lignes.
    private var previewCallToAction: some View {
        BrandButton(
            BookCopy.Wallet.previewBook,
            style: .primary,
            fillsWidth: true
        ) {
            onIntent(.openBookPreview)
        }
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        .padding(.vertical, MemoBookSpacing.snug)
        // Le fond de la barre reprend celui de l'écran, en matériau : le
        // contenu passe dessous et se laisse deviner, ce qui dit que la liste
        // continue.
        .background(.thinMaterial)
    }

    private func addFunds() {
        guard model.canTopUp else {
            onIntent(.topUpUnavailable)
            Task { await model.addFunds(0) }
            return
        }
        onIntent(.addFunds)
    }
}

/// Ce que la cagnotte demande à l'app d'ouvrir.
public enum WalletIntent: Sendable, Hashable {
    /// Partager la cagnotte — la feuille de partage, avec le message et le lien.
    case shareWallet
    /// « Inviter des proches », depuis la cagnotte vide. Le même partage, dit
    /// autrement : c'est le premier geste plutôt qu'un geste de plus.
    case inviteFriends
    /// « Ajouter » — recharger, quand l'encaissement existera.
    case addFunds
    /// « Ajouter », mais l'encaissement n'est pas branché.
    case topUpUnavailable
    case openBookPreview
    case openHelp
}

// MARK: - La carte de solde

/// Le solde, l'estimation, et les deux gestes qui les font bouger.
///
/// C'est la seule carte de l'app dont le contenu principal est **centré** : un
/// montant se lit comme un chiffre sur un relevé, pas comme une valeur en bout
/// de ligne.
private struct WalletBalanceCard: View {
    let wallet: Wallet?
    let isLoading: Bool
    let onAdd: () -> Void
    let onShare: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.galleryCornerRadius)

        return VStack(spacing: MemoBookSpacing.sectionGap) {
            balance
            estimate

            Rectangle()
                .fill(MemoBookColor.hairline)
                .frame(height: 1)
                .accessibilityHidden(true)

            actions
        }
        .padding(MemoBookSpacing.m)
        .frame(maxWidth: .infinity)
        .background(MemoBookColor.surface, in: shape)
        .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
    }

    private var balance: some View {
        VStack(spacing: MemoBookSpacing.xs / 2 + 2) {
            Text(BookCopy.Wallet.available)
                .font(MemoBookFont.sectionOverline)
                .foregroundStyle(MemoBookColor.inkMuted)
                .textCase(.uppercase)

            if isLoading {
                BrandSkeleton(width: 160, height: 48, cornerRadius: MemoBookSpacing.snug)
            } else {
                Text(wallet?.balance.roundedEuros ?? "")
                    .font(MemoBookFont.balance)
                    // **Vert dès qu'il y a quelque chose dessus, gris à zéro.**
                    // C'est la différence que dessinent les deux maquettes, et
                    // elle porte tout : une cagnotte vide ne doit pas avoir
                    // l'air d'une réussite.
                    .foregroundStyle(
                        (wallet?.balance ?? 0) > 0 ? MemoBookColor.action : MemoBookColor.inkMuted
                    )
                    // Le solde s'anime chiffre par chiffre quand une
                    // contribution arrive : c'est le moment que l'écran existe
                    // pour montrer.
                    .contentTransition(.numericText())
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// « À ce rythme, ton carnet fera 50 pages » d'un côté, le coût estimé de
    /// l'autre, et la barre qui dit où on en est.
    @ViewBuilder
    private var estimate: some View {
        if isLoading {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                BrandSkeleton()
                BrandSkeleton(
                    height: MemoBookSpacing.progressBarHeight,
                    cornerRadius: MemoBookSpacing.progressBarHeight / 2
                )
            }
        } else if let wallet, let estimate = wallet.estimate {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                estimateLine(estimate)

                BrandProgressTrack(
                    fraction: estimate.coverage(of: wallet.balance),
                    tone: .tinted
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(BookCopy.Wallet.paceEstimate(pages: estimate.pageCount)). \(BookCopy.Wallet.estimatedCost) \(estimate.cost.euros)"
            )
            .accessibilityValue(
                Text(estimate.coverage(of: wallet.balance), format: .percent.precision(.fractionLength(0)))
            )
        }
    }

    /// En taille accessible, la phrase et le coût s'empilent : côte à côte, ils
    /// n'auraient plus que deux mots de large chacun.
    @ViewBuilder
    private func estimateLine(_ estimate: WalletEstimate) -> some View {
        let pace = Text(BookCopy.Wallet.paceEstimate(pages: estimate.pageCount))
            .font(MemoBookFont.caption)
            .foregroundStyle(MemoBookColor.inkMuted)

        let cost = VStack(alignment: .trailing, spacing: 0) {
            Text(BookCopy.Wallet.estimatedCost)
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.ink)
            Text(estimate.cost.euros)
                .font(MemoBookFont.label)
                .foregroundStyle(MemoBookColor.ink)
        }

        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                pace.multilineTextAlignment(.leading)
                cost.frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(alignment: .bottom, spacing: MemoBookSpacing.l) {
                pace
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                cost
            }
        }
    }

    /// ⚠️ Les deux boutons sont en taille `small` alors que la maquette les
    /// dessine à 48 pt de haut, soit la taille pleine.
    ///
    /// C'est **la typographie** qui décide, pas la hauteur : Figma leur donne
    /// un libellé de 16 pt, et notre taille pleine impose 18 — le compromis
    /// avec le bouton d'Apple, expliqué dans ``MemoBookFont/button``. À 18 pt,
    /// « Partager » et son icône demandent 152 pt dans une moitié de carte qui
    /// en offre 133 sur un iPhone SE, et le mot se coupait en deux.
    /// ``BrandButton/Size/small`` porte exactement le 16 pt de la maquette.
    ///
    /// Coût : 44 pt de haut au lieu de 48. Quatre points au-dessus du seuil de
    /// R2 — écart assumé et signalé dans la fiche de la cagnotte. Le vrai
    /// arbitrage appartient à Clara : soit la maquette descend son libellé de
    /// taille pleine à 16, soit ces deux boutons montent à 48.
    @ViewBuilder
    private var actions: some View {
        let add = BrandButton(
            BookCopy.Wallet.add,
            icon: Image(brand: "IconPlus"),
            style: .tertiary,
            size: .small,
            fillsWidth: true,
            action: onAdd
        )

        let share = BrandButton(
            BookCopy.Wallet.share,
            icon: Image(brand: "IconShareSystem"),
            style: .primary,
            size: .small,
            fillsWidth: true,
            action: onShare
        )

        // Le test de taille accessible, et non `ViewThatFits` : deux boutons
        // qui **remplissent** leur moitié demandent chacun une largeur infinie,
        // et `ViewThatFits` conclut donc toujours qu'ils ne tiennent pas — il
        // choisissait la colonne même là où la ligne allait très bien. Les deux
        // libellés sont courts ; c'est le corps du texte, et lui seul, qui
        // décide ici. La carte de l'aperçu, dont les libellés sont longs et les
        // boutons ajustés à leur contenu, garde `ViewThatFits` — voir
        // ``BookOfferCard``.
        if typeSize.isAccessibilitySize {
            VStack(spacing: MemoBookSpacing.snug) {
                add
                share
            }
        } else {
            HStack(spacing: MemoBookSpacing.snug) {
                add
                share
            }
        }
    }
}

// MARK: - L'historique

/// « Historique des contributions » : qui a donné quoi, et quand.
private struct WalletHistory: View {
    let wallet: Wallet?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
            Text(BookCopy.Wallet.historySection)
                .font(MemoBookFont.sectionOverline)
                .foregroundStyle(MemoBookColor.inkMuted)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)

            entries

            if let wallet, !wallet.isEmpty {
                WalletTotals(wallet: wallet)
            }
        }
    }

    private var entries: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.cornerRadius)

        return VStack(spacing: 0) {
            if isLoading {
                // Trois lignes en attente : assez pour que le bloc ait sa
                // hauteur, pas assez pour promettre un historique bien rempli.
                ForEach(0..<3, id: \.self) { index in
                    if index > 0 { separator }
                    WalletEntryRow.placeholder
                }
            } else {
                ForEach(Array((wallet?.entries ?? []).enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { separator }
                    WalletEntryRow(entry: entry)
                        // Une contribution qui arrive glisse par le haut : la
                        // liste commence par le plus récent, elle s'écrit donc
                        // par là.
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .padding(.vertical, MemoBookSpacing.xs)
        .background(MemoBookColor.surface, in: shape)
        .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
        .clipShape(shape)
    }

    /// Le filet sépare, il n'encadre pas : il vit entre deux lignes et s'arrête
    /// aux marges du texte — comme dans ``BrandRowGroup``.
    private var separator: some View {
        Rectangle()
            .fill(MemoBookColor.hairline)
            .frame(height: 1)
            .padding(.horizontal, MemoBookSpacing.s)
            .accessibilityHidden(true)
    }
}

/// Une ligne de l'historique : qui, quoi, quand, combien.
private struct WalletEntryRow: View {
    let entry: WalletEntry?

    static let placeholder = WalletEntryRow(entry: nil)

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: MemoBookSpacing.snug) {
            badge

            VStack(alignment: .leading, spacing: 2) {
                nameLine

                if let entry {
                    Text(entry.dateLabel)
                        .font(MemoBookFont.mention)
                        .foregroundStyle(MemoBookColor.inkMuted)
                } else {
                    BrandSkeleton(width: 48)
                }
            }

            Spacer(minLength: MemoBookSpacing.xs)

            amount
        }
        .padding(.horizontal, MemoBookSpacing.s)
        .padding(.vertical, MemoBookSpacing.snug)
        .frame(minHeight: MemoBookSpacing.minimumTapTarget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    /// La pastille : l'initiale du donateur, ou l'engrenage d'un versement
    /// automatique.
    ///
    /// **Bleue pour un don, lime pour l'abonnement.** C'est ce qui distingue
    /// les deux natures d'un coup d'œil, sans lire la pastille de texte : le
    /// bleu est quelqu'un, le lime est le produit.
    private var badge: some View {
        Group {
            if let entry {
                if entry.kind.isFromSomeoneElse {
                    Text(entry.initial)
                        .font(MemoBookFont.label)
                        .foregroundStyle(MemoBookColor.action)
                } else {
                    Image(brand: "IconSettings")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: MemoBookSpacing.snug + 2, height: MemoBookSpacing.snug + 2)
                        .foregroundStyle(MemoBookColor.ink)
                }
            }
        }
        .frame(width: MemoBookSpacing.initialsSide, height: MemoBookSpacing.initialsSide)
        .background(pastilleColor, in: .circle)
        .accessibilityHidden(true)
    }

    private var pastilleColor: Color {
        guard let entry else { return MemoBookColor.ink.opacity(0.06) }
        return entry.kind.isFromSomeoneElse
            ? MemoBookColor.outline.opacity(0.25)
            : MemoBookColor.accent.opacity(0.25)
    }

    /// Le nom, et la pastille qui dit d'où vient l'argent.
    ///
    /// En taille accessible, la pastille passe **sous** le nom : « Abonnement »
    /// à côté de « Abonnement MB » ne laisserait plus de place au nom.
    @ViewBuilder
    private var nameLine: some View {
        if let entry {
            let name = Text(entry.displayName)
                .font(MemoBookFont.label)
                .foregroundStyle(MemoBookColor.ink)

            if let badge = entry.kind.badge {
                let pill = Text(badge)
                    .font(MemoBookFont.microBadge)
                    .foregroundStyle(
                        entry.kind.isFromSomeoneElse ? MemoBookColor.action : MemoBookColor.ink
                    )
                    .textCase(.uppercase)
                    .padding(.horizontal, MemoBookSpacing.xs / 2 + 2)
                    .padding(.vertical, 1)
                    .background(
                        entry.kind.isFromSomeoneElse ? MemoBookColor.outline : MemoBookColor.accent,
                        in: .rect(cornerRadius: MemoBookSpacing.xs - 2)
                    )

                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) { name; pill }
                } else {
                    HStack(spacing: MemoBookSpacing.xs / 2 + 2) { name; pill }
                }
            } else {
                name
            }
        } else {
            BrandSkeleton(width: 110)
        }
    }

    /// Le montant. Vert quand il vient de quelqu'un, gris quand il vient de
    /// l'abonnement : le même écart que les pastilles, et pour la même raison.
    private var amount: some View {
        Group {
            if let entry {
                Text(entry.signedAmountLabel)
                    .font(MemoBookFont.bodySemibold)
                    .foregroundStyle(
                        entry.kind.isFromSomeoneElse ? MemoBookColor.action : MemoBookColor.inkMuted
                    )
                    .monospacedDigit()
            } else {
                BrandSkeleton(width: 64)
            }
        }
    }

    private var accessibilityDescription: String {
        guard let entry else { return "" }
        return [entry.displayName, entry.kind.badge, entry.dateLabel, entry.signedAmountLabel]
            .compactMap(\.self)
            .joined(separator: ", ")
    }
}

/// Les deux pastilles de synthèse : ce que les proches ont offert, et ce que
/// l'abonnement a versé.
///
/// Elles ne répètent pas l'historique, elles le résument — c'est la réponse à
/// « combien mes proches ont donné, en tout ? », qu'on ne peut pas obtenir en
/// lisant une liste.
private struct WalletTotals: View {
    let wallet: Wallet

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let gifted = tile(wallet.giftedTotal, BookCopy.Wallet.giftedTile)
        let subscription = tile(wallet.subscriptionTotal, BookCopy.Wallet.subscriptionTile)

        return Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: MemoBookSpacing.snug) { gifted; subscription }
            } else {
                HStack(spacing: MemoBookSpacing.snug) { gifted; subscription }
            }
        }
    }

    private func tile(_ amount: Decimal, _ label: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.cornerRadius)

        return VStack(alignment: .leading, spacing: 0) {
            Text(amount.roundedEuros)
                .font(MemoBookFont.figure)
                .foregroundStyle(MemoBookColor.ink)
                .monospacedDigit()

            Text(label)
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.ink)
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(MemoBookSpacing.snug - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MemoBookColor.outline.opacity(0.3), in: shape)
        .overlay { shape.strokeBorder(MemoBookColor.outline, lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(amount.roundedEuros) \(label)")
    }
}

// MARK: - La cagnotte vide

/// Ce qu'on montre quand rien n'est encore arrivé : le cadeau, la phrase, et le
/// seul geste qui change quelque chose.
///
/// **Pas un état d'erreur, et pas un vide.** Une cagnotte sans contribution est
/// l'état normal d'une cagnotte qu'on vient d'ouvrir ; la carte propose donc
/// une action, elle ne s'excuse pas.
private struct WalletEmptyCard: View {
    let onInvite: () -> Void

    @ScaledMetric(relativeTo: .body) private var markSide: CGFloat = 48

    var body: some View {
        VStack(spacing: MemoBookSpacing.s) {
            Text(verbatim: "🎁")
                .font(.system(size: MemoBookSpacing.m))
                .frame(width: min(markSide, 72), height: min(markSide, 72))
                .background(MemoBookColor.accent.opacity(0.5), in: .circle)
                .accessibilityHidden(true)

            VStack(spacing: MemoBookSpacing.xs / 2 + 2) {
                Text(BookCopy.Wallet.emptyTitle)
                    .font(MemoBookFont.bodySemibold)
                    .foregroundStyle(MemoBookColor.ink)

                Text(BookCopy.Wallet.emptyMessage)
                    .font(MemoBookFont.h3)
                    .foregroundStyle(MemoBookColor.inkMuted)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            BrandButton(
                BookCopy.Wallet.invite,
                icon: Image(brand: "IconShareNodes"),
                style: .primary,
                size: .small,
                action: onInvite
            )
        }
        .padding(MemoBookSpacing.m)
        .frame(maxWidth: .infinity)
    }
}

#Preview("Cagnotte") {
    NavigationStack {
        WalletView(model: WalletModel(tripId: "trip-rome")) { _ in }
    }
}

#Preview("Cagnotte vide") {
    NavigationStack {
        WalletView(model: WalletModel(tripId: "trip-rome", source: { _ in .emptyFixture })) { _ in }
    }
}

#Preview("Cagnotte — valeurs en route") {
    NavigationStack {
        WalletView(
            model: WalletModel(
                tripId: "trip-rome",
                source: { _ in
                    try await Task.sleep(for: .seconds(3600))
                    return .fixture
                }
            )
        ) { _ in }
    }
}

#Preview("Cagnotte — AX3") {
    NavigationStack {
        WalletView(model: WalletModel(tripId: "trip-rome")) { _ in }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
