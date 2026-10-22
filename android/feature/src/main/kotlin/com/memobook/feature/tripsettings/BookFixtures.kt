package com.memobook.feature.tripsettings

import com.memobook.core.BookCustomisation
import com.memobook.core.BookExcerpt
import com.memobook.core.BookPreview
import com.memobook.core.BookPreviewStatus
import com.memobook.core.DailyCredit
import com.memobook.core.NarrationPace
import com.memobook.core.TripSettings
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

// Jeu d'essai du parcours « carnet » — **temporaire**, comme celui du profil.
// Le jumeau de `BookFixtures.swift`.
//
// Ce fichier expose, au module `:feature` seulement :
// - `TripSettings.fixture`, les réglages du voyage de Rome (crédit du jour
//   entamé, trois co-voyageurs dont le propriétaire, aucun PDF) ;
// - `BookCustomisation.fixture`, les valeurs de la maquette et de la base ;
// - `BookPreview.fixture` (le carnet prêt à feuilleter, sans PDF) et
//   `BookPreview.composingFixture` (le carnet en train de se composer).
//
// Les quatre écrans sont entièrement pilotés par ces données : pas un libellé
// de valeur, pas un montant, pas une date n'est écrit dans une vue. Le jour où
// l'API rend ces structures, ce fichier disparaît et rien d'autre ne bouge.
//
// Les valeurs sont celles des maquettes, pour que la comparaison avec Figma
// porte sur le dessin et non sur le contenu.

internal val TripSettings.Companion.fixture: TripSettings
    get() = TripSettings(
        tripId = "trip-rome",
        name = "Rome 2026",
        // Un voyage **entamé** : 1 min 40 racontée aujourd'hui, il en reste
        // 3 min 20 — la jauge verte au tiers, la ligne d'un non-abonné. C'est
        // l'état de tout le monde, celui qu'il faut voir par défaut ; le panneau
        // de débogage rejoue le neuf, les 30 dernières secondes, l'épuisé et
        // l'abonné. Le crédit se recharge au prochain minuit.
        dailyCredit = DailyCredit(
            usedMs = 100_000,
            resetsAt = LocalDate.now().plusDays(1).atStartOfDay(ZoneId.systemDefault()).toInstant(),
        ),
        startDate = settingsDay(26, 8, 2026),
        endDate = settingsDay(15, 9, 2026),
        narrationPace = NarrationPace.EveryTwoDays,
        wantsNotifications = true,
        // Le propriétaire **est dans la liste** : c'est ce que montre la feuille
        // « Inviter un proche », et c'est ce qui fait lire la liste comme celle
        // du voyage entier. Il en est retiré là où l'on compte les autres — voir
        // [TripSettings.guests].
        companions = listOf(
            com.memobook.core.Companion(id = "margaux", name = "Margaux Dupont", isOwner = true, isViewer = true),
            com.memobook.core.Companion(id = "tom", name = "Tom John", role = "Ton pote d’enfance"),
            // Le troisième n'est jamais entré : c'est lui qui montre l'action
            // « Renvoyer » du glissé.
            com.memobook.core.Companion(id = "ana", name = "@ana.prn", isPending = true),
        ),
        accessCode = "JHKFDA",
        theme = "City trip & découvertes",
        isPublicGallery = false,
        styleSummary = "Pointillés, cadres, etc.",
        // **Pas de PDF** : un jeu d'essai n'a pas de carnet composé, et c'est
        // très bien — c'est l'état que R11 réclame et que la maquette ne dessine
        // pas. Les feuilles de personnalisation s'ouvrent alors sans les deux
        // pages au-dessus d'elles (voir `BookPagesPeek`). Pour les voir dans
        // l'émulateur, poser ici l'URL d'un PDF de carnet.
        isPrintable = true,
        customisation = BookCustomisation.fixture,
    )

/**
 * Une date fixe, sans dépendre du jour où l'aperçu tourne : deux captures
 * prises à un mois d'écart doivent se superposer. À minuit dans le fuseau de
 * l'appareil, comme le calendrier grégorien d'iOS.
 */
private fun settingsDay(day: Int, month: Int, year: Int): Instant =
    LocalDate.of(year, month, day).atStartOfDay(ZoneId.systemDefault()).toInstant()

/**
 * Les valeurs de la maquette « Personnalisations du carnet — Mise en page ».
 * Ce sont aussi les défauts de la base (`memos`, M4) : les deux disent la même
 * chose, et c'est voulu — un carnet neuf ressemble à ce que la maquette montre.
 */
internal val BookCustomisation.Companion.fixture: BookCustomisation
    get() = BookCustomisation(
        photoTextRatio = 50,
        targetPageCount = 60,
        funFactsEnabled = true,
        rulesEnabled = true,
        decorationQuota = 2,
        fontTitle = "Hansley",
        fontDisplay = "Playfair Display",
        fontHand = "Gloria Hallelujah",
        fontFacts = "Playfair Display",
        quizEnabled = true,
        freeZonesEnabled = true,
        crosswordEnabled = true,
    )

/**
 * Le carnet de la maquette, prêt à feuilleter.
 *
 * **Sans PDF** : un aperçu n'a pas de document dans un jeu d'essai, et c'est
 * très bien — c'est l'état « le carnet existe, le fichier n'est pas encore là »
 * que R11 réclame et que la maquette ne dessine pas.
 */
internal val BookPreview.Companion.fixture: BookPreview
    get() = BookPreview(
        memoId = "memo-rome",
        title = "Rome et la Dolce Vita",
        status = BookPreviewStatus.Ready,
        pageCount = 10,
        tripDate = settingsDay(12, 10, 2026),
        excerpt = BookExcerpt(
            quote = "Ce voyage commence bien avant le décollage...",
            detail = "Les ruines dorées du Colisée nous rappellent la grandeur de l’histoire à chaque coin de rue.",
        ),
        hasConfiguredCovers = false,
    )

/** Le carnet en train de se composer — l'écran « On compose ton Carnet ». */
internal val BookPreview.Companion.composingFixture: BookPreview
    get() = BookPreview(
        memoId = "memo-rome",
        title = "Rome et la Dolce Vita",
        status = BookPreviewStatus.Composing,
        pageCount = 10,
    )
