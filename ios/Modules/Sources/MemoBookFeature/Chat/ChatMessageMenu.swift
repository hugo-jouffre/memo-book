import MemoBookCore
import MemoBookDesign
import SwiftUI
import UIKit

/// **Le menu d'un appui long sur une bulle** (T270, Hugo, 05/11/2026 — « un
/// appui long sur un message doit ouvrir le menu contextuel natif iOS »).
///
/// Quatre gestes, et jamais plus : copier, partager, déplacer dans une autre
/// étape, supprimer. Ce qui ne s'applique pas à cette bulle n'y figure pas —
/// un menu de quatre lignes dont deux ne font rien apprend à ne plus être
/// ouvert.
///
/// **Celui du système, et pas le nôtre.** L'appui long, l'aperçu de la bulle
/// qui se soulève, le flou derrière, le placement du menu au-dessus ou en
/// dessous selon la place : rien de tout ça ne se redessine aussi bien à la
/// main, et le geste est celui que l'utilisateur connaît de ses autres
/// messageries.
///
/// ⚠️ **Sans pictogrammes, comme le menu de ``BrandSwipeDrawer``.** Les
/// icônes d'un menu du système sont des SF Symbols, et l'app n'en pose aucun
/// dans son interface — ses pictogrammes viennent de Figma
/// (`ios/CLAUDE.md` § Images). Mélanger les deux familles dans le même menu
/// se verrait ; des libellés seuls, non.
///
/// Ce n'est pas un ``BrandSwipeDrawer`` parce qu'une bulle n'a pas de tiroir :
/// le composant est une bande qui défile horizontalement, et une bande par
/// bulle disputerait le défilement vertical du fil, qui est tout ce qu'on y
/// fait. Seul le menu est commun, et il l'est par le système.
struct ChatMessageMenu: View {
    let message: ChatMessage
    let model: ChatModel

    /// « Partager » et « Supprimer » remontent à la rangée : l'une ouvre la
    /// feuille du système, l'autre demande confirmation d'abord.
    let onShare: () -> Void
    let onDelete: () -> Void

    var body: some View {
        // **Les gestes d'une fiche, d'abord** (T288) : ce sont les siens, et
        // ils parlent du souvenir qu'elle raconte. Copier et partager suivent,
        // comme sur n'importe quelle bulle.
        if let card = transcriptCard {
            Button(ChatCopy.Menu.reanalyse) { model.reanalyse(card) }
            Button(ChatCopy.Menu.editByHand) { model.edit(message) }
            Button(ChatCopy.Menu.changeDates) { model.changeDates(of: card) }
            Button(ChatCopy.Menu.changePlace) { model.changePlace(of: card) }
        }
        if message.spokenText?.isEmpty == false {
            Button(ChatCopy.Menu.copy) { model.copy(message) }
        }
        if isShareable {
            Button(ChatCopy.Menu.share, action: onShare)
        }
        if model.canMove(message) {
            Menu(ChatCopy.Menu.move) {
                ForEach(model.destinations(for: message)) { step in
                    Button(step.label) { model.move(message, toStepId: step.id) }
                }
            }
        }
        // **Les deux étoiles** (T270), sur une bulle qui ne porte **qu'une**
        // photo : sur une bulle qui en porte quatre, « cette photo » ne veut
        // rien dire. Pour les autres, c'est la photo ouverte en plein écran
        // qui porte le geste — là, il n'y a aucun doute sur laquelle.
        if let only = singlePhoto {
            // L'étape seulement si la bulle en a une : une photo qui n'est
            // rangée nulle part n'a pas d'étape à illustrer, et une ligne de
            // menu qui ne fait rien est pire que pas de ligne.
            if message.stepId != nil {
                Button(only.isStepCover ? ChatCopy.Menu.unsetStepCover : ChatCopy.Menu.stepCover) {
                    model.electStepCover(only, in: message)
                }
            }
            Button(only.isTripCover ? ChatCopy.Menu.unsetTripCover : ChatCopy.Menu.tripCover) {
                model.electTripCover(only)
            }
        }
        if model.canDelete(message) {
            Button(ChatCopy.Menu.delete, role: .destructive, action: onDelete)
        }
    }

    /// **La fiche de cette bulle**, quand elle en est une et que son souvenir
    /// existe (T288) : c'est lui que les quatre gestes corrigent. Une fiche en
    /// cours d'écoute ou de rédaction n'en a pas encore — rien à corriger d'un
    /// texte qui n'est pas arrivé.
    private var transcriptCard: TranscriptCard? { Self.transcriptCardOf(message) }

