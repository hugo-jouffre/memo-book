package com.memobook.design

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

// Palette et typographie de la marque, recopiées de `MemoBookDesign/Tokens.swift`,
// lui-même recopié des variables Figma du fichier « MemoBook — Product ». Ce
// fichier est la seule source de vérité côté Android : aucune couleur, taille
// de police ou marge codée en dur ailleurs. Un token change ? Les deux fichiers
// changent dans la même PR.
//
// Les couleurs sont volontairement **fixes** : MemoBook est un carnet de papier
// crème, il ne se retourne pas en sombre. L'app ne suit pas le thème sombre du
// téléphone.

/** Couleurs de l'app. Les noms sont ceux de `MemoBookColor` côté iOS. */
object MemoBookColor {
    /** Couleur d'action : boutons primaires, liens, sélection. — Figma `Brand Colors/Green`. */
    val action = Color(0xFF28654B)

    /** Vert clair : les signaux discrets. — Figma `Brand Colors/Green Lighter`. */
    val actionLight = Color(0xFF3D9A6F)

    /** Le voyant du micro, et rien d'autre. Le rouge système d'iOS, repris tel quel. */
    val recording = Color(0xFFFF3B30)

    /** Texte principal, un noir chaud. — Figma `Brand Colors/Black`. */
    val ink = Color(0xFF2D231A)

    /** Le gris système d'iOS. — Figma `Grays/Gray`. */
    val gray = Color(0xFF8E8E93)
    val inkMuted = Color(0xFF2B231B).copy(alpha = 0.5f)
    val inkFaint = Color(0xFF2B231B).copy(alpha = 0.3f)
    val hairline = Color(0xFF2B231B).copy(alpha = 0.1f)

    /** Le papier crème de tous les écrans. */
    val background = Color(0xFFFCF2E9)
    val surface = Color(0xFFFFFCF8)
    val paper = Color(0xFFFFFCF8)
    val onAction = Color(0xFFFFFCF8)
    val beige = Color(0xFFF9E6D6)
    val noticeBeige = Color(0xFFE6D5C4)
    val listeningBackground = Color(0xFFC9DDF0)

    /** L'accent de tout ce qui n'est pas l'abonnement. — Figma `Brand Colors/Blue`. */
    val outline = Color(0xFFAFD2F0)
    val bubbleTraveller = outline
    val bubbleMemo = surface

    /** Le lime **ne dit que l'abonnement** (T7). */
    val accent = Color(0xFFE2F32B)
    val blueText = Color(0xFF4088C6)
    val send = blueText
    val separator = Color(0xFFCFBBAA)
    val disabled = Color(0xFFC3C3C7)
    val disabledOutline = Color(0xFFC8C8C8)

    val valid = Color(0xFF3FA673)
    val warning = Color(0xFFFF682C)
    val error = Color(0xFFDE2B2E)
    val errorSoft = Color(0xFFFBDDDD)
    val information = Color(0xFF4A8FE0)

    val coverCream = Color(0xFFF5EDE5)
    val coverMint = Color(0xFFCDF9F5)
    val coverForest = Color(0xFF19532B)
    val coverPostmark = Color(0xFF8E3343)
    val coverWash = Color(0xFFE9DDD1)
}

/**
 * Marges, rayons et tailles. Les valeurs iOS sont en points, ici en dp : 1 pt
 * d'iPhone et 1 dp d'Android désignent la même taille à l'œil, et Figma fait foi
 * (1 rem = 16).
 */
object MemoBookSpacing {
    val xs = 8.dp
    val s = 16.dp
    val m = 24.dp
    val l = 32.dp
    val xl = 40.dp

    /** **La** marge latérale de l'app. Un écran ne définit jamais la sienne. */
    val screenMargin = 16.dp
    val snug = 12.dp
    val sectionGap = 20.dp

    val cornerRadius = 14.dp
    val largeCornerRadius = 20.dp
    val galleryCornerRadius = 24.dp
    val bubbleCornerRadius = 12.dp
    val controlCornerRadius = 16.dp
    val sheetCornerRadius = 28.dp
    val overlayCornerRadius = 40.dp
    val pageCornerRadius = 8.dp

    /** 44 pt sur iOS ; Android recommande 48 dp, et c'est 48 qui s'applique ici. */
    val minimumTapTarget = 48.dp
    val avatarSide = 40.dp
    val initialsSide = 36.dp
    val navigationIcon = 28.dp

