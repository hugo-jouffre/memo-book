package com.memobook.design

import androidx.annotation.DrawableRes
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.max
import androidx.compose.ui.unit.min

/**
 * L'en-tête d'un écran secondaire : par où l'on sort, de quoi on parle, et au
 * plus une action. Jumeau de `BrandScreenHeader.swift`.
 *
 * Plusieurs écrans le dessinaient à l'identique — les paramètres d'un voyage,
 * la composition du carnet, l'aperçu PDF. C'est **le** motif de l'écran poussé,
 * et il vit ici pour une raison précise : la flèche de retour est le même geste
 * partout, elle doit donc tomber au même endroit et faire la même taille d'un
 * écran à l'autre. Elle valait déjà trois valeurs différentes avant que
 * [MemoBookSpacing.navigationIcon] existe.
 *
 * ```kotlin
 * BrandScreenHeader(BookCopy.Order.TITLE, onBack = onClose, subtitle = OrderStep.Copies.progressLabel)
 * ```
 *
 * Il ne pose pas de barre de navigation, et le geste de retour reste celui du
 * système. **[onBack] est obligatoire ici**, alors qu'iOS referme l'écran par
 * `dismiss()` quand on ne le donne pas : Compose n'a pas de `dismiss` sans
 * `activity-compose`, que `:design` n'embarque pas. L'écran passe donc le même
 * retour que celui du geste système — ou l'étape précédente d'un parcours.
 *
 * @param subtitle la ligne sous le titre. `null` quand l'écran n'en a pas —
 *   l'en-tête se contente alors d'une ligne, il ne réserve pas la place.
 * @param isSubtitleLoading le sous-titre vient du serveur et n'est pas encore
 *   là. Le **titre**, lui, s'affiche toujours tout de suite : il appartient à
 *   l'app. Voir [BrandSkeleton].
 * @param onBack ce que fait la flèche. Un **parcours en étapes** la détourne
 *   pour revenir à l'étape précédente : la flèche reste alors le même geste au
 *   même endroit, et c'est bien pour ça qu'elle vit ici et non dans chaque écran.
 * @param trailing l'action de bout de ligne, au plus une — [BrandHeaderAction].
 *   Deux commandes en tête d'un écran poussé et on ne sait plus laquelle est la
 *   sortie.
 */
@Composable
fun BrandScreenHeader(
    title: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    isSubtitleLoading: Boolean = false,
    trailing: (@Composable () -> Unit)? = null,
) {
    // La hauteur d'une ligne du titre (`MemoBookFont.heading`, Sora 20), pour
    // poser la flèche **en face** de cette ligne.
    val titleLineHeight = scaled(26.dp)
    // La ligne du haut aligne la flèche sur le **titre** et non sur le bloc
    // entier : avec un sous-titre de trois lignes, un centrage vertical faisait
    // descendre la sortie au milieu du texte. Et en face de sa première ligne,
    // pas de son bord haut : posés bord à bord, la flèche tombait sous le
    // milieu du titre (Hugo, 14/09/2026, T103). La marge du titre vaut donc la
    // moitié de l'écart entre la cible et la ligne. En taille accessible le
    // titre dépasse la cible : plus rien à rattraper.
    val titleInset = if (isAccessibilityTextSize()) {
        0.dp
    } else {
        max(0.dp, (MemoBookSpacing.minimumTapTarget - titleLineHeight) / 2)
    }

    Row(
        modifier.padding(bottom = MemoBookSpacing.xs),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        verticalAlignment = Alignment.Top,
    ) {
        BackButton(onBack)

        // Le texte prend la place qui reste et la garde : sans ça, un titre
        // court laissait l'action revenir se coller contre lui. Les deux lignes
        // s'enroulent plutôt que de se faire rogner : en taille accessible,
        // « Rome et la Dolce Vita - 10 pages composées » tient sur trois
        // lignes, et l'en-tête grandit avec.
        Column(
            Modifier
                .weight(1f)
                .padding(top = titleInset),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            BrandText(title, MemoBookFont.heading, Modifier.semantics { heading() })

            if (isSubtitleLoading) {
                BrandSkeleton(width = 180.dp)
            } else if (subtitle != null) {
                // Le sous-titre d'un parcours en étapes change à chaque
                // « Continuer » — « Étape 2/7 », « Étape 3/7 ». Il se remplace
                // en fondu plutôt que d'un coup sec, sans quoi c'est la seule
                // chose de l'en-tête qui saute. (iOS fait rouler les chiffres,
                // `numericText` ; Compose n'a que le fondu.)
                Crossfade(subtitle, animationSpec = SwiftMotion.smooth(0.25f), label = "subtitle") { text ->
                    BrandText(text, MemoBookFont.h3)
                }
            }
        }

        trailing?.invoke()
    }
}

