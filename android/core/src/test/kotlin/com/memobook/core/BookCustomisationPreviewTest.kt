package com.memobook.core

import kotlinx.serialization.Serializable
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * L'**aperçu de personnalisation** : quelle image, parmi deux cents, surmonte
 * l'écran « Personnalisations ». `docs/apercu-personnalisation.md` fait foi.
 * Mêmes cas que `BookCustomisationPreviewTests.swift`.
 *
 * Comme le test iOS, deux cas lisent le dépôt lui-même : le dossier des exports
 * Figma (`assets/illustrations/aperçu personnalisation/`) et le manifeste publié
 * (`assets/illustrations/apercus-personnalisation.manifest.json`). Rien n'est
 * recopié dans `android/` : le test remonte du dossier de travail de Gradle
 * (`android/core`) jusqu'à la racine du dépôt.
 */
class BookCustomisationPreviewTest {
    private val fallback = BookCustomisationPreview.fallbackFileName

    // MARK: La règle

    @Test
    fun theUntouchedBookShowsTheDefaultPreview() {
        // Celui qui s'affiche à l'ouverture de l'écran : il doit exister, et
        // ne pas être le repli.
        assertEquals(
            "Pointillés=on, Ratio image=50%, Fun fact=on, Stickers=2, Typos=Playfair Display - Hansley - Gloria Hallelujah.png",
            BookCustomisationPreview.fileName(BookCustomisation()),
        )
    }

    @Test
    fun eachComboNamesItsOwnPreview() {
        // Hors de l'assortiment par défaut, la contrainte éteint les
        // pointillés : ce sont ces états-là qui existent.
        assertEquals(
            "Pointillés=off, Ratio image=50%, Fun fact=on, Stickers=2, Typos=Playfair Display - Hansley - Gloria Hallelujah.png",
            BookCustomisationPreview.fileName(book(BookFontCombo.travelJournal, rules = false)),
        )
        assertEquals(
            "Pointillés=off, Ratio image=50%, Fun fact=on, Stickers=2, Typos=Hansley - Gloria Hellelujah.png",
            BookCustomisationPreview.fileName(book(BookFontCombo.handwritten, rules = false)),
        )
        assertEquals(
            "Pointillés=off, Ratio image=50%, Fun fact=on, Stickers=2, Typos=Playfair Display.png",
            BookCustomisationPreview.fileName(book(BookFontCombo.editorial, rules = false)),
        )
    }

    @Test
    fun theHandwrittenTypoIsKept() {
        // « Hellelujah » est figé dans cinquante noms de fichiers. La police,
        // elle, s'appelle bien Gloria Hallelujah : corriger le segment
        // ferait tomber tout *Manuscrit* sur le repli.
        val name = BookCustomisationPreview.fileName(book(BookFontCombo.handwritten, rules = false))
        assertTrue(name.endsWith("Typos=Hansley - Gloria Hellelujah.png"), name)
        assertEquals("Gloria Hallelujah", BookFontCombo.handwritten.font(BookFontRole.Texts))
    }

    @Test
    fun everyRatioStepHasItsPreview() {
        // Les bornes du curseur, et chaque cran entre elles.
        for (ratio in 0..100 step 25) {
            assertEquals(
                "Pointillés=on, Ratio image=$ratio%, Fun fact=on, Stickers=2, Typos=Playfair Display - Hansley - Gloria Hallelujah.png",
                BookCustomisationPreview.fileName(book(BookFontCombo.travelJournal, ratio = ratio)),
            )
        }
    }

    @Test
    fun aRatioOffTheSliderFallsBack() {
        // Une valeur posée par un autre client, ou d'avant le pas de 25 : la
        // règle ne l'arrondit pas, elle n'a pas d'image pour elle.
        for (ratio in listOf(-25, 10, 60, 125)) {
            assertEquals(
                fallback,
                BookCustomisationPreview.fileName(book(BookFontCombo.travelJournal, ratio = ratio)),
                "ratio $ratio",
            )
        }
    }

    @Test
    fun everyStickerCountHasItsPreview() {
        for (quota in 0..4) {
            assertEquals(
                "Pointillés=on, Ratio image=50%, Fun fact=on, Stickers=$quota, Typos=Playfair Display - Hansley - Gloria Hallelujah.png",
                BookCustomisationPreview.fileName(book(BookFontCombo.travelJournal, quota = quota)),
            )
        }
    }

