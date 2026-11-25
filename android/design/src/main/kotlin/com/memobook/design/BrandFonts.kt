package com.memobook.design

import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight

/**
 * Les polices de la marque, dans `res/font`.
 *
 * Ce sont **les mêmes fichiers** que ceux de l'app iOS
 * (`MemoBookDesign/Resources/Fonts`) : des instances statiques des polices
 * variables du dépôt, aux interlignes calés sur Figma. Ne jamais les éditer à
 * la main — `python3 ios/Tools/make-brand-fonts.py` écrit les deux copies.
 */
object BrandFonts {
    /** Sora — titres. Deux graisses : le paywall écrit ses titres en deux temps. */
    val sora = FontFamily(
        Font(R.font.sora_regular, FontWeight.Normal),
        Font(R.font.sora_semibold, FontWeight.SemiBold),
    )

    /** General Sans — corps de texte, dans les trois graisses de la maquette. */
    val generalSans = FontFamily(
        Font(R.font.generalsans_regular, FontWeight.Normal),
        Font(R.font.generalsans_medium, FontWeight.Medium),
        Font(R.font.generalsans_semibold, FontWeight.SemiBold),
    )

    /** Gloria Hallelujah — l'écriture à la main du carnet (`memos.fontHand`). */
    val gloriaHallelujah = FontFamily(Font(R.font.gloriahallelujah, FontWeight.Normal))

    /**
     * **Les typographies des sept plats**, celles de l'atelier d'impression
     * (`MemoBook Generator/public/couverture-styles.js`, § `POLICES`).
     *
     * Elles ne servent **qu'aux plats** : l'app n'écrit rien d'autre avec.
     * Jusqu'au 25/11/2026 elle les approchait par les polices du système — un
     * empattement pour « Par défaut » et « Élégant », le grotesque le plus
     * lourd pour les trois autres —, si bien qu'un même plat sortait en trois
     * typographies selon qu'on le regardait à l'écran, dans le PDF du carnet ou
     * sur le livre imprimé. On choisit une couverture en la regardant
     * (T256, Hugo). Le détail de l'attribution est dans le jumeau Swift.
     *
     * Chacune est une famille d'**un seul** fichier, demandée en
     * [FontWeight.Normal] : la graisse est dans le dessin (Playfair Black,
     * Poppins Black), pas dans la requête — un `FontWeight.Black` sur une
     * famille qui ne l'a pas donnerait un faux gras synthétique.
     *
     * ⚠️ Au sous-ensemble latin, comme sur iOS : une lettre d'Europe centrale
     * dans un titre tomberait sur la police du système.
     */
    object Cover {
        /** « Par défaut » : le titre en capitales. Et « Assouline » pour tout ce qui n'est pas son titre. */
        val playfairBlack = FontFamily(Font(R.font.playfairdisplay_black, FontWeight.Normal))
        val playfairRegular = FontFamily(Font(R.font.playfairdisplay_regular, FontWeight.Normal))

        /** « Élégant » : le titre, puis le reste dans la variante Infant. */
        val cormorantGaramond = FontFamily(Font(R.font.cormorantgaramond_regular, FontWeight.Normal))
        val cormorantInfant = FontFamily(Font(R.font.cormorantinfant_medium, FontWeight.Normal))

        /** « Assouline » : le titre, large et noir. */
        val archivoBlack = FontFamily(Font(R.font.archivoblack_regular, FontWeight.Normal))

        /** « Aquarelle » : le titre, puis le reste en Manrope. */
        val poppinsBlack = FontFamily(Font(R.font.poppins_black, FontWeight.Normal))
        val manrope = FontFamily(Font(R.font.manrope_regular, FontWeight.Normal))

        /** « Travel book » : une seule police pour tout le plat. */
        val lilitaOne = FontFamily(Font(R.font.lilitaone, FontWeight.Normal))

        /**
         * « Photo-dessin » : le pinceau. « Dessin », lui, garde
         * [BrandFonts.gloriaHallelujah] — c'est la police que l'atelier lui donne aussi.
         */
        val caveatBrush = FontFamily(Font(R.font.caveatbrush_regular, FontWeight.Normal))
    }
}
