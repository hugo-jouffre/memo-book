import Foundation

// La Politique de confidentialité, recopiée du site memobook.fr (Hugo,
// 17/09/2026), en onze chapitres. La forme est dans ``LegalDocument``.
//
// Deux endroits du texte source ont été corrigés sur retour de Clara
// (26/09/2026), et non en silence (R8) :
//   - le chapitre 3 annonçait « les prestataires techniques suivants : » sans
//     la liste, que le site porte dans un tableau non fourni — la voici (T152) ;
//   - le chapitre 9 se terminait par un point-virgule (T153).

public enum PrivacyPolicy {
    private static let contactLink = LegalContact.emailLink

    /// Le document : le titre de l'écran et les onze chapitres, dans l'ordre du
    /// site. Le titre est celui de la page du site, là où la ligne du profil
    /// qui y mène dit seulement « Confidentialité ».
    public static let document = LegalDocument(
        id: "confidentialite",
        title: "Politique de confidentialité",
        chapters: [
            introduction, collectedData, recipients, transfers, security, rights,
            complaint, cookies, minors, changes, contact,
        ]
    )

    // MARK: - 1. Introduction

    public static let introduction = LegalChapter(
        id: "confidentialite.introduction",
        number: 1,
        title: "Introduction",
        blocks: [
            .paragraph("Hugo Jouffre, opérant sous le nom de MemoBook (micro-entrepreneur, SIRET : 815\u{00A0}246\u{00A0}442, 28 rue Tête d’Or, 69006 Lyon), attache une grande importance à la protection de vos données personnelles."),
            .paragraph("La présente Politique de confidentialité décrit quelles données nous collectons, pourquoi nous les collectons, comment nous les utilisons, combien de temps nous les conservons, et quels sont vos droits conformément au Règlement Général sur la Protection des Données (RGPD — Règlement UE 2016/679) et à la loi française Informatique et Libertés."),
            .heading("Responsable du traitement :"),
            .paragraph("Hugo Jouffre — \(contactLink) — 28 rue Tête d’Or, 69006 Lyon"),
        ]
    )

    // MARK: - 2. Données collectées et finalités

    public static let collectedData = LegalChapter(
        id: "confidentialite.donnees-collectees",
        number: 2,
        title: "Données collectées et finalités",
        blocks: [
            .heading("2.1 Formulaire bêta-testeur (inscription via numéro WhatsApp)"),
            .lines([
                "**Données collectées :** numéro de téléphone",
                "**Finalité :** vous contacter sur WhatsApp pour vous expliquer le fonctionnement du service bêta et vous remettre votre premier carnet gratuit",
                "**Base légale :** consentement (article 6.1.a du RGPD) — vous soumettez volontairement votre numéro via le formulaire",
                "**Durée de conservation :** jusqu’à la fin de la phase bêta ou jusqu’à votre demande de suppression, et au maximum 3 ans après le dernier contact",
            ]),

            .heading("2.2 Données de navigation et de mesure d’audience"),
            .lines([
                "**Données collectées :** adresse IP anonymisée, pages visitées, durée de visite, type d’appareil et de navigateur, provenance (via cookies Google Analytics et Hotjar)",
                "**Finalité :** analyser l’utilisation du site pour améliorer l’expérience utilisateur",
                "**Base légale :** consentement (article 6.1.a du RGPD) — vous acceptez ces cookies via le bandeau de consentement",
                "**Durée de conservation :** 13 mois maximum (Google Analytics) / 1 an (Hotjar)",
            ]),

            .heading("2.3 Données publicitaires"),
            .lines([
                "**Données collectées :** données comportementales de navigation transmises à Meta via le Meta Pixel (pages visitées, actions effectuées), permettant de mesurer l’efficacité de nos publicités Facebook et Instagram",
                "**Finalité :** mesure des campagnes publicitaires et reciblage publicitaire",
                "**Base légale :** consentement (article 6.1.a du RGPD)",
                "**Durée de conservation :** jusqu’à 90 jours chez Meta",
            ]),

            .heading("2.4 Données techniques (Webflow)"),
            .lines([
                "**Données collectées :** cookies techniques de session nécessaires au bon fonctionnement du site",
                "**Finalité :** assurer le fonctionnement et la sécurité du site",
                "**Base légale :** intérêt légitime et nécessité technique (article 6.1.f du RGPD) — ces cookies ne nécessitent pas de consentement",
                "**Durée de conservation :** durée de la session de navigation",
            ]),
        ]
    )

    // MARK: - 3. Destinataires des données

    public static let recipients = LegalChapter(
        id: "confidentialite.destinataires",
        number: 3,
        title: "Destinataires des données",
        blocks: [
            .paragraph("Vos données peuvent être transmises aux prestataires techniques suivants dans le cadre strict des finalités décrites ci-dessus :"),
            // La liste donnée par Clara (T152). « Hotter Ltd » dans son
            // message : Hotjar Ltd, l'éditeur de Hotjar, que le ticket citait.
            .bullets(["Webflow Inc.", "Google LLC (Analytics)", "Hotjar Ltd", "Meta Platforms Inc."]),
            .paragraph("Aucune de vos données n’est vendue à des tiers. Aucune donnée n’est partagée à des fins commerciales sans votre consentement explicite."),
        ]
    )

