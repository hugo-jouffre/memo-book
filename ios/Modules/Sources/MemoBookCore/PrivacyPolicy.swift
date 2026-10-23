import Foundation

// La Politique de confidentialité, en dix chapitres. La forme est dans ``LegalDocument``.
//
// **Réécrite le 23/10/2026** (Hugo, avant la fiche Play) pour décrire l'app,
// et non plus seulement le site : compte, profil, récits, traitement par l'IA,
// commandes, abonnement, notifications, assistance, et chaque prestataire qui
// les traite. Les trois sections du site (mesure d'audience, publicité,
// Webflow) restent, en 2.10 à 2.12. Le texte vaut pour les deux stores : il
// est **le même sur iOS et sur Android**, mot pour mot — un changement se
// fait dans les deux fichiers. L'âge minimum passe à 16 ans (chapitre 8),
// comme dans les CGU. Ce que le texte décrit a été relevé dans le code du
// 23/10/2026 (`backend/prisma/schema.prisma`, `backend/src/services`).
//
// Historique : recopiée du site memobook.fr le 17/09/2026 ; liste des
// destinataires (T152) et ponctuation (T153) corrigées sur retour de Clara le
// 26/09 ; abonnement et crédit du jour ajoutés le 03/10 ; formulaire bêta
// retiré et Stripe ajouté le 19/10 (D6).
//
// ⚠️ **C'est le site qui fait foi** : memobook.fr doit publier ce texte le
// même jour que l'app, et c'est son adresse que demandent l'App Store et la
// Play Console.

public enum PrivacyPolicy {
    private static let contactLink = LegalContact.emailLink

    /// Le document : le titre de l'écran et les dix chapitres, dans l'ordre du
    /// site — moins « Cookies » : une app n'en pose pas, et Apple ne demande
    /// aucune politique de cookies, seulement celle-ci (Hugo, 29/09/2026,
    /// T154). Voir `docs/archive/ui-development-journal.md` § 32. Le titre est celui de la page du site, là où la ligne du profil
    /// qui y mène dit seulement « Confidentialité ».
    public static let document = LegalDocument(
        id: "confidentialite",
        title: "Politique de confidentialité",
        chapters: [
            introduction, collectedData, recipients, transfers, security, rights,
            complaint, minors, changes, contact,
        ]
    )

    // MARK: - 1. Introduction

