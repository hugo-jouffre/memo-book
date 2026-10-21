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
}
