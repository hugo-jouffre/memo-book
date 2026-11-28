package com.memobook.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * **La manière d'être rédigé** du carnet — T292. Le jumeau de
 * `RedactionManner.swift`.
 *
 * Elle règle la façon d'**écrire** le récit, et non le dessin du livre : le
 * style visuel, lui, est dans [BookCustomisation]. Les fiches de chaque manière
 * vivent dans `agents/redaction-manieres/`, et c'est le serveur qui les
 * charge — l'app n'en connaît que la clé et le libellé.
 */
enum class RedactionManner(val rawValue: String) {
    /**
     * Le défaut : le carnet garde sa façon de raconter. **N'ajoute rien au
     * prompt**, côté serveur — un carnet qui n'a jamais touché au réglage est
     * rédigé exactement comme avant T292.
     */
    Spoken("spoken"),

    /** Des phrases plus amples, l'oral qui s'efface davantage. */
    Literary("literary"),

    /** Court, chronologique, sans effets. */
    Factual("factual");

    companion object {
        /** `null` pour une clé que ce build ne connaît pas — voir [RedactionSettings]. */
        fun from(storedValue: String?): RedactionManner? =
            entries.firstOrNull { it.rawValue == storedValue }
    }
}

/**
 * Pourquoi le réglage est ouvert, ou ne l'est pas — `mannerAccess` côté serveur
 * (`backend/src/services/redactionMannerAccess.ts`).
 *
 * L'app ne refait pas le calcul : elle lit ce que le serveur a tranché. C'est
 * ce qui évite deux règles à tenir d'accord, et un réglage ouvert dans l'app
 * que le serveur refuserait.
 */
enum class RedactionMannerReason(val rawValue: String) {
    /** Abonné illimité : ouvert, et la reprise peut être longue. */
    Unlimited("unlimited"),

    /** Carnet d'une seule étape : ouvert, la reprise ne coûte qu'un appel. */
    SingleStep("single_step"),

    /** Ni l'un ni l'autre : le réglage se montre **pâli** et mène au paywall. */
    NeedsUnlimited("needs_unlimited");

    companion object {
        fun from(storedValue: String?): RedactionMannerReason? =
            entries.firstOrNull { it.rawValue == storedValue }
    }
}

/**
 * Le bloc `redaction` de `GET /v1/trips/:id/settings`.
 *
 * ⚠️ **Les deux clés arrivent en texte brut**, et les énumérations se lisent
 * par [chosenManner] et [reason] : une manière ou une raison ajoutées par une
 * version plus récente du serveur ne doivent pas faire échouer **tout l'écran**
 * des réglages, seulement cette ligne. C'est la règle d'`ios/CLAUDE.md` — « un
 * état inconnu ne casse pas le décodage » —, tenue ici sans sérialiseur sur
 * mesure : le JSON ne porte que des chaînes, la lecture est tolérante par
 * construction.
 */
@Serializable
data class RedactionSettings(
    /** La clé telle que le serveur la sert. `null` : personne n'a choisi. */
    @SerialName("manner") var storedManner: String? = null,

    /** Les indications libres du voyageur. `null` quand il n'en a donné aucune. */
    var notes: String? = null,

    /**
     * Le réglage est ouvert. Faux, il se montre pâli et mène au paywall —
     * **jamais désactivé** (voir `ios/CLAUDE.md`, « Ce qu'on ne peut pas faire
     * pâlit »).
     */
    var isAvailable: Boolean = false,

    /** Pourquoi, pour que l'écran dise la cause et la sortie. */
    @SerialName("reason") var storedReason: String? = null,
) {
    /**
     * La manière **choisie**, ou `null` si personne n'a choisi — ou si le
     * serveur a servi une clé que ce build ne connaît pas.
     *
     * ⚠️ La distinction ne vit que dans l'app, pour la pastille « Par
     * défaut » : le serveur traite `null` et [RedactionManner.Spoken] de la
     * même façon (`mannerOf`).
     */
    val chosenManner: RedactionManner? get() = RedactionManner.from(storedManner)

    /** Ce que l'écran coche : la manière choisie, ou celle par défaut. */
    val manner: RedactionManner get() = chosenManner ?: RedactionManner.Spoken

    /** Une raison inconnue ferme le réglage : c'est le refus sûr. */
    val reason: RedactionMannerReason
        get() = RedactionMannerReason.from(storedReason) ?: RedactionMannerReason.NeedsUnlimited

    companion object {
        /**
         * La longueur maximale des indications — `REDACTION_NOTES_MAX` côté
         * serveur, qui coupe silencieusement au-delà. L'app compte avant
         * d'envoyer plutôt que de laisser le serveur trancher dans le texte de
         * quelqu'un.
         */
        const val NOTES_LIMIT = 600

        /** Le réglage fermé : ce que l'écran lit d'un serveur qui se tait. */
        val closed = RedactionSettings()
    }
}