    /// La même lecture pour le rotor VoiceOver, qui passe par une fonction
    /// statique et n'a donc pas la vue sous la main.
    private static func transcriptCardOf(_ message: ChatMessage) -> TranscriptCard? {
        guard case .transcript(let card) = message.body, card.entryId != nil else { return nil }
        switch card.phase {
        case .ready, .unwritten, .failed: return card
        case .listening, .writing, .unknown: return nil
        }
    }

    /// La photo de cette bulle, **s'il n'y en a qu'une** — et si elle est
    /// arrivée chez nous : une photo qui attend le réseau n'a pas de souvenir
    /// à élire.
    private var singlePhoto: PhotoAttachment? {
        guard message.delivery == .sent, case .photos(let attachments) = message.body else { return nil }
        return attachments.count == 1 ? attachments.first : nil
    }

    /// Ce qui se partage : un texte, ou des photos. Un vocal non — partager un
    /// fichier audio sans son souvenir n'a pas de sens, et sa fiche, elle, se
    /// partage.
    private var isShareable: Bool {
        if case .photos(let attachments) = message.body {
            return attachments.contains { $0.displayUrl != nil }
        }
        return message.spokenText?.isEmpty == false
    }

    /// Les mêmes gestes pour VoiceOver, où rien ne se touche longuement : le
    /// rotor d'actions les donne un par un.
    ///
    /// « Déplacer » y est **plat** et non en sous-menu : une action du rotor
    /// par étape d'arrivée, nommée en entier — « Déplacer dans l'étape 2 ·
    /// Trastevere ». Un sous-menu ne s'ouvre pas au rotor.
    @ViewBuilder
    static func accessibilityActions(for message: ChatMessage, model: ChatModel, onShare: @escaping () -> Void, onDelete: @escaping () -> Void) -> some View {
        // Les gestes de la fiche y sont aussi (T288) : rien ne se touche
        // longuement au rotor, et ce sont pourtant les mêmes gestes.
        if let card = transcriptCardOf(message) {
            Button(ChatCopy.Menu.reanalyse) { model.reanalyse(card) }
            Button(ChatCopy.Menu.editByHand) { model.edit(message) }
            Button(ChatCopy.Menu.changeDates) { model.changeDates(of: card) }
            Button(ChatCopy.Menu.changePlace) { model.changePlace(of: card) }
        }
        if message.spokenText?.isEmpty == false {
            Button(ChatCopy.Menu.copy) { model.copy(message) }
            Button(ChatCopy.Menu.share, action: onShare)
        }
        if model.canMove(message) {
            ForEach(model.destinations(for: message)) { step in
                Button(ChatCopy.Menu.moveTo(step.label)) { model.move(message, toStepId: step.id) }
            }
        }
        if let only = singlePhotoOf(message) {
            if message.stepId != nil {
                Button(only.isStepCover ? ChatCopy.Menu.unsetStepCover : ChatCopy.Menu.stepCover) {
                    model.electStepCover(only, in: message)
                }
            }
            Button(only.isTripCover ? ChatCopy.Menu.unsetTripCover : ChatCopy.Menu.tripCover) {
                model.electTripCover(only)
            }
        }
        if model.canDelete(message) {
            Button(ChatCopy.Menu.delete, action: onDelete)
        }
    }

    /// La même règle que ``singlePhoto``, pour le rotor VoiceOver — qui passe
    /// par une fonction statique et n'a donc pas la vue sous la main.
    private static func singlePhotoOf(_ message: ChatMessage) -> PhotoAttachment? {
        guard message.delivery == .sent, case .photos(let attachments) = message.body else { return nil }
        return attachments.count == 1 ? attachments.first : nil
    }
}

/// Ce qu'une bulle partage : son texte, ou ses photos à leur taille d'écran.
///
/// `Identifiable` pour la feuille : c'est l'identité qui la présente, et une
/// seconde demande de partage pendant qu'elle est ouverte la remplace.
public struct ChatSharing: Identifiable {
    public let id = UUID()
    var text: String?
    var images: [UIImage] = []

    init(text: String) {
        self.text = text
    }

    init(images: [UIImage]) {
        self.images = images
    }

    /// Ce que la feuille du système reçoit. Le texte d'abord quand il y en a :
    /// c'est lui qu'une app de messagerie met dans le corps du message.
    var items: [Any] {
        var items: [Any] = []
        if let text, !text.isEmpty { items.append(text) }
        items.append(contentsOf: images)
        return items
    }
}

/// La feuille de partage du système, pour une bulle.
///
/// Un cousin de ``BookShareSheet``, et volontairement plus simple : le carnet
/// partage un lien, un aperçu et deux gestes à lui ; une bulle partage ce
/// qu'elle dit.
struct ChatShareSheet: UIViewControllerRepresentable {
    let sharing: ChatSharing

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: sharing.items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