    @Test
    fun aStickerCountOffTheSliderFallsBack() {
        for (quota in listOf(-1, 5)) {
            assertEquals(
                fallback,
                BookCustomisationPreview.fileName(book(BookFontCombo.travelJournal, quota = quota)),
                "quota $quota",
            )
        }
    }

    @Test
    fun aHandComposedBookFallsBack() {
        // L'état « Personnalisé » : quatre polices qui ne forment aucun des
        // trois assortiments. Le seul qui n'a pas d'aperçu une fois la
        // contrainte posée.
        val oneOff = BookCustomisation(rulesEnabled = false).copy(fontHand = "Montserrat")

        // L'ancien « Moderne », retiré le 18/09/2026, et l'ancien
        // « Éditorial », qui mariait Alegreya au récit : leurs carnets
        // gardent leurs polices et se lisent « Personnalisé ».
        val modern = BookCustomisation(
            rulesEnabled = false,
            fontTitle = "Montserrat",
            fontDisplay = "Montserrat",
            fontHand = "Alegreya",
            fontFacts = "Montserrat",
        )
        val formerEditorial = book(BookFontCombo.editorial, rules = false)
            .copy(fontHand = "Alegreya", fontFacts = "Alegreya")

        for (custom in listOf(oneOff, modern, formerEditorial)) {
            assertNull(BookFontCombo.matching(custom))
            assertNull(BookCustomisationPreview.composedFileName(custom))
            assertEquals(fallback, BookCustomisationPreview.fileName(custom))
        }
    }

    @Test
    fun theShortFamilyNameStillFindsThePreview() {
        // La base a longtemps reçu « Playfair » là où le gabarit dit
        // « Playfair Display » : ces carnets sont dans l'assortiment par
        // défaut, et doivent en avoir l'aperçu.
        val book = BookCustomisation().copy(fontDisplay = "Playfair", fontFacts = "Playfair")
        val name = BookCustomisationPreview.fileName(book)
        assertNotEquals(fallback, name)
        assertEquals(BookCustomisationPreview.fileName(BookCustomisation()), name)
    }

    @Test
    fun settingsOutsideThePreviewLeaveItAlone() {
        // Nombre de pages, quiz, zones libres, mots fléchés : aucun ne doit
        // changer l'image — donc aucun ne doit la recharger.
        val changes: List<Pair<String, (BookCustomisation) -> BookCustomisation>> = listOf(
            "targetPageCount" to { it.copy(targetPageCount = 120) },
            "quizEnabled" to { it.copy(quizEnabled = !it.quizEnabled) },
            "freeZonesEnabled" to { it.copy(freeZonesEnabled = !it.freeZonesEnabled) },
            "crosswordEnabled" to { it.copy(crosswordEnabled = !it.crosswordEnabled) },
            "hasConfiguredCovers" to { it.copy(hasConfiguredCovers = !it.hasConfiguredCovers) },
        )

        val starts = listOf(
            book(BookFontCombo.travelJournal),
            book(BookFontCombo.handwritten, rules = false),
            book(BookFontCombo.editorial, rules = false),
        )
        for (start in starts) {
            val reference = BookCustomisationPreview.fileName(start)
            // Sinon le test passerait à vide : le repli ne change jamais.
            assertNotEquals(fallback, reference)

            var all = start
            for ((property, change) in changes) {
                val one = change(start)
                all = change(all)
                assertEquals(reference, BookCustomisationPreview.fileName(one), property)
            }
            assertEquals(reference, BookCustomisationPreview.fileName(all), "les cinq à la fois")
        }
    }

    @Test
    fun aStateMissingFromTheManifestFallsBack() {
        // *Manuscrit* avec pointillés : la règle sait le nommer, le dossier
        // n'a pas l'image. Tant que la contrainte ne l'a pas éteint en amont,
        // c'est le repli — pas l'aperçu sans pointillés, qui mentirait sur le
        // carnet imprimé.
        val ruled = book(BookFontCombo.handwritten, rules = true)
        assertNotNull(BookCustomisationPreview.composedFileName(ruled))
        assertEquals(fallback, BookCustomisationPreview.fileName(ruled))

        // Et ce que la règle cherche, elle le cherche dans le manifeste qu'on
        // lui donne.
        assertEquals(fallback, BookCustomisationPreview.fileName(BookCustomisation(), among = emptySet()))
    }

