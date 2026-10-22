package com.memobook.feature.trip

import androidx.annotation.DrawableRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.memobook.core.TripDetail
import com.memobook.design.BrandFilterChip
import com.memobook.design.BrandSkeleton
import com.memobook.design.BrandText
import com.memobook.design.DeviceScreen
import com.memobook.design.LucideIcon
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.feature.home.CompanionStack
import com.memobook.feature.home.TripCoverPlaceholder
import com.memobook.feature.home.homeCard
import com.memobook.feature.home.TripStatsRow

/**
 * La couverture d'un voyage : sa photo pleine largeur, ce qu'on y a fait, et
 * qui y est. Jumeau de `Trip/TripHeader.swift`.
 *
 * **Le texte est blanc sur une photo qu'on ne choisit pas.** C'est le seul
 * endroit de l'app où le contraste ne peut pas se calculer d'avance : une
 * couverture claire rendrait le titre illisible. Deux voiles dégradés le
 * garantissent — un en haut pour les commandes, un en bas pour le titre — et
 * ils sont donc du dessin, pas de la décoration.
 *
 * @param isAwaitingServer le serveur n'a pas encore reçu ce voyage : les
 *   réglages, l'aperçu et l'invitation pâlissent — voir [TripAwaitingServer].
 */
@Composable
internal fun TripHeader(
    detail: TripDetail,
    onBack: () -> Unit,
    onPrint: () -> Unit,
    onSettings: () -> Unit,
    onInvite: () -> Unit,
    isAwaitingServer: Boolean = false,
) {
    val trip = detail.trip

    // Une **pile**, et non des calques posés sur un cadre fixe : c'est le
    // contenu qui décide de la hauteur, et rien ne peut donc en sortir. La
    // photo et le voile se calent sur elle.
    Box(Modifier.fillMaxWidth().clipToBounds()) {
        Box(Modifier.matchParentSize().clearAndSetSemantics {}) {
            // L'aplat d'abord, la photo par-dessus : il tient la place tant
            // qu'elle charge, et la remplace si elle ne vient pas — les deux
            // phases de l'`AsyncImage` d'iOS.
            TripCoverPlaceholder(trip.id, Modifier.matchParentSize())
            trip.coverPhotoUrl?.let { url ->
                AsyncImage(
                    model = url.toString(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.matchParentSize(),
                )
            }
            Scrim(Modifier.matchParentSize())
        }

        Column(
            Modifier
                .fillMaxWidth()
                .heightIn(min = TripHeaderMetrics.minimumHeight()),
            // Les commandes en haut, la légende en bas : l'écart se répartit
            // entre elles, et ne descend jamais sous `xl`.
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Controls(onBack, onSettings, onPrint, isAwaitingServer)
            Spacer(Modifier.height(MemoBookSpacing.xl))
            Caption(detail, onInvite, isAwaitingServer)
        }
    }
}

internal object TripHeaderMetrics {
    /**
     * Le rapport de la maquette : la photo occupe un peu plus d'un carré. Un
     * rapport plutôt qu'une hauteur, pour que la couverture garde ses
     * proportions du petit au grand téléphone.
     */
    const val aspectRatio: Float = 390f / 440f

    /**
     * La hauteur de la maquette — un **plancher**, pas une hauteur figée.
     *
     * C'est toute la différence : figée, elle rognait tout en taille de texte
     * accessible. Les compteurs, qui s'empilent alors les uns sous les autres,
     * débordaient par le haut et venaient se poser sur la flèche de retour.
     * En plancher, la photo grandit avec ce qu'elle porte.
     */
    @Composable
    fun minimumHeight(): Dp = DeviceScreen.width() / aspectRatio
}

/**
 * Le voile. Deux dégradés dans le même calque : le haut porte les commandes,
 * le bas porte le titre, et le milieu de la photo reste net.
 */
@Composable
private fun Scrim(modifier: Modifier) {
    Box(
        modifier.background(
            Brush.verticalGradient(
                0f to Color.Black.copy(alpha = 0.45f),
                0.32f to Color.Black.copy(alpha = 0.05f),
                0.55f to Color.Black.copy(alpha = 0.10f),
                1f to Color.Black.copy(alpha = 0.65f),
            ),
        ),
    )
}

// MARK: - Commandes

@Composable
private fun Controls(onBack: () -> Unit, onSettings: () -> Unit, onPrint: () -> Unit, isAwaitingServer: Boolean) {
    // Les commandes gardent leur place quelle que soit la taille du texte :
    // ce sont trois ronds de 48, pas des libellés.
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = MemoBookSpacing.screenMargin)
            // La photo passe sous la barre d'état ; les commandes, elles, se
            // posent dessous. `DeviceScreen` porte la mesure parce qu'elle
            // change d'un téléphone à l'autre.
            .padding(top = DeviceScreen.topSafeInset() + MemoBookSpacing.xs),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs + 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TripHeaderButton(
            icon = R.drawable.icon_arrow,
            iconSide = MemoBookSpacing.navigationIcon,
            label = "Retour",
            action = onBack,
        )
        Spacer(Modifier.weight(1f))
        // Les réglages **avant** l'imprimante : c'est l'ordre de l'en-tête
        // de la conversation, et les deux écrans du voyage doivent poser
        // la roue au même endroit (Hugo, 15/09/2026).
        TripHeaderButton(
            icon = R.drawable.icon_settings,
            label = "Paramètres du voyage",
            action = onSettings,
            modifier = Modifier.dimmedWhileAwaitingServer(isAwaitingServer),
        )
        TripHeaderButton(
            icon = R.drawable.icon_printer,
            label = "Prévisualiser et commander ce carnet",
            action = onPrint,
            modifier = Modifier.dimmedWhileAwaitingServer(isAwaitingServer),
        )
    }
}

