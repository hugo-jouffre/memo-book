import SwiftUI

/// **Le** bloc d'information de l'app : une phrase posée sur un aplat beige,
/// qui dit à quoi s'en tenir sans rien demander.
///
/// Ce n'est ni une erreur ni une alerte, et c'est pour ça qu'il ne ressemble à
/// aucune des deux. ``ErrorBanner`` dit « quelque chose a raté, voilà le
/// bouton pour réessayer » ; celui-ci dit « voilà où on en est, tu peux
/// continuer » — pas de rouge, pas de pictogramme, pas d'action. Il disparaît
/// tout seul quand la situation qu'il décrit a changé.
///
/// **Le gras n'est pas une décoration** : chaque message porte une phrase qui
/// compte — ce que la personne peut faire malgré la panne, ou ce qui est
/// garanti malgré elle — et c'est elle qu'on lit en diagonale. Elle se marque
/// avec `**…**`, comme en Markdown, et le balisage est résolu **à la
/// construction** : rien à calculer dans un `body`, donc rien à recalculer à
/// chaque image d'animation.
public struct BrandNotice: View {
    private let message: AttributedString

    /// - Parameter markup: le message, dont la partie qui compte est entourée
    ///   de `**`. Un balisage invalide n'efface rien : la phrase s'affiche
    ///   telle quelle, sans gras.
    public init(_ markup: String) {
        message = Self.resolved(markup)
    }

    public var body: some View {
        Text(message)
            // La police de base est posée deux fois — ici et sur chaque
            // portion de texte — et c'est voulu : `Text` a besoin d'une police
            // même quand le balisage n'a pas pu être lu.
            .font(MemoBookFont.body)
            .foregroundStyle(MemoBookColor.ink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(MemoBookSpacing.s)
            // `Beige Darker`, le seul aplat discret de la palette : plus
            // soutenu que le crème du fond, donc le bloc se détache ; assez
            // proche pour ne pas se lire comme une carte de contenu.
            .background(
                MemoBookColor.separator,
                in: .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
            )
    }

    /// Traduit `**…**` en portions de texte en demi-gras.
    ///
    /// Le gras est une **autre police** — General Sans Semibold — et non un
    /// épaississement du tracé : les instances statiques embarquées sont des
    /// familles distinctes, et demander à SwiftUI de « graisser » la régulière
    /// donnerait un faux gras synthétique. D'où le passage par les portions
    /// plutôt qu'un `.bold()`.
    private static func resolved(_ markup: String) -> AttributedString {
        guard
            var text = try? AttributedString(
                markdown: markup,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        else {
            return AttributedString(markup)
        }

        // Les portées sont relevées **avant** d'écrire : modifier le texte
        // pendant qu'on parcourt ses portions invaliderait le parcours.
        let emphasised = text.runs.compactMap { run in
            run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true ? run.range : nil
        }

        text.font = MemoBookFont.body
        for range in emphasised { text[range].font = MemoBookFont.bodySemibold }
        return text
    }
}

#Preview("Bloc d’information") {
    VStack(spacing: MemoBookSpacing.s) {
        BrandNotice(
            "Tu sembles hors ligne. **Tu peux consulter tes récits et enregistrer des étapes**, qui seront retranscrites plus tard."
        )
        BrandNotice(
            "**Tes vocaux enregistrés hors ligne sont bien conservés.** Ils seront envoyés dès ta reconnexion."
        )
        BrandNotice("**Ton vocal est bien arrivé.** Il sera retranscrit dans quelques instants.")
    }
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}