    public static let introduction = LegalChapter(
        id: "confidentialite.introduction",
        number: 1,
        title: "Introduction",
        blocks: [
            .paragraph("Hugo Jouffre, opérant sous le nom de MemoBook (micro-entrepreneur, SIRET : 815\u{00A0}246\u{00A0}442, 28 rue Tête d’Or, 69006 Lyon), édite l’application MemoBook, sur iPhone et sur Android, et le site memobook.fr. Il attache une grande importance à la protection de vos données personnelles."),
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
            .paragraph("Les sections 2.1 à 2.9 concernent l’application MemoBook, les sections 2.10 à 2.12 le site memobook.fr."),

            .heading("2.1 Votre compte"),
            .lines([
                "**Données collectées :** adresse e-mail, prénom et nom, mot de passe (enregistré sous une forme hachée, que nous ne pouvons pas relire) ; si vous vous connectez avec Apple ou avec Google, l’identifiant de votre compte chez ce service, l’adresse e-mail qu’il nous transmet et, le cas échéant, sa photo de profil ; le fuseau horaire de votre téléphone",
                "**Finalité :** créer et sécuriser votre compte, vous permettre de retrouver vos voyages sur tous vos téléphones",
                "**Base légale :** exécution du contrat (article 6.1.b du RGPD)",
                "**Durée de conservation :** tant que votre compte existe",
            ]),

            .heading("2.2 Votre profil"),
            .lines([
                "**Données collectées :** toutes facultatives — photo de profil, date de naissance, genre, numéro de téléphone (WhatsApp), adresse postale. Si vous n’indiquez pas votre genre, il est déduit de votre prénom, sur nos serveurs et sans prestataire, pour accorder les textes de l’app",
                "**Finalité :** personnaliser l’app (accords, rappel d’anniversaire, statistiques de vos voyages), pré-remplir l’adresse de livraison d’un carnet, vous contacter au sujet d’une commande",
                "**Base légale :** exécution du contrat (article 6.1.b du RGPD) ; ces informations se modifient ou s’effacent à tout moment depuis votre profil",
                "**Durée de conservation :** tant que votre compte existe",
            ]),

            .heading("2.3 Vos voyages et vos récits"),
            .lines([
                "**Données collectées :** les voyages que vous créez ou rejoignez (titre, dates, destination, étapes, dépenses, et le contexte du voyage, comme l’occasion ou les prénoms de vos compagnons), vos enregistrements vocaux, vos textes, vos photos, votre conversation avec MEMO, les souvenirs rédigés et vos corrections, les carnets composés, et les informations tirées de vos récits pour vos statistiques (pays, villes, personnes rencontrées, distances, moyens de transport)",
                "**Finalité :** composer votre carnet de voyage, le partager avec les participants du voyage, l’afficher dans l’app et vous permettre de le commander imprimé",
                "**Base légale :** exécution du contrat (article 6.1.b du RGPD)",
                "**Durée de conservation :** tant que le voyage existe ; vous pouvez supprimer un souvenir, ou un voyage que vous avez créé, à tout moment",
            ]),
            .paragraph("Vos récits sont visibles des autres participants du voyage. Ils peuvent parler d’autres personnes (vos compagnons de voyage, les personnes rencontrées) : ne racontez que ce que vous êtes en droit de partager. Nous ne vous demandons aucune donnée sensible (santé, opinions, religion…) ; si vos récits en contiennent, elles servent uniquement à fabriquer votre carnet. Si vous partagez un carnet par lien, toute personne qui a ce lien peut le consulter."),

            .heading("2.4 Le traitement de vos récits par l’intelligence artificielle"),
            .lines([
                "**Données traitées :** vos enregistrements vocaux, vos textes et votre conversation avec MEMO, avec votre prénom, les prénoms de vos compagnons, le contexte, les dates et les lieux du voyage. Vos photos ne sont pas envoyées aux modèles d’intelligence artificielle",
                "**Finalité :** transcrire vos vocaux (OpenAI), faire converser MEMO avec vous et rédiger chaque souvenir (Anthropic), puis le mettre en page dans le carnet (OpenAI)",
                "**Base légale :** exécution du contrat (article 6.1.b du RGPD)",
                "**Durée de conservation :** nos prestataires ne conservent ces contenus que le temps limité prévu par leurs conditions, pour prévenir les abus ; nous les conservons comme vos récits (2.3)",
            ]),
            .paragraph("Ces prestataires traitent vos contenus pour notre compte et, selon les conditions de leur offre professionnelle, ne les utilisent pas pour entraîner leurs modèles. Le texte rédigé reste modifiable, et vos corrections priment toujours. Aucune décision produisant des effets juridiques à votre égard n’est prise sur le seul fondement d’un traitement automatisé (article 22 du RGPD)."),
            .paragraph("Sur iPhone, le texte qui s’affiche pendant que vous parlez vient de la reconnaissance vocale d’Apple, sur le téléphone ou, à défaut, sur les serveurs d’Apple. Il ne sert qu’à l’affichage : la transcription du souvenir est faite par nos serveurs."),

            .heading("2.5 Commande d’un carnet imprimé"),
            .lines([
                "**Données collectées :** nom et adresse de livraison, adresse e-mail, numéro de téléphone si vous acceptez un suivi par WhatsApp, montant et contenu de la commande ; pour une carte enregistrée, ses 4 derniers chiffres, sa marque et sa date d’expiration. Le paiement est traité par Stripe : nous ne voyons ni ne conservons jamais le numéro complet de votre carte",
                "**Finalité :** encaisser, fabriquer et livrer votre carnet, vous en donner le suivi, et tenir notre comptabilité",
                "**Base légale :** exécution du contrat (article 6.1.b du RGPD) ; obligation légale pour la comptabilité (article 6.1.c du RGPD)",
                "**Durée de conservation :** tant que le voyage existe ; une carte enregistrée, jusqu’à ce que vous la retiriez. Stripe conserve de son côté les données de paiement selon ses propres obligations légales",
            ]),

            .heading("2.6 Abonnement souscrit dans l’application (App Store ou Google Play)"),
            .lines([
                "**Données collectées :** selon le store où vous l’avez souscrit, les identifiants de transaction App Store (abonnement souscrit sur un iPhone) ou le jeton d’achat et l’identifiant de commande Google Play (abonnement souscrit sur un téléphone Android) ; l’abonnement souscrit, son prix, son statut, les dates d’achat, de renouvellement et de fin de période, et la raison de la résiliation si vous choisissez de la donner. Aucune donnée bancaire : le paiement est traité par le store, qui ne nous transmet ni vos moyens de paiement ni vos coordonnées bancaires",
                "**Finalité :** ouvrir et maintenir l’accès illimité, l’honorer jusqu’à la fin de la période payée après une résiliation, vous rappeler que vous pouvez résilier quand votre dernier voyage en cours se termine, et répondre à vos demandes d’assistance",
                "**Base légale :** exécution du contrat (article 6.1.b du RGPD)",
                "**Durée de conservation :** tant que votre compte existe ; ces données sont supprimées avec lui",
            ]),

            .heading("2.7 Compteur d’usage quotidien (crédit du jour)"),
            .lines([
                "**Données collectées :** pour chaque voyage et chaque jour, la durée cumulée des enregistrements vocaux et le nombre de caractères des textes envoyés, ainsi que le fuseau horaire de votre téléphone, qui fixe l’heure de minuit",
                "**Finalité :** appliquer la limite d’utilisation gratuite (le crédit du jour de 5 minutes par voyage) et vous indiquer ce qu’il reste",
                "**Base légale :** exécution du contrat (article 6.1.b du RGPD)",
                "**Durée de conservation :** tant que le voyage existe ; le compteur est supprimé avec lui",
            ]),

            .heading("2.8 Notifications et e-mails"),
            .lines([
                "**Données collectées :** l’identifiant de notification de votre téléphone, la version de l’app, vos réglages de notifications, les notifications envoyées et le moment où vous les ouvrez",
                "**Finalité :** vous envoyer les notifications que vous avez autorisées (rappel d’écriture, fin de voyage, carnet à commander, anniversaire…), à un rythme adapté à vos habitudes, et les e-mails liés à votre compte (mot de passe oublié, export de vos données, rappel de fin de voyage d’un abonné)",
                "**Base légale :** consentement pour les notifications, que vous retirez à tout moment dans les réglages de votre téléphone ou dans votre profil (article 6.1.a du RGPD) ; exécution du contrat pour les e-mails liés au compte (article 6.1.b du RGPD)",
                "**Durée de conservation :** tant que votre compte existe",
            ]),
            .paragraph("Si vous activez la « Newsletter mensuelle MemoBook » dans votre profil, nous utilisons votre adresse e-mail pour vous l’envoyer, sur la base de votre consentement, que vous retirez en désactivant ce réglage."),

            .heading("2.9 Assistance et avis"),
            .lines([
                "**Données collectées :** vos messages au support, avec la version de l’app, le modèle, la version du système et la langue de votre téléphone ; vos réponses aux questionnaires d’avis et vos votes sur la foire aux questions",
                "**Finalité :** vous répondre et améliorer MemoBook",
                "**Base légale :** intérêt légitime (article 6.1.f du RGPD) à répondre à vos demandes et à améliorer le service",
                "**Durée de conservation :** tant que votre compte existe",
            ]),

            .heading("2.10 Site memobook.fr : navigation et mesure d’audience"),
            .lines([
                "**Données collectées :** adresse IP anonymisée, pages visitées, durée de visite, type d’appareil et de navigateur, provenance (via cookies Google Analytics et Hotjar)",
                "**Finalité :** analyser l’utilisation du site pour améliorer l’expérience utilisateur",
                "**Base légale :** consentement (article 6.1.a du RGPD) — vous acceptez ces cookies via le bandeau de consentement",
                "**Durée de conservation :** 13 mois maximum (Google Analytics) / 1 an (Hotjar)",
            ]),

            .heading("2.11 Site memobook.fr : données publicitaires"),
            .lines([
                "**Données collectées :** données comportementales de navigation transmises à Meta via le Meta Pixel (pages visitées, actions effectuées), permettant de mesurer l’efficacité de nos publicités Facebook et Instagram",
                "**Finalité :** mesure des campagnes publicitaires et reciblage publicitaire",
                "**Base légale :** consentement (article 6.1.a du RGPD)",
                "**Durée de conservation :** jusqu’à 90 jours chez Meta",
            ]),

            .heading("2.12 Site memobook.fr : données techniques (Webflow)"),
            .lines([
                "**Données collectées :** cookies techniques de session nécessaires au bon fonctionnement du site",
                "**Finalité :** assurer le fonctionnement et la sécurité du site",
                "**Base légale :** intérêt légitime et nécessité technique (article 6.1.f du RGPD) — ces cookies ne nécessitent pas de consentement",
                "**Durée de conservation :** durée de la session de navigation",
            ]),
            .paragraph("L’application ne contient ni publicité, ni outil de mesure d’audience, ni traceur publicitaire."),
        ]
    )

