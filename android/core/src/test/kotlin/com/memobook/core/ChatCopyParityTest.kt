package com.memobook.core

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

// **Les textes du chat, mot pour mot comme le Swift.**
//
// `docs/android.md` promettait que `ChatCopy` était « comparé chaîne à chaîne
// avec le Swift ». Rien ne le faisait : la mention de confidentialité est
// restée treize jours en deux versions — « Ta conversation est privée : seuls
// toi et tes co-voyageurs pouvez la lire. » d'un côté, deux phrases et un
// cadenas de l'autre — sans que rien ne le dise. Ce test est la promesse,
// tenue.
//
// Il lit les deux fichiers **sur le disque** plutôt que les constantes
// compilées : c'est le seul moyen d'atteindre le Swift depuis la JVM, et la
// CI a tout le dépôt sous la main.
//
// Ce qu'il compare : les constantes écrites **sur une seule ligne**, des deux
// côtés, appariées par leur nom qualifié (`Transcript.reanalyse`). Ce qu'il
// laisse de côté, faute de pouvoir le lire sans interpréter le langage : les
// fonctions, les textes construits, et une constante dont le littéral passe à
// la ligne. D'où [MINIMUM_COMPARED] : si une réécriture faisait tomber la
// couverture, le test le dirait au lieu de comparer trois chaînes et de se
// taire.
class ChatCopyParityTest {
    private companion object {
        /**
         * Le plancher de couverture. Il y avait 108 constantes appariées le
         * jour où ce test a été écrit ; le baisser se fait à la main, en
         * sachant pourquoi.
         */
        const val MINIMUM_COMPARED = 100

        /**
         * Les textes **voulus différents** — les seuls (`docs/android.md`,
         * « Textes propres à Android, à relire par Clara ») : Android dit
         * « Paramètres » là où iOS dit « Réglages ».
         *
         * Une exception doit rester une divergence : si les deux textes
         * finissent par se rejoindre, [deliberateDivergencesStillDiverge] le
         * dit et la ligne se retire d'ici. Une liste d'exceptions qui ne sert
         * plus à rien est le début d'une liste d'exceptions qui couvre tout.
         */
        val DELIBERATE_DIVERGENCES = setOf("Voice.microphoneDenied")

        val SWIFT_FILE = "ios/Modules/Sources/MemoBookCore/ChatCopy.swift"
        val KOTLIN_FILE = "android/core/src/main/kotlin/com/memobook/core/ChatCopy.kt"

        /** `public static let reanalyse = "Ré-analyser"` */
        val SWIFT_CONSTANT = Regex("""^\s*(?:public\s+)?static\s+let\s+([A-Za-z0-9_]+)\s*=\s*"([^"]*)"\s*$""")

        /** `const val reanalyse = "Ré-analyser"` */
        val KOTLIN_CONSTANT = Regex("""^\s*const\s+val\s+([A-Za-z0-9_]+)\s*=\s*"([^"]*)"\s*$""")

        /** `public enum Transcript {` */
        val SWIFT_CONTAINER = Regex("""^\s*(?:public\s+)?enum\s+([A-Za-z0-9_]+)\s*\{""")

        /** `object Transcript {` */
        val KOTLIN_CONTAINER = Regex("""^\s*(?:data\s+)?object\s+([A-Za-z0-9_]+)\s*\{""")
    }

    /**
     * La racine du dépôt, trouvée en remontant depuis le dossier du module :
     * Gradle lance les tests dans `android/core`, la CI ailleurs.
     */
    private fun repositoryRoot(): File {
        var directory: File? = File(System.getProperty("user.dir")).absoluteFile
        while (directory != null) {
            if (File(directory, SWIFT_FILE).isFile && File(directory, KOTLIN_FILE).isFile) return directory
            directory = directory.parentFile
        }
        error("Dépôt introuvable depuis ${System.getProperty("user.dir")}")
    }