// MARK: - Ce qu'on lit sur la photo

@Composable
private fun Caption(detail: TripDetail, onInvite: () -> Unit, isAwaitingServer: Boolean) {
    val trip = detail.trip
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = MemoBookSpacing.screenMargin)
            // La légende s'arrête **au-dessus du panneau crème**, pas au bord
            // de la photo : celui-ci mord sur elle de la hauteur de son arrondi
            // — voir `TripHomeView` — et une ligne calée sur le bord se
            // retrouvait collée au crème, la file de collaborateurs à demi
            // dessous. La marge se lit donc « ce que le panneau recouvre, plus
            // de quoi respirer ».
            .padding(bottom = MemoBookSpacing.overlayCornerRadius + MemoBookSpacing.m),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        TripStatsRow(trip.stats, tint = MemoBookColor.onAction, isSpread = false)

        BrandText(trip.title, MemoBookFont.h1, color = MemoBookColor.onAction)

        People(detail, onInvite, isAwaitingServer)
    }
}

/**
 * Les **collaborateurs** : ceux qui peuvent ajouter des étapes au voyage.
 *
 * La maquette montre un second groupe à côté — les visages croisés en
 * chemin. Il attend la v2, et n'est donc dessiné nulle part : un groupe
 * qu'on ne peut ni remplir ni comprendre vaut moins que son absence.
 */
@Composable
private fun People(detail: TripDetail, onInvite: () -> Unit, isAwaitingServer: Boolean) {
    val companions = detail.trip.companions
    Row(verticalAlignment = Alignment.CenterVertically) {
        Image(
            painterResource(R.drawable.icon_user),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.onAction),
            modifier = Modifier
                .padding(end = MemoBookSpacing.xs)
                .size(MemoBookSpacing.m),
        )

        // Le « + » est **dans** la pile, pas à côté : c'est elle qui tient
        // le recouvrement des visages, et il doit être le même pour lui.
        CompanionStack(
            companions,
            visibleLimit = 2,
            onAdd = onInvite,
            isAddDimmed = isAwaitingServer,
            facesLabel = if (companions.isEmpty()) {
                "Tu racontes ce voyage seul"
            } else {
                "Racontent aussi ce voyage : ${frenchList(companions.map { it.name })}"
            },
        )

        Spacer(Modifier.weight(1f))
    }
}

/**
 * Un rond translucide posé sur la photo.
 *
 * Le fond sombre n'est pas un choix de marque mais une garantie de
 * lisibilité : une icône blanche sur une couverture claire disparaîtrait sans
 * lui.
 *
 * @param iconSide la boîte du dessin. Les trois ronds font la même taille ; ce
 *   qui est dessiné dedans, non : la flèche de retour garde
 *   [MemoBookSpacing.navigationIcon], validée telle quelle, et les deux
 *   commandes prennent [MemoBookSpacing.contentIcon] — leurs glyphes
 *   (l'imprimante, la roue des réglages) n'occupent qu'une part de leur boîte
 *   et se lisaient à peine à 28. La roue, elle, restait plus petite que
 *   l'imprimante dans la même boîte (42 % contre 68 %) : c'est son fichier qui
 *   a été recadré (`Settings.svg`, `viewBox` resserrée), pas le code. Recadrée
 *   à 15 unités elle paraissait cette fois **plus grosse** — un rond plein de
 *   la largeur d'une imprimante à traits fins pèse plus qu'elle —, 17 unités
 *   la posent à sa hauteur (Hugo, 16/09/2026).
 */
