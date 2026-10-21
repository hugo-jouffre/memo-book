package com.memobook.tools

import com.android.ide.common.vectordrawable.Svg2Vector
import java.io.ByteArrayOutputStream
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import kotlin.io.path.createDirectories
import kotlin.io.path.deleteRecursively
import kotlin.io.path.exists
import kotlin.io.path.extension
import kotlin.io.path.isDirectory
import kotlin.io.path.listDirectoryEntries
import kotlin.io.path.name
import kotlin.io.path.readText
import kotlin.io.path.writeText

/**
 * Recopie le catalogue d'images de l'app iOS dans `:design`.
 *
 * **La source est `MemoBookAssets.xcassets`, pas `assets/`.** Les scripts de
 * `ios/Tools` ont déjà tout fait en amont : choisi les noms (`IconPrinterDuo`),
 * nettoyé les exports Figma, décodé en PNG les planches incrustées. Partir de
 * leur sortie donne aux deux apps **les mêmes images sous les mêmes noms**, par
 * construction. Ajouter une image, c'est donc lancer le script iOS, puis
 * celui-ci.
 *
 * - Un SVG devient un VectorDrawable, par le convertisseur d'Android Studio.
 * - Un PNG ou un JPG est recopié, à la densité que dit son échelle iOS.
 * - `BrandImages.kt` est réécrit : la table nom iOS → ressource, pour les clés
 *   qui arrivent du serveur (`LucideIcon`).
 *
 * Le dossier de sortie, `res-brand/`, n'appartient qu'à ce script : il est
 * vidé puis réécrit à chaque passage. Une image retirée du catalogue disparaît
 * donc aussi d'Android, et rien d'écrit à la main n'y vit.
 */
@OptIn(kotlin.io.path.ExperimentalPathApi::class)
fun main(args: Array<String>) {
    val repo = Path.of(args.firstOrNull() ?: error("Usage : ImportBrandAssets <racine du dépôt>"))
    val catalogue = repo.resolve("ios/Modules/Sources/MemoBookDesign/Resources/MemoBookAssets.xcassets")
    val design = repo.resolve("android/design/src/main")
    val output = design.resolve("res-brand")

    require(catalogue.isDirectory()) { "Catalogue introuvable : $catalogue" }
    if (output.exists()) output.deleteRecursively()

    val entries = mutableListOf<Pair<String, String>>()
    val notes = mutableListOf<String>()

    for (set in catalogue.listDirectoryEntries("*.imageset").sortedBy { it.name }) {
        val iosName = set.name.removeSuffix(".imageset")
        val resource = resourceName(iosName)
        val contents = set.resolve("Contents.json").readText()
        val file = Regex("\"filename\"\\s*:\\s*\"([^\"]+)\"").find(contents)?.groupValues?.get(1)
            ?: continue.also { notes += "$iosName : aucun fichier dans Contents.json, ignoré" }
        val source = set.resolve(file)

        when (source.extension.lowercase()) {
            "svg" -> {
                val target = output.resolve("drawable").createDirectories().resolve("$resource.xml")
                val warnings = convert(source, target)
                if (warnings.isNotBlank()) notes += "$iosName : ${warnings.trim().replace('\n', ' ')}"
            }
            "png", "jpg", "jpeg" -> {
                val scale = Regex("\"scale\"\\s*:\\s*\"(\\d)x\"").find(contents)?.groupValues?.get(1)
                val folder = when (scale) {
                    "3" -> "drawable-xxhdpi"
                    "2" -> "drawable-xhdpi"
                    else -> "drawable-nodpi"
                }
                val target = output.resolve(folder).createDirectories()
                    .resolve("$resource.${source.extension.lowercase().replace("jpeg", "jpg")}")
                Files.copy(source, target, StandardCopyOption.REPLACE_EXISTING)
            }
            else -> {
                notes += "$iosName : format ${source.extension} non pris en charge, ignoré"
                continue
            }
        }
        entries += iosName to resource
    }

    design.resolve("kotlin/com/memobook/design/BrandImages.kt").writeText(brandImagesSource(entries))

    println("${entries.size} images importées dans ${repo.relativize(output)}")
    notes.forEach { println("  · $it") }
}

/**
 * `IconPrinterDuo` → `icon_printer_duo`, `IconDesktopPCChecked1` →
 * `icon_desktop_pc_checked1` : une ressource Android ne prend que des
 * minuscules, des chiffres et des tirets bas.
 */
fun resourceName(iosName: String): String = iosName
    .replace(Regex("([A-Z]+)([A-Z][a-z])"), "$1_$2")
    .replace(Regex("([a-z0-9])([A-Z])"), "$1_$2")
    .lowercase()

