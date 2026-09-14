import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Étape 7 — c'est parti.
///
/// Elle lit **la commande** et non le brouillon : c'est le serveur qui a le
/// dernier mot sur ce qui a été enregistré, y compris le délai annoncé.
///
/// Il n'y a pas de flèche de retour utile ici — ``OrderStep/allowsGoingBack``
/// la referme sur l'écran plutôt que de ramener au paiement d'une commande
/// déjà passée.
struct OrderConfirmationStep: View {
    let model: OrderModel
    let onShare: () -> Void
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasLanded = false

    var body: some View {
        OrderStepLayout {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                seal
                headline
                deliveryCard
                giftCard

                if let message = model.errorMessage {
                    ErrorBanner(message: message)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } actions: {
            BrandButton(
                BookCopy.Order.Confirmation.share,
                isLoading: model.isPreparingLink,
                fillsWidth: true,
                action: onShare
            )
            .disabled(model.isPreparingLink)

            BrandButton(
                BookCopy.Order.Confirmation.home,
                style: .secondary,
                fillsWidth: true,
                action: onFinish
            )
        }
        .task {
            // La pastille se pose une fois, à l'arrivée. Sans ce délai elle
            // apparaîtrait pendant la transition de l'étape et les deux
            // mouvements se marcheraient dessus.
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { hasLanded = true }
        }
    }

    /// La pastille verte et sa coche. Le seul moment de l'app où quelque chose
    /// se conclut : elle a le droit de rebondir une fois.
    private var seal: some View {
        Image(brand: "IconLucideCheck")
            .resizable()
            .scaledToFit()
            .frame(width: 26, height: 26)
            .foregroundStyle(MemoBookColor.action)
            .frame(width: 66, height: 66)
            .background(MemoBookColor.accent, in: .circle)
            .scaleEffect(hasLanded || reduceMotion ? 1 : 0.4)
            .opacity(hasLanded || reduceMotion ? 1 : 0)
            .accessibilityHidden(true)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
            Text(BookCopy.Order.Confirmation.title)
                .font(MemoBookFont.h1)
                .foregroundStyle(MemoBookColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(model.confirmationDetail)
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Ce qui part, quand, et en combien d'exemplaires.
    ///
    /// ⚠️ Le bouton « Être informé par WhatsApp » de la maquette **n'est pas
    /// ici**, et volontairement : il n'y a ni numéro collecté pour le suivi, ni
    /// envoi côté serveur. Une case qui ne retient rien est exactement l'écran
    /// qui ment que `CLAUDE.md` interdit — il reviendra avec la route qui le
    /// tient.
    private var deliveryCard: some View {
        HStack(alignment: .top, spacing: MemoBookSpacing.s) {
            cover

            VStack(alignment: .leading, spacing: MemoBookSpacing.xs / 2) {
                Text(BookCopy.Order.Confirmation.delivery)
                    .font(MemoBookFont.overline)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .textCase(.uppercase)

                if let days = model.confirmationDays {
                    Text(days.deliveryLabel)
                        .font(MemoBookFont.bodySemibold)
                        .foregroundStyle(MemoBookColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(model.confirmationSummary)
                    .font(MemoBookFont.label)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(MemoBookSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MemoBookColor.surface,
            in: .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)
                .strokeBorder(MemoBookColor.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// La couverture du carnet commandé — celle que le serveur a figée avec la
    /// commande, et à défaut celle du voyage.
    @ViewBuilder
    private var cover: some View {
        let url = model.order?.coverImageUrl ?? model.context?.trip.coverPhotoUrl

        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                MemoBookColor.beige
            }
        }
        .frame(width: 84, height: 98)
        .clipShape(.rect(cornerRadius: MemoBookSpacing.cornerRadius))
        .accessibilityHidden(true)
    }

    /// « Envie de l'offrir ? » — l'aplat lime, seul large aplat que porte la
    /// marque.
    ///
    /// Elle **n'est pas un bouton** : recommander se fait depuis le carnet, à
    /// tout moment, et c'est exactement ce que la phrase dit. Un bouton ici
    /// promettrait un raccourci qui n'existe pas.
    private var giftCard: some View {
        HStack(alignment: .top, spacing: MemoBookSpacing.s) {
            Image(brand: "IconLucideHeart")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(MemoBookColor.action)
                .frame(width: 44, height: 44)
                .background(MemoBookColor.surface.opacity(0.6), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(BookCopy.Order.Confirmation.giftTitle)
                    .font(MemoBookFont.bodySemibold)
                    .foregroundStyle(MemoBookColor.ink)

                Text(BookCopy.Order.Confirmation.giftDetail)
                    .font(MemoBookFont.label)
                    .foregroundStyle(MemoBookColor.ink.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(MemoBookSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MemoBookColor.accent.opacity(0.5),
            in: .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
        )
        .accessibilityElement(children: .combine)
    }
}
