import MemoBookCore
import MemoBookDesign
import SwiftUI

/// « Tes limites de souvenirs » — où on en est, ce que ça consomme, et les deux
/// paliers.
///
/// **Une seule feuille dont le contenu change**, comme celle de l'abonnement :
/// on y regarde son solde, on compare deux paliers, on étend, et on voit la
/// confirmation — sans jamais empiler une feuille sur une autre (règle du
/// design system).
///
/// ```
/// « Tes limites de souvenirs »  ──  Étendre mes limites  ──▶  .compare
///   (la jauge, le barème)                                      │ Étendre pour 3,99 €/semaine
///                                                                ▼
///                                                              .done  (« C’est étendu »)
/// ```
///
/// **Le parcours est celui du paywall, pas un autre** (Hugo, 16/09/2026) : on
/// explique ce qu'on a, on montre ce qu'on aurait, on annonce le prix une seule
/// fois, et le bouton porte le prix. C'est ce qui fait qu'on décide sans avoir
/// à faire défiler pour retrouver le chiffre.
///
/// ⚠️ **Rien n'est encaissé.** L'extension est un service numérique : Apple
/// impose l'achat intégré, et c'est StoreKit qui portera la transaction. La
/// route pose le palier, ce qui permet de dérouler le parcours de bout en bout.
struct MemoryAllowanceSheet: View {
    let model: TripSettingsModel

    @State private var step: Step = .status
    @Environment(\.dismiss) private var dismiss

    enum Step: Hashable {
        case status
        case compare
        case done
    }

    /// Ce que le palier étendu ouvre, pour l'annoncer avant de l'avoir.
    ///
    /// ⚠️ **Écrit ici et non servi par le serveur**, faute d'une route de
    /// catalogue : la réponse ne porte que le palier *courant*. C'est la seule
    /// valeur de cet écran que l'app connaît d'elle-même, et elle est à
    /// remplacer le jour où `GET /v1/catalog` existe. Elle s'accorde avec
    /// `MEMORY_ALLOWANCE.extended` côté serveur.
    private static let extendedAllowance = 8_000

    private var memory: MemoryAllowance { model.memory ?? MemoryAllowance() }

    var body: some View {
        Group {
            switch step {
            case .status: status
            case .compare: compare
            case .done: done
            }
        }
        .animation(.smooth(duration: 0.3), value: step)
    }

    // MARK: - Où on en est

