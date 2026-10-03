import Foundation

// Les Conditions Générales d'Utilisation, recopiées du site memobook.fr
// (Hugo, 17/09/2026), en dix chapitres. La forme est dans ``LegalDocument``.
//
// **Revues le 03/10/2026 (Hugo) pour l'abonnement mensuel** : le chapitre 5
// « Abonnement » est né (les suivants ont glissé d'un rang), la « phase bêta
// gratuite (freemium) » a laissé place au crédit du jour, l'impression se
// conjugue au présent, et la clause « modifier, limiter ou interrompre le
// service à tout moment, sans préavis ni indemnité » ne pouvait plus tenir
// pour un service payant. Apple demande que le prix, la durée, le
// renouvellement automatique et la résiliation d'un abonnement figurent dans
// les conditions liées au paywall.
//
// ⚠️ **C'est le site qui fait foi** : memobook.fr doit publier le même texte,
// le même jour que l'app.

public enum TermsOfUse {
    private static let contactLink = LegalContact.emailLink

    /// Le document : le titre de l'écran — celui de la ligne du profil qui y
    /// mène — et les dix chapitres, dans l'ordre du site.
    public static let document = LegalDocument(
        id: "cgu",
        title: "Conditions d’utilisation",
        chapters: [
            presentation, acceptance, access, service, subscription,
            intellectualProperty, liability, personalData, law, changes,
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
            .paragraph("MemoBook est un service de création de carnets illustrés personnalisés à partir d’enregistrements audio ou de récits. L’application est gratuite dans la limite d’un crédit quotidien par voyage ; un abonnement payant permet de raconter sans limite. L’impression et la livraison des carnets sont vendues séparément."),
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
            .heading("4.1 Utilisation gratuite et crédit du jour"),
            .paragraph("Sans abonnement, MemoBook permet à l’utilisateur de :"),
            .bullets([
                "Enregistrer ou déposer des histoires orales",
                "Recevoir un carnet illustré généré automatiquement",
                "Accéder à une version numérique de son carnet",
            ]),
            .paragraph("Cette utilisation gratuite est limitée par un crédit du jour : chaque voyage peut recevoir 5 minutes de récit par jour, partagées entre ses participants non abonnés. Un enregistrement vocal consomme sa durée, un texte écrit consomme une minute pour 800 caractères, et les photos ne consomment rien."),
            .paragraph("Le crédit se renouvelle chaque jour à minuit, à l’heure du téléphone de l’utilisateur. Lorsqu’il est épuisé, l’enregistrement en cours s’arrête : les contenus déjà enregistrés sont conservés, et le récit peut reprendre le lendemain ou sans limite avec un abonnement (chapitre 5)."),
            .paragraph("MemoBook peut faire évoluer le service gratuit, notamment le montant du crédit du jour. Les changements importants sont annoncés dans l’application et ne s’appliquent jamais rétroactivement à une période d’abonnement déjà payée."),

            .heading("4.2 Service d’impression et de livraison"),
            .paragraph("MemoBook propose un service payant d’impression et de livraison physique des carnets, aux conditions suivantes :"),

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
            .paragraph("Si vous recevez un produit endommagé ou non conforme à votre commande, vous devez nous contacter sous 14 jours calendaires après réception à l’adresse \(contactLink), en joignant des photos du défaut. Nous procéderons alors à une réimpression ou un remboursement à notre discrétion."),
        ]
    )

    // MARK: - 5. Abonnement

