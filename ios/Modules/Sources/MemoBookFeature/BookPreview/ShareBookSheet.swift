import MemoBookCore
import MemoBookDesign
import SwiftUI
import UIKit

/// « Partager ton MemoBook » : le choix entre un fichier et un lien.
///
/// Deux façons de partager, et elles ne disent pas la même chose :
///
/// - **Le PDF** est le carnet tel qu'il est aujourd'hui. Il s'ouvre hors
///   connexion, il s'imprime, il ne bougera plus.
/// - **Le lien** est le carnet tel qu'il sera. Il suit la conversation : ceux
///   qui l'ouvrent voient les étapes s'ajouter, ce qui est exactement ce qu'il
///   faut pour donner envie d'aider à le financer.
///
/// La carte du haut n'est pas décorative : c'est **l'aperçu de ce que le
/// destinataire verra**. Le lien de prévisualisation porte des métadonnées Open
/// Graph, et c'est cette vignette-là qui apparaîtra dans WhatsApp. La montrer
/// avant d'envoyer évite la surprise.
struct ShareBookSheet: View {
    let preview: BookPreview?
    let isPreparingLink: Bool
    let onSharePdf: () -> Void
    let onShareLink: () -> Void

    var body: some View {
        BrandSheet(BookCopy.Share.title) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                previewCard

                VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
                    Text(BookCopy.Share.message)
                        .font(MemoBookFont.caption)
                        .foregroundStyle(MemoBookColor.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    BrandButton(
                        BookCopy.Share.sharePdf,
                        icon: Image(brand: "IconCube"),
                        style: .secondary,
                        fillsWidth: true,
                        action: onSharePdf
                    )

                    BrandButton(
                        BookCopy.Share.shareLink,
                        icon: Image(brand: "IconCube"),
                        style: .primary,
                        isLoading: isPreparingLink,
                        fillsWidth: true,
                        action: onShareLink
                    )
                }
            }
        }
    }

    /// La carte que le destinataire verra : la couverture, le voyage, sa date,
    /// et deux lignes du récit.
    private var previewCard: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)

        return VStack(spacing: 0) {
            cover
            excerpt
        }
        .background(MemoBookColor.background, in: shape)
        .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
        .clipShape(shape)
        .brandShadow(.soft)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    /// La couverture, sous un dégradé qui part du milieu : le titre posé
    /// dessus doit rester lisible quelle que soit la photo, et une photo claire
    /// en bas est le cas courant — c'est là que tombe la plage ou le ciel.
    private var cover: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: preview?.coverPhotoUrl) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    // Pas de couverture : le bleu de la marque plutôt qu'un
                    // gris. La carte reste une carte de voyage.
                    MemoBookColor.outline
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.5),
                        .init(
                            color: Color(red: 0.102, green: 0.184, blue: 0.145).opacity(0.63),
                            location: 1
                        ),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            tripInfo
        }
        .overlay(alignment: .topTrailing) { mark }
    }

    private var tripInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(preview?.title ?? "")
                .font(MemoBookFont.heading)
                .foregroundStyle(MemoBookColor.onAction)
                .lineLimit(2)

            if let tripDate = preview?.tripDate {
                let date = tripDate.formatted(.dateTime.day().month(.abbreviated).year())

                HStack(spacing: MemoBookSpacing.xs / 2) {
                    Image(brand: "IconLucideCalendar")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 10, height: 10)
                        .foregroundStyle(MemoBookColor.onAction.opacity(0.8))

                    Text(date)
                        .font(MemoBookFont.caption)
                        .foregroundStyle(MemoBookColor.onAction.opacity(0.8))
                }
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(MemoBookSpacing.s)
    }

    /// Le signe de la marque, dans une pastille floutée. C'est la seule marque
    /// que porte la carte partagée : elle voyage hors de l'app, elle doit dire
    /// d'où elle vient.
    private var mark: some View {
        Image(brand: "LogoMemobookCreme")
            .resizable()
            .scaledToFit()
            .frame(width: 38, height: 26)
            .padding(.horizontal, MemoBookSpacing.xs)
            .padding(.vertical, MemoBookSpacing.xs / 2)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: MemoBookSpacing.xs))
            .padding(MemoBookSpacing.s)
            .accessibilityHidden(true)
    }

    private var excerpt: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs / 2) {
            // Les guillemets font partie de la citation et non du récit : c'est
            // la carte qui cite, le carnet écrit au fil de l'eau.
            Text("« \(preview?.excerpt?.quote ?? "") »")
                .font(MemoBookFont.bodySemibold)
                .foregroundStyle(MemoBookColor.ink)
                .lineLimit(1)

            if let detail = preview?.excerpt?.detail {
                Text(detail)
                    .font(MemoBookFont.body)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MemoBookSpacing.s)
    }

    private var accessibilityDescription: String {
        [preview?.title, preview?.excerpt?.quote, preview?.excerpt?.detail]
            .compactMap(\.self)
            .joined(separator: ". ")
    }
}

// MARK: - La feuille de partage du système

/// Ce qui part dans la feuille de partage : un message, et au plus un fichier.
///
/// `Identifiable` pour être présentable par `sheet(item:)` — l'identité change
/// à chaque partage, ce qui garantit que la feuille se rouvre même si on
/// repartage la même chose.
struct BookSharePayload: Identifiable {
    let id = UUID()
    let title: String
    let steps: Int
    /// Le PDF écrit sur le disque, quand c'est lui qu'on partage.
    let file: URL?
    /// Le lien de la cagnotte. Il accompagne **les deux** modes de partage :
    /// c'est le message qui demande un coup de main, pas la pièce jointe.
    let link: URL?

    /// Le message pré-rempli. C'est lui qui apparaît dans WhatsApp, iMessage ou
    /// Snapchat dès que l'app de destination est choisie.
    var message: String? {
        guard let link else { return nil }
        return BookCopy.Share.invitation(title: title, steps: steps, link: link)
    }
}

/// La feuille de partage d'iOS, avec le message et le fichier dedans.
///
/// **Celle du système et pas la nôtre.** Elle seule connaît les apps
/// installées, les appareils AirDrop à portée, les raccourcis de l'utilisateur
/// et l'ordre dans lequel il partage d'habitude. En redessiner une ne donnerait
/// qu'une liste plus courte et périmée — c'est pour ça que les deux maquettes
/// « Modale - Partager son MB - 2 » et « - 5 » ne sont pas implémentées : elles
/// dessinent la feuille du système, elles ne la remplacent pas.
struct BookShareSheet: UIViewControllerRepresentable {
    let payload: BookSharePayload

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // L'ordre compte : le message d'abord, le fichier ensuite. C'est lui
        // qui décide de ce qu'une app de messagerie met dans le corps du
        // message et de ce qu'elle met en pièce jointe.
        var items: [Any] = []
        if let message = payload.message { items.append(message) }
        if let file = payload.file { items.append(file) }
        // Ni message ni fichier ne devrait pas arriver — la vue ne présente la
        // feuille qu'avec l'un des deux — mais un partage vide vaut mieux qu'un
        // plantage.
        if items.isEmpty { items.append(payload.title) }

        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.setValue(BookCopy.Share.subject(title: payload.title), forKey: "subject")
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview("Partager ton MemoBook") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            ShareBookSheet(
                preview: .fixture,
                isPreparingLink: false,
                onSharePdf: {},
                onShareLink: {}
            )
        }
        .environment(\.colorScheme, .light)
}
