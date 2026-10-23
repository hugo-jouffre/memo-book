package com.memobook.core

// Les Conditions Générales d'Utilisation, recopiées du site memobook.fr
// (Hugo, 17/09/2026), en dix chapitres. Le jumeau de
// `MemoBookCore/TermsOfUse.swift` ; la forme est dans [LegalDocument].
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
//
// **La version Google Play** (A8b, 23/10/2026) : recopié de l'app iOS, sauf
// le chapitre 5, où l'abonnement se paie, se gère, se résilie et se rembourse
// par Google Play — et où un abonnement pris sur un iPhone reste chez Apple.
// Chaque phrase changée est listée dans la PR, pour Clara. ⚠️ Le site doit
// porter les deux versions, ou un texte qui vaut pour les deux stores.

object TermsOfUse {
    private const val contactLink = LegalContact.emailLink

    /**
     * Le document : le titre de l'écran — celui de la ligne du profil qui y
     * mène — et les dix chapitres, dans l'ordre du site.
     *
     * `by lazy`, comme un `static let` Swift : les chapitres sont déclarés plus
     * bas, et un `val` simple les lirait avant leur initialisation.
     */
    val document: LegalDocument by lazy {
        LegalDocument(
            id = "cgu",
            title = "Conditions d’utilisation",
            chapters = listOf(
                presentation, acceptance, access, service, subscription,
                intellectualProperty, liability, personalData, law, changes,
            ),
        )
    }


    val presentation = LegalChapter(
        id = "cgu.presentation",
        number = 1,
        title = "Présentation du service",
        blocks = listOf(
            LegalBlock.Paragraph("MemoBook est un service proposé par Hugo Jouffre, micro-entrepreneur."),
            LegalBlock.Lines(listOf(
                "SIRET : 815\u00A0246\u00A0442 — TVA intracommunautaire : FR\u00A059815246442",
                "Siège social : 28 rue Tête d’Or, 69006 Lyon, France",
                "Contact : $contactLink",
            )),
            LegalBlock.Paragraph("MemoBook est un service de création de carnets illustrés personnalisés à partir d’enregistrements audio ou de récits. L’application est gratuite dans la limite d’un crédit quotidien par voyage ; un abonnement payant permet de raconter sans limite. L’impression et la livraison des carnets sont vendues séparément."),
        )
    )

    // 2. Acceptation des conditions

    val acceptance = LegalChapter(
        id = "cgu.acceptation",
        number = 2,
        title = "Acceptation des conditions",
        blocks = listOf(
            LegalBlock.Paragraph("En accédant au site memobook.fr et en utilisant le service MemoBook, vous acceptez sans réserve les présentes Conditions Générales d’Utilisation (CGU). Si vous n’acceptez pas ces conditions, veuillez ne pas utiliser le service."),
        )
    )

    // 3. Accès au service et âge minimum

    val access = LegalChapter(
        id = "cgu.acces",
        number = 3,
        title = "Accès au service et âge minimum",
        blocks = listOf(
            LegalBlock.Paragraph("L’utilisation de MemoBook est autorisée à partir de 4 ans. Pour les utilisateurs mineurs de moins de 16 ans, l’accord d’un parent ou tuteur légal est requis. En utilisant le service, vous confirmez que vous êtes soit majeur, soit que vous avez obtenu cette autorisation parentale."),
        )
    )

    // 4. Description du service

