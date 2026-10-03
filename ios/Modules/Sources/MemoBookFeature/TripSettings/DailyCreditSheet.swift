import MemoBookCore
import MemoBookDesign
import SwiftUI

/// « Crédit du jour » — ce que le voyage peut encore raconter aujourd'hui,
/// comment le crédit se consomme, et la porte de l'illimité.
///
/// **Une seule étape** (Hugo, 03/10/2026). Elle remplace la feuille des
/// limites de souvenirs et ses trois temps (le solde, la comparaison des
/// paliers, « C’est étendu ») : il n'y a plus de palier à choisir ici. On lit
/// le reste, on comprend la règle, et l'on passe en illimité — ce qui se fait
/// **dans le paywall**, pas dans cette feuille.
///
/// ```
/// Il reste 3 min 20 aujourd’hui        ← ou « Plus rien pour aujourd’hui : reviens demain »
/// ▬▬▬▬▬▬▬▬▬▬▬▬▬▭▭▭▭▭▭▭                  ← ce qui reste : verte, le rail rouge à zéro
/// soit environ 2 650 caractères à l’écrit
///
/// (co-voyageurs) 5 minutes par jour pour ce voyage, à partager entre co-voyageurs.
/// (micro)        Un vocal consomme sa durée ; à l’écrit, 800 caractères valent une minute…
/// (calendrier)   Le crédit se recharge chaque nuit, à minuit.
///
/// [ Passer en illimité ]   ← lime : le lime ne dit que l'abonnement
/// [ Fermer ]
/// ```
///
/// **Le bouton ne pose pas le paywall sur la feuille.** Une feuille ne
/// s'empile pas sur une autre (règle du design system) : ``onSubscribe``
/// remonte à ``TripSettingsView``, qui referme la feuille puis ouvre le
/// paywall en plein écran — le motif de « En savoir plus » dans le profil.
///
/// Pour un abonné, ni jauge ni bouton : « Illimité », et un paragraphe qui
/// rappelle ce que l'abonnement n'ouvre pas — ses co-voyageurs non abonnés
/// partagent toujours le crédit du voyage.
///
/// ⚠️ **Aucune maquette ne la dessine** (T248). Elle reprend les composants
/// validés — ``BrandSheet``, ``BrandGauge``, ``BrandButton`` — et reste à
/// dessiner dans Figma.
struct DailyCreditSheet: View {
    let model: TripSettingsModel