/**
 * La flèche de retour, bichrome comme sur toutes les maquettes d'écran poussé.
 *
 * Sa cible tactile est **alignée à gauche sur la marge de la colonne** et le
 * dessin centré dedans : centrée sur l'icône, elle débordait de la colonne et
 * la moitié gauche des touches tombait à côté.
 */
@Composable
private fun BackButton(onBack: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    Box(
        Modifier
            .size(MemoBookSpacing.minimumTapTarget)
            .alpha(plainPressAlpha(interaction))
            .clickable(interactionSource = interaction, indication = null, role = Role.Button, onClick = onBack)
            .semantics { contentDescription = "Retour" },
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painter = painterResource(R.drawable.icon_arrow_duo),
            contentDescription = null,
            modifier = Modifier.size(MemoBookSpacing.navigationIcon),
        )
    }
}

/**
 * Une commande carrée en bout d'en-tête : une icône cerclée d'un filet
 * d'encre, à la cible tactile de l'app.
 *
 * Le cerne la distingue de la flèche de retour, qui n'en a pas : la sortie est
 * un geste qu'on connaît, l'action de l'écran est un bouton qu'on découvre.
 *
 * @param icon une icône du catalogue (`R.drawable.icon_share_system`), là où
 *   iOS reçoit son nom.
 * @param label ce que TalkBack annonce.
 */
@Composable
fun BrandHeaderAction(@DrawableRes icon: Int, label: String, modifier: Modifier = Modifier, action: () -> Unit) {
    // L'icône suit le texte, la cible non : une commande qui grandit à l'infini
    // pousserait le titre hors de sa ligne. 24 et non 28 (Hugo, 19/09/2026) :
    // le tracé du partage remplit sa boîte bien plus que le crayon ou
    // l'engrenage, et à 28 il pesait plus lourd que le titre qu'il accompagne.
    val iconSide = min(scaled(24.dp), MemoBookSpacing.l)
    val shape = RoundedCornerShape(MemoBookSpacing.snug)
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier
            .size(MemoBookSpacing.minimumTapTarget)
            .alpha(plainPressAlpha(interaction))
            // Figma dessine un filet de 0,75 pt ; 1 est l'épaisseur unique de
            // l'app (`Stroke/Border Width`) : un second filet plus fin ne se
            // verrait pas, il ne ferait que se distinguer à l'export.
            .border(1.dp, MemoBookColor.ink, shape)
            .clickable(interactionSource = interaction, indication = null, role = Role.Button, onClick = action)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painter = painterResource(icon),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.ink),
            modifier = Modifier.size(iconSide),
        )
    }
}

/**
 * Le `.buttonStyle(.plain)` d'iOS : rien au repos, le dessin pâlit sous le
 * doigt. Partagé par les deux commandes de l'en-tête.
 */
@Composable
private fun plainPressAlpha(interaction: MutableInteractionSource): Float {
    val pressed by interaction.collectIsPressedAsState()
    val alpha by animateFloatAsState(if (pressed) 0.7f else 1f, tween(120), label = "press")
    return alpha
}

@Preview(locale = "fr-rFR", name = "En-têtes d’écran", widthDp = 390, heightDp = 500)
@Composable
private fun BrandScreenHeaderPreview() {
    Column(
        Modifier
            .fillMaxSize()
            .background(MemoBookColor.background)
            .padding(horizontal = MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.l),
    ) {
        BrandScreenHeader("Paramètres du voyage", onBack = {})
        BrandScreenHeader("Commander mon carnet", onBack = {}, subtitle = "Étape 3/7 - Exemplaires")
        BrandScreenHeader("Aperçu PDF", onBack = {}, subtitle = "Rome et la Dolce Vita - 10 pages composées") {
            BrandHeaderAction(R.drawable.icon_share_system, "Partager mon carnet") {}
        }
        BrandScreenHeader("Aperçu PDF", onBack = {}, isSubtitleLoading = true)
    }
}
