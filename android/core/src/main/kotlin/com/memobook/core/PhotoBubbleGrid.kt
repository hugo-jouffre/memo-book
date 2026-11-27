package com.memobook.core

/**
 * **Comment une bulle range ses photos** (T305, Hugo — « les photos en nombre
 * impair se rangent comme sur WhatsApp : toute la largeur de la bulle occupée,
 * chacune au format qu'elle a »). Le jumeau de `PhotoBubbleGrid.swift`.
 *
 * La bulle les posait toutes dans le même carré, et laissait un **trou** à la
 * dernière place quand elles étaient en nombre impair. Une photo portrait y
 * était rognée en carré, une panoramique aussi, et le trou se lisait comme une
 * photo qui manque.
 *
 * La règle tient en deux temps : **deux par rangée**, jamais trois, la
 * dernière seule prenant toute la largeur ; et **une rangée remplit la
 * largeur**, ses photos y gardant leur format — la hauteur commune se déduit
 * de la somme de leurs rapports largeur sur hauteur.
 *
 * ⚠️ Les formats viennent du serveur, pas de l'image chargée : une hauteur de
 * bulle qui se découvre au chargement ferait sauter le fil (T295, T313). Une
 * photo sans mesure compte pour un carré.
 */
object PhotoBubbleGrid {
    /** Deux par rangée, jamais trois. */
    const val MAXIMUM_PER_ROW = 2

    /** Le rapport d'une photo sans mesure : un carré. */
    const val SQUARE_ASPECT = 1.0

    /** Les rangées, par rangs de photos. */
    fun rows(count: Int): List<IntRange> {
        if (count <= 0) return emptyList()
        return (0 until count step MAXIMUM_PER_ROW).map { start ->
            start until minOf(start + MAXIMUM_PER_ROW, count)
        }
    }

    /** La hauteur d'une rangée qui remplit [width], formats compris. */
    fun rowHeight(aspects: List<Double>, width: Double, spacing: Double, maximum: Double): Double {
        val usable = maxOf(0.0, width - spacing * maxOf(0, aspects.size - 1))
        val total = aspects.sumOf { if (it > 0) it else SQUARE_ASPECT }
        if (total <= 0 || usable <= 0) return 0.0
        return minOf(maximum, usable / total)
    }

    /**
     * Les largeurs d'une rangée, à la hauteur donnée. La dernière prend ce qui
     * reste : à l'arrondi près, les divisions ne retombent pas sur la largeur
     * de la bulle, et un cheveu de fond se verrait.
     */
    fun widths(aspects: List<Double>, height: Double, width: Double, spacing: Double): List<Double> {
        if (aspects.isEmpty()) return emptyList()
        val kept = aspects.map { if (it > 0) it else SQUARE_ASPECT }
        val widths = kept.map { it * height }.toMutableList()
        val gaps = spacing * (kept.size - 1)
        val last = width - gaps - widths.dropLast(1).sum()
        if (last > 0) widths[widths.size - 1] = last
        return widths
    }
}
