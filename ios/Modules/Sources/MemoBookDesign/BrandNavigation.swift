import SwiftUI

extension View {
    /// Masque la barre de navigation, et **rend le glissé de retour** qu'elle
    /// emportait avec elle.
    ///
    /// Deux écrans dessinent leur propre en-tête plutôt que d'employer la barre
    /// système : le profil, dont la flèche et le titre partagent une ligne, et
    /// l'accueil d'un voyage, dont la photo passe sous la barre d'état. Aucune
    /// barre de navigation ne sait faire l'un ou l'autre — et sur iOS 26, un
    /// élément personnalisé de barre est enfermé d'office dans une pastille de
    /// verre qui avale le titre.
    ///
    /// Mais masquer la barre supprime le **glissé depuis le bord**, que le
    /// système attache à son bouton de retour. C'est le retour arrière de la
    /// moitié des mains sur un grand écran : on le refait à la main, ici, une
    /// fois pour toutes.
    public func brandHiddenNavigationBar() -> some View {
        modifier(BrandHiddenNavigationBar())
    }
}

private struct BrandHiddenNavigationBar: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            // `simultaneous` et non `gesture` : le défilement vertical doit
            // continuer de fonctionner pendant qu'on guette le geste.
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .global)
                    .onEnded(handleEdgeSwipe)
            )
    }

    /// Trois conditions : partir du bord gauche, aller franchement vers la
    /// droite, et rester horizontal. Sans elles, un défilement un peu de travers
    /// refermerait l'écran au milieu de la lecture.
    private func handleEdgeSwipe(_ drag: DragGesture.Value) {
        let horizontal = drag.translation.width
        guard drag.startLocation.x < MemoBookSpacing.m,
            horizontal > 80,
            horizontal > abs(drag.translation.height) * 1.5
        else { return }
        dismiss()
    }
}
