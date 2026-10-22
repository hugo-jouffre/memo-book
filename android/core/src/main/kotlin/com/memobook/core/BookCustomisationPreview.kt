package com.memobook.core

import java.net.URI

// L'aperçu de personnalisation : l'image qui surmonte l'écran
// « Personnalisations » et change à chaque réglage touché. Le jumeau de
// `MemoBookCore/BookCustomisationPreview.swift`.
//
// Ce n'est pas l'aperçu du carnet (`BookPreview`, le PDF composé) : c'est une
// image **déjà rendue**, choisie parmi deux cents d'après cinq réglages. Ce
// fichier dit laquelle, et où la lire — pas comment elle s'anime, qui est
// l'affaire de l'écran. `docs/apercu-personnalisation.md` fait foi ;
// l'hébergement est décrit dans `assets/README.md`.

/**
 * Quelle image d'aperçu montrer pour un état du carnet.
 *
 * Les noms disponibles sont une **donnée** — [availableFileNames], recopiée de
 * `BookCustomisationPreviewManifest.swift`, que génère
 * `ios/Tools/make-customisation-preview-manifest.py` depuis le dossier des
 * visuels —, pas un accès disque dont on rattraperait l'échec : le choix se fait
 * sans rien charger, et se teste.
 */
object BookCustomisationPreview {
    /**
     * L'image de repli, dans le même dossier que les aperçus.
     *
     * **Sans cédille**, et c'est voulu : c'était le seul nom du dossier en
     * Unicode décomposé, et le nom « évident » renvoyait un 404. L'ASCII le
     * tient hors de portée du problème.
     */
    const val fallbackFileName = "apercu non existant.png"

    /**
     * Où vivent les images publiées : le bucket **public** `memobook-public`,
     * sous `apercus/`, derrière le CDN de Supabase (`assets/README.md`). Le
     * même pour tous les environnements — ce sont les mêmes images pour tout
     * le monde, lues sans session.
     */
    val publicBaseURL: URI =
        URI("https://pjmetjdnajskijoljulc.supabase.co/storage/v1/object/public/memobook-public/apercus/")

    /**
     * L'adresse de l'image à afficher pour ce carnet : celle de [fileName],
     * publiée.
     *
     * Les exports Figma pèsent 800 Ko ; l'app lit leur version publiée, en
     * WebP à 900 × 840. La correspondance est **embarquée** (Hugo,
     * 02/10/2026) : un seul appel réseau, celui de l'image, et aucun manifeste
     * à attendre. Le repli a sa propre image publiée, comme les autres.
     */
    fun imageURL(customisation: BookCustomisation): URI {
        val name = fileName(customisation)
        val file = publishedFiles[name] ?: publishedFallback
        return publicBaseURL.resolve(file)
    }

    /**
     * Le nom du fichier d'aperçu à afficher pour ce carnet.
     *
     * Cinq propriétés seulement le décident : `rulesEnabled`,
     * `photoTextRatio`, `funFactsEnabled`, `decorationQuota`, et l'assortiment
     * que forment les quatre polices. Le nombre de pages, le quiz, les zones
     * libres et les mots fléchés n'y entrent pas — c'est ce qui permet à
     * l'écran de ne recharger l'image que quand ce nom change.
     *
     * Le repli dans deux cas : un carnet « Personnalisé », dont les polices ne
     * forment aucun des trois assortiments ; et une combinaison absente du
     * manifeste.
     *
     * ⚠️ **Les pointillés sont lus tels quels.** La contrainte qui les éteint
     * hors de l'assortiment par défaut vit en amont, sur l'écran : une fois
     * posée, chaque état atteignable a son aperçu. Ne pas la redoubler ici —
     * le jour où les rendus manquants arrivent, elle saute, et cette fonction
     * ne doit pas avoir à bouger : relancer le script suffit. Un carnet que
     * la contrainte n'a pas touché — passé sur *Manuscrit* avant elle, avec
     * ses pointillés — tombe sur le repli plutôt que sur une image sans les
     * pointillés qu'il imprimera.
     *
     * Kotlin compare les chaînes unité par unité (comme une URL, et à la
     * différence de Swift) : le nom composé et l'élément du manifeste sont donc
     * les mêmes octets dès qu'ils sont égaux.
     */
    fun fileName(
        customisation: BookCustomisation,
        among: Set<String> = availableFileNames,
    ): String {
        val name = composedFileName(customisation) ?: return fallbackFileName
        return among.firstOrNull { it == name } ?: fallbackFileName
    }

    /**
     * Le nom que la règle compose, que le fichier existe ou non. `null` pour un
     * carnet « Personnalisé ».
     *
     * L'ordre des segments et leur séparateur sont ceux des fichiers, au
     * caractère près.
     */
    internal fun composedFileName(customisation: BookCustomisation): String? {
        val combo = BookFontCombo.matching(customisation) ?: return null
        val typos = typographySegments[combo.id] ?: return null

        val segments = listOf(
            "Pointillés=${if (customisation.rulesEnabled) "on" else "off"}",
            "Ratio image=${customisation.photoTextRatio}%",
            "Fun fact=${if (customisation.funFactsEnabled) "on" else "off"}",
            "Stickers=${customisation.decorationQuota}",
            "Typos=$typos",
        )
        return segments.joinToString(", ") + ".png"
    }

    /**
     * Le segment `Typos=` de chaque assortiment, **tel que les fichiers
     * l'écrivent** : une forme abrégée, non normalisée, qui nomme
     * l'assortiment et non ses quatre polices.
     */
    internal val typographySegments: Map<String, String> = mapOf(
        BookFontCombo.travelJournal.id to "Playfair Display - Hansley - Gloria Hallelujah",
        // « Hellelujah » : une faute de frappe figée dans cinquante noms de
        // fichiers. La corriger ici ferait tomber *Manuscrit* sur le repli.
        BookFontCombo.handwritten.id to "Hansley - Gloria Hellelujah",
        BookFontCombo.editorial.id to "Playfair Display",
    )

    /**
     * Les 200 aperçus du dossier, image de repli exclue — chacun
     * écrit comme sur le disque. La table est dans
     * `BookCustomisationPreviewManifest.kt`.
     */
    val availableFileNames: Set<String> = BookCustomisationPreviewManifest.publishedFiles.keys

    /**
     * L'image publiée de chaque aperçu, à résoudre contre [publicBaseURL]. Ce
     * sont des empreintes : une image refaite change de nom, l'ancienne reste
     * en ligne.
     */
    internal val publishedFiles: Map<String, String> get() = BookCustomisationPreviewManifest.publishedFiles

    /** L'image publiée du repli. */
    internal val publishedFallback: String get() = BookCustomisationPreviewManifest.publishedFallback
}
