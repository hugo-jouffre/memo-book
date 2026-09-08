import MemoBookCore
import MemoBookDesign
import SwiftUI

/// La couverture d'un voyage : sa photo pleine largeur, ce qu'on y a fait, et
/// qui y est.
///
/// **Le texte est blanc sur une photo qu'on ne choisit pas.** C'est le seul
/// endroit de l'app où le contraste ne peut pas se calculer d'avance : une
/// couverture claire rendrait le titre illisible. Deux voiles dégradés le
/// garantissent — un en haut pour les commandes, un en bas pour le titre — et
/// ils sont donc du dessin, pas de la décoration.
struct TripHeader: View {
    let detail: TripDetail

    let onBack: () -> Void
    let onPrint: () -> Void
    let onSettings: () -> Void
    let onInvite: () -> Void

    /// Le rapport de la maquette : la photo occupe un peu plus d'un carré. Un
    /// rapport plutôt qu'une hauteur en points, pour que la couverture garde
    /// ses proportions du SE au Pro Max.
    private static let aspectRatio: CGFloat = 390 / 440

    private var trip: Trip { detail.trip }

    /// La hauteur de la maquette — un **plancher**, pas une hauteur figée.
    ///
    /// C'est toute la différence : figée, elle rognait tout en taille de texte
    /// accessible. Les compteurs, qui s'empilent alors les uns sous les autres,
    /// débordaient par le haut et venaient se poser sur la flèche de retour.
    /// En plancher, la photo grandit avec ce qu'elle porte.
    private var minimumHeight: CGFloat { DeviceScreen.width / Self.aspectRatio }

