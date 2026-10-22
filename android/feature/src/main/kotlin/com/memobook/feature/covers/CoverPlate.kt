package com.memobook.feature.covers

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.memobook.core.BookCopy
import com.memobook.core.BookCover
import com.memobook.core.CoverFace
import com.memobook.core.CoverFamily
import com.memobook.core.CoverPhoto
import com.memobook.core.CoverStat
import com.memobook.core.CoverStyle
import com.memobook.core.CoverTint
import com.memobook.core.CoverTreatment
import com.memobook.design.BrandFonts
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookShadow
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R
import com.memobook.design.brandShadow

/**
 * Un plat de couverture, dessiné. Jumeau de `Covers/CoverPlate.swift`.
 *
 * **La seule vue de couverture de l'app.** Les quatre écrans du parcours s'en
 * servent — le choix, le carrousel des styles, celui des photos et l'écran des
 * textes —, et c'est ce qui garantit qu'on regarde la même chose du début à la
 * fin : un plat qui changerait d'un écran à l'autre ne serait plus un aperçu.
 *
 * ⚠️ **Ce n'est pas le rendu d'impression.** Le carnet est mis en page par le
 * gabarit, que l'app ne rejoue pas. Ce plat-ci montre la **composition** — le
 * cadrage, la place du titre, le rapport A5 — avec la photo et les mots du
 * voyageur. Le jour où le gabarit rendra les couvertures, cette vue laisse la
 * place à une image et rien d'autre ne bouge.
 *
 * Les mesures du plat sont des **fractions de sa largeur** et non des dp : le
 * même dessin sert à 208 dans un carrousel et à 300 sur l'écran de choix, et il
 * doit se réduire entièrement — marges comprises.
 *
 * ⚠️ **Et ses typographies ne suivent pas la taille de police du téléphone.**
 * C'est la seule entorse de l'app à la règle, et elle est délibérée : ce plat
 * n'est pas de l'interface, c'est **l'image d'un objet imprimé**. Le titre d'une
 * couverture ne grossit pas parce que son lecteur a agrandi le texte — à 200 %,
 * il déborderait du plat. L'interface autour, elle, suit la taille de police
 * comme partout ailleurs.
 *
 * @param stats les chiffres à imprimer au dos. Vides sur la première de couverture.
 * @param companion le plat d'en face : le dos d'un gabarit reprend qui a voyagé, et quand.
 * @param gallery les photos du voyage, pour les gabarits qui en posent plusieurs.
 * @param width la largeur du plat. Sa hauteur en découle — voir [CoverPlate.ratio].
 * @param titleBadge ce que les crayons de l'écran des textes viennent poser
 *   par-dessus le titre. Rien sur les trois autres écrans — comme
 *   [subtitleBadge] et [statsBadge].
 */
@Composable
fun CoverPlate(
    cover: BookCover,
    style: CoverStyle?,
    photo: CoverPhoto?,
    face: CoverFace,
    width: Dp,
    modifier: Modifier = Modifier,
    stats: List<CoverStat> = emptyList(),
    companion: BookCover? = null,
    gallery: List<CoverPhoto> = emptyList(),
    titleBadge: (@Composable () -> Unit)? = null,
    subtitleBadge: (@Composable () -> Unit)? = null,
    statsBadge: (@Composable () -> Unit)? = null,
) {
    val shape = RoundedCornerShape(MemoBookSpacing.snug)
    Box(
        modifier
            .size(width, width / CoverPlate.ratio)
            .brandShadow(MemoBookShadow.Soft, shape)
            .clip(shape)
            .border(1.dp, MemoBookColor.hairline, shape),
    ) {
        // **Un des sept gabarits** quand le style en porte un (08/10/2026,
        // `CoverTemplate`) ; sinon la composition d'avant, pour un style qu'un
        // serveur plus ancien — ou plus récent — servirait sans famille connue.
        val family = style?.family
        if (family != null) {
            CoverTemplate(
                family = family,
                face = face,
                cover = cover,
                companion = companion,
                photo = photo,
                gallery = gallery,
                stats = stats,
                width = width,
                titleBadge = titleBadge,
                subtitleBadge = subtitleBadge,
                statsBadge = statsBadge,
            )
        } else {
            TreatmentCover(cover, style, photo, face, stats, width, titleBadge, subtitleBadge, statsBadge)
        }
    }
}

object CoverPlate {
    /**
     * Le rapport d'un carnet A5 — celui du carnet imprimé, et celui que la
     * vignette des réglages emploie déjà.
     *
     * La maquette dessine 233 × 339, soit 1,455 : neuf points d'écart sur la
     * hauteur. C'est **le format du papier** qui tranche, pas l'artboard.
     * Signalé (T87).
     */
    const val ratio: Float = 1f / 1.414f
}