    /**
     * Les constantes d'un fichier, par nom qualifié.
     *
     * Les accolades se comptent pour savoir dans quel type on est. Aucun
     * littéral de ces deux fichiers n'en contient — et si l'un venait à en
     * porter une, l'appariement se déferait bruyamment plutôt que
     * silencieusement.
     */
    private fun constants(file: File, constant: Regex, container: Regex): Map<String, String> {
        val found = linkedMapOf<String, String>()
        val stack = mutableListOf<Pair<String, Int>>()
        var depth = 0
        for (line in file.readLines()) {
            container.find(line)?.let { stack += it.groupValues[1] to depth }
            constant.find(line)?.let {
                // Le type racine (`ChatCopy`) ne qualifie rien : il est le même des deux côtés.
                val path = stack.drop(1).map { entry -> entry.first } + it.groupValues[1]
                found[path.joinToString(".")] = it.groupValues[2]
            }
            depth += line.count { character -> character == '{' } - line.count { character -> character == '}' }
            while (stack.isNotEmpty() && depth <= stack.last().second) stack.removeAt(stack.lastIndex)
        }
        return found
    }

    /**
     * Les deux fichiers, lus et appariés. Calculé une fois par test : les
     * deux en ont besoin.
     */
    private fun shared(): Map<String, Pair<String, String>> {
        val root = repositoryRoot()
        val swift = constants(File(root, SWIFT_FILE), SWIFT_CONSTANT, SWIFT_CONTAINER)
        val kotlin = constants(File(root, KOTLIN_FILE), KOTLIN_CONSTANT, KOTLIN_CONTAINER)
        return (swift.keys intersect kotlin.keys).associateWith { swift.getValue(it) to kotlin.getValue(it) }
    }

    /**
     * Une constante que les deux portent ne peut pas dire deux choses.
     *
     * **Toutes les divergences d'un coup**, et non la première : quand un
     * texte est repris d'un côté, il l'est rarement seul, et corriger à
     * l'aveugle une erreur sur six fait relancer six fois.
     */
    @Test
    fun everySharedConstantReadsTheSameOnBothSides() {
        val shared = shared()
        assertTrue(
            shared.size >= MINIMUM_COMPARED,
            "Seules ${shared.size} constantes appariées, moins que le plancher de $MINIMUM_COMPARED : " +
                "la comparaison ne couvre presque plus rien. Lire le commentaire en tête de ce test.",
        )

        val diverging = shared
            .filterKeys { it !in DELIBERATE_DIVERGENCES }
            .filter { (_, texts) -> texts.first != texts.second }

        assertTrue(
            diverging.isEmpty(),
            buildString {
                appendLine("${diverging.size} texte(s) du chat divergent entre iOS et Android.")
                appendLine("Le Swift fait foi (`android/CLAUDE.md`, la règle de parité).")
                appendLine("Voulu ? L'ajouter à DELIBERATE_DIVERGENCES, avec sa raison.")
                for ((name, texts) in diverging.entries.sortedBy { it.key }) {
                    appendLine()
                    appendLine("— ChatCopy.$name")
                    appendLine("   iOS     : ${texts.first}")
                    appendLine("   Android : ${texts.second}")
                }
            },
        )
    }

    /** Une exception qui ne diverge plus n'est plus une exception. */
    @Test
    fun deliberateDivergencesStillDiverge() {
        val shared = shared()
        for (name in DELIBERATE_DIVERGENCES) {
            val texts = shared[name]
            assertTrue(
                texts != null,
                "DELIBERATE_DIVERGENCES cite ChatCopy.$name, que l'un des deux fichiers ne porte plus : " +
                    "retirer la ligne.",
            )
            assertTrue(
                texts!!.first != texts.second,
                "ChatCopy.$name est désormais identique des deux côtés (« ${texts.first} ») : " +
                    "le retirer de DELIBERATE_DIVERGENCES, pour que la parité le surveille comme les autres.",
            )
        }
    }

    /**
     * La mention de confidentialité, nommément : c'est elle qui a dérivé, et
     * elle n'est pas qu'un texte — le cadenas et les deux lignes de
     * `ChatPrivacyNote` en dépendent.
     */
    @Test
    fun thePrivacyNoteIsTwoSentencesOnBothSides() {
        assertEquals("Ta conversation est privée.", ChatCopy.privacyNote)
        assertEquals("Seuls toi et tes co-voyageurs pouvez la lire.", ChatCopy.privacyNoteDetail)
    }
}
