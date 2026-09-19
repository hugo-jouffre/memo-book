import SwiftUI

/// **Le** bloc d'information de l'app : une phrase posée sur un aplat beige,
/// qui dit à quoi s'en tenir sans rien demander.
///
/// Ce n'est ni une erreur ni une alerte, et c'est pour ça qu'il ne ressemble à
/// aucune des deux. ``ErrorBanner`` dit « quelque chose a raté, voilà le
/// bouton pour réessayer » ; celui-ci dit « voilà où on en est, tu peux
/// continuer » — pas de rouge, pas d'action. Il disparaît tout seul quand la
/// situation qu'il décrit a changé.
///
/// Il a **deux tons** — voir ``Tone`` : le beige de l'état des choses, et le
/// bleu d'information pour ce qu'on vient d'expliquer à quelqu'un qui a tapé
/// quelque part où ça ne mène pas encore.
///
/// **Le gras n'est pas une décoration** : chaque message porte une phrase qui
/// compte — ce que la personne peut faire malgré la panne, ou ce qui est
/// garanti malgré elle — et c'est elle qu'on lit en diagonale. Elle se marque
/// avec `**…**`, comme en Markdown, et le balisage est résolu **à la
/// construction** : rien à calculer dans un `body`, donc rien à recalculer à
/// chaque image d'animation.
public struct BrandNotice<Footer: View>: View {
    /// Ce que le bloc dit de lui-même.
    public enum Tone {
        /// L'état des choses, sur le beige de la marque. Le cas courant.
        case neutral

        /// **Une explication qu'on vient de demander** : pourquoi un réglage
        /// n'est pas ouvert, pourquoi une porte ne mène nulle part. Elle porte
        /// la couleur sémantique d'information (``MemoBookColor/information``)
        /// — un filet, un pictogramme et un texte bleus sur un aplat très
        /// clair — parce qu'elle répond à un geste au lieu de décrire un fond
        /// de situation, et qu'il faut la distinguer d'une erreur.
        case information
    }

    private let message: AttributedString
    private let tone: Tone

    /// Ce qui se pose **sous la phrase, dans la boîte** : un lien, jamais un
    /// pavé. Une boîte d'information ne demande rien — mais quand elle explique
    /// pourquoi une porte est fermée, elle peut porter celle qui reste ouverte,
    /// et c'est plus honnête que de renvoyer ailleurs (Hugo, 19/09/2026).
    ///
    /// `EmptyView` dans la quasi-totalité des cas, et la boîte est alors
    /// exactement celle d'avant.
    private let footer: Footer

    /// - Parameters:
    ///   - markup: le message, dont la partie qui compte est entourée de `**`.
    ///     Un balisage invalide n'efface rien : la phrase s'affiche telle
    ///     quelle, sans gras.
    ///   - tone: voir ``Tone``. Neutre par défaut, c'est-à-dire le bloc d'avant.
    public init(
        _ markup: String,
        tone: Tone = .neutral,
        @ViewBuilder footer: () -> Footer
    ) {
        message = Self.resolved(markup)
        self.tone = tone
        self.footer = footer()
    }

    public var body: some View {
        VStack(spacing: MemoBookSpacing.xs) {
            content
                .multilineTextAlignment(tone == .information ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: tone == .information ? .leading : .center)

            footer
        }
            .padding(MemoBookSpacing.s)
            .background { backdrop }
            .overlay {
                if tone == .information {
                    RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)
                        .strokeBorder(MemoBookColor.information, lineWidth: 1)
                }
            }
            .accessibilityElement(children: .combine)
    }

    /// Le fond. **Un verre dépoli sous un beige doux** pour le ton neutre
    /// (Hugo, 17/09/2026) : l'aplat `Beige Darker` d'avant était trop foncé, et
    /// une boîte qui laisse deviner ce qui passe dessous se lit comme une
    /// information posée sur la page, pas comme un bloc de plus. Un liseré
    /// blanc à demi-transparent fait le bord du verre.
    @ViewBuilder
    private var backdrop: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)

        switch tone {
        case .neutral:
            shape
                .fill(.ultraThinMaterial)
                .overlay { shape.fill(MemoBookColor.noticeBeige.opacity(0.7)) }
                .overlay { shape.strokeBorder(.white.opacity(0.45), lineWidth: 1) }
        case .information:
            shape.fill(background)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tone {
        case .neutral:
            text
        case .information:
            // Le pictogramme se cale sur la **première ligne** du texte et non
            // sur le milieu du bloc : sur trois lignes, un centrage vertical le
            // faisait descendre au milieu de la phrase.
            HStack(alignment: .firstTextBaseline, spacing: MemoBookSpacing.xs) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(MemoBookColor.information)
                    .accessibilityHidden(true)
                text
            }
        }
    }

    private var text: some View {
        Text(message)
            // La police de base est posée deux fois — ici et sur chaque
            // portion de texte — et c'est voulu : `Text` a besoin d'une police
            // même quand le balisage n'a pas pu être lu.
            .font(MemoBookFont.body)
            .foregroundStyle(MemoBookColor.ink)
    }

    private var background: Color {
        switch tone {
        case .neutral: MemoBookColor.noticeBeige
        // Le bleu d'information, très dilué : c'est le filet et le pictogramme
        // qui portent la couleur, pas l'aplat — un fond bleu franc sous du
        // texte encre tombe sous le contraste demandé.
        case .information: MemoBookColor.information.opacity(0.12)
        }
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

extension BrandNotice where Footer == EmptyView {
    /// La boîte d'information telle qu'elle est partout : une phrase, et rien
    /// en dessous.
    public init(_ markup: String, tone: Tone = .neutral) {
        self.init(markup, tone: tone) { EmptyView() }
    }
}