    private var status: some View {
        BrandSheet(MemoryCopy.sheetTitle, subtitle: MemoryCopy.sheetIntro) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                gauge
                pricing

                if let message = model.errorMessage {
                    ErrorBanner(message: message)
                }

                VStack(spacing: MemoBookSpacing.s) {
                    if memory.plan == .included {
                        BrandButton(
                            MemoryCopy.upgradeCta(price: memory.upgradeWeeklyPrice.euros),
                            style: .accent,
                            fillsWidth: true
                        ) {
                            step = .compare
                        }
                    } else {
                        // Revenir en arrière **existe**, et se trouve ici :
                        // une limite qu'on a relevée doit pouvoir se
                        // redescendre, sinon l'extension n'est pas un réglage
                        // mais un piège.
                        BrandButton(
                            MemoryCopy.downgradeCta,
                            style: .destructive,
                            isLoading: model.isChangingMemoryPlan,
                            fillsWidth: true
                        ) {
                            Task { await model.changeMemoryPlan(to: .included) }
                        }
                    }

                    BrandButton(MemoryCopy.close, style: .secondary, fillsWidth: true) { dismiss() }
                }
            }
        }
    }

    /// La jauge, son solde, et le bandeau qui prévient — quand il y a de quoi
    /// prévenir.
    private var gauge: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: MemoBookSpacing.xs) {
                Text(memory.plan.title)
                    .font(MemoBookFont.calloutTitle)
                    .foregroundStyle(MemoBookColor.ink)
                Spacer(minLength: MemoBookSpacing.xs)
                Text(MemoryCopy.rowValue(used: memory.used, allowance: memory.allowance))
                    .font(MemoBookFont.label)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .monospacedDigit()
                    .fixedSize()
            }

            BrandGauge(
                fraction: memory.fraction,
                isExhausted: memory.isExhausted,
                accessibilityLabel: MemoryCopy.rowTitle
            )

            Text(MemoryCopy.remaining(memory.remaining, renewsOn: memory.renewsOn?.dayAndMonth))
                .font(MemoBookFont.caption)
                .foregroundStyle(MemoBookColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            if memory.isExhausted {
                BrandNotice(MemoryCopy.exhausted, tone: .information)
            } else if memory.isRunningLow {
                BrandNotice(MemoryCopy.runningLow, tone: .information)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Le barème, et pourquoi un vocal pèse plus.
    private var pricing: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            Text(MemoryCopy.pricingHeading)
                .font(MemoBookFont.sectionOverline)
                .foregroundStyle(MemoBookColor.inkMuted)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)

            ForEach(
                MemoryCopy.pricing(
                    text: memory.textCost,
                    voicePerMinute: memory.voiceCostPerMinute
                ),
                id: \.self
            ) { line in
                Text(line)
                    .font(MemoBookFont.body)
                    .foregroundStyle(MemoBookColor.ink)
            }

            Text(MemoryCopy.voiceExplanation)
                .font(MemoBookFont.taglineRegular)
                .foregroundStyle(MemoBookColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Les deux paliers, côte à côte

    /// L'écran de décision : ce qu'on a, ce qu'on aurait, et le prix une seule
    /// fois — sur le bouton.
    private var compare: some View {
        BrandSheet(MemoryCopy.compareHeading, subtitle: MemoryCopy.sheetIntro) {
            VStack(spacing: MemoBookSpacing.m) {
                VStack(spacing: MemoBookSpacing.xs) {
                    MemoryPlanCard(
                        title: MemoryPlan.included.title,
                        detail: MemoryCopy.includedDetail(memory.allowance),
                        price: MemoryCopy.includedPrice,
                        isCurrent: memory.plan == .included
                    )
                    MemoryPlanCard(
                        title: MemoryPlan.extended.title,
                        detail: MemoryCopy.extendedDetail(
                            allowance: Self.extendedAllowance,
                            price: "\(memory.upgradeWeeklyPrice.euros)/semaine"
                        ),
                        price: memory.upgradeWeeklyPrice.euros,
                        isCurrent: memory.plan == .extended
                    )
                }

                if let message = model.errorMessage {
                    ErrorBanner(message: message)
                }

                VStack(spacing: MemoBookSpacing.s) {
                    BrandButton(
                        MemoryCopy.upgradeCta(price: memory.upgradeWeeklyPrice.euros),
                        style: .accent,
                        isLoading: model.isChangingMemoryPlan,
                        fillsWidth: true
                    ) {
                        Task {
                            if await model.changeMemoryPlan(to: .extended) { step = .done }
                        }
                    }

                    BrandButton(MemoryCopy.close, style: .secondary, fillsWidth: true) {
                        step = .status
                    }
                }
            }
        }
    }

    // MARK: - C'est fait

    private var done: some View {
        BrandSheet(
            "C’est étendu",
            paragraphs: [
                MemoryCopy.extendedDetail(
                    allowance: memory.allowance,
                    price: "\(memory.upgradeWeeklyPrice.euros)/semaine"
                ),
                "Tu peux revenir aux limites comprises quand tu veux, depuis cette même ligne.",
            ]
        ) {
            BrandButton(MemoryCopy.close, fillsWidth: true) { dismiss() }
        }
    }
}

// MARK: - Une carte de palier

/// Un palier, dans l'écran de comparaison.
///
/// Ce n'est pas une ``BrandOptionRow`` : on ne coche pas un palier, on en
/// choisit un par le bouton du bas. Celle-ci **décrit** — un nom, un prix, une
/// phrase — et signale seulement lequel on a déjà.
private struct MemoryPlanCard: View {
    let title: String
    let detail: String
    let price: String
    let isCurrent: Bool

    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.controlCornerRadius)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs / 2) {
            HStack(alignment: .firstTextBaseline, spacing: MemoBookSpacing.xs) {
                Text(title)
                    .font(MemoBookFont.bodySemibold)
                    .foregroundStyle(MemoBookColor.ink)

                if isCurrent {
                    BrandTagPill("Ton palier", tone: .accentOutlined, isUppercased: true)
                }

                Spacer(minLength: MemoBookSpacing.xs)

                Text(price)
                    .font(MemoBookFont.label)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .fixedSize()
            }

            Text(detail)
                .font(MemoBookFont.taglineRegular)
                .foregroundStyle(MemoBookColor.inkMuted)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MemoBookSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCurrent ? MemoBookColor.outline.opacity(0.35) : Color.clear, in: shape)
        .overlay {
            shape.strokeBorder(
                isCurrent ? MemoBookColor.outline : MemoBookColor.hairline,
                lineWidth: 1
            )
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Limites de souvenirs") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            MemoryAllowanceSheet(model: TripSettingsModel(tripId: "preview"))
        }
}