/** La composition d'avant les gabarits : un fond selon le traitement, le titre, la signature, le dos. */
@Composable
private fun TreatmentCover(
    cover: BookCover,
    style: CoverStyle?,
    photo: CoverPhoto?,
    face: CoverFace,
    stats: List<CoverStat>,
    width: Dp,
    titleBadge: (@Composable () -> Unit)?,
    subtitleBadge: (@Composable () -> Unit)?,
    statsBadge: (@Composable () -> Unit)?,
) {
    val m = rememberCoverMetrics(width)
    val treatment = style?.treatment ?: CoverTreatment.Plain
    val tint = style?.tint ?: CoverTint.Paper
    // L'encre du plat : claire sur les fonds sombres, sombre sur les clairs.
    val ink = when (treatment) {
        CoverTreatment.Photo -> MemoBookColor.paper
        CoverTreatment.Framed, CoverTreatment.Kraft -> MemoBookColor.ink
        CoverTreatment.Plain -> when (tint) {
            CoverTint.Forest, CoverTint.Ink -> MemoBookColor.paper
            CoverTint.Paper, CoverTint.Sand, CoverTint.Slate -> MemoBookColor.ink
        }
    }
    // La photo, ou la trame du voyage. Un lien signé expiré redemande des liens
    // neufs (T237) — voir `CoverPhotoImage`.
    val photoLayer: @Composable (Modifier) -> Unit = { CoverPhotoImage(photo, seed = photo?.id ?: cover.styleId, modifier = it) }

    Box(Modifier.fillMaxSize()) {
        // Le fond.
        when (treatment) {
            CoverTreatment.Photo -> {
                photoLayer(Modifier.fillMaxSize())
                // Le titre se pose **sur** la photo : sans ce voile, un ciel
                // clair avale les lettres blanches. Il descend du haut et
                // remonte du bas, là où le texte tombe, et laisse le milieu intact.
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.45f), Color.Transparent, Color.Black.copy(alpha = 0.45f)))),
                )
            }
            CoverTreatment.Framed, CoverTreatment.Plain, CoverTreatment.Kraft -> Box(Modifier.fillMaxSize().background(tint.color))
        }

        when (face) {
            // Le devant : le titre en haut, la signature en bas.
            CoverFace.Front -> Column(
                Modifier
                    .fillMaxSize()
                    .padding(m.u(0.09f)),
            ) {
                CoverBadged(titleBadge, Alignment.TopEnd, Modifier.fillMaxWidth()) {
                    // Le titre du carnet. Manuscrit sur un kraft, composé partout ailleurs.
                    val titleStyle = if (treatment == CoverTreatment.Kraft) m.hand(0.13f) else m.font(BrandFonts.sora, FontWeight.SemiBold, 0.155f)
                    CoverText(cover.title, titleStyle, ink, Modifier.fillMaxWidth(), maxLines = 2, minimumScaleFactor = 0.5f)
                }
                Spacer(Modifier.weight(1f))
                CoverBadged(subtitleBadge, Alignment.BottomEnd, Modifier.fillMaxWidth()) {
                    CoverText(cover.subtitle, m.sans(0.055f), ink, Modifier.fillMaxWidth(), maxLines = 3, minimumScaleFactor = 0.6f)
                }
            }
            // Le dos : la photo encadrée, le texte de quatrième, les chiffres,
            // le logo. C'est l'ordre de la maquette, et il raconte quelque
            // chose : on regarde, on lit, on compte, puis on voit d'où ça vient.
            CoverFace.Back -> Column(
                Modifier
                    .fillMaxSize()
                    .padding(m.u(0.09f)),
                verticalArrangement = Arrangement.spacedBy(m.u(0.05f)),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                if (treatment == CoverTreatment.Framed) {
                    photoLayer(
                        Modifier
                            .fillMaxWidth()
                            .height(m.u(0.3f))
                            .clip(RoundedCornerShape(m.u(0.02f))),
                    )
                }
                // **Une photo pleine page ne porte pas de texte de quatrième**,
                // et c'est ce que l'écran des textes annonce en grisant le plat
                // (Hugo, 16/09/2026). Le dessin doit dire la même chose.
                if (treatment.carriesText(CoverFace.Back)) {
                    // Le crayon du texte de dos, en haut à droite du texte (T90)
                    // — le devant pose le sien en bas de la signature.
                    CoverBadged(subtitleBadge, Alignment.TopEnd, Modifier.fillMaxWidth()) {
                        CoverText(
                            cover.subtitle,
                            m.sans(0.045f),
                            ink,
                            Modifier.fillMaxWidth(),
                            lineSpacing = m.u(0.014f),
                            minimumScaleFactor = 0.5f,
                        )
                    }
                }
                Spacer(Modifier.weight(1f))
                if (stats.isNotEmpty()) TreatmentStats(stats, ink, m, statsBadge)
                CoverLogo(ink.copy(alpha = ink.alpha * 0.7f), Modifier.height(m.u(0.07f)))
            }
        }
    }
}

