import Foundation

/// **La grille des prix du carnet, telle que le serveur la sert** — le bloc
/// `printPricing` des réglages du voyage (`serializePrintPricing`,
/// `backend/src/routes/appSerializers.ts`).
///
/// ⚠️ **Aucun prix n'est écrit ici.** C'est le serveur qui tarife, et lui seul
/// (`services/printPricing.ts`) : il facture à la commande, et il sert la même
/// grille à l'écran « Nombre de pages » pour que celui-ci annonce ce qu'il
/// facturera. Une copie des paliers côté Swift serait une seconde vérité à
/// tenir d'accord, et c'est le client qui aurait tort devant la personne qui
/// paie. Le jour où un palier change, il change au serveur seul.
///
/// Elle voyage **entière** et non prix par prix : le curseur de
/// « Personnalisé » change le nombre de pages à chaque cran, et un
/// aller-retour par cran ferait clignoter le prix.
///
/// Nulle quand un serveur plus ancien ne la sert pas : l'écran se tait alors
/// — pas de prix plutôt qu'un prix inventé, comme la ligne « Crédit du jour ».
public struct PrintPricing: Codable, Sendable, Hashable {
    /// Un palier : ses bornes en pages, comprises, et son prix en euros.
    public struct Tier: Codable, Sendable, Hashable, Identifiable {
        /// Le nom interne du palier (« compact », « large-plus »). **Jamais
        /// affiché** : ce ne sont pas les noms des options de l'écran.
        public let id: String
        /// La première page du palier, comprise.
        public let from: Int
        /// La dernière page du palier, comprise.
        public let to: Int
        /// Le prix TTC du carnet à ce palier, livraison standard comprise.
        public let price: Decimal

        public init(id: String, from: Int, to: Int, price: Decimal) {
            self.id = id
            self.from = from
            self.to = to
            self.price = price
        }
    }

    /// Les paliers, du plus mince au plus épais. Seuls ceux que le serveur
    /// accepte de facturer y figurent : au-delà de 300 pages, le dernier n'y
    /// est que si la configuration l'ouvre (`ALLOW_OVER_300_PAGES`).
    public var tiers: [Tier]

    /// Le minimum de l'imprimeur — 16 pages. Un carnet plus court se facture
    /// comme un carnet de 16.
    public var minPages: Int

    /// Le maximum qu'on accepte de facturer — 300, ou 400 si la configuration
    /// ouvre le dernier palier. Au-delà, pas de prix.
    public var maxPages: Int

    /// L'écart toléré entre le carnet composé et sa cible — 5 pages
    /// (`PAGE_TARGET_TOLERANCE`). C'est lui qui fait annoncer le prix de
    /// **cible + tolérance** : le carnet final n'ira pas plus haut, donc le
    /// prix facturé ne dépassera jamais le prix affiché.
    public var tolerancePages: Int

    /// Le supplément de l'option « Zones libres », par exemplaire. Nul quand
    /// le serveur ne le sert pas : la ligne s'affiche alors sans prix.
    public var freeZonesPrice: Decimal?

    public init(
        tiers: [Tier] = [],
        minPages: Int = 16,
        maxPages: Int = 300,
        tolerancePages: Int = 5,
        freeZonesPrice: Decimal? = nil
    ) {
        self.tiers = tiers
        self.minPages = minPages
        self.maxPages = maxPages
        self.tolerancePages = tolerancePages
        self.freeZonesPrice = freeZonesPrice
    }

    /// **Le prix d'un carnet de `pages` pages** — la même lecture que
    /// `getPrintPrice` côté serveur : sous le minimum, le premier palier ;
    /// au-delà du maximum, rien à annoncer.
    ///
    /// `nil` aussi quand la grille est vide — un serveur qui a servi le bloc
    /// sans paliers : mieux vaut une ligne sans prix qu'un prix faux.
    public func price(forPages pages: Int) -> Decimal? {
        let billed = max(pages, minPages)
        guard billed <= maxPages else { return nil }
        return tiers.first { billed <= $0.to }?.price
    }

    /// Le palier où tombe un nombre de pages, pour les journaux de débogage.
    public func tier(forPages pages: Int) -> Tier? {
        let billed = max(pages, minPages)
        guard billed <= maxPages else { return nil }
        return tiers.first { billed <= $0.to }
    }

    /// **Le prix que l'écran annonce pour une cible** : celui du palier de
    /// `cible + tolérance`.
    ///
    /// Le carnet composé tient dans sa cible à cinq pages près. Annoncer le
    /// prix de la cible nue exposerait à facturer un palier au-dessus de ce
    /// qui a été montré ; annoncer celui du haut de la fourchette ne peut que
    /// facturer moins.
    public func displayedPrice(forTarget target: Int) -> Decimal? {
        price(forPages: target + tolerancePages)
    }

    /// Le nombre de pages est-il dans ce que le serveur accepte de facturer ?
    public func allows(pages: Int) -> Bool {
        pages >= minPages && pages <= maxPages
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tiers = try container.decodeIfPresent([Tier].self, forKey: .tiers) ?? []
        minPages = try container.decodeIfPresent(Int.self, forKey: .minPages) ?? 16
        maxPages = try container.decodeIfPresent(Int.self, forKey: .maxPages) ?? 300
        tolerancePages = try container.decodeIfPresent(Int.self, forKey: .tolerancePages) ?? 5
        freeZonesPrice = try container.decodeIfPresent(Decimal.self, forKey: .freeZonesPrice)
    }

    private enum CodingKeys: String, CodingKey {
        case tiers, minPages, maxPages, tolerancePages, freeZonesPrice
    }
}