    // MARK: - 3. Destinataires des données

    public static let recipients = LegalChapter(
        id: "confidentialite.destinataires",
        number: 3,
        title: "Destinataires des données",
        blocks: [
            .paragraph("Vos données sont traitées par les prestataires suivants, pour notre compte et dans le cadre strict des finalités décrites ci-dessus :"),
            .bullets([
                "Railway Corporation (hébergement des serveurs de l’application)",
                "Supabase Inc. (base de données et stockage des fichiers : enregistrements, photos, carnets)",
                "Anthropic (conversation avec MEMO, rédaction des souvenirs)",
                "OpenAI (transcription des vocaux, mise en page du carnet)",
                "APITemplate.io (fabrication du PDF du carnet)",
                "Webflow Inc. (hébergement du site, diffusion des photos d’un carnet pour sa mise en page)",
                "Resend (envoi des e-mails)",
                "Stripe Payments Europe Ltd. (paiement des carnets imprimés, cartes enregistrées)",
                "Apple Distribution International Ltd. (App Store : paiement d’un abonnement souscrit sur un iPhone ; connexion avec Apple et notifications sur iPhone)",
                "Google Commerce Limited (Google Play : vente et paiement d’un abonnement souscrit sur un téléphone Android)",
                "Google Ireland Limited (connexion avec Google ; Firebase Cloud Messaging, notifications sur Android ; Google Sheets, suivi interne des livraisons)",
                "Google LLC (Google Analytics, sur le site)",
                "Hotjar Ltd (sur le site)",
                "Meta Platforms Inc. (sur le site)",
            ]),
            .paragraph("Les autres participants d’un voyage voient ce que vous y racontez et le carnet commun. Aucune de vos données n’est vendue à des tiers. Aucune donnée n’est partagée à des fins commerciales sans votre consentement explicite."),
        ]
    )