@Composable
private fun TripHeaderButton(
    @DrawableRes icon: Int,
    label: String,
    action: () -> Unit,
    modifier: Modifier = Modifier,
    iconSide: Dp = MemoBookSpacing.contentIcon,
) {
    Box(
        modifier
            .size(MemoBookSpacing.minimumTapTarget)
            .background(Color.Black.copy(alpha = 0.35f), CircleShape)
            .border(1.dp, Color.White.copy(alpha = 0.25f), CircleShape)
            .clickable(interactionSource = null, indication = PlainButtonIndication, role = Role.Button, onClick = action)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painterResource(icon),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.onAction),
            modifier = Modifier.size(iconSide),
        )
    }
}

/**
 * La place de l'en-tête, le temps que le voyage arrive.
 *
 * **Même hauteur, même flèche, même dégradé sombre** que le vrai : c'est ce
 * qui fait que l'écran ne bouge pas quand la photo se pose. Seuls les
 * compteurs, le titre et les co-voyageurs sont remplacés par des barres
 * d'attente — voir [BrandSkeleton].
 *
 * La flèche de retour, elle, n'est pas une barre : c'est la seule sortie de
 * l'écran, et la faire attendre le réseau serait la pire chose à faire d'un
 * chargement lent.
 */
@Composable
internal fun TripHeaderPlaceholder(onBack: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .heightIn(min = TripHeaderMetrics.minimumHeight())
            // Le gris de la couverture manquante, dans le même dégradé sombre
            // que le voile du vrai en-tête : les barres claires s'y lisent, et
            // la photo ne fera que remplacer un fond par un autre.
            .background(Brush.verticalGradient(listOf(MemoBookColor.ink.copy(alpha = 0.55f), MemoBookColor.ink.copy(alpha = 0.75f))))
            .clipToBounds(),
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = MemoBookSpacing.screenMargin)
                .padding(top = DeviceScreen.topSafeInset() + MemoBookSpacing.xs),
        ) {
            TripHeaderButton(icon = R.drawable.icon_arrow, label = "Retour", action = onBack)
        }

        Spacer(Modifier.height(MemoBookSpacing.xl))

        Column(
            Modifier
                .padding(horizontal = MemoBookSpacing.screenMargin)
                // La même marge que la vraie légende, pour la même raison :
                // rien ne doit se glisser sous le panneau crème.
                .padding(bottom = MemoBookSpacing.overlayCornerRadius + MemoBookSpacing.m),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        ) {
            BrandSkeleton(width = 150.dp, onDark = true)
            Box(Modifier.height(MemoBookSpacing.m), contentAlignment = Alignment.CenterStart) {
                BrandSkeleton(width = 220.dp, onDark = true)
            }
            BrandSkeleton(width = 110.dp, onDark = true)
        }
    }
}

/**
 * La place des étapes, le temps qu'elles arrivent : les deux filtres, éteints,
 * et trois cartes vides.
 *
 * Trois et pas une : c'est le nombre courant, et une seule carte laisserait
 * croire à un voyage d'une étape avant de se démultiplier sous les yeux.
 */
@Composable
internal fun TripStepsPlaceholder() {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        // Les **mêmes icônes** que les vrais filtres, et pas un chevron :
        // `BrandFilterChip` en dessine déjà un à droite, et la pastille se
        // retrouvait avec deux chevrons et un libellé coupé. (Sur iOS, la
        // pastille d'attente des transports garde un symbole système ; ici
        // le train des vrais filtres, faute de SF Symbols.)
        Row(
            Modifier
                .padding(horizontal = MemoBookSpacing.screenMargin)
                .clearAndSetSemantics {},
            horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        ) {
            BrandFilterChip("Pays", Modifier.alpha(0.5f), icon = painterResource(TripStepsFilterIcons.country))
            BrandFilterChip("Transports", Modifier.alpha(0.5f), icon = painterResource(LucideIcon.image("train-front")))
        }

        Column(
            Modifier.padding(horizontal = MemoBookSpacing.screenMargin),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        ) {
            repeat(3) { PlaceholderStepCard() }
        }
    }
}

/** La coque exacte d'une `TripStepCard` : vignette carrée à gauche, trois lignes à droite. */
@Composable
private fun PlaceholderStepCard() {
    Row(
        Modifier
            .fillMaxWidth()
            .homeCard()
            .padding(MemoBookSpacing.xs + 2.dp)
            .clearAndSetSemantics {},
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(76.dp)
                .background(MemoBookColor.ink.copy(alpha = 0.07f), RoundedCornerShape(MemoBookSpacing.cornerRadius)),
        )
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            BrandSkeleton(width = 110.dp)
            BrandSkeleton(width = 150.dp)
            BrandSkeleton(width = 90.dp)
        }
    }
}
