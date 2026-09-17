import Foundation

// Les Conditions Générales d'Utilisation, recopiées du site memobook.fr
// (Hugo, 17/09/2026), en neuf chapitres. La forme est dans ``LegalDocument``.

public enum TermsOfUse {
    private static let contactLink = LegalContact.emailLink

    /// Le document : le titre de l'écran — celui de la ligne du profil qui y
    /// mène — et les neuf chapitres, dans l'ordre du site.
    public static let document = LegalDocument(
        id: "cgu",
        title: "Conditions d’utilisation",
        chapters: [
            presentation, acceptance, access, service, intellectualProperty,
            liability, personalData, law, changes,
        ]
    )

    // MARK: - 1. Présentation du service

    public static let presentation = LegalChapter(
        id: "cgu.presentation",
        number: 1,
        title: "Présentation du service",
        blocks: [
            .paragraph("MemoBook est un service proposé par Hugo Jouffre, micro-entrepreneur."),
            .lines([
                "SIRET : 815\u{00A0}246\u{00A0}442 — TVA intracommunautaire : FR\u{00A0}59815246442",
                "Siège social : 28 rue Tête d’Or, 69006 Lyon, France",
                "Contact : \(contactLink)",
            ]),
            .paragraph("MemoBook est un service de création de carnets illustrés personnalisés à partir d’enregistrements audio ou de récits. Le service est actuellement en phase bêta et proposé gratuitement (freemium), dans l’attente d’une offre payante incluant l’impression et la livraison physique des carnets."),
        ]
    )

    // MARK: - 2. Acceptation des conditions

    public static let acceptance = LegalChapter(
        id: "cgu.acceptation",
        number: 2,
        title: "Acceptation des conditions",
        blocks: [
            .paragraph("En accédant au site memobook.fr et en utilisant le service MemoBook, vous acceptez sans réserve les présentes Conditions Générales d’Utilisation (CGU). Si vous n’acceptez pas ces conditions, veuillez ne pas utiliser le service."),
        ]
    )

    // MARK: - 3. Accès au service et âge minimum

    public static let access = LegalChapter(
        id: "cgu.acces",
        number: 3,
        title: "Accès au service et âge minimum",
        blocks: [
            .paragraph("L’utilisation de MemoBook est autorisée à partir de 4 ans. Pour les utilisateurs mineurs de moins de 16 ans, l’accord d’un parent ou tuteur légal est requis. En utilisant le service, vous confirmez que vous êtes soit majeur, soit que vous avez obtenu cette autorisation parentale."),
        ]
    )

    // MARK: - 4. Description du service

    public static let service = LegalChapter(
        id: "cgu.service",
        number: 4,
        title: "Description du service",
        blocks: [
            .heading("4.1 Phase bêta gratuite (freemium)"),
            .paragraph("Pendant la phase bêta, MemoBook permet à l’utilisateur de :"),
            .bullets([
                "Enregistrer ou déposer des histoires orales",
                "Recevoir un carnet illustré généré automatiquement",
                "Accéder à une version numérique de son carnet",
            ]),
            .paragraph("Ce service est fourni gratuitement à titre d’expérimentation. MemoBook se réserve le droit de modifier, limiter ou interrompre le service à tout moment, sans préavis ni indemnité."),

            .heading("4.2 Futur service d’impression payant"),
            .paragraph("À terme, MemoBook proposera un service payant d’impression et de livraison physique des carnets. Les conditions spécifiques à ce service seront les suivantes :"),

            .heading("Commande et paiement"),
            .bullets([
                "Le prix de chaque commande est indiqué en euros toutes taxes comprises (TTC) au moment de la validation.",
                "La commande est définitivement enregistrée après confirmation du paiement.",
                "Le paiement s’effectue en ligne via un prestataire sécurisé. MemoBook ne conserve aucune donnée bancaire.",
            ]),

            .heading("Délais de production et livraison"),
            .bullets([
                "Les délais de production sont indiqués au moment de la commande (généralement entre 5 et 10 jours ouvrés).",
                "Les délais de livraison s’ajoutent au délai de production selon le transporteur et la destination.",
                "Ces délais sont donnés à titre indicatif et peuvent être affectés par des circonstances exceptionnelles (grèves, intempéries, etc.).",
            ]),

            .heading("Droit de rétractation"),
            .paragraph("Conformément à l’article L221-28 du Code de la consommation, le droit de rétractation de 14 jours ne s’applique pas aux biens personnalisés fabriqués sur mesure selon les spécifications du consommateur. Chaque carnet étant produit à la demande et personnalisé, il ne peut être ni repris ni échangé sauf en cas de défaut de fabrication avéré."),

            .heading("Produit défectueux ou non conforme"),
            .paragraph("Si vous recevez un produit endommagé ou non conforme à votre commande, vous devez nous contacter sous 14 jours calendaires après réception à l’adresse \(contactLink), en joignant des photos du défaut. Nous procéderons alors à un réimpression ou un remboursement à notre discrétion."),
        ]
    )

    // MARK: - 5. Propriété intellectuelle

    public static let intellectualProperty = LegalChapter(
        id: "cgu.propriete-intellectuelle",
        number: 5,
        title: "Propriété intellectuelle",
        blocks: [
            .heading("5.1 Vos contenus"),
            .paragraph("Vous restez propriétaire de l’intégralité des contenus que vous soumettez (histoires, enregistrements, photos). En utilisant MemoBook, vous nous accordez une licence limitée, non exclusive, pour traiter ces contenus dans le seul but de générer votre carnet personnalisé. Vos données ne sont jamais utilisées à des fins commerciales ou partagées avec des tiers."),
            .heading("5.2 Nos contenus"),
            .paragraph("Le nom MemoBook, le logo, le site et les éléments graphiques sont la propriété exclusive d’Hugo Jouffre. Toute reproduction sans autorisation écrite est interdite."),
        ]
    )

    // MARK: - 6. Responsabilité

    public static let liability = LegalChapter(
        id: "cgu.responsabilite",
        number: 6,
        title: "Responsabilité",
        blocks: [
            .paragraph("MemoBook est fourni « en l’état ». Nous ne garantissons pas une disponibilité continue du service, notamment pendant la phase bêta. MemoBook ne saurait être tenu responsable des dommages indirects liés à l’utilisation ou à l’impossibilité d’utiliser le service."),
        ]
    )

    // MARK: - 7. Données personnelles

    public static let personalData = LegalChapter(
        id: "cgu.donnees-personnelles",
        number: 7,
        title: "Données personnelles",
        blocks: [
            .paragraph("Vos données sont traitées conformément à notre Politique de confidentialité et à notre Politique de cookies, disponibles sur ce site. Vous disposez d’un droit d’accès, de rectification et de suppression de vos données en écrivant à \(contactLink)."),
        ]
    )

    // MARK: - 8. Loi applicable et juridiction

    public static let law = LegalChapter(
        id: "cgu.loi-applicable",
        number: 8,
        title: "Loi applicable et juridiction",
        blocks: [
            .paragraph("Les présentes CGU sont soumises au droit français. En cas de litige, les parties s’engagent à rechercher une solution amiable. À défaut, le litige sera soumis aux tribunaux compétents de Lyon."),
        ]
    )

    // MARK: - 9. Modifications

    public static let changes = LegalChapter(
        id: "cgu.modifications",
        number: 9,
        title: "Modifications",
        blocks: [
            .paragraph("MemoBook se réserve le droit de modifier les présentes CGU à tout moment. Les utilisateurs seront informés des modifications significatives via le site. La poursuite de l’utilisation du service après modification vaut acceptation des nouvelles conditions."),
        ]
    )
}