    // MARK: - 4. Transferts hors Union européenne

    public static let transfers = LegalChapter(
        id: "confidentialite.transferts",
        number: 4,
        title: "Transferts hors Union européenne",
        blocks: [
            .paragraph("Certains de nos prestataires sont établis aux États-Unis ou peuvent y traiter vos données, notamment Railway, Supabase, Anthropic, OpenAI, Webflow, Resend, Google et Meta. Ces transferts sont encadrés par la décision d’adéquation de la Commission européenne pour les entreprises certifiées au cadre de protection des données UE–États-Unis (Data Privacy Framework) et, à défaut, par des clauses contractuelles types approuvées par la Commission européenne, conformément aux articles 45 et 46 du RGPD."),
        ]
    )

    // MARK: - 5. Sécurité des données

    public static let security = LegalChapter(
        id: "confidentialite.securite",
        number: 5,
        title: "Sécurité des données",
        blocks: [
            .paragraph("Hugo Jouffre met en œuvre les mesures techniques et organisationnelles appropriées pour protéger vos données contre tout accès non autorisé, perte, altération ou divulgation : les échanges entre l’app et nos serveurs sont chiffrés (HTTPS), les mots de passe sont hachés, et vos enregistrements et vos photos sont stockés dans un espace privé. Le site est hébergé par Webflow, avec connexion chiffrée HTTPS."),
            .paragraph("Votre photo de profil, les photos de la conversation et celles d’un carnet en cours de mise en page s’affichent par une adresse unique, impossible à deviner, qui ne demande pas de connexion. Seule l’équipe de MemoBook a accès à vos données, pour faire fonctionner le service et répondre à vos demandes."),
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
            .paragraph("Depuis l’app, vous pouvez à tout moment corriger votre profil, recevoir une copie de vos données (Profil, « Exporter mes données » : un lien valable 7 jours vous est envoyé par e-mail) et supprimer votre compte (Profil, « Supprimer mon compte »). La suppression est immédiate et définitive : votre compte, vos voyages et les fichiers que nous stockons sont effacés, à l’exception des voyages partagés avec d’autres participants, qui leur restent avec ce que vous y avez raconté. Les copies de photos diffusées par Webflow et le PDF d’un carnet fabriqué par APITemplate.io sont supprimés sur simple demande."),
            .paragraph("Pour exercer vos droits, ou pour supprimer votre compte sans l’app, contactez-nous par email à : \(contactLink), en précisant votre identité. Nous nous engageons à répondre dans un délai d’un mois."),
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

    // MARK: - 8. Mineurs

    public static let minors = LegalChapter(
        id: "confidentialite.mineurs",
        number: 8,
        title: "Mineurs",
        blocks: [
            .paragraph("MemoBook est réservé aux personnes âgées d’au moins 16 ans, et nous ne collectons pas sciemment de données d’enfants de moins de 16 ans. Un parent peut raconter les souvenirs de voyage de ses enfants depuis son propre compte. Si vous apprenez qu’un enfant de moins de 16 ans a ouvert un compte, écrivez-nous à \(contactLink) : nous le supprimerons."),
        ]
    )

    // MARK: - 9. Modifications de la politique

    public static let changes = LegalChapter(
        id: "confidentialite.modifications",
        number: 9,
        title: "Modifications de la politique",
        blocks: [
            .paragraph("Cette politique peut être mise à jour à tout moment pour refléter des changements dans nos pratiques ou la réglementation applicable. La date de mise à jour est indiquée ci-dessous. Nous vous encourageons à la consulter régulièrement."),
            .paragraph("Dernière mise à jour : 23 octobre 2026."),
        ]
    )

    // MARK: - 10. Contact

    public static let contact = LegalChapter(
        id: "confidentialite.contact",
        number: 10,
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
