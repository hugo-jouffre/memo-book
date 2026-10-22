package com.memobook.feature.gallery

import com.memobook.core.Destination
import com.memobook.core.Gallery
import com.memobook.core.GalleryCategory
import com.memobook.core.GalleryTrip

// Jeu d'essai de la galerie — **temporaire**. Le jumeau de `GalleryFixtures.swift`.
//
// Ce fichier expose, au module `:feature` seulement, `Gallery.fixture` (neuf
// catégories, neuf carnets, un voyage à reprendre) et
// `Gallery.emptyTravellerFixture` (la même galerie, sans voyage à reprendre).
//
// L'écran est entièrement piloté par ces données : pas un titre, pas une
// catégorie, pas un pictogramme n'est écrit dans une vue. Le jour où l'API rend
// une `Gallery`, ce fichier disparaît et rien d'autre ne bouge.
//
// Il recopie ce que `backend/prisma/seed.ts` pose en base : les deux doivent
// montrer le même écran, sans quoi l'aperçu cesse d'être une référence.

/**
 * Les identifiants des catégories. Des chaînes lisibles plutôt que des UUID :
 * ce sont eux qu'on lit dans un aperçu quand une carte se range mal.
 */
private object Category {
    const val tourDuMonde = "cat-tour-du-monde"
    const val randonnee = "cat-randonnee"
    const val roadTrip = "cat-road-trip"
    const val cityTrip = "cat-city-trip"
    const val plage = "cat-plage-et-iles"
    const val montagne = "cat-montagne"
    const val famille = "cat-en-famille"
    const val velo = "cat-velo"
    const val voile = "cat-voile"
}

private val fixtureCategories = listOf(
    GalleryCategory(id = Category.tourDuMonde, slug = "tour-du-monde", name = "Tour du monde", iconKey = "globe"),
    GalleryCategory(id = Category.randonnee, slug = "randonnee", name = "Randonnée", iconKey = "footprints"),
    GalleryCategory(id = Category.roadTrip, slug = "road-trip", name = "Road trip", iconKey = "car-front"),
    GalleryCategory(id = Category.cityTrip, slug = "city-trip", name = "City trip", iconKey = "building-2"),
    GalleryCategory(id = Category.plage, slug = "plage-et-iles", name = "Plage & îles", iconKey = "palmtree"),
    GalleryCategory(id = Category.montagne, slug = "montagne", name = "Montagne", iconKey = "mountain-snow"),
    GalleryCategory(id = Category.famille, slug = "en-famille", name = "En famille", iconKey = "users"),
    GalleryCategory(id = Category.velo, slug = "velo", name = "Vélo", iconKey = "bike"),
    GalleryCategory(id = Category.voile, slug = "voile", name = "Voile & mer", iconKey = "sailboat"),
)

private val fixtureTrips = listOf(
    GalleryTrip(
        id = "gallery-bali",
        title = "Bali entre amis",
        subtitle = "2 semaines de trek",
        destinations = listOf(Destination(name = "Indonésie", countryCode = "ID")),
        categoryIds = listOf(Category.randonnee, Category.plage),
    ),
    GalleryTrip(
        id = "gallery-philippines",
        title = "Philippines avec Claire & Gus",
        subtitle = "2 mois de tour du monde",
        // Trois pays : c'est le globe qui se pose dans le coin, pas un drapeau.
        destinations = listOf(
            Destination(name = "Philippines", countryCode = "PH"),
            Destination(name = "Vietnam", countryCode = "VN"),
            Destination(name = "Thaïlande", countryCode = "TH"),
        ),
        categoryIds = listOf(Category.tourDuMonde, Category.plage),
    ),
    GalleryTrip(
        id = "gallery-tdm-2025",
        title = "TDM 2025",
        subtitle = "Un couple autour du monde",
        destinations = listOf(
            Destination(name = "Argentine", countryCode = "AR"),
            Destination(name = "Chili", countryCode = "CL"),
            Destination(name = "Pérou", countryCode = "PE"),
            Destination(name = "Nouvelle-Zélande", countryCode = "NZ"),
        ),
        categoryIds = listOf(Category.tourDuMonde),
    ),
    GalleryTrip(
        id = "gallery-alpes",
        title = "La traversée des Alpes",
        subtitle = "12 jours de refuge en refuge",
        destinations = listOf(
            Destination(name = "France", countryCode = "FR"),
            Destination(name = "Suisse", countryCode = "CH"),
            Destination(name = "Italie", countryCode = "IT"),
        ),
        categoryIds = listOf(Category.randonnee, Category.montagne),
    ),
    GalleryTrip(
        id = "gallery-islande",
        title = "Road trip en Islande",
        subtitle = "1 400 km sur la ring road",
        destinations = listOf(Destination(name = "Islande", countryCode = "IS")),
        categoryIds = listOf(Category.roadTrip),
    ),
    GalleryTrip(
        id = "gallery-lisbonne",
        title = "Lisbonne en famille",
        subtitle = "5 jours à quatre, sans voiture",
        destinations = listOf(Destination(name = "Portugal", countryCode = "PT")),
        categoryIds = listOf(Category.cityTrip, Category.famille),
    ),
    GalleryTrip(
        id = "gallery-velodyssee",
        title = "De Nantes à Saint-Malo à vélo",
        subtitle = "8 jours sur la Vélodyssée",
        destinations = listOf(Destination(name = "France", countryCode = "FR")),
        categoryIds = listOf(Category.velo),
    ),
    GalleryTrip(
        id = "gallery-cyclades",
        title = "Les Cyclades à la voile",
        subtitle = "3 semaines d’île en île",
        destinations = listOf(Destination(name = "Grèce", countryCode = "GR")),
        categoryIds = listOf(Category.voile, Category.plage),
    ),
    GalleryTrip(
        id = "gallery-kyoto",
        title = "Kyoto au printemps",
        // Sans résumé, volontairement : l'agent n'a pas encore écrit le sien, et
        // la carte doit alors n'afficher que son titre.
        destinations = listOf(Destination(name = "Japon", countryCode = "JP")),
        categoryIds = listOf(Category.cityTrip),
    ),
)

private val galleryFixture = Gallery(
    categories = fixtureCategories,
    trips = fixtureTrips,
    resumableTripId = "trip-rome",
)

/**
 * La galerie telle qu'on la voit avec un voyage déjà ouvert : le bouton du bas
 * dit alors « Continuer mon voyage ».
 */
internal val Gallery.Companion.fixture: Gallery get() = galleryFixture

private val galleryEmptyTravellerFixture = Gallery(
    categories = fixtureCategories,
    trips = fixtureTrips,
    resumableTripId = null,
)

/**
 * La même galerie, vue par quelqu'un qui n'a encore aucun carnet : le bouton
 * passe à « Créer mon voyage ».
 */
internal val Gallery.Companion.emptyTravellerFixture: Gallery get() = galleryEmptyTravellerFixture
