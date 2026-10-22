package com.memobook.feature.covers

import com.memobook.core.BookCover
import com.memobook.core.BookCovers
import com.memobook.core.CoverFace
import com.memobook.core.CoverFamily
import com.memobook.core.CoverPhoto
import com.memobook.core.CoverStat
import com.memobook.core.CoverStyle
import com.memobook.core.CoverTint
import com.memobook.core.CoverTreatment

// Jeu d'essai des couvertures — **temporaire**, comme celui des quatre autres
// écrans du carnet. Le jumeau de `CoverFixtures.swift`.
//
// Ce fichier expose, au module `:feature` seulement, `BookCovers.fixture` (les
// deux plats du voyage de Rome, les sept familles de gabarits, cinq photos,
// huit chiffres du dos) et `CoverStyle.fixture(family, face)`.
//
// ⚠️ **Le contenu est celui du voyage de Rome**, et non celui de la maquette,
// qui raconte les Philippines. C'est le seul endroit où ce fichier s'écarte de
// la règle « les valeurs sont celles des maquettes » — et c'est pour une raison
// qui prime : on arrive sur les couvertures **depuis les réglages de Rome**, et
// ouvrir la couverture d'un carnet appelé « Rome 2026 » sur le mot PHILIPPINES
// se lit comme un bogue, pas comme un jeu d'essai. Le dessin, lui, est bien
// celui de Figma — c'est ce que la comparaison doit porter.

internal val BookCovers.Companion.fixture: BookCovers
    get() = BookCovers(
        front = BookCover(
            styleId = "front-default",
            photoId = "photo-2",
            title = "Rome",
            subtitle = "Maylis, Claire et Augustin\nAoût 2026",
        ),
        back = BookCover(
            styleId = "back-default",
            photoId = "photo-4",
            subtitle = "Quelques jours à la découverte de Rome, entre ruelles baignées de soleil, marchés animés, architecture baroque et longues soirées italiennes.\n\nUn carnet de voyage fait de lieux, de rencontres et de petits moments que l’on aurait aimé ne jamais oublier.",
            statIds = listOf("stat-days", "stat-km", "stat-countries"),
        ),
        // **Les sept gabarits de `assets/covers`**, par paires (08/10/2026) — les
        // mêmes identifiants que `coverCatalogue.ts`. La pastille « Assortie à ta
        // 1ère de couverture » suit la famille du devant.
        frontStyles = CoverFamily.entries.map { CoverStyle.fixture(it, face = CoverFace.Front) },
        backStyles = CoverFamily.entries.map { CoverStyle.fixture(it, face = CoverFace.Back) },
        // Sans URL : un jeu d'essai n'a pas de photothèque. Les plats dessinent
        // alors l'aplat de repli du voyage — le même que les cartes de l'accueil,
        // teinté d'après l'identifiant.
        photos = (1..5).map { CoverPhoto(id = "photo-$it") },
        stats = listOf(
            CoverStat(id = "stat-days", value = "21", label = "jours\nde voyage"),
            CoverStat(id = "stat-km", value = "2,3k", label = "km\nparcourus"),
            CoverStat(id = "stat-countries", value = "1", label = "pays\nvisité"),
            CoverStat(id = "stat-steps", value = "14", label = "étapes\nde voyage"),
            CoverStat(id = "stat-stays", value = "6", label = "logements\ndifférents"),
            CoverStat(id = "stat-meals", value = "38", label = "plats\ndécouverts"),
            CoverStat(id = "stat-people", value = "27", label = "personnes\nrencontrées"),
            CoverStat(id = "stat-transport", value = "4", label = "transports\nutilisés"),
        ),
    )

/**
 * Le style d'une famille, tel que le serveur le sert — identifiant, nom, et la
 * composition de repli des apps d'avant les gabarits.
 */
internal fun CoverStyle.Companion.fixture(family: CoverFamily, face: CoverFace): CoverStyle {
    val front = face == CoverFace.Front
    val (name, treatment, tint) = when (family) {
        CoverFamily.Default -> Triple(
            "Par défaut",
            if (front) CoverTreatment.Photo else CoverTreatment.Plain,
            if (front) CoverTint.Ink else CoverTint.Paper,
        )
        CoverFamily.Watercolor -> Triple("Aquarelle", CoverTreatment.Framed, CoverTint.Sand)
        CoverFamily.Assouline -> Triple("Assouline", CoverTreatment.Plain, CoverTint.Slate)
        CoverFamily.Drawing -> Triple("Dessin", CoverTreatment.Kraft, CoverTint.Paper)
        CoverFamily.PhotoDrawing -> Triple(
            "Photo-dessin",
            if (front) CoverTreatment.Photo else CoverTreatment.Plain,
            if (front) CoverTint.Ink else CoverTint.Paper,
        )
        CoverFamily.TravelBook -> Triple("Travel book", CoverTreatment.Framed, CoverTint.Paper)
        CoverFamily.Elegant -> Triple("Élégant", CoverTreatment.Framed, CoverTint.Paper)
    }
    return CoverStyle(
        id = "${face.rawValue}-${family.rawValue}",
        name = name,
        treatment = treatment,
        tint = tint,
        family = family,
    )
}
