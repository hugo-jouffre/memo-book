import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Le mot des fondateurs : deux personnes qui parlent, au milieu d'une app.
///
/// **Elle s'ouvre toute seule**, une fois, une douzaine de secondes après le
/// premier aperçu d'un carnet — et c'est tout son intérêt. Personne ne va
/// chercher un mot des fondateurs dans un menu ; il n'a de valeur que s'il
/// arrive au moment où l'on vient de voir ce que l'app sait faire.
///
/// **La maquette du 12/10/2026** (« Claude Import », `3709:17115`) : la photo
/// ne dépasse plus au-dessus de la feuille, elle se pose **sur la ligne du
/// titre**, penchée, cerclée de blanc ; la lettre passe au corps de 14. Trois
/// choses la distinguent toujours des autres feuilles de l'app, et aucune
/// n'est décorative :
///
/// 1. **La photo est penchée**, cerclée de blanc, avec deux ombres. C'est une
///    photo collée sur une page, pas un avatar dans une liste.
/// 2. **Une ligne est écrite à la main**, en vert. C'est la promesse de
///    MemoBook, et c'est la seule phrase manuscrite de l'app.
/// 3. **La signature est un dessin**, pas du texte. Un nom tapé sous un mot
///    manuscrit annulerait tout ce qui précède.
struct FoundersNoteSheet: View {
    let onFeedback: () -> Void
    let onContinue: () -> Void

    /// Le prénom du compte, pour le bonjour. Il vient de la session et non du
    /// serveur : la feuille ne doit pas attendre un aller-retour pour dire
    /// bonjour.
    @Environment(\.travellerFirstName) private var firstName
    @Environment(\.dismiss) private var dismiss

    /// Le diamètre de la photo. **Fixe, hors Dynamic Type** : une photo n'est
    /// pas du texte, et elle partage sa ligne avec le titre.
    private static let photoSide: CGFloat = 84

    /// Le carré que la photo penchée occupe sur la ligne : ses coins tournés
    /// débordent du cercle (93,7 pt dans la maquette).
    private static let photoSlot: CGFloat = 94

    var body: some View {
        BrandSheet(BookCopy.Founders.title, leading: { photo }) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
                VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                    letter
                    signature
                }
                actions
            }
        }
    }

    // MARK: La photo

    private var photo: some View {
        Image(brand: "PhotoFounders")
            .resizable()
            .scaledToFill()
            .frame(width: Self.photoSide, height: Self.photoSide)
            .clipShape(.circle)
            .overlay { Circle().strokeBorder(MemoBookColor.surface, lineWidth: 0.75) }
            // Les deux ombres de la maquette : une large et diffuse qui la
            // détache du fond, une courte et décalée qui la pose. C'est le seul
            // endroit de l'app où deux ombres se superposent, parce que c'est le
            // seul objet qui est *collé* sur la page.
            .shadow(color: Color(red: 0.106, green: 0.165, blue: 0.212).opacity(0.2), radius: 12)
            .shadow(
                color: Color(red: 0.106, green: 0.165, blue: 0.212).opacity(0.2),
                radius: 3,
                x: 1.5,
                y: 3
            )
            .rotationEffect(.degrees(7.1))
            .frame(width: Self.photoSlot, height: Self.photoSlot)
            .accessibilityLabel(BookCopy.Founders.signatureVoice)
    }

    // MARK: La lettre

    /// Le corps de 14 de la maquette, paragraphe après paragraphe — un blanc
    /// de 8 entre chacun, la ligne manuscrite prise dans le même pas.
    private var letter: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            paragraph(BookCopy.Founders.hello(firstName))
            paragraph(BookCopy.Founders.intro)

            handwrittenPromise

            ForEach(BookCopy.Founders.body, id: \.self, content: paragraph)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(MemoBookFont.taglineRegular)
            .foregroundStyle(MemoBookColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// La ligne manuscrite, légèrement de travers.
    ///
    /// Un degré d'inclinaison, comme la maquette : c'est ce qui la sort du
    /// gabarit sans la rendre difficile à lire. La rotation est **après** le
    /// dimensionnement pour que la phrase garde toute la largeur disponible.
    private var handwrittenPromise: some View {
        Text(BookCopy.Founders.promise)
            .font(MemoBookFont.handwriting)
            .foregroundStyle(MemoBookColor.action)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rotationEffect(.degrees(-1))
    }

    private var signature: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(brand: "IllustrationSignature")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                // La signature garde sa taille : c'est un dessin, et un
                // paraphe qui grandit avec le corps de texte devient un logo.
                .frame(width: 114, height: 47)
                .foregroundStyle(MemoBookColor.ink)
                .accessibilityHidden(true)

            Text(BookCopy.Founders.signature)
                .font(MemoBookFont.taglineRegular)
                .foregroundStyle(MemoBookColor.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(BookCopy.Founders.signatureVoice), \(BookCopy.Founders.signature)")
    }

    /// Les deux boutons de 16 sur 48 pt de la maquette (`medium`), l'un
    /// sous l'autre.
    private var actions: some View {
        VStack(spacing: MemoBookSpacing.snug) {
            BrandButton(
                BookCopy.Founders.feedback,
                style: .secondary,
                size: .medium,
                fillsWidth: true
            ) {
                sendFeedback()
            }

            BrandButton(
                BookCopy.Founders.carryOn,
                style: .primary,
                size: .medium,
                fillsWidth: true
            ) {
                dismiss()
                onContinue()
            }
        }
    }

    /// **Le formulaire de l'app, et non un courrier** (Hugo, 19/09/2026).
    ///
    /// Le bouton ouvrait `mailto:` : on quittait MemoBook pour une app de mail
    /// qui n'est pas toujours configurée, avec un message vide et un objet
    /// prérempli. Or l'app a déjà un endroit où l'on écrit à l'équipe — celui
    /// du support, avec son champ, son envoi et sa confirmation. C'est lui qui
    /// s'ouvre, et la feuille se referme d'abord pour qu'il prenne sa place.
    ///
    /// **Et le message part vraiment** (T226, 06/10/2026) : marqué
    /// `founders_note`, avec le voyage du carnet — voir `BookPreviewFlowView`.
    private func sendFeedback() {
        dismiss()
        onFeedback()
    }
}

extension EnvironmentValues {
    /// Le prénom de la personne connectée, pour les écrans qui s'adressent à
    /// elle.
    ///
    /// Dans l'environnement et non dans un modèle : le mot des fondateurs n'a
    /// pas de données à lui, il n'a qu'un bonjour à écrire. Lui donner un modèle
    /// et un appel réseau pour un prénom aurait été disproportionné.
    @Entry public var travellerFirstName: String?
}

#Preview("Mot des fondateurs") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            FoundersNoteSheet(onFeedback: {}, onContinue: {})
                .environment(\.travellerFirstName, "Margaux")
        }
        .environment(\.colorScheme, .light)
}

#Preview("Mot des fondateurs — AX3") {
    Color.clear
        .brandSheet(isPresented: .constant(true)) {
            FoundersNoteSheet(onFeedback: {}, onContinue: {})
                .environment(\.travellerFirstName, "Margaux")
                .environment(\.dynamicTypeSize, .accessibility3)
        }
        .environment(\.colorScheme, .light)
}