    var body: some View {
        // Une **pile**, et non des calques posés sur un cadre fixe : c'est le
        // contenu qui décide de la hauteur, et rien ne peut donc en sortir.
        VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
            controls
            Spacer(minLength: MemoBookSpacing.xl)
            caption
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .top)
        .background {
            artwork
            scrim
        }
        .clipped()
    }

    @ViewBuilder
    private var artwork: some View {
        AsyncImage(url: trip.coverPhotoUrl) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                TripCoverPlaceholder(seed: trip.id)
            }
        }
        .accessibilityHidden(true)
    }

    /// Le voile. Deux dégradés dans le même calque : le haut porte les
    /// commandes, le bas porte le titre, et le milieu de la photo reste net.
    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.45), location: 0),
                .init(color: .black.opacity(0.05), location: 0.32),
                .init(color: .black.opacity(0.10), location: 0.55),
                .init(color: .black.opacity(0.65), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Commandes

    private var controls: some View {
        // Les commandes gardent leur place quelle que soit la taille du texte :
        // ce sont trois ronds de 44, pas des libellés.
        HStack(spacing: MemoBookSpacing.xs + 2) {
            TripHeaderButton(icon: "IconArrow", label: "Retour", action: onBack)
            Spacer(minLength: 0)
            TripHeaderButton(icon: "IconPrinter", label: "Imprimer ce carnet", action: onPrint)
            TripHeaderButton(icon: "IconSettings", label: "Paramètres du voyage", action: onSettings)
        }
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        // La photo passe sous la barre d'état ; les commandes, elles, se posent
        // dessous. `DeviceScreen` porte la mesure parce qu'elle change d'un
        // iPhone à l'autre — 20 pt sur un SE, 59 sur un modèle à Dynamic Island.
        .padding(.top, DeviceScreen.topSafeInset + MemoBookSpacing.xs)
    }

    // MARK: - Ce qu'on lit sur la photo

    private var caption: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            TripStatsRow(stats: trip.stats, tint: MemoBookColor.onAction, isSpread: false)

            Text(trip.title)
                .font(MemoBookFont.h1)
                .foregroundStyle(MemoBookColor.onAction)
                .fixedSize(horizontal: false, vertical: true)

            people
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        // La légende s'arrête **au-dessus du panneau crème**, pas au bord de la
        // photo : celui-ci mord sur elle de la hauteur de son arrondi — voir
        // `TripHomeView.canopy` — et une ligne calée sur le bord se retrouvait
        // collée au crème, la file de collaborateurs à demi dessous. La marge
        // se lit donc « ce que le panneau recouvre, plus de quoi respirer ».
        .padding(.bottom, MemoBookSpacing.overlayCornerRadius + MemoBookSpacing.m)
    }

    /// Les **collaborateurs** : ceux qui peuvent ajouter des étapes au voyage.
    ///
    /// La maquette montre un second groupe à côté — les visages croisés en
    /// chemin. Il attend la v2, et n'est donc dessiné nulle part : un groupe
    /// qu'on ne peut ni remplir ni comprendre vaut moins que son absence.
    private var people: some View {
        HStack(spacing: 0) {
            marker("IconUser")
                .padding(.trailing, MemoBookSpacing.xs)

            CompanionStack(companions: trip.companions, visibleLimit: 2)
                .accessibilityElement()
                .accessibilityLabel(collaboratorsLabel)

            inviteButton
                .padding(.leading, inviteOffset)

            Spacer(minLength: 0)
        }
    }

    /// De combien le « + » recule pour venir **sur** la dernière pastille.
    ///
    /// Il fait partie du groupe, il ne le suit pas : posé à côté, il se lisait
    /// comme un troisième bouton de la ligne. À demi dessus, il dit « ajoute
    /// quelqu'un **ici** ». C'est ce que montre la maquette, et c'est aussi ce
    /// qui le sépare du second groupe qui viendra à sa droite.
    ///
    /// Deux termes, et pas un nombre choisi à l'œil : la moitié d'une pastille,
    /// plus la marge transparente que sa cible tactile ajoute autour du rond
    /// dessiné. Sans le second, le chevauchement se réduisait de cinq points à
    /// chaque fois qu'on retouchait la taille minimale d'une cible.
    ///
    /// Nul quand il n'y a personne : il n'y a alors rien à chevaucher, et le
    /// bouton viendrait mordre sur le pictogramme.
    private var inviteOffset: CGFloat {
        guard !trip.companions.isEmpty else { return 0 }
        let tapInset = (MemoBookSpacing.minimumTapTarget - CompanionStack.diameter) / 2
        return -(CompanionStack.diameter / 2 + tapInset)
    }

    /// Le rond blanc qui invite. Même diamètre que les pastilles qu'il
    /// chevauche : c'est ce qui le fait lire comme le dernier de la file.
    private var inviteButton: some View {
        Button(action: onInvite) {
            Image(brand: "IconPlus")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: MemoBookSpacing.s, height: MemoBookSpacing.s)
                .foregroundStyle(MemoBookColor.ink)
                .frame(width: CompanionStack.diameter, height: CompanionStack.diameter)
                .background(MemoBookColor.surface, in: .circle)
        }
        .frame(
            minWidth: MemoBookSpacing.minimumTapTarget,
            minHeight: MemoBookSpacing.minimumTapTarget
        )
        .contentShape(.circle)
        .accessibilityLabel("Inviter quelqu’un à raconter ce voyage")
    }

    private func marker(_ name: String) -> some View {
        Image(brand: name)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: MemoBookSpacing.s + 2, height: MemoBookSpacing.s + 2)
            .foregroundStyle(MemoBookColor.onAction)
            .accessibilityHidden(true)
    }

    private var collaboratorsLabel: String {
        guard !trip.companions.isEmpty else { return "Tu racontes ce voyage seul" }
        let names = trip.companions.map(\.name).formatted(.list(type: .and))
        return "Racontent aussi ce voyage : \(names)"
    }
}

/// Un rond translucide posé sur la photo.
///
/// Le fond sombre n'est pas un choix de marque mais une garantie de lisibilité :
/// une icône blanche sur une couverture claire disparaîtrait sans lui.
private struct TripHeaderButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(brand: icon)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: MemoBookSpacing.m, height: MemoBookSpacing.m)
                .foregroundStyle(MemoBookColor.onAction)
                .frame(
                    width: MemoBookSpacing.minimumTapTarget,
                    height: MemoBookSpacing.minimumTapTarget
                )
                .background(.black.opacity(0.35), in: .circle)
                .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1) }
        }
        .contentShape(.circle)
        .accessibilityLabel(label)
    }
}