    /** Une icône de contenu du jeu de marque se dessine à 2 rem, pas à 24. */
    val contentIcon = 32.dp
    val controlHeight = 50.dp
    val mediumControlHeight = 48.dp
    val fieldHeight = 56.dp
    val progressBarHeight = 6.dp
}

/**
 * Les styles de texte. Tailles en sp : elles suivent la taille de police
 * choisie dans les réglages du téléphone, comme le Dynamic Type sur iOS.
 *
 * L'interligne n'est pas posé ici : il est **dans les polices**, que
 * `ios/Tools/make-brand-fonts.py` cale sur Figma et recopie dans `res/font`.
 * Un `lineHeight` posé en plus ne ferait que s'y ajouter.
 */
object MemoBookFont {
    /** L'espacement des lettres de la maquette : 1 % de la taille. */
    private val tracking: TextUnit = 0.01.em

    private fun style(family: FontFamily, weight: FontWeight, size: Int) =
        TextStyle(fontFamily = family, fontWeight = weight, fontSize = size.sp, letterSpacing = tracking)

    val h1 = style(BrandFonts.sora, FontWeight.SemiBold, 32)
    val h1Light = style(BrandFonts.sora, FontWeight.Normal, 32)
    val h2 = style(BrandFonts.sora, FontWeight.SemiBold, 24)
    val h3 = style(BrandFonts.sora, FontWeight.Normal, 14)
    val eyebrow = style(BrandFonts.sora, FontWeight.Normal, 16)
    val heading = style(BrandFonts.sora, FontWeight.SemiBold, 20)
    val headingLight = style(BrandFonts.sora, FontWeight.Normal, 20)
    val button = style(BrandFonts.sora, FontWeight.SemiBold, 18)
    val buttonSmall = style(BrandFonts.sora, FontWeight.SemiBold, 16)
    val cardTitle = style(BrandFonts.sora, FontWeight.SemiBold, 16)
    val balance = style(BrandFonts.sora, FontWeight.SemiBold, 48)
    val figure = style(BrandFonts.sora, FontWeight.SemiBold, 24)
    val sectionOverline = style(BrandFonts.sora, FontWeight.SemiBold, 12)
    val screenTitle = h1

    fun bookTitle(size: Int = 28) = style(BrandFonts.sora, FontWeight.SemiBold, size)

    val body = style(BrandFonts.generalSans, FontWeight.Normal, 16)
    val bodySemibold = style(BrandFonts.generalSans, FontWeight.SemiBold, 16)
    val tagline = style(BrandFonts.generalSans, FontWeight.SemiBold, 14)
    val taglineRegular = style(BrandFonts.generalSans, FontWeight.Normal, 14)
    val caption = style(BrandFonts.generalSans, FontWeight.Normal, 12)
    val bubble = style(BrandFonts.generalSans, FontWeight.Normal, 17)
    val bubbleAction = style(BrandFonts.generalSans, FontWeight.Medium, 17)
    val composer = style(BrandFonts.generalSans, FontWeight.Normal, 21)
    val mention = style(BrandFonts.generalSans, FontWeight.Normal, 11)
    val notification = body
    val sectionTitle = style(BrandFonts.generalSans, FontWeight.SemiBold, 17)
    val greeting = style(BrandFonts.generalSans, FontWeight.Normal, 24)
    val calloutTitle = style(BrandFonts.generalSans, FontWeight.SemiBold, 20)
    val label = style(BrandFonts.generalSans, FontWeight.Medium, 14)
    val overline = style(BrandFonts.generalSans, FontWeight.SemiBold, 12)
    val rowAction = style(BrandFonts.generalSans, FontWeight.Normal, 13)
    val microBadge = style(BrandFonts.generalSans, FontWeight.SemiBold, 11)

    /** L'écriture à la main du carnet, et rien d'autre dans l'app. */
    val handwriting = style(BrandFonts.gloriaHallelujah, FontWeight.Normal, 16)

    /** La transcription en direct : la chasse fixe du système. */
    val transcript = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 16.sp)
}

/** Les deux ombres nommées de la marque. Il n'y en aura pas de troisième. */
enum class MemoBookShadow(val color: Color, val radius: Dp, val offsetY: Dp) {
    Soft(Color.Black.copy(alpha = 0.10f), 2.dp, 1.dp),
    Raised(Color.Black.copy(alpha = 0.15f), 12.dp, 4.dp),
}