    // MARK: Le manifeste et le dossier

    @Test
    fun theManifestIsTheFolder() {
        // Comparé **octet par octet** : « é » et « e + accent » ne sont pas les
        // mêmes octets, et une URL non plus ne les confond pas. C'est ce qui a
        // fait répondre 404 à l'ancien repli.
        //
        // ⚠️ La JVM lit les noms de fichiers dans l'encodage du système
        // (`sun.jnu.encoding`) : sous une locale POSIX, les « é » deviennent des
        // « ? ». Le test se lance donc sous une locale UTF-8 (`LC_ALL=C.UTF-8`).
        val names = (previewFolder.list() ?: emptyArray()).filter { !it.startsWith(".") }
        assertTrue(names.contains(fallback), "L’image de repli manque au dossier ($previewFolder)")

        val onDisk = names.filter { it != fallback }.map { it.toByteArray(Charsets.UTF_8).toList() }.toSet()
        val listed = BookCustomisationPreview.availableFileNames.map { it.toByteArray(Charsets.UTF_8).toList() }.toSet()
        val rerun = "relancer `python3 ios/Tools/make-customisation-preview-manifest.py`"
        assertEquals(emptyList(), names(onDisk - listed), "Dans le dossier, pas dans le manifeste : $rerun")
        assertEquals(emptyList(), names(listed - onDisk), "Dans le manifeste, plus dans le dossier : $rerun")
    }

    @Test
    fun everyPreviewIsOneTheRuleCanPick() {
        // Un fichier que la règle ne compose jamais est un fichier mal nommé :
        // un segment de travers, un suffixe oublié.
        val composable = everyState.mapNotNull(BookCustomisationPreview::composedFileName).toSet()
        assertEquals(300, composable.size)
        assertEquals(emptyList(), (BookCustomisationPreview.availableFileNames - composable).sorted())
    }

    @Test
    fun everyReachableStateHasItsPreview() {
        // Une fois la contrainte posée — `BookFontCombo.allowsRules`, que lit
        // le verrou des pointillés —, les deux cents états atteignables ont
        // leur image : le repli ne sert plus qu'à « Personnalisé ».
        val reachable = everyState.filter { !it.rulesEnabled || allowsRules(it) }
        assertEquals(200, reachable.size)

        val missing = reachable
            .filter { BookCustomisationPreview.fileName(it) == fallback }
            .map { BookCustomisationPreview.composedFileName(it) ?: "sans assortiment : $it" }
        assertEquals(emptyList(), missing)
        // Que ces noms s'écrivent comme sur le disque, octet pour octet, c'est
        // `theManifestIsTheFolder` qui le tient : `fileName` rend un élément du
        // manifeste, le comparer au manifeste ne prouverait rien.
    }

    @Test
    fun theConstraintStillMatchesTheFolder() {
        // Les cent états qu'elle écarte sont exactement ceux qui n'ont pas
        // d'image. Le jour où ce test casse, les rendus manquants sont
        // arrivés : la contrainte doit sauter — `allowsRules` à `true`, elle
        // seule, la règle ne bouge pas.
        val excluded = everyState.filter { it.rulesEnabled && !allowsRules(it) }
        assertEquals(100, excluded.size)

        val present = excluded
            .mapNotNull(BookCustomisationPreview::composedFileName)
            .filter { it in BookCustomisationPreview.availableFileNames }
        assertEquals(emptyList(), present)
    }

    // MARK: L'image publiée

    @Test
    fun theUntouchedBookPointsAtItsPublishedImage() {
        val url = BookCustomisationPreview.imageURL(BookCustomisation())
        val file = assertNotNull(
            BookCustomisationPreview.publishedFiles[BookCustomisationPreview.fileName(BookCustomisation())],
        )
        assertEquals(BookCustomisationPreview.publicBaseURL.resolve(file), url)
        assertEquals("pjmetjdnajskijoljulc.supabase.co", url.host)
        assertTrue(url.path.startsWith("/storage/v1/object/public/memobook-public/apercus/"), url.path)
        assertEquals("webp", url.path.substringAfterLast('.'))
    }

    @Test
    fun aHandComposedBookPointsAtThePublishedFallback() {
        val custom = BookCustomisation(rulesEnabled = false).copy(fontHand = "Montserrat")
        assertEquals(
            BookCustomisationPreview.publicBaseURL.resolve(BookCustomisationPreview.publishedFallback),
            BookCustomisationPreview.imageURL(custom),
        )
    }

