import MemoBookCore
import MemoBookDesign
import SwiftUI

/// L'abonnement : ce qu'il coûte, ce qu'il rend, et la porte de sortie.
///
/// Le prix apparaît **trois fois** — la pastille, la phrase, le bouton — et
/// c'est voulu : on ne demande pas d'appuyer sur un bouton dont le montant se
/// lit ailleurs. Il n'est écrit qu'une fois dans le code.
struct SubscriptionSheet: View {
    let subscription: Subscription?
    let onActivate: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private var price: String { (subscription?.weeklyPrice ?? 0).euros }

    var body: some View {
        BrandSheet(
            "Mon Abonnement",
            subtitle: "Poursuis l’enregistrement de tes souvenirs de voyage sans aucune interruption."
        ) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                offer

                BrandButton("Activer mon abonnement (\(price))", fillsWidth: true) {
                    onActivate()
                    dismiss()
                }
                .padding(.top, MemoBookSpacing.xs)

                BrandButton("Plus tard (consulter les souvenirs existants)", style: .secondary, fillsWidth: true) {
                    dismiss()
                }
            }
        }
    }

    /// L'argument de vente, sur l'aplat bleu de la marque.
    private var offer: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            priceLine

            Text("100% de la somme versée est déduite du prix final de ton carnet imprimé !")
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.action)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: typeSize.isAccessibilitySize ? .leading : .center)

            learnMore
                .frame(maxWidth: .infinity, alignment: typeSize.isAccessibilitySize ? .leading : .center)
        }
        .padding(MemoBookSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MemoBookColor.outline.opacity(0.35),
            in: .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
        )
    }

    @ViewBuilder
    private var priceLine: some View {
        let pill = Text(price)
            .font(MemoBookFont.bodySemibold)
            .foregroundStyle(MemoBookColor.ink)
            .padding(.horizontal, MemoBookSpacing.s)
            .padding(.vertical, MemoBookSpacing.xs)
            .background(
                // Le vert de la marque, assez posé pour porter de l'encre :
                // la pastille est une étiquette de prix, pas un bouton.
                MemoBookColor.action.opacity(0.35),
                in: .rect(cornerRadius: MemoBookSpacing.controlCornerRadius)
            )

        let cadence = Text("/ semaine (sans engagement)")
            .font(MemoBookFont.bodySemibold)
            .foregroundStyle(MemoBookColor.action)
            .fixedSize(horizontal: false, vertical: true)

        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                pill
                cadence
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: MemoBookSpacing.xs) {
                pill
                cadence
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// ⚠️ Aucune destination n'est dessinée derrière « En savoir plus ». Le lien
    /// est posé comme la maquette le montre et ne mène nulle part — signalé dans
    /// la fiche écran.
    private var learnMore: some View {
        BrandButton(
            "En savoir plus",
            icon: Image(brand: "IconQuestion"),
            style: .link
        ) {}
    }
}

#Preview("Mon Abonnement") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            SubscriptionSheet(subscription: TravellerProfile.fixture.subscription) {}
        }
}