    // MARK: - 4. Transferts hors Union européenne

    public static let transfers = LegalChapter(
        id: "confidentialite.transferts",
        number: 4,
        title: "Transferts hors Union européenne",
        blocks: [
            .paragraph("Certains de nos prestataires (Webflow, Google, Meta) sont basés aux États-Unis. Ces transferts sont encadrés par des clauses contractuelles types (CCT) approuvées par la Commission européenne, conformément à l’article 46 du RGPD, garantissant un niveau de protection adéquat de vos données."),
        ]
    )

    // MARK: - 5. Sécurité des données

    public static let security = LegalChapter(
        id: "confidentialite.securite",
        number: 5,
        title: "Sécurité des données",
        blocks: [
            .paragraph("Hugo Jouffre met en œuvre les mesures techniques et organisationnelles appropriées pour protéger vos données contre tout accès non autorisé, perte, altération ou divulgation. Le site est hébergé sur une infrastructure sécurisée (Webflow) avec connexion chiffrée HTTPS."),
            .paragraph("Vos numéros de téléphone collectés via le formulaire bêta sont stockés dans un outil sécurisé accessible uniquement par les fondateurs de MemoBook (Hugo Jouffre et Paul Jouffre)."),
        ]
    )

    // MARK: - 6. Vos droits

    public static let rights = LegalChapter(
        id: "confidentialite.droits",
        number: 6,
        title: "Vos droits",
        blocks: [
            .paragraph("Conformément au RGPD et à la loi Informatique et Libertés, vous disposez des droits suivants concernant vos données personnelles :"),
            .bullets([
                "**Droit d’accès :** obtenir la confirmation que des données vous concernant sont traitées, et en recevoir une copie.",
                "**Droit de rectification :** corriger des données inexactes ou incomplètes vous concernant.",
                "**Droit à l’effacement (« droit à l’oubli ») :** demander la suppression de vos données, sous réserve de nos obligations légales.",
                "**Droit à la limitation du traitement :** demander la suspension du traitement de vos données dans certains cas.",
                "**Droit à la portabilité :** recevoir vos données dans un format structuré et lisible par machine.",
                "**Droit d’opposition :** vous opposer à tout moment au traitement de vos données fondé sur notre intérêt légitime, notamment à des fins de publicité.",
                "**Droit de retirer votre consentement :** lorsque le traitement est fondé sur votre consentement, vous pouvez le retirer à tout moment sans que cela nuise à la licéité du traitement effectué avant ce retrait.",
            ]),
            .paragraph("Pour exercer vos droits, contactez-nous par email à : \(contactLink), en précisant votre identité. Nous nous engageons à répondre dans un délai d’un mois."),
        ]
    )

    // MARK: - 7. Droit de réclamation

    public static let complaint = LegalChapter(
        id: "confidentialite.reclamation",
        number: 7,
        title: "Droit de réclamation",
        blocks: [
            .paragraph("Si vous estimez que vos droits ne sont pas respectés, vous avez le droit de déposer une réclamation auprès de la Commission Nationale de l’Informatique et des Libertés (CNIL) :"),
            .lines([
                "CNIL — 3 Place de Fontenoy, TSA 80715, 75334 Paris Cedex 07",
                "Site : [https://www.cnil.fr](https://www.cnil.fr)",
                "Formulaire de plainte en ligne : [https://www.cnil.fr/fr/plaintes](https://www.cnil.fr/fr/plaintes)",
            ]),
        ]
    )

    // MARK: - 8. Cookies

    public static let cookies = LegalChapter(
        id: "confidentialite.cookies",
        number: 8,
        title: "Cookies",
        blocks: [
            .paragraph("Pour des informations détaillées sur les cookies utilisés par MemoBook, veuillez consulter notre Politique de cookies, disponible sur ce site."),
        ]
    )

    // MARK: - 9. Mineurs

    public static let minors = LegalChapter(
        id: "confidentialite.mineurs",
        number: 9,
        title: "Mineurs",
        blocks: [
            .paragraph("MemoBook est accessible à partir de 4 ans. Dans le cadre du RGPD, le traitement des données d’un enfant de moins de 16 ans n’est licite que si le titulaire de la responsabilité parentale a donné son consentement. En soumettant un numéro de téléphone via notre formulaire pour un enfant de moins de 16 ans, le parent ou tuteur légal confirme avoir donné son accord."),
        ]
    )

    // MARK: - 10. Modifications de la politique

    public static let changes = LegalChapter(
        id: "confidentialite.modifications",
        number: 10,
        title: "Modifications de la politique",
        blocks: [
            .paragraph("Cette politique peut être mise à jour à tout moment pour refléter des changements dans nos pratiques ou la réglementation applicable. La date de mise à jour est systématiquement indiquée en haut de la page. Nous vous encourageons à la consulter régulièrement."),
        ]
    )

    // MARK: - 11. Contact

    public static let contact = LegalChapter(
        id: "confidentialite.contact",
        number: 11,
        title: "Contact",
        blocks: [
            .paragraph("Pour toute question relative à la protection de vos données personnelles :"),
            .lines([
                "Hugo Jouffre",
                "28 rue Tête d’Or, 69006 Lyon",
                contactLink,
            ]),
        ]
    )
}
