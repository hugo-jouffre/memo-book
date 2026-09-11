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
/// Trois choses la distinguent de toutes les autres feuilles de l'app, et
/// aucune n'est décorative :
///
/// 1. **La photo dépasse en haut**, penchée, cerclée de blanc. C'est une photo
///    collée sur une page, pas un avatar dans une liste.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    /// La photo flotte : elle monte et descend d'un cheveu, sans fin.
    ///
    /// Deux points d'amplitude et six secondes de cycle — assez pour qu'on le
    /// remarque au bout d'un moment, pas assez pour que ça attire l'œil pendant
    /// la lecture. Elle s'arrête sous « Réduire les animations ».
    @State private var isFloating = false

    /// Le diamètre de la photo. **Fixe, hors Dynamic Type** : une photo n'est
    /// pas du texte, et celle-ci dépasse d'un bord — la faire grandir la
    /// pousserait hors de l'écran.
    private static let photoSide: CGFloat = 112

    var body: some View {
        BrandSheet(BookCopy.Founders.title) {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                letter
                signature
                actions
            }
        }
        // La photo est posée **par-dessus** la feuille et dépasse en haut. Elle
        // est dans un `overlay` de la feuille et non dans son contenu : dedans,
        // elle aurait été rognée par les coins arrondis.
        .overlay(alignment: .top) { photo }
        .onAppear { isFloating = true }
    }

    // MARK: La photo

    private var photo: some View {
        Image(brand: "PhotoFounders")
            .resizable()
            .scaledToFill()
            .frame(width: Self.photoSide, height: Self.photoSide)
            .clipShape(.circle)
            .overlay { Circle().strokeBorder(MemoBookColor.onAction, lineWidth: 1) }
            // Les deux ombres de la maquette : une large et diffuse qui la
            // détache du fond, une courte et décalée qui la pose. C'est le seul
            // endroit de l'app où deux ombres se superposent, parce que c'est le
            // seul objet qui *flotte* vraiment.
            .shadow(color: Color(red: 0.106, green: 0.165, blue: 0.212).opacity(0.2), radius: 16)
            .shadow(
                color: Color(red: 0.106, green: 0.165, blue: 0.212).opacity(0.2),
                radius: 4,
                x: 2,
                y: 4
            )
            .rotationEffect(.degrees(7.1))
            .offset(
                x: Self.photoSide * 0.55,
                y: -Self.photoSide * 0.5 + (isFloating && !reduceMotion ? -2 : 2)
            )
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 3).repeatForever(autoreverses: true),
                value: isFloating
            )
            .accessibilityLabel(BookCopy.Founders.signatureVoice)
    }

    // MARK: La lettre

    private var letter: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            Text(BookCopy.Founders.hello(firstName))
                .font(MemoBookFont.h3)
                .foregroundStyle(MemoBookColor.ink)

            Text(BookCopy.Founders.intro)
                .font(MemoBookFont.h3)
                .foregroundStyle(MemoBookColor.ink)

            handwrittenPromise

            ForEach(BookCopy.Founders.body, id: \.self) { paragraph in
                Text(paragraph)
                    .font(MemoBookFont.h3)
                    .foregroundStyle(MemoBookColor.ink)
            }
        }
        .multilineTextAlignment(.leading)
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
            .padding(.vertical, MemoBookSpacing.xs / 2)
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
                .font(MemoBookFont.h3)
                .foregroundStyle(MemoBookColor.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(BookCopy.Founders.signatureVoice), \(BookCopy.Founders.signature)")
    }

    private var actions: some View {
        VStack(spacing: MemoBookSpacing.snug) {
            BrandButton(
                BookCopy.Founders.feedback,
                style: .secondary,
                fillsWidth: true
            ) {
                sendFeedback()
            }

            BrandButton(
                BookCopy.Founders.carryOn,
                style: .primary,
                fillsWidth: true
            ) {
                dismiss()
                onContinue()
            }
        }
        .padding(.top, MemoBookSpacing.xs)
    }

    /// Ouvre un courrier pré-rempli vers les fondateurs.
    ///
    /// Un `mailto:` et non un formulaire : il n'y a pas de back-end de retours,
    /// et le courrier laisse une trace des deux côtés — celui qui écrit garde
    /// ce qu'il a envoyé. L'écran remonte quand même l'intention, pour que
    /// ``RootView`` puisse un jour la router ailleurs.
    private func sendFeedback() {
        onFeedback()

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = BookCopy.Founders.feedbackAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: BookCopy.Founders.feedbackSubject)
        ]

        if let url = components.url { openURL(url) }
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