/**
 * Le SVG, puis le VectorDrawable. Rend les avertissements du convertisseur.
 *
 * Un seul prétraitement : les `<mask>` de Figma sont retirés. VectorDrawable ne
 * sait pas masquer, et dans ce catalogue un masque ne sert qu'à cacher la
 * moitié intérieure d'un contour de 0,3 posé sur un aplat de la même couleur
 * (`IconStar`, `IconPlusOutlinedDuo`) : sans lui, le dessin est le même.
 *
 * Un cas de plus : Figma exporte parfois ce contour **déjà développé**, en un
 * tracé plein masqué — 73 180 caractères pour `IconPlusOutlined`. aapt2 ne
 * stocke pas une chaîne de plus de 32 767 caractères, et la tronque sans le
 * dire : l'image plantait l'écran qui l'affichait (21/10/2026). Ce tracé-là est
 * redessiné en ce qu'il est, le contour de 0,3 du tracé du masque — le dessin
 * même de son jumeau `Duo`.
 */
fun convert(source: Path, target: Path): String {
    val notes = StringBuilder()
    var svg = source.readText()
    val maskPaths = Regex("<mask\\b[^>]*\\bid=\"([^\"]+)\"[^>]*>(.*?)</mask>", RegexOption.DOT_MATCHES_ALL)
        .findAll(svg)
        .associate { it.groupValues[1] to Regex("<path\\b[^>]*\\bd=\"([^\"]+)\"").find(it.groupValues[2])?.groupValues?.get(1) }
    svg = Regex("<path\\b([^>]*)\\bd=\"([^\"]{$MAX_PATH_LENGTH,})\"([^>]*)\\bmask=\"url\\(#([^)]+)\\)\"([^>]*)/>").replace(svg) { match ->
        val outline = maskPaths[match.groupValues[4]] ?: return@replace match.value
        val color = Regex("fill=\"([^\"]+)\"").find(match.value)?.groupValues?.get(1) ?: "#2D231A"
        notes.append("contour développé de ${match.groupValues[2].length} caractères redessiné en trait de 0,3")
        "<path d=\"$outline\" stroke=\"$color\" stroke-width=\"0.3\" stroke-linejoin=\"round\"/>"
    }
    svg = svg
        .replace(Regex("<mask\\b[^>]*>.*?</mask>", RegexOption.DOT_MATCHES_ALL), "")
        .replace(Regex("\\smask=\"url\\(#[^)]*\\)\""), "")
    val prepared = Files.createTempFile("memobook-", ".svg")
    try {
        prepared.writeText(svg)
        val out = ByteArrayOutputStream()
        notes.append(Svg2Vector.parseSvgToXml(prepared, out))
        val xml = out.toString(Charsets.UTF_8)
        target.writeText(xml)
        Regex("pathData=\"([^\"]{$MAX_PATH_LENGTH,})\"").findAll(xml).forEach {
            notes.append(" ⚠️ tracé de ${it.groupValues[1].length} caractères : aapt2 le tronquera, simplifier la source")
        }
        return notes.toString()
    } finally {
        Files.deleteIfExists(prepared)
    }
}

/** La plus longue chaîne qu'aapt2 sait stocker dans une ressource compilée. */
private const val MAX_PATH_LENGTH = 32_767

private fun brandImagesSource(entries: List<Pair<String, String>>): String = buildString {
    appendLine("// Généré par `./gradlew :tools:importBrandAssets` — ne pas éditer à la main.")
    appendLine("package com.memobook.design")
    appendLine()
    appendLine("import androidx.annotation.DrawableRes")
    appendLine()
    appendLine("/**")
    appendLine(" * Les images de marque, sous leur nom iOS : `BrandImages[\"IconPrinterDuo\"]`")
    appendLine(" * est `R.drawable.icon_printer_duo`. Le code qui connaît son image l'appelle")
    appendLine(" * par `R.drawable` ; cette table sert aux noms qui arrivent en texte.")
    appendLine(" */")
    appendLine("object BrandImages {")
    appendLine("    private val byName: Map<String, Int> = mapOf(")
    entries.forEach { (ios, res) -> appendLine("        \"$ios\" to R.drawable.$res,") }
    appendLine("    )")
    appendLine()
    appendLine("    /** La ressource d'une image du catalogue, ou `null` pour un nom inconnu. */")
    appendLine("    @DrawableRes")
    appendLine("    operator fun get(name: String): Int? = byName[name]")
    appendLine()
    appendLine("    /** Tous les noms du catalogue, pour l'écran-catalogue du design system. */")
    appendLine("    val names: List<String> get() = byName.keys.toList()")
    appendLine("}")
}