    @Test
    fun everyReachableStateHasItsOwnPublishedImage() {
        // Deux cents états, deux cents images distinctes, et aucune n'est le
        // repli : une empreinte partagée voudrait dire deux réglages qui
        // montrent la même page.
        val reachable = everyState.filter { !it.rulesEnabled || allowsRules(it) }
        val urls = reachable.map(BookCustomisationPreview::imageURL)
        val fallback = BookCustomisationPreview.publicBaseURL.resolve(BookCustomisationPreview.publishedFallback)

        assertFalse(urls.contains(fallback))
        assertEquals(200, urls.toSet().size)
    }

    @Test
    fun theEmbeddedManifestIsThePublishedOne() {
        // `npm run previews:publish` réécrit le manifeste publié ; s'il est
        // commité sans relancer le script iOS, l'app pointerait des images
        // d'avant. La correspondance embarquée doit être la sienne, au nom près.
        val manifest = MemoBookJson.decodeFromString(PublishedManifest.serializer(), publishedManifest.readText())

        assertEquals(1, manifest.version)
        assertEquals(fallback, manifest.fallback.source)
        assertEquals(BookCustomisationPreview.publishedFallback, manifest.fallback.file)

        val published = manifest.previews.associate { it.source to it.file }
        val rerun = "relancer `python3 ios/Tools/make-customisation-preview-manifest.py`"
        assertEquals(BookCustomisationPreview.publishedFiles, published, rerun)
    }

    // MARK: Outils

    /** Ce que l'app lit du manifeste réécrit par `npm run previews:publish`. */
    @Serializable
    private data class PublishedManifest(
        val version: Int,
        val fallback: Entry,
        val previews: List<Entry>,
    ) {
        @Serializable
        data class Entry(val source: String, val file: String)
    }

    /** Un carnet réglé sur cet assortiment, le reste aux valeurs par défaut. */
    private fun book(
        combo: BookFontCombo,
        rules: Boolean = true,
        ratio: Int = 50,
        funFacts: Boolean = true,
        quota: Int = 2,
    ): BookCustomisation = Companion.book(combo, rules, ratio, funFacts, quota)

    private fun names(spellings: Set<List<Byte>>): List<String> =
        spellings.map { String(it.toByteArray(), Charsets.UTF_8) }.sorted()

    companion object {
        fun book(combo: BookFontCombo, rules: Boolean, ratio: Int, funFacts: Boolean, quota: Int): BookCustomisation {
            var book = BookCustomisation(
                photoTextRatio = ratio,
                funFactsEnabled = funFacts,
                rulesEnabled = rules,
                decorationQuota = quota,
            )
            for (role in BookFontRole.entries) {
                book = role.writing(combo.font(role), into = book)
            }
            return book
        }

        /**
         * Les trois cents états que les cinq propriétés produisent : trois
         * assortiments, deux pointillés, cinq ratios, deux fun facts, cinq quotas.
         */
        private val everyState: List<BookCustomisation> = BookFontCombo.all.flatMap { combo ->
            listOf(true, false).flatMap { rules ->
                (0..100 step 25).flatMap { ratio ->
                    listOf(true, false).flatMap { funFacts ->
                        (0..4).map { quota -> book(combo, rules, ratio, funFacts, quota) }
                    }
                }
            }
        }

        private fun allowsRules(book: BookCustomisation): Boolean =
            BookFontCombo.matching(book)?.allowsRules ?: false

        /**
         * `assets/illustrations/`, en remontant du dossier de travail de Gradle
         * (`android/core`) jusqu'à la racine du dépôt — le `#filePath` du test iOS.
         */
        private val illustrations: File by lazy {
            var dir: File? = File(System.getProperty("user.dir")).absoluteFile
            while (dir != null && !File(dir, "assets/illustrations").isDirectory) dir = dir.parentFile
            File(checkNotNull(dir) { "Racine du dépôt introuvable depuis ${System.getProperty("user.dir")}" }, "assets/illustrations")
        }

        /** Les exports Figma : `assets/illustrations/aperçu personnalisation/`. */
        private val previewFolder: File get() = File(illustrations, "aperçu personnalisation")

        /** Le manifeste publié, à côté du dossier et non dedans. */
        private val publishedManifest: File get() = File(illustrations, "apercus-personnalisation.manifest.json")
    }
}