    /// « Passer en illimité ». La vue des réglages ferme la feuille et ouvre le
    /// paywall ; la feuille, elle, ne présente rien.
    let onSubscribe: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.subscriptionSession) private var subscriptionSession

    @ScaledMetric(relativeTo: .body) private var ruleIconSide: CGFloat = MemoBookSpacing.contentIcon

    /// Le crédit servi avec les réglages, relu avec le dernier geste de la
    /// session : juste après un achat, il dit « Illimité » sans attendre que
    /// les réglages soient relus. Sans réponse du serveur — un aperçu —, le
    /// barème du catalogue, neuf.
    private var credit: DailyCredit {
        let served = model.dailyCredit ?? DailyCredit()
        return subscriptionSession?.applied(to: served) ?? served
    }

    var body: some View {
        let credit = credit

        BrandSheet(DailyCreditCopy.title) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                if credit.isUnlimited {
                    unlimited(credit)
                } else {
                    balance(credit)
                    rules(credit)
                }

                VStack(spacing: MemoBookSpacing.s) {
                    if !credit.isUnlimited {
                        BrandButton(
                            DailyCreditCopy.unlimitedCallToAction,
                            style: .accent,
                            fillsWidth: true,
                            action: onSubscribe
                        )
                    }

                    BrandButton(
                        DailyCreditCopy.Sheet.close,
                        style: credit.isUnlimited ? .primary : .secondary,
                        fillsWidth: true
                    ) {
                        dismiss()
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: credit)
    }

    // MARK: - Ce qui reste

    /// Le reste du jour, la jauge, et ce que ça vaut au clavier.
    private func balance(_ credit: DailyCredit) -> some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            Text(DailyCreditCopy.Sheet.remaining(credit))
                .font(MemoBookFont.calloutTitle)
                .foregroundStyle(MemoBookColor.ink)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)

            // Ce qui **reste**, comme la phrase au-dessus (recette du
            // 03/10/2026). Deux couleurs, comme partout : le vert tant qu'il
            // reste du crédit, le rouge sémantique quand il n'y a plus rien.
            BrandGauge(
                fraction: credit.gaugeFraction,
                isExhausted: credit.isExhausted,
                accessibilityLabel: DailyCreditCopy.title,
                accessibilityValue: DailyCreditCopy.Sheet.gaugeAccessibilityValue(credit)
            )

            if let characters = DailyCreditCopy.Sheet.charactersEquivalent(credit) {
                Text(characters)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - La règle

    /// Les trois phrases qui font le crédit : le partage, ce qui consomme, la
    /// recharge. Une icône chacune, pour qu'on les retrouve d'un coup d'œil
    /// sans les relire.
    private func rules(_ credit: DailyCredit) -> some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
            rule(icon: "IconLucideUsers", DailyCreditCopy.Sheet.sharing(limitMs: credit.limitMs))
            rule(
                icon: "IconMic",
                DailyCreditCopy.Sheet.consumption(textMsPerCharacter: credit.textMsPerCharacter)
            )
            rule(icon: "IconLucideCalendar", DailyCreditCopy.Sheet.recharge)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rule(icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: MemoBookSpacing.snug) {
            Image(brand: icon)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: ruleIconSide, height: ruleIconSide)
                .foregroundStyle(MemoBookColor.inkMuted)
                .accessibilityHidden(true)

            Text(text)
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Abonné

    private func unlimited(_ credit: DailyCredit) -> some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            Text(DailyCreditCopy.unlimited)
                .font(MemoBookFont.calloutTitle)
                .foregroundStyle(MemoBookColor.ink)

            Text(DailyCreditCopy.Sheet.unlimitedExplanation(limitMs: credit.limitMs))
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension DailyCredit {
    /// Ce que la jauge des réglages remplit : la part du crédit qui **reste**
    /// (recette du 03/10/2026) — pleine au matin, elle se vide à mesure qu'on
    /// raconte. Le chiffre posé à côté dit le reste, la barre dit la même
    /// chose. Rien à remplir sans limite à partager.
    var gaugeFraction: Double {
        guard limitMs > 0 else { return 0 }
        return min(1, Double(remainingMs) / Double(limitMs))
    }
}

#Preview("Crédit du jour") {
    let model = TripSettingsModel(tripId: "preview")

    return Color.clear
        .background(MemoBookColor.background)
        .task { await model.load() }
        .sheet(isPresented: .constant(true)) {
            DailyCreditSheet(model: model, onSubscribe: {})
        }
}

#Preview("Crédit du jour — épuisé") {
    let model = TripSettingsModel(
        tripId: "preview",
        source: { _ in
            var settings = TripSettings.fixture
            settings.dailyCredit = DailyCredit(usedMs: DailyCredit.Catalog.limitMs)
            return settings
        }
    )

    return Color.clear
        .background(MemoBookColor.background)
        .task { await model.load() }
        .sheet(isPresented: .constant(true)) {
            DailyCreditSheet(model: model, onSubscribe: {})
        }
}

#Preview("Crédit du jour — abonné") {
    let model = TripSettingsModel(
        tripId: "preview",
        source: { _ in
            var settings = TripSettings.fixture
            settings.dailyCredit = DailyCredit(isUnlimited: true)
            return settings
        }
    )

    return Color.clear
        .background(MemoBookColor.background)
        .task { await model.load() }
        .sheet(isPresented: .constant(true)) {
            DailyCreditSheet(model: model, onSubscribe: {})
        }
}
