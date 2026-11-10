package com.memobook.core

import java.math.BigDecimal
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KeepGeneratedSerializer
import kotlinx.serialization.Serializable

/**
 * **La grille des prix du carnet, telle que le serveur la sert** — le bloc
 * `printPricing` des réglages du voyage (`serializePrintPricing`,
 * `backend/src/routes/appSerializers.ts`). Le jumeau de `PrintPricing.swift`.
 *
 * ⚠️ **Aucun prix n'est écrit ici.** C'est le serveur qui tarife, et lui seul
 * (`services/printPricing.ts`) : il facture à la commande, et il sert la même
 * grille à l'écran « Nombre de pages » pour que celui-ci annonce ce qu'il
 * facturera. Une copie des paliers côté Kotlin serait une seconde vérité à
 * tenir d'accord, et c'est le client qui aurait tort devant la personne qui
 * paie. Le jour où un palier change, il change au serveur seul.
 *
 * Elle voyage **entière** et non prix par prix : le curseur de
 * « Personnalisé » change le nombre de pages à chaque cran, et un
 * aller-retour par cran ferait clignoter le prix.
 *
 * Nulle quand un serveur plus ancien ne la sert pas : l'écran se tait alors
 * — pas de prix plutôt qu'un prix inventé, comme la ligne « Crédit du jour ».
 */
@OptIn(ExperimentalSerializationApi::class)
@KeepGeneratedSerializer
@Serializable(with = PrintPricing.Serializer::class)
data class PrintPricing(
    /**
     * Les paliers, du plus mince au plus épais. Seuls ceux que le serveur
     * accepte de facturer y figurent : au-delà de 300 pages, le dernier n'y
     * est que si la configuration l'ouvre (`ALLOW_OVER_300_PAGES`).
     */
    val tiers: List<Tier> = emptyList(),
    /**
     * Le minimum de l'imprimeur — 16 pages. Un carnet plus court se facture
     * comme un carnet de 16.
     */
    val minPages: Int = 16,
    /**
     * Le maximum qu'on accepte de facturer — 300, ou 400 si la configuration
     * ouvre le dernier palier. Au-delà, pas de prix.
     */
    val maxPages: Int = 300,
    /**
     * L'écart toléré entre le carnet composé et sa cible — 5 pages
     * (`PAGE_TARGET_TOLERANCE`). C'est lui qui fait annoncer le prix de
     * **cible + tolérance** : le carnet final n'ira pas plus haut, donc le
     * prix facturé ne dépassera jamais le prix affiché.
     */
    val tolerancePages: Int = 5,
    /**
     * Le supplément de l'option « Zones libres », par exemplaire. Nul quand
     * le serveur ne le sert pas : la ligne s'affiche alors sans prix.
     */
    @Serializable(with = BigDecimalSerializer::class) val freeZonesPrice: BigDecimal? = null,
) {
    /** Un palier : ses bornes en pages, comprises, et son prix en euros. */
    @Serializable
    data class Tier(
        /**
         * Le nom interne du palier (« compact », « large-plus »). **Jamais
         * affiché** : ce ne sont pas les noms des options de l'écran.
         */
        val id: String,
        /** La première page du palier, comprise. */
        val from: Int,
        /** La dernière page du palier, comprise. */
        val to: Int,
        /** Le prix TTC du carnet à ce palier, livraison standard comprise. */
        @Serializable(with = BigDecimalSerializer::class) val price: BigDecimal,
    )

    /**
     * **Le prix d'un carnet de [forPages] pages** — la même lecture que
     * `getPrintPrice` côté serveur : sous le minimum, le premier palier ;
     * au-delà du maximum, rien à annoncer.
     *
     * `null` aussi quand la grille est vide — un serveur qui a servi le bloc
     * sans paliers : mieux vaut une ligne sans prix qu'un prix faux.
     */
    fun price(forPages: Int): BigDecimal? = tier(forPages = forPages)?.price

    /** Le palier où tombe un nombre de pages, pour les journaux de débogage. */
    fun tier(forPages: Int): Tier? {
        val billed = maxOf(forPages, minPages)
        if (billed > maxPages) return null
        return tiers.firstOrNull { billed <= it.to }
    }

    /**
     * **Le prix que l'écran annonce pour une cible** : celui du palier de
     * `cible + tolérance`.
     *
     * Le carnet composé tient dans sa cible à cinq pages près. Annoncer le
     * prix de la cible nue exposerait à facturer un palier au-dessus de ce
     * qui a été montré ; annoncer celui du haut de la fourchette ne peut que
     * facturer moins.
     */
    fun displayedPrice(forTarget: Int): BigDecimal? = price(forPages = forTarget + tolerancePages)

    /** Le nombre de pages est-il dans ce que le serveur accepte de facturer ? */
    fun allows(pages: Int): Boolean = pages in minPages..maxPages

    object Serializer : DecodeIfPresentSerializer<PrintPricing>(generatedSerializer())
}
