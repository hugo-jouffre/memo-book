import MemoBookCore
import MemoBookDesign
import SwiftUI

/// « Exporter mes données » — la feuille qu'ouvre la ligne du bas du profil.
///
/// **Deux temps dans la même feuille**, comme celle du support : la
/// proposition, puis la confirmation. On n'empile pas deux ``BrandSheet``, et
/// la hauteur s'anime d'un temps à l'autre au lieu de sauter.
///
/// **Pas de confirmation avant d'envoyer**, contrairement à la suppression du
/// compte : la demande ne détruit rien et ne coûte rien. La feuille dit ce qui
/// va se passer — un lien par e-mail, à l'adresse du compte, valable sept
/// jours — et un seul bouton le fait.
///
/// ⚠️ **Aucune maquette Figma** pour cette feuille (relevé le 01/10/2026 : la
/// page App ne montre que la ligne du profil). Elle est faite des pièces des
/// autres feuilles — le chapeau en paragraphes de la résiliation, la coche du
/// support — en attendant d'être dessinée (T241).
struct DataExportSheet: View {
    let model: ProfileModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if case .sent(let receipt) = model.dataExport {
                BrandSheet(
                    receipt.alreadyRequested ? DataExportCopy.alreadySentTitle : DataExportCopy.sentTitle,
                    paragraphs: DataExportCopy.sentParagraphs(receipt)
                ) {
                    confirmation
                }
            } else {
                BrandSheet(DataExportCopy.title, paragraphs: [DataExportCopy.intro, DataExportCopy.contents]) {
                    offer
                }
            }
        }
        .animation(reduceMotion ? .none : .snappy(duration: 0.3), value: model.dataExport)
        .interactiveDismissDisabled(model.dataExport == .requesting)
        // Rouverte plus tard, la feuille repart de la proposition.
        .onDisappear { model.resetDataExport() }
    }

    // MARK: - La proposition

    private var offer: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
            if let email = model.profile?.email {
                Text(DataExportCopy.destination(email))
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .failed(let problem) = model.dataExport {
                Text(problem)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            BrandButton(
                DataExportCopy.send,
                isLoading: model.dataExport == .requesting,
                fillsWidth: true
            ) {
                Task { await model.requestDataExport() }
            }
        }
    }

    // MARK: - La confirmation

    /// Le rond et sa coche de la feuille du support (`SupportSheet`), puis
    /// « Compris » : le titre et le chapeau ont déjà tout dit.
    private var confirmation: some View {
        VStack(spacing: MemoBookSpacing.m) {
            Image(brand: "IconLucideCheck")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: Self.checkSide, height: Self.checkSide)
                .foregroundStyle(MemoBookColor.ink)
                .frame(width: Self.confirmationSide, height: Self.confirmationSide)
                .background(MemoBookColor.outline.opacity(0.5), in: .circle)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(DataExportCopy.confirmationVoice)

            BrandButton(DataExportCopy.understood, fillsWidth: true) {
                dismiss()
            }
        }
    }

    /// Les mesures de la coche du support : 66 et 28.
    private static let confirmationSide: CGFloat = 66
    private static let checkSide: CGFloat = 28
}

/// Les mots de la feuille. Sans maquette : à relire avec elle (T241).
enum DataExportCopy {
    static let title = "Exporter mes données"

    static let intro =
        "On t’envoie par e-mail un lien pour télécharger une copie de tout ce que MemoBook garde de toi."

    /// La même phrase que l'e-mail et la page de téléchargement
    /// (`DATA_EXPORT_CONTENTS`, `backend/src/services/mailTemplates.ts`).
    static let contents =
        "Dans l’archive : ton compte, tes voyages et leurs récits, chaque souvenir tel que tu l’as raconté et tel que MEMO l’a écrit, tes photos et tes vocaux d’origine, tes carnets en PDF, tes commandes et ton abonnement."

    static func destination(_ email: String) -> String {
        "Le lien partira à \(email). Il sera valable sept jours."
    }

    static let send = "M’envoyer le lien"

    static let sentTitle = "Regarde ta boîte mail"
    static let alreadySentTitle = "Ton e-mail est déjà en route"

    static func sentParagraphs(_ receipt: DataExportReceipt) -> [String] {
        let first =
            receipt.alreadyRequested
            ? "Un lien est parti à \(receipt.email) à \(time(receipt.requestedAt)). Il peut mettre quelques minutes à arriver."
            : "Le lien est parti à \(receipt.email). Il est valable jusqu’au \(day(receipt.expiresAt))."
        return [first, "Rien dans ta boîte d’ici quelques minutes ? Regarde dans tes indésirables."]
    }

    static let understood = "Compris"
    static let confirmationVoice = "Lien envoyé"

    /// Le 404 d'un serveur qui ne connaît pas encore la route.
    static let notYetAvailable =
        "L’export de tes données n’est pas encore ouvert sur notre serveur. Réessaie un peu plus tard."

    private static let french = Locale(identifier: "fr_FR")

    /// « mercredi 8 octobre » — et « 1er », que le format ne sait pas écrire.
    static func day(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: french).weekday(.wide).day().month(.wide))
            .replacingOccurrences(of: #"(^|\s)1(\s)"#, with: "$11er$2", options: .regularExpression)
    }

    /// « 15 h 02 ».
    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: french).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            .replacingOccurrences(of: ":", with: " h ")
    }
}

#Preview("Export — proposition") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            DataExportSheet(model: ProfileModel())
        }
}

#Preview("Export — envoyé") {
    let model = ProfileModel()
    return Color.clear
        .brandSheet(isPresented: .constant(true)) {
            DataExportSheet(model: model)
        }
        .task {
            await model.load()
            await model.requestDataExport()
        }
}