    val service = LegalChapter(
        id = "cgu.service",
        number = 4,
        title = "Description du service",
        blocks = listOf(
            LegalBlock.Heading("4.1 Utilisation gratuite et crédit du jour"),
            LegalBlock.Paragraph("Sans abonnement, MemoBook permet à l’utilisateur de :"),
            LegalBlock.Bullets(listOf(
                "Enregistrer ou déposer des histoires orales",
                "Recevoir un carnet illustré généré automatiquement",
                "Accéder à une version numérique de son carnet",
            )),
            LegalBlock.Paragraph("Cette utilisation gratuite est limitée par un crédit du jour : chaque voyage peut recevoir 5 minutes de récit par jour, partagées entre ses participants non abonnés. Un enregistrement vocal consomme sa durée, un texte écrit consomme une minute pour 800 caractères, et les photos ne consomment rien."),
            LegalBlock.Paragraph("Le crédit se renouvelle chaque jour à minuit, à l’heure du téléphone de l’utilisateur. Lorsqu’il est épuisé, l’enregistrement en cours s’arrête : les contenus déjà enregistrés sont conservés, et le récit peut reprendre le lendemain ou sans limite avec un abonnement (chapitre 5)."),
            LegalBlock.Paragraph("MemoBook peut faire évoluer le service gratuit, notamment le montant du crédit du jour. Les changements importants sont annoncés dans l’application et ne s’appliquent jamais rétroactivement à une période d’abonnement déjà payée."),

            LegalBlock.Heading("4.2 Service d’impression et de livraison"),
            LegalBlock.Paragraph("MemoBook propose un service payant d’impression et de livraison physique des carnets, aux conditions suivantes :"),

            LegalBlock.Heading("Commande et paiement"),
            LegalBlock.Bullets(listOf(
                "Le prix de chaque commande est indiqué en euros toutes taxes comprises (TTC) au moment de la validation.",
                "La commande est définitivement enregistrée après confirmation du paiement.",
                "Le paiement s’effectue en ligne via un prestataire sécurisé. MemoBook ne conserve aucune donnée bancaire.",
            )),

            LegalBlock.Heading("Délais de production et livraison"),
            LegalBlock.Bullets(listOf(
                "Les délais de production sont indiqués au moment de la commande (généralement entre 5 et 10 jours ouvrés).",
                "Les délais de livraison s’ajoutent au délai de production selon le transporteur et la destination.",
                "Ces délais sont donnés à titre indicatif et peuvent être affectés par des circonstances exceptionnelles (grèves, intempéries, etc.).",
            )),

            LegalBlock.Heading("Droit de rétractation"),
            LegalBlock.Paragraph("Conformément à l’article L221-28 du Code de la consommation, le droit de rétractation de 14 jours ne s’applique pas aux biens personnalisés fabriqués sur mesure selon les spécifications du consommateur. Chaque carnet étant produit à la demande et personnalisé, il ne peut être ni repris ni échangé sauf en cas de défaut de fabrication avéré."),

            LegalBlock.Heading("Produit défectueux ou non conforme"),
            LegalBlock.Paragraph("Si vous recevez un produit endommagé ou non conforme à votre commande, vous devez nous contacter sous 14 jours calendaires après réception à l’adresse $contactLink, en joignant des photos du défaut. Nous procéderons alors à une réimpression ou un remboursement à notre discrétion."),
        )
    )

    // 5. Abonnement

    /**
     * L'abonnement mensuel (Hugo, 03/10/2026). Ce que les stores exigent d'un
     * abonnement à renouvellement automatique — prix, durée, renouvellement,
     * résiliation — et ce que le produit a décidé : l'illimité est personnel,
     * il reste ouvert jusqu'au bout de la période payée. Sur Android, il se
     * paie et se résilie par Google Play ; le jumeau iOS dit l'App Store.
     */
    val subscription = LegalChapter(
        id = "cgu.abonnement",
        number = 5,
        title = "Abonnement",
        blocks = listOf(
            LegalBlock.Paragraph("MemoBook propose un abonnement facultatif qui rend le récit illimité pour l’abonné : ses enregistrements vocaux et ses textes ne consomment pas le crédit du jour de ses voyages. L’abonnement est personnel ; il n’étend pas l’accès illimité aux autres participants d’un voyage, qui continuent de partager le crédit du jour."),

            LegalBlock.Heading("Prix et paiement"),
            LegalBlock.Bullets(listOf(
                "L’abonnement est un abonnement à renouvellement automatique, au prix de 4,99 € TTC par mois. Le prix applicable est celui affiché dans l’application au moment de la souscription.",
                "Sur Android, il est souscrit et payé via Google Play : le montant est prélevé avec le moyen de paiement de votre compte Google à la confirmation de l’achat, puis à chaque renouvellement. MemoBook ne reçoit ni ne conserve aucune donnée bancaire.",
                "Un abonnement souscrit sur un iPhone reste payé via l’App Store d’Apple, selon ses règles : il s’utilise aussi sur Android, avec le même compte MemoBook.",
                "Toute modification du prix vous est annoncée à l’avance, selon les règles de Google Play, et vous laisse la possibilité de résilier avant qu’elle ne s’applique.",
            )),

            LegalBlock.Heading("Renouvellement et résiliation"),
            LegalBlock.Bullets(listOf(
                "L’abonnement se renouvelle automatiquement chaque mois, au même prix, sauf résiliation au moins 24 heures avant la fin de la période en cours.",
                "Vous pouvez gérer et résilier votre abonnement à tout moment dans le Play Store (votre profil, Paiements et abonnements, puis Abonnements), ou sur play.google.com. Un abonnement souscrit sur un iPhone se résilie dans les réglages de cet iPhone.",
                "La résiliation prend effet à la fin de la période déjà payée : l’accès illimité reste ouvert jusqu’à cette date, puis le service revient à l’utilisation gratuite décrite au chapitre 4. Vos carnets et vos contenus sont conservés.",
                "Quand votre dernier voyage en cours se termine, MemoBook vous rappelle que vous pouvez résilier votre abonnement.",
            )),

            LegalBlock.Heading("Remboursement"),
            LegalBlock.Paragraph("Une période commencée est due : la résiliation n’entraîne aucun remboursement au prorata de la période en cours. Les demandes de remboursement suivent les règles de Google Play : elles se font depuis l’historique des commandes de votre compte Google Play ([play.google.com](https://play.google.com)), ou en nous écrivant à $contactLink. Celles d’un abonnement souscrit sur un iPhone sont traitées par Apple, depuis [reportaproblem.apple.com](https://reportaproblem.apple.com)."),
        )
    )