/// La place de l'en-tête, le temps que le voyage arrive.
///
/// **Même hauteur, même flèche, même dégradé sombre** que le vrai : c'est ce
/// qui fait que l'écran ne bouge pas quand la photo se pose. Seuls les
/// compteurs, le titre et les co-voyageurs sont remplacés par des barres
/// d'attente — voir ``BrandSkeleton``.
///
/// La flèche de retour, elle, n'est pas une barre : c'est la seule sortie de
/// l'écran, et la faire attendre le réseau serait la pire chose à faire d'un
/// chargement lent.
struct TripHeaderPlaceholder: View {
    let onBack: () -> Void

    private static let aspectRatio: CGFloat = 390 / 440
    private var minimumHeight: CGFloat { DeviceScreen.width / Self.aspectRatio }

    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.m) {
            HStack {
                TripHeaderButton(icon: "IconArrow", label: "Retour", action: onBack)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .padding(.top, DeviceScreen.topSafeInset + MemoBookSpacing.xs)

            Spacer(minLength: MemoBookSpacing.xl)

            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                BrandSkeleton(width: 150, onDark: true)
                BrandSkeleton(width: 220, onDark: true)
                    .frame(height: MemoBookSpacing.m)
                BrandSkeleton(width: 110, onDark: true)
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            // La même marge que la vraie légende, pour la même raison : rien ne
            // doit se glisser sous le panneau crème.
            .padding(.bottom, MemoBookSpacing.overlayCornerRadius + MemoBookSpacing.m)
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .top)
        .background {
            // Le gris de la couverture manquante, dans le même dégradé sombre
            // que le voile du vrai en-tête : les barres claires s'y lisent, et
            // la photo ne fera que remplacer un fond par un autre.
            LinearGradient(
                colors: [MemoBookColor.ink.opacity(0.55), MemoBookColor.ink.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
    }
}

/// La place des étapes, le temps qu'elles arrivent : les trois filtres, éteints,
/// et trois cartes vides.
///
/// Trois et pas une : c'est le nombre courant, et une seule carte laisserait
/// croire à un voyage d'une étape avant de se démultiplier sous les yeux.
struct TripStepsPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
            // Les **mêmes icônes** que les vrais filtres, et pas un chevron :
            // `BrandFilterChip` en dessine déjà un à droite, et la pastille se
            // retrouvait avec deux chevrons et un libellé coupé.
            HStack(spacing: MemoBookSpacing.xs) {
                chip("Pays", "flag")
                chip("Étapes", "bag")
                chip("Transports", "arrow.triangle.turn.up.right.diagonal")
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
            .allowsHitTesting(false)

            VStack(spacing: MemoBookSpacing.s) {
                ForEach(0..<3, id: \.self) { _ in
                    stepCard
                }
            }
            .padding(.horizontal, MemoBookSpacing.screenMargin)
        }
    }

    private func chip(_ title: String, _ symbol: String) -> some View {
        BrandFilterChip(title, icon: Image(systemName: symbol), isActive: false)
            .opacity(0.5)
    }

    /// La coque exacte d'une ``TripStepCard`` : vignette carrée à gauche, trois
    /// lignes à droite.
    private var stepCard: some View {
        HStack(spacing: MemoBookSpacing.s) {
            RoundedRectangle(cornerRadius: MemoBookSpacing.cornerRadius)
                .fill(MemoBookColor.ink.opacity(0.07))
                .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                BrandSkeleton(width: 110)
                BrandSkeleton(width: 150)
                BrandSkeleton(width: 90)
            }

            Spacer(minLength: 0)
        }
        .padding(MemoBookSpacing.xs + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeCard()
        .accessibilityHidden(true)
    }
}
