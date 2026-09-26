import MemoBookCore
import MemoBookDesign
import LinkPresentation
import SwiftUI
import UniformTypeIdentifiers
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

                    // Deux gestes, deux icônes (Hugo, 17/09/2026, T68) : le
                    // fichier porte le PDF, le lien porte l'œil de la
                    // prévisualisation. Le cube Relume de la maquette était un
                    // reste de composant.
                    BrandButton(
                        BookCopy.Share.sharePdf,
                        icon: Image(brand: "IconPDF"),
                        style: .secondary,
                        fillsWidth: true,
                        action: onSharePdf
                    )

                    BrandButton(
                        BookCopy.Share.shareLink,
                        icon: Image(brand: "IconView"),
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
    /// Les étapes déjà racontées, que le message annonce. `nil` depuis la
    /// cagnotte, qui ne sait pas où en est le récit : la phrase s'en passe.
    let steps: Int?
    /// Le PDF écrit sur le disque, quand c'est lui qu'on partage.
    let file: URL?
    /// Le lien de la cagnotte. Il accompagne **les deux** modes de partage :
    /// c'est le message qui demande un coup de main, pas la pièce jointe.
    let link: URL?
    /// La photo du voyage, en tête de la feuille — la vignette de la maquette
    /// (`3551:26331`). Sans elle, iOS pose l'icône de l'app.
    var coverPhotoUrl: URL?
    /// Les gestes que la feuille ajoute aux apps du système : « Commander »,
    /// « Partager sur Whatsapp ».
    var actions: [ShareAction] = []

    init(
        title: String,
        steps: Int?,
        file: URL?,
        link: URL?,
        coverPhotoUrl: URL? = nil,
        actions: [ShareAction] = []
    ) {
        self.title = title
        self.steps = steps
        self.file = file
        self.link = link
        self.coverPhotoUrl = coverPhotoUrl
        self.actions = actions
    }

    /// Le message pré-rempli. C'est lui qui apparaît dans WhatsApp, iMessage ou
    /// Snapchat dès que l'app de destination est choisie.
    var message: String? {
        guard let link else { return nil }
        guard let steps else { return BookCopy.Share.invitation(title: title, link: link) }
        return BookCopy.Share.invitation(title: title, steps: steps, link: link)
    }
}

/// Un geste de plus dans la feuille du système — une ligne sous les apps,
/// comme « Imprimer ».
struct ShareAction: Identifiable {
    let id = UUID()
    let title: String
    /// Un nom du catalogue de la marque.
    let icon: String
    let perform: () -> Void

    /// « Partager sur Whatsapp » : WhatsApp ouvert sur le message, sans passer
    /// par son extension de partage — qui laisse le texte de côté quand un
    /// lien l'accompagne.
    static func whatsApp(message: String) -> ShareAction? {
        guard
            let encoded = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "whatsapp://send?text=\(encoded)"),
            UIApplication.shared.canOpenURL(url)
        else { return nil }
        return ShareAction(title: BookCopy.Share.whatsAppAction, icon: "LogoWhatsApp") {
            UIApplication.shared.open(url)
        }
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
///
/// Ce qu'on y met, en revanche, suit la maquette `3551:26331` : le titre du
/// voyage et sa photo en tête, et deux gestes sous les apps — « Commander »,
/// « Partager sur Whatsapp ».
struct BookShareSheet: UIViewControllerRepresentable {
    let payload: BookSharePayload

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // L'ordre compte : le message d'abord, le fichier ensuite. C'est lui
        // qui décide de ce qu'une app de messagerie met dans le corps du
        // message et de ce qu'elle met en pièce jointe.
        var items: [Any] = []
        if let message = payload.message {
            items.append(
                ShareMessageSource(
                    message: message,
                    title: payload.title,
                    link: payload.link,
                    coverPhotoUrl: payload.coverPhotoUrl
                )
            )
        }
        if let file = payload.file { items.append(file) }
        // Ni message ni fichier ne devrait pas arriver — la vue ne présente la
        // feuille qu'avec l'un des deux — mais un partage vide vaut mieux qu'un
        // plantage.
        if items.isEmpty { items.append(payload.title) }

        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: payload.actions.map(ClosureActivity.init)
        )
        controller.setValue(BookCopy.Share.subject(title: payload.title), forKey: "subject")
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Le message, et l'en-tête qui va avec : le titre du voyage et sa photo.
///
/// Un `UIActivityItemSource` et non la chaîne seule : c'est par
/// `LPLinkMetadata` qu'iOS dessine l'en-tête de sa feuille. Sans lui, il
/// écrit le début du message tronqué sous l'icône de l'app.
private final class ShareMessageSource: NSObject, UIActivityItemSource {
    let message: String
    let metadata: LPLinkMetadata

    init(message: String, title: String, link: URL?, coverPhotoUrl: URL?) {
        self.message = message
        let metadata = LPLinkMetadata()
        metadata.title = title.isEmpty ? BookCopy.Share.title : title
        metadata.originalURL = link
        metadata.url = link
        if let coverPhotoUrl {
            // Chargée par iOS quand la feuille la demande, pas avant : la
            // feuille s'ouvre sans attendre le réseau.
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.image.identifier, visibility: .all) {
                completion in
                let task = URLSession.shared.dataTask(with: coverPhotoUrl) { data, _, error in
                    completion(data, error)
                }
                task.resume()
                return task.progress
            }
            metadata.imageProvider = provider
        }
        self.metadata = metadata
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        message
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        message
    }

    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
        metadata
    }
}

/// Un ``ShareAction`` habillé en geste de la feuille du système.
private final class ClosureActivity: UIActivity {
    private let action: ShareAction

    init(_ action: ShareAction) {
        self.action = action
        super.init()
    }

    override class var activityCategory: UIActivity.Category { .action }

    override var activityType: UIActivity.ActivityType? {
        UIActivity.ActivityType("com.memobook.share.\(action.title)")
    }

    override var activityTitle: String? { action.title }

    override var activityImage: UIImage? { UIImage.brand(action.icon) }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool { true }

    override func perform() {
        // La feuille se referme d'abord : le geste mène ailleurs, et on ne
        // doit pas la retrouver en revenant. Le geste lui-même oublie la
        // feuille côté SwiftUI avant de naviguer — voir ceux qui le posent.
        activityDidFinish(true)
        action.perform()
    }
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