    // 6. Propriété intellectuelle

    val intellectualProperty = LegalChapter(
        id = "cgu.propriete-intellectuelle",
        number = 6,
        title = "Propriété intellectuelle",
        blocks = listOf(
            LegalBlock.Heading("6.1 Vos contenus"),
            LegalBlock.Paragraph("Vous restez propriétaire de l’intégralité des contenus que vous soumettez (histoires, enregistrements, photos). En utilisant MemoBook, vous nous accordez une licence limitée, non exclusive, pour traiter ces contenus dans le seul but de générer votre carnet personnalisé. Vos données ne sont jamais utilisées à des fins commerciales ou partagées avec des tiers."),
            LegalBlock.Heading("6.2 Nos contenus"),
            LegalBlock.Paragraph("Le nom MemoBook, le logo, le site et les éléments graphiques sont la propriété exclusive d’Hugo Jouffre. Toute reproduction sans autorisation écrite est interdite."),
        )
    )

    // 7. Responsabilité

    val liability = LegalChapter(
        id = "cgu.responsabilite",
        number = 7,
        title = "Responsabilité",
        blocks = listOf(
            LegalBlock.Paragraph("MemoBook est fourni « en l’état ». Nous ne garantissons pas une disponibilité continue du service. MemoBook ne saurait être tenu responsable des dommages indirects liés à l’utilisation ou à l’impossibilité d’utiliser le service."),
        )
    )

    // 8. Données personnelles

    val personalData = LegalChapter(
        id = "cgu.donnees-personnelles",
        number = 8,
        title = "Données personnelles",
        blocks = listOf(
            LegalBlock.Paragraph("Vos données sont traitées conformément à notre Politique de confidentialité, disponible dans l’app. Vous disposez d’un droit d’accès, de rectification et de suppression de vos données en écrivant à $contactLink."),
        )
    )

    // 9. Loi applicable et juridiction

    val law = LegalChapter(
        id = "cgu.loi-applicable",
        number = 9,
        title = "Loi applicable et juridiction",
        blocks = listOf(
            LegalBlock.Paragraph("Les présentes CGU sont soumises au droit français. En cas de litige, les parties s’engagent à rechercher une solution amiable. À défaut, le litige sera soumis aux tribunaux compétents de Lyon."),
        )
    )

    // 10. Modifications

    val changes = LegalChapter(
        id = "cgu.modifications",
        number = 10,
        title = "Modifications",
        blocks = listOf(
            LegalBlock.Paragraph("MemoBook se réserve le droit de modifier les présentes CGU à tout moment. Les utilisateurs seront informés des modifications significatives via le site. La poursuite de l’utilisation du service après modification vaut acceptation des nouvelles conditions."),
        )
    )
}
