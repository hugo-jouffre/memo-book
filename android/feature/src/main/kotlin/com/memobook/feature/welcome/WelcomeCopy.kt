package com.memobook.feature.welcome

import androidx.annotation.DrawableRes
import com.memobook.design.R

/**
 * Les textes de l'écran d'entrée, recopiés du nœud Figma
 * « Accueil - 1ère Connexion » (`3420:10409`) au caractère près — apostrophes
 * typographiques comprises (R8). Jumeau de `WelcomeCopy.swift`.
 *
 * La mention légale vouvoyait dans la maquette (« vous acceptez ») ; Figma
 * tutoie depuis, et l'app suit (Hugo, 17/09/2026, T113).
 */
object WelcomeCopy {
    /**
     * Le titre se lit en deux temps, comme ceux du paywall : la moitié
     * courante à l'encre, la chute en vert et en gras.
     */
    const val titleLead = "Raconte tes histoires, "
    const val titleStrong = "on s’occupe du reste."

    const val subtitle =
        "Crée ton journal de voyage à l’oral ou à l’écrit, et reçois un magnifique carnet imprimé !"

    /**
     * Les trois temps du produit, sous les trois icônes de la marque.
     *
     * **Les bichromes** (`…Duo`), et non les traits d'encre qu'on pose
     * ailleurs : cet écran est une vitrine, pas une barre d'outils. Le bleu
     * d'aplat de la marque les fait ressortir sur le crème de la carte, et il
     * les tient ensemble — c'est pour ça qu'aucune des trois ne reste
     * monochrome.
     *
     * ⚠️ **L'imprimante est la version pleine.** `IconPrinterDuo` dessine un
     * contour ; le micro et le cadre photo, eux, sont pleins. Les trois côte à
     * côte, ça se voit : l'imprimante paraissait vide au milieu des deux
     * autres. `Printer Filled 2` la remplit comme ses voisines.
     */
    data class Feature(@param:DrawableRes val icon: Int, val label: String) {
        val id: String get() = label
    }

    val features: List<Feature> = listOf(
        Feature(R.drawable.icon_mic_duo, "1. Raconte"),
        Feature(R.drawable.icon_picture_frame_duo, "2. Ajoute"),
        Feature(R.drawable.icon_printer_filled_duo, "3. Reçois"),
    )

    const val rating = "🌟 4.9/5"
    const val community = "Rejoint par 12 000+ voyageurs"

    const val hello = "Hello ! 👋"
    const val helloDetail = "Nous allons t’accompagner dans tes récits."

    /**
     * Le libellé du bouton Apple. Sur iOS, `SignInWithAppleButton(.continue)`
     * écrit le sien, dans la langue de l'appareil ; Android n'a pas de bouton
     * Apple du système, l'app écrit donc le mot qu'Apple y met en français.
     */
    const val apple = "Continuer avec Apple"
    const val google = "Continuer avec Google"
    const val email = "S’inscrire avec un e-mail"
    const val legal = "En continuant, tu acceptes nos conditions d’utilisation."

    /** La même phrase, en trois morceaux : le lien est le milieu (T151). */
    const val legalLead = "En continuant, tu acceptes nos "
    const val legalLink = "conditions d’utilisation"
    const val legalTail = "."

    /**
     * La flèche de retour des écrans d'entrée par e-mail. Elle ramène ici, et
     * c'est la seule sortie de ces écrans-là.
     */
    const val back = "Retour"

    object Voice {
        const val hero = "Des carnets de voyage MemoBook posés sur une table"
        const val rating = "Noté 4,9 sur 5, rejoint par plus de 12 000 voyageurs"
    }
}
