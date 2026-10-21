package com.memobook.design

import androidx.annotation.DrawableRes

/**
 * Les pictogrammes empruntés à [Lucide](https://lucide.dev), là où le jeu de
 * marque n'a rien à proposer : les types de voyage, les modes de transport.
 * Jumeau de `LucideIcon.swift`.
 *
 * **La clé est celle de la source** — le nom du fichier Lucide. Elle vient de
 * la base pour les catégories de la galerie (`gallery_categories.iconKey`). Une
 * clé inconnue retombe sur la boussole : une catégorie ajoutée en base
 * n'attend pas la prochaine version de l'app.
 */
object LucideIcon {
    /** Les clés que l'app sait dessiner. */
    val known: Set<String> = setOf(
        "backpack",
        "bike",
        "building-2",
        "car-front",
        "compass",
        "footprints",
        "globe",
        "heart",
        "mountain-snow",
        "palmtree",
        "sailboat",
        "tent-tree",
        "train-front",
        "users",
        "utensils",
    )

    /** Ce qu'on met quand on ne sait pas : une boussole, qui ne ment sur aucune catégorie. */
    const val FALLBACK = "compass"

    /** Le pictogramme d'une clé. Toujours une image. */
    @DrawableRes
    fun image(key: String?): Int = BrandImages[assetName(key)] ?: R.drawable.icon_lucide_compass

    /**
     * « mountain-snow » → `IconLucideMountainSnow`, le nom du catalogue. La même
     * règle que `ios/Tools/import-lucide-icons.py` et que `LucideIcon.swift`.
     */
    internal fun assetName(key: String?): String {
        val resolved = key?.takeIf { it in known } ?: FALLBACK
        return "IconLucide" + resolved.split('-', '_').joinToString("") { word ->
            word.replaceFirstChar { it.uppercase() }
        }
    }
}