/** « Mon voyage en quelques chiffres », et les trois ou quatre retenus. */
@Composable
private fun TreatmentStats(stats: List<CoverStat>, ink: Color, m: CoverMetrics, statsBadge: (@Composable () -> Unit)?) {
    CoverBadged(statsBadge, Alignment.TopEnd) {
        Column(
            Modifier
                .border(1.dp, ink.copy(alpha = 0.4f), RoundedCornerShape(m.u(0.03f)))
                .padding(m.u(0.04f)),
            verticalArrangement = Arrangement.spacedBy(m.u(0.03f)),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            CoverText(BookCopy.Covers.Stats.heading, m.font(BrandFonts.generalSans, FontWeight.SemiBold, 0.04f), ink)
            Row(horizontalArrangement = Arrangement.spacedBy(m.u(0.03f)), verticalAlignment = Alignment.Top) {
                stats.forEach { stat ->
                    Column(
                        Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(m.u(0.012f)),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        // « 2,3k » se coupait en deux lignes sur une colonne
                        // étroite (Clara, 17/09/2026) : un chiffre tient sur une
                        // ligne et rapetisse s'il le faut.
                        CoverText(stat.value, m.font(BrandFonts.sora, FontWeight.SemiBold, 0.085f), ink, maxLines = 1, minimumScaleFactor = 0.5f)
                        CoverText(stat.label, m.sans(0.035f), ink, minimumScaleFactor = 0.5f)
                    }
                }
            }
        }
    }
}

/** L'aplat d'un plat sans photo. */
private val CoverTint.color: Color
    get() = when (this) {
        CoverTint.Paper -> MemoBookColor.paper
        CoverTint.Sand -> MemoBookColor.beige
        CoverTint.Forest -> MemoBookColor.action
        CoverTint.Slate -> MemoBookColor.outline
        CoverTint.Ink -> MemoBookColor.ink
    }

// MARK: - La pastille de sélection

/**
 * Le rond coché qui coiffe le plat retenu, dans les deux carrousels.
 *
 * Il déborde du coin haut-droit du plat, comme la maquette : posé dedans, il
 * serait passé pour un bouton de la couverture elle-même.
 */
@Composable
fun CoverSelectionBadge(modifier: Modifier = Modifier) {
    // 27 de dessin dans un rond de 45 sur la maquette ; le rond visible en fait
    // 32, le reste est la marge du composant.
    Box(
        modifier
            .size(32.dp)
            .background(MemoBookColor.surface, CircleShape)
            .border(1.5.dp, MemoBookColor.outline, CircleShape)
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painterResource(R.drawable.icon_lucide_check),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.action),
            modifier = Modifier.size(MemoBookSpacing.s),
        )
    }
}

/**
 * Renouvelle les liens signés des photos de couverture quand l'une d'elles ne
 * charge plus (T237). Posé par les écrans des couvertures ; `null` ailleurs.
 */
val LocalRefreshCoverPhotos = staticCompositionLocalOf<(suspend () -> Unit)?> { null }

@Preview(locale = "fr-rFR", name = "Plats sans famille — devant et dos")
@Composable
private fun CoverPlateTreatmentPreview() {
    val cover = BookCover(styleId = "framed", title = "Rome et la Dolce Vita", subtitle = "Camille, Paul et Léa\nAoût 2026")
    val stats = listOf(CoverStat("days", "12", "jours"), CoverStat("km", "2,3k", "kilomètres"), CoverStat("photos", "184", "photos"))
    Row(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.s),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        CoverPlate(cover, CoverStyle("photo", "Photo", CoverTreatment.Photo, CoverTint.Paper), photo = null, face = CoverFace.Front, width = 160.dp)
        CoverPlate(cover, CoverStyle("framed", "Encadrée", CoverTreatment.Framed, CoverTint.Sand), photo = null, face = CoverFace.Back, width = 160.dp, stats = stats)
    }
}

@Preview(locale = "fr-rFR", name = "Les sept gabarits, devant", widthDp = 900)
@Composable
private fun CoverTemplatesFrontPreview() {
    val cover = BookCover(styleId = "default", title = "Philippines", subtitle = "Maylis, Claire et Augustin\nAoût 2026")
    Row(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.s),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        CoverFamily.entries.forEach { family ->
            CoverPlate(cover, CoverStyle(family.rawValue, family.name, CoverTreatment.Photo, CoverTint.Paper, family), photo = null, face = CoverFace.Front, width = 116.dp)
        }
    }
}

@Preview(locale = "fr-rFR", name = "Les sept gabarits, dos", widthDp = 900)
@Composable
private fun CoverTemplatesBackPreview() {
    val front = BookCover(styleId = "default", title = "Philippines", subtitle = "Maylis, Claire et Augustin\nAoût 2026")
    val back = BookCover(
        styleId = "default",
        subtitle = "Trois semaines d’îles en îles.\n\nDes ferries à l’aube, des plages sans personne.\n\nEt ce dernier coucher de soleil à El Nido.",
    )
    val stats = listOf(CoverStat("days", "21", "jours"), CoverStat("km", "2,3k", "kilomètres"), CoverStat("photos", "412", "photos"))
    Row(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.s),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        CoverFamily.entries.forEach { family ->
            CoverPlate(
                back,
                CoverStyle(family.rawValue, family.name, CoverTreatment.Framed, CoverTint.Paper, family),
                photo = null,
                face = CoverFace.Back,
                width = 116.dp,
                stats = stats,
                companion = front,
            )
        }
    }
}
