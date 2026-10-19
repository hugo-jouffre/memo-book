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
    let onOpenBook: () -> Void
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var hasLanded = false

    /// La phrase d'ouverture, titre du carnet en gras.
    ///
    /// Elle est montée **une fois**, à l'arrivée de la commande, et pas dans le
    /// `body` : analyser du Markdown à chaque image d'animation, c'est le
    /// travail qu'un `body` ne doit jamais faire. `.task(id:)` la remonte si le
    /// serveur change la phrase sous nos yeux.
    @State private var detail = AttributedString()

    /// La feuille qui demande le numéro, quand le compte n'en a pas encore.
    @State private var isAskingPhone = false

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
                icon: Image(brand: "IconShareNodes"),
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
        .brandSheet(isPresented: $isAskingPhone) {
            OrderWhatsAppSheet(
                suggested: model.suggestedPhoneNumber,
                onConfirm: { phone in
                    isAskingPhone = false
                    Task { await model.setWhatsAppTracking(phone: phone) }
                }
            )
        }
        .task(id: model.confirmationDetail) {
            detail = (try? AttributedString(markdown: model.confirmationDetail))
                ?? AttributedString(model.confirmationDetail)
        }
        .task {
            // La pastille se pose une fois, à l'arrivée. Sans ce délai elle
            // apparaîtrait pendant la transition de l'étape et les deux
            // mouvements se marcheraient dessus.
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { hasLanded = true }
        }
    }

    /// La pastille verte et sa coche, **centrée** — seul élément de l'écran qui
    /// ne s'aligne pas à gauche : c'est un sceau posé sur la page, pas une
    /// ligne du texte. Le seul moment de l'app où quelque chose se conclut :
    /// elle a le droit de rebondir une fois.
    private var seal: some View {
        Image(brand: "IconLucideCheck")
            .resizable()
            .scaledToFit()
            .frame(width: 26, height: 26)
            .foregroundStyle(MemoBookColor.ink)
            .frame(width: 66, height: 66)
            .background(MemoBookColor.accent, in: .circle)
            .scaleEffect(hasLanded || reduceMotion ? 1 : 0.4)
            .opacity(hasLanded || reduceMotion ? 1 : 0)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityHidden(true)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
            Text(BookCopy.Order.Confirmation.title)
                .font(MemoBookFont.h1)
                .foregroundStyle(MemoBookColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Ce qui part, quand, et en combien d'exemplaires — et « Être informé par
    /// WhatsApp », qui enregistre l'accord et le numéro sur la commande
    /// (`POST /v1/orders/:id/whatsapp`). Aucun message ne part encore : le
    /// bouton le dit une fois accepté.
    ///
    /// Aux tailles de texte accessibles, la couverture passe **au-dessus** du
    /// texte au lieu d'être à côté : à 200 %, « Dans 5 à 7 jours » n'a plus que
    /// deux mots par ligne dans la colonne qui reste.
    ///
    /// ⚠️ **« Être informé par whatsapp » est sous la rangée, pas dans la
    /// colonne** comme sur la maquette : à côté d'une couverture, la colonne
    /// qui reste fait 195 pt sur un iPhone SE et le libellé s'y coupait en
    /// « Être informé par what… ». Un `ViewThatFits` qui aurait gardé la
    /// maquette sur les grands écrans se range sur la largeur *idéale* de la
    /// colonne, pas sur celle du libellé : il descendait le bouton partout. Une
    /// seule disposition, qui tient de 375 à 440 pt, vaut mieux qu'un libellé
    /// rogné sur le plus petit téléphone encore vendu.
    private var deliveryCard: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            if typeSize.isAccessibilitySize {
                cover
                deliveryDetails
            } else {
                HStack(alignment: .top, spacing: MemoBookSpacing.s) {
                    cover
                    deliveryDetails
                }
            }

            whatsappButton
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
    }

    private var deliveryDetails: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs / 2) {
            // Le vert d'action plutôt que le gris : dans la maquette, c'est
            // lui qui dit que cette carte parle de ce qui arrive, et non d'un
            // réglage qu'on vient de choisir.
            Text(BookCopy.Order.Confirmation.delivery)
                .font(MemoBookFont.overline)
                .foregroundStyle(MemoBookColor.action)

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

    /// « Être informé par WhatsApp ».
    ///
    /// Il **bascule** : accepter puis se raviser doit être possible sans
    /// quitter l'écran. Un compte qui a déjà son numéro accepte d'un seul
    /// geste ; les autres passent par la feuille, qui enregistre le numéro sur
    /// le compte au passage.
    @ViewBuilder
    private var whatsappButton: some View {
        VStack(alignment: .leading, spacing: 4) {
            BrandButton(
                model.wantsWhatsApp
                    ? BookCopy.Order.Confirmation.whatsappStop
                    : BookCopy.Order.Confirmation.whatsapp,
                icon: Image(brand: "LogoWhatsApp"),
                style: .link,
                size: .small,
                isLoading: model.isSavingWhatsApp,
                tint: MemoBookColor.action
            ) {
                guard !model.isSavingWhatsApp else { return }

                if model.wantsWhatsApp {
                    Task { await model.setWhatsAppTracking(phone: nil) }
                } else if let known = model.suggestedPhoneNumber {
                    Task { await model.setWhatsAppTracking(phone: known) }
                } else {
                    isAskingPhone = true
                }
            }

            // ⚠️ Ce que l'écran ne promet pas : rien ne part encore. Le dire
            // une fois accepté, plutôt que de laisser attendre un message.
            if model.wantsWhatsApp {
                Text(BookCopy.Order.Confirmation.whatsappNotLiveYet)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.25), value: model.wantsWhatsApp)
    }

    /// La couverture du carnet commandé — celle que le serveur a figée avec la
    /// commande, et à défaut celle du voyage.
    ///
    /// Le fond beige est posé **sous** l'image et non à sa place : la carte
    /// garde sa forme dès la première image, et la photo n'y apparaît qu'une
    /// fois reçue, en fondu, sans faire sauter la hauteur de la carte.
    @ViewBuilder
    private var cover: some View {
        let url = model.order?.coverImageUrl ?? model.context?.trip.coverPhotoUrl

        MemoBookColor.beige
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: .smooth(duration: 0.2))) {
                    phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    }
                }
            }
            .frame(width: coverSide, height: coverSide)
            .clipShape(.rect(cornerRadius: MemoBookSpacing.largeCornerRadius))
            .accessibilityHidden(true)
    }

    /// Le côté de la couverture, qui suit le Dynamic Type : elle est à côté du
    /// texte, elle grandit avec lui.
    @ScaledMetric(relativeTo: .body) private var coverSide: CGFloat = 100

    /// « Envie de l'offrir ? » — l'aplat lime, seul large aplat que porte la
    /// marque.
    ///
    /// Elle **mène au carnet**, qui est exactement ce que la phrase dit : c'est
    /// de là qu'un exemplaire se recommande, à tout moment. La flèche n'est
    /// donc pas un ornement — toute la carte est le bouton, et elle vide la
    /// pile comme « Retour à l'accueil » avant d'ouvrir le carnet : derrière la
    /// commande il y a l'aperçu et les réglages, et reculer les rejouerait un
    /// par un.
    ///
    /// Aux tailles accessibles elle s'empile, comme la carte de livraison : le
    /// pictogramme et la flèche laissaient deux mots par ligne au texte. La
    /// flèche disparaît alors — ce n'est pas elle qui porte le geste, c'est la
    /// carte entière, et VoiceOver l'annonce par son conseil.
    private var giftCard: some View {
        Button(action: onOpenBook) {
            giftLayout
        }
        .buttonStyle(GiftCardPress())
        .accessibilityElement(children: .combine)
        .accessibilityHint(BookCopy.Order.Confirmation.giftHint)
    }

    @ViewBuilder
    private var giftLayout: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                    giftIcon
                    giftText
                }
            } else {
                HStack(alignment: .center, spacing: MemoBookSpacing.s) {
                    giftIcon
                    giftText

                    // La flèche ne suit pas le Dynamic Type : c'est un signe,
                    // pas un mot, et elle prendrait la moitié de la carte.
                    Image(brand: "IconArrowRight")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(MemoBookColor.ink)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(MemoBookSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MemoBookColor.accent,
            in: .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
        )
        .contentShape(.rect(cornerRadius: MemoBookSpacing.largeCornerRadius))
    }

    private var giftIcon: some View {
        Image(brand: "IconLucideGift")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: MemoBookSpacing.contentIcon, height: MemoBookSpacing.contentIcon)
            .foregroundStyle(MemoBookColor.ink)
            .frame(width: 52, height: 52)
            .background(
                MemoBookColor.surface.opacity(0.6),
                in: .rect(cornerRadius: MemoBookSpacing.cornerRadius)
            )
    }

    private var giftText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(BookCopy.Order.Confirmation.giftTitle)
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(BookCopy.Order.Confirmation.giftDetail)
                .font(MemoBookFont.label)
                .foregroundStyle(MemoBookColor.ink.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
    }
}

/// L'enfoncement de la carte « Envie de l'offrir ? » : elle recule à peine,
/// comme les boutons de la marque — ``BrandButton`` fait exactement ça, et une
/// carte qui ne bouge pas sous le doigt ne se lit pas comme un bouton.
private struct GiftCardPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
    }
}