    /// L'abonnement mensuel (Hugo, 03/10/2026). Ce qu'Apple exige d'un
    /// abonnement à renouvellement automatique — prix, durée, renouvellement,
    /// résiliation — et ce que le produit a décidé : l'illimité est personnel,
    /// il reste ouvert jusqu'au bout de la période payée, et les remboursements
    /// passent par Apple.
    public static let subscription = LegalChapter(
        id: "cgu.abonnement",
        number: 5,
        title: "Abonnement",
        blocks: [
            .paragraph("MemoBook propose un abonnement facultatif qui rend le récit illimité pour l’abonné : ses enregistrements vocaux et ses textes ne consomment pas le crédit du jour de ses voyages. L’abonnement est personnel ; il n’étend pas l’accès illimité aux autres participants d’un voyage, qui continuent de partager le crédit du jour."),

            .heading("Prix et paiement"),
            .bullets([
                "L’abonnement est un abonnement à renouvellement automatique, au prix de 4,99 € TTC par mois. Le prix applicable est celui affiché dans l’application au moment de la souscription.",
                "Il est souscrit et payé via l’App Store d’Apple : le montant est prélevé sur votre compte Apple à la confirmation de l’achat, puis à chaque renouvellement. MemoBook ne reçoit ni ne conserve aucune donnée bancaire.",
                "Toute modification du prix vous est annoncée à l’avance, selon les règles de l’App Store, et vous laisse la possibilité de résilier avant qu’elle ne s’applique.",
            ]),

            .heading("Renouvellement et résiliation"),
            .bullets([
                "L’abonnement se renouvelle automatiquement chaque mois, au même prix, sauf résiliation au moins 24 heures avant la fin de la période en cours.",
                "Vous pouvez gérer et résilier votre abonnement à tout moment dans les réglages de votre compte Apple (Réglages de l’iPhone, votre nom, puis Abonnements).",
                "La résiliation prend effet à la fin de la période déjà payée : l’accès illimité reste ouvert jusqu’à cette date, puis le service revient à l’utilisation gratuite décrite au chapitre 4. Vos carnets et vos contenus sont conservés.",
                "À la fin de chaque voyage, MemoBook vous rappelle que vous pouvez résilier votre abonnement.",
            ]),

            .heading("Remboursement"),
            .paragraph("Une période commencée est due : la résiliation n’entraîne aucun remboursement au prorata de la période en cours. Les demandes de remboursement sont traitées par Apple, selon ses propres conditions, depuis [reportaproblem.apple.com](https://reportaproblem.apple.com)."),
        ]
    )

    // MARK: - 6. Propriété intellectuelle

    public static let intellectualProperty = LegalChapter(
        id: "cgu.propriete-intellectuelle",
        number: 6,
        title: "Propriété intellectuelle",
        blocks: [
            .heading("6.1 Vos contenus"),
            .paragraph("Vous restez propriétaire de l’intégralité des contenus que vous soumettez (histoires, enregistrements, photos). En utilisant MemoBook, vous nous accordez une licence limitée, non exclusive, pour traiter ces contenus dans le seul but de générer votre carnet personnalisé. Vos données ne sont jamais utilisées à des fins commerciales ou partagées avec des tiers."),
            .heading("6.2 Nos contenus"),
            .paragraph("Le nom MemoBook, le logo, le site et les éléments graphiques sont la propriété exclusive d’Hugo Jouffre. Toute reproduction sans autorisation écrite est interdite."),
        ]
    )

    // MARK: - 7. Responsabilité

    public static let liability = LegalChapter(
        id: "cgu.responsabilite",
        number: 7,
        title: "Responsabilité",
        blocks: [
            .paragraph("MemoBook est fourni « en l’état ». Nous ne garantissons pas une disponibilité continue du service. MemoBook ne saurait être tenu responsable des dommages indirects liés à l’utilisation ou à l’impossibilité d’utiliser le service."),
        ]
    )

    // MARK: - 8. Données personnelles

    public static let personalData = LegalChapter(
        id: "cgu.donnees-personnelles",
        number: 8,
        title: "Données personnelles",
        blocks: [
            .paragraph("Vos données sont traitées conformément à notre Politique de confidentialité, disponible dans l’app. Vous disposez d’un droit d’accès, de rectification et de suppression de vos données en écrivant à \(contactLink)."),
        ]
    )

    // MARK: - 9. Loi applicable et juridiction

    public static let law = LegalChapter(
        id: "cgu.loi-applicable",
        number: 9,
        title: "Loi applicable et juridiction",
        blocks: [
            .paragraph("Les présentes CGU sont soumises au droit français. En cas de litige, les parties s’engagent à rechercher une solution amiable. À défaut, le litige sera soumis aux tribunaux compétents de Lyon."),
        ]
    )

    // MARK: - 10. Modifications

    public static let changes = LegalChapter(
        id: "cgu.modifications",
        number: 10,
        title: "Modifications",
        blocks: [
            .paragraph("MemoBook se réserve le droit de modifier les présentes CGU à tout moment. Les utilisateurs seront informés des modifications significatives via le site. La poursuite de l’utilisation du service après modification vaut acceptation des nouvelles conditions."),
        ]
    )
}
