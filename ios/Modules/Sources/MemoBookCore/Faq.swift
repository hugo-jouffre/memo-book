import Foundation

// La foire aux questions de l'app, recopiée de la page Notion « FAQ in-app
// MemoBook » (version 1.0) qui en est la source de vérité rédactionnelle.
// Relue **en entier** sur la page du 29/09/2026 (Hugo) : vingt réponses
// réécrites, une question de plus (« Comment marche l'abonnement ? »), quatre
// variables de plus, et les deux questions de la carte retirées — « La carte
// est prévue pour la V2 de l'app. Les deux questions qui la concernent ne sont
// publiées qu'au moment où la carte sort. »
//
// **Le paquet « Prix et paiement » a été réécrit le 03/10/2026** (Hugo), avec
// le crédit du jour : plus d'étapes offertes ni d'abonnement à la semaine. Le
// récit est gratuit dans la limite de cinq minutes par jour et par voyage,
// l'abonnement mensuel le rend illimité. Une question de plus
// (`faq.prix.credit-du-jour`), deux variables de plus, et les réponses de
// « Découvrir » et « Raconter » qui promettaient de parler sans compter
// disent désormais où est la limite. Ce fichier se corrige directement, sans
// repasser par la page Notion.
//
// **Les règles de rédaction de cette page tiennent dans le temps**, et elles
// expliquent la forme de ce fichier :
//
//   - Tutoiement partout, même ton que MEMO dans la conversation.
//   - Vocabulaire : **carnet**, **souvenirs**, **voyageurs**. Jamais « livre »,
//     jamais « utilisateur », jamais « client ». « Carnet » a perdu sa
//     majuscule le 06/10/2026, avec toutes les majuscules à l'anglaise de
//     l'app (T213).
//   - **Une réponse dit ce que l'app fait aujourd'hui** (T202, 06/10/2026) :
//     chaque réponse a été relue contre le code, et celles qui promettaient
//     une option, un contrôle ou un écran qui n'existe pas ont été réécrites.
//     Ce qui manque encore passe par « Écris à notre équipe ».
//   - Aucune réponse ne se termine par un refus sec : chaque limite est suivie
//     d'une alternative actionnable.
//   - Les valeurs qui bougent — prix, délais, seuils, prestataires — sont des
//     variables `{{…}}` résolues **à l'affichage** (voir ``FaqVariables``), et
//     jamais écrites en dur dans une réponse.
//   - Chaque question porte un identifiant stable `faq.categorie.slug` qui ne
//     change **jamais**, même si le texte est réécrit : il porte les
//     traductions, les liens profonds et les statistiques de consultation.
//
// ⚠️ **Trois points de la page Notion ne sont pas encore tenus ici**, et c'est
// délibéré plutôt qu'oublié :
//
//   1. « Contenu servi depuis une source distante, pas figé dans le binaire,
//      pour corriger une réponse sans passer par une mise à jour App Store. »
//      Le contenu est statique pour l'instant, mais ``SupportModel`` le reçoit
//      par une fonction : le jour où la route existe, seul ce branchement
//      change, pas l'écran.
//   2. Le champ « mots-clés par question » de la recherche interne n'existe
//      toujours pas. L'écran a désormais **une recherche** (Hugo, 16/09/2026),
//      mais elle cherche dans la question, dans la réponse et dans le titre du
//      paquet — voir ``FaqQuery`` —, ce qui couvre ce que des mots-clés
//      auraient couvert sans demander à Clara d'en écrire quarante-cinq jeux.
//      Le champ reste à ajouter le jour où une réponse doit se trouver sur un
//      mot qu'elle n'emploie pas.
//   3. Une entrée par langue rattachée au même identifiant. L'app est en
//      français seul aujourd'hui ; l'identifiant est déjà là pour porter le
//      reste.

/// Les valeurs qui bougent, et que les réponses appellent par leur nom.
///
/// La page Notion est formelle : un prix, un délai, un seuil ou un nom de
/// prestataire ne s'écrit jamais dans une phrase. Il s'écrit `{{nom}}` et se
/// résout au moment de l'affichage — sinon corriger un tarif demande de relire
/// quarante réponses pour en trouver trois.
public struct FaqVariables: Sendable, Hashable {
    /// Le nombre de pages minimum d’un carnet relié.
    ///
    /// **Imposé par la reliure**, pas par nous : en dessous, l'imprimeur ne sait
    /// pas coudre le dos. À revoir si la reliure ou l'imprimeur change.
    public var minimumPageCount: Int

    /// « 4,99 € » — le prix de l'abonnement par mois, écrit comme on le lit.
    /// Affiché dans `faq.prix.app`, `faq.prix.credit-du-jour` et
    /// `faq.prix.abonnement`, résolu à l'affichage et jamais écrit en dur.
    ///
    /// Le même que `SUBSCRIPTION_MONTHLY_CENTS` côté serveur et que le repli du
    /// paywall ; le prix qui fait foi à l'achat est celui que StoreKit affiche.
    public var monthlyPrice: String

    /// « 5 minutes » — le crédit du jour d'un voyage, à partager entre ses
    /// co-voyageurs non abonnés. Le même que `DAILY_CREDIT_LIMIT_MS` côté
    /// serveur (``DailyCredit/Catalog``).
    public var dailyCredit: String

    /// « 800 caractères » — ce qui, à l'écrit, consomme une minute de crédit
    /// (75 ms par caractère, `TEXT_MS_PER_CHARACTER`).
    public var charactersPerMinute: String

    /// « 5 ans » — combien de temps les souvenirs restent accessibles après le
    /// voyage. Doit rester aligné mot pour mot avec la politique de
    /// confidentialité.
    public var retention: String

    /// « encore en plein développement » — dans l'en-tête de la modale « Nous
    /// contacter » côté suggestion. À revoir dès que l'app n'est plus perçue
    /// comme jeune, sinon la phrase sonnera faux dans un an.
    public var developmentStatus: String

    public init(
        minimumPageCount: Int,
        monthlyPrice: String = "4,99 €",
        dailyCredit: String = "5 minutes",
        charactersPerMinute: String = "800 caractères",
        retention: String = "5 ans",
        developmentStatus: String = "encore en plein développement"
    ) {
        self.minimumPageCount = minimumPageCount
        self.monthlyPrice = monthlyPrice
        self.dailyCredit = dailyCredit
        self.charactersPerMinute = charactersPerMinute
        self.retention = retention
        self.developmentStatus = developmentStatus
    }

    /// Les valeurs en vigueur. Elles viendront d'une configuration distante le
    /// jour où il y en aura une ; en attendant, elles sont ici, à un seul
    /// endroit, et non dans le texte des réponses.
    public static let current = FaqVariables(minimumPageCount: 16)

    /// Remplace les `{{…}}` d'une réponse par les valeurs du moment.
    ///
    /// Une variable inconnue est **laissée telle quelle** plutôt qu'effacée :
    /// « {{delai_livraison}} » dans l'app se voit et se corrige, une phrase
    /// amputée passe inaperçue.
    public func resolve(_ text: String) -> String {
        text
            .replacingOccurrences(of: "{{nb_pages_min}}", with: String(minimumPageCount))
            .replacingOccurrences(of: "{{prix_abo_mensuel}}", with: monthlyPrice)
            .replacingOccurrences(of: "{{credit_jour}}", with: dailyCredit)
            .replacingOccurrences(of: "{{caracteres_par_minute}}", with: charactersPerMinute)
            .replacingOccurrences(of: "{{duree_conservation}}", with: retention)
            .replacingOccurrences(of: "{{statut_developpement}}", with: developmentStatus)
    }
}

/// Une question et sa réponse.
public struct FaqEntry: Sendable, Hashable, Identifiable {
    /// `faq.categorie.slug` — immuable. C'est lui que pointe un lien profond
    /// depuis un écran, et lui que compte la mesure « cette réponse t'a-t-elle
    /// aidé ».
    public let id: String
    public let question: String

    /// La réponse, **paragraphe par paragraphe**. Une liste et non une chaîne à
    /// `\n` : l'écart entre deux paragraphes est une mesure du design system, et
    /// une ligne vide ne se lit pas à VoiceOver.
    public let answer: [String]

    public init(id: String, question: String, answer: [String]) {
        self.id = id
        self.question = question
        self.answer = answer
    }

    /// La réponse prête à afficher, variables résolues.
    public func answer(with variables: FaqVariables = .current) -> [String] {
        answer.map(variables.resolve)
    }

    /// Cette question répond-elle à ce qu'on cherche ?
    ///
    /// **La question et la réponse, toutes les deux.** Quelqu'un qui tape
    /// « remboursement » ne cherche pas un titre, il cherche une phrase — et
    /// aucun des quarante-cinq titres ne porte ce mot alors que trois réponses
    /// le portent. Chercher dans les seuls titres aurait rendu le champ
    /// décevant sur exactement les mots qu'on tape quand on est bloqué.
    ///
    /// Les variables sont résolues avant la comparaison : on doit pouvoir
    /// trouver « 16 pages » alors que le texte dit `{{nb_pages_min}}`.
    public func matches(_ query: FaqQuery, variables: FaqVariables = .current) -> Bool {
        guard !query.isEmpty else { return true }
        return query.matches(question) || answer(with: variables).contains(where: query.matches)
    }
}

/// Un paquet de questions. Les dix titres sont ceux de la page Notion.
public struct FaqCategory: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let entries: [FaqEntry]

    public init(id: String, title: String, entries: [FaqEntry]) {
        self.id = id
        self.title = title
        self.entries = entries
    }

    /// Le même paquet, réduit à ce qui répond. `nil` quand plus rien n'y
    /// répond : un paquet vide se retire de l'écran entier plutôt que de
    /// laisser un titre de section sans lignes dessous.
    ///
    /// **Le titre du paquet compte aussi.** Taper « photos » doit rendre le
    /// paquet « Photos et souvenirs » en entier, même si le mot ne figure dans
    /// aucune de ses questions : on cherche souvent le rayon avant l'article.
    public func filtered(by query: FaqQuery, variables: FaqVariables = .current) -> FaqCategory? {
        guard !query.isEmpty else { return self }
        if query.matches(title) { return self }

        let kept = entries.filter { $0.matches(query, variables: variables) }
        guard !kept.isEmpty else { return nil }
        return FaqCategory(id: id, title: title, entries: kept)
    }
}

/// Ce qu'on a tapé dans le champ de recherche, préparé une seule fois.
///
/// **Le travail est fait à la construction, pas à chaque comparaison.** Une
/// recherche vivante rejoue le filtre à chaque caractère sur quarante-cinq
/// questions et leurs réponses : normaliser la requête une fois par frappe au
/// lieu d'une fois par comparaison, c'est deux ordres de grandeur.
///
/// La comparaison ignore la **casse** et les **accents** : on tape « reglage »
/// et on trouve « réglage », ce que personne ne pense à faire marcher et que
/// tout le monde remarque quand ça ne marche pas.
public struct FaqQuery: Sendable, Hashable {
    private let needles: [String]

    /// La requête brute, telle qu'elle est tapée. L'écran l'affiche.
    public let raw: String

    public init(_ raw: String) {
        self.raw = raw
        // Chaque mot compte séparément : « carnet papier » doit trouver une
        // réponse qui parle du « papier du carnet ». Un seul bloc n'aurait
        // trouvé que la suite exacte.
        needles = Self.folded(raw)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    public var isEmpty: Bool { needles.isEmpty }

    /// Tous les mots de la requête, et non un seul : ajouter un mot **réduit**
    /// les résultats, comme partout ailleurs.
    public func matches(_ text: String) -> Bool {
        guard !needles.isEmpty else { return true }
        let haystack = Self.folded(text)
        return needles.allSatisfy { haystack.contains($0) }
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

/// La foire aux questions elle-même.
public enum Faq {
    /// Les neuf paquets de « sujets courants ».
    ///
    /// Le dixième de la page Notion — « Aide et contact » — n'est pas ici : il
    /// vit dans ``contact``, parce que l'écran en fait une section à part
    /// (« NOUS CONTACTER ») et non un sujet parmi d'autres.
    public static let topics: [FaqCategory] = [
        discover, tell, photos, ai, printedBook, sharing, mapAndTrips, privacy, pricing,
    ]

    /// Toutes les questions, tous paquets confondus — y compris celles de la
    /// section « Nous contacter ».
    public static var entries: [FaqEntry] {
        (topics + [contact]).flatMap(\.entries)
    }

    /// La question que pointe un identifiant.
    ///
    /// C'est ce que la page Notion appelle le contextuel : « Chaque écran de
    /// l'app peut pointer vers une question précise par son identifiant, plutôt
    /// que vers la FAQ entière. »
    public static func entry(id: String) -> FaqEntry? {
        entries.first { $0.id == id }
    }

    // MARK: - 1. Découvrir MemoBook

    public static let discover = FaqCategory(
        id: "faq.decouvrir",
        title: "Découvrir MemoBook",
        entries: [
            FaqEntry(
                id: "faq.decouvrir.cest-quoi",
                question: "MemoBook, c’est quoi exactement ?",
                answer: [
                    "MemoBook transforme ta voix en carnet de voyage.",
                    "Tu racontes tes journées à l’oral, tu ajoutes tes photos, et ton carnet se construit tout seul.",
                    "Tu peux le partager en version numérique tout le long de sa création, et le recevoir imprimé chez toi une fois terminé.",
                ]
            ),
            FaqEntry(
                id: "faq.decouvrir.pendant-ou-apres",
                question: "Je raconte pendant le voyage ou au retour ?",
                answer: [
                    "Pendant, idéalement le soir même ou le lendemain.",
                    "C’est là que les détails sont encore frais, et deux minutes de voix suffisent pour une étape.",
                    "Si tu es déjà rentré, tu peux tout raconter au fil des jours, ou d’un coup avec l’abonnement : le carnet se construira de la même façon.",
                ]
            ),
            FaqEntry(
                id: "faq.decouvrir.savoir-ecrire",
                question: "Il faut savoir écrire pour faire un beau carnet ?",
                answer: [
                    "Non. Tu parles normalement, comme si tu racontais ta journée à un proche.",
                    "L’écriture, la mise en forme et la mise en page sont prises en charge.",
                ]
            ),
            FaqEntry(
                id: "faq.decouvrir.type-de-voyage",
                question: "Ça marche pour quel type de voyage ?",
                answer: [
                    "Un tour du monde, un week-end, une randonnée, un road trip, un voyage professionnel, un moment de vie important.",
                    "Il n’y a pas de durée minimum imposée par le format.",
                    "À noter qu’un carnet imprimé fait au minimum {{nb_pages_min}} pages : un récit trop court donne un carnet avec des pages blanches.",
                    "Avant de commander, feuillette son aperçu, et ajoute des étapes s’il te semble encore trop court.",
                ]
            ),
            FaqEntry(
                id: "faq.decouvrir.hors-voyage",
                question: "Je peux l’utiliser pour autre chose qu’un voyage ?",
                answer: [
                    "Oui. Beaucoup de carnets racontent une année, une naissance, une rénovation, un projet.",
                    "La mécanique reste la même : tu racontes à voix haute, étape après étape.",
                ]
            ),
        ]
    )

    // MARK: - 2. Raconter tes souvenirs

    public static let tell = FaqCategory(
        id: "faq.raconter",
        title: "Raconter tes souvenirs",
        entries: [
            FaqEntry(
                id: "faq.raconter.comment",
                question: "Comment j’enregistre un souvenir ?",
                answer: [
                    "Dans la conversation, tu appuies sur le micro et tu parles.",
                    "Tu peux aussi lancer un enregistrement rapide depuis l’écran d’accueil : quand tu t’arrêtes, la conversation de ton voyage en cours s’ouvre, ton message déjà posé.",
                    "Ton récit est transcrit automatiquement, puis mis en forme.",
                    "Tu peux relire et corriger chaque étape à tout moment, à la main depuis sa fiche, et supprimer un souvenir depuis l’accueil de ton voyage.",
                ]
            ),
            FaqEntry(
                id: "faq.raconter.enregistrement-rapide",
                question: "Où va un enregistrement rapide si j’ai plusieurs récits en cours ?",
                answer: [
                    "Le plus souvent tu n’as qu’un seul récit en cours, et ton souvenir y est ajouté directement.",
                    "Si tu en as plusieurs, il va dans celui que tu as commencé le plus récemment, et sa conversation s’ouvre dès que tu t’arrêtes : tu vois tout de suite où il est arrivé.",
                    "Pour raconter un autre voyage, lance l’enregistrement depuis sa conversation : il n’est ajouté qu’à celui-ci.",
                ]
            ),
            FaqEntry(
                id: "faq.raconter.duree",
                question: "Combien de temps je dois parler ?",
                answer: [
                    "Autant que tu veux avec l’abonnement. Sans lui, ton voyage peut raconter {{credit_jour}} par jour, de quoi bien raconter une journée.",
                    "Une minute donne un récit court, deux ou trois minutes donnent une étape bien remplie.",
                    "MEMO te dit combien de photos remplissent la page de ton étape, d’après la longueur de ton texte : plus il est long, plus il en faut. Une étape tient sur une ou deux pages ; si tu as encore à raconter, fais-en une nouvelle étape.",
                ]
            ),
            FaqEntry(
                id: "faq.raconter.plusieurs-fois",
                question: "Je peux enregistrer plusieurs fois pour la même étape ?",
                answer: [
                    "Pas à la voix : chaque vocal devient sa propre étape.",
                    "Pour compléter une étape avant de la valider, écris à MEMO ce qui manque — un prénom, un lieu, un détail : il reprend le texte avec. Ce que tu écris compte dans le crédit du jour si tu n’es pas abonné.",
                    "Et si tu as oublié tout un moment, raconte-le dans un nouveau vocal : il fera une étape de plus.",
                ]
            ),
            FaqEntry(
                id: "faq.raconter.hors-ligne",
                question: "Et si je n’ai pas de réseau ?",
                answer: [
                    "Tes enregistrements et tes photos sont conservés sur ton téléphone et se synchronisent dès que la connexion revient.",
                    "Tu peux donc continuer à raconter en avion, en montagne ou sans forfait local.",
                    "Si le crédit du jour est épuisé quand ils partent, ils attendent sur ton téléphone, marqués « Partira demain », et repartent tout seuls après minuit, dès que tu rouvres l’app.",
                    "Un vocal plus long que {{credit_jour}} ne tient dans aucune journée : il attend que tu passes en illimité, ou tu le supprimes depuis sa bulle.",
                ]
            ),
            FaqEntry(
                id: "faq.raconter.bruit",
                question: "Il y a du bruit autour de moi, ça pose problème ?",
                answer: [
                    "Rarement. La transcription tolère bien les environnements sonores courants.",
                    "Si un mot est mal compris, corrige le texte à la main depuis sa fiche, ou écris à MEMO le bon mot : il reprend le texte avec.",
                ]
            ),
            FaqEntry(
                id: "faq.raconter.langue",
                question: "Je peux raconter dans une autre langue ?",
                answer: [
                    "Pour le moment, MemoBook fonctionne en français : c’est la langue dans laquelle ton récit est transcrit et rédigé.",
                    "Les mots d’ailleurs qui font partie de ta façon de raconter sont gardés tels quels ; si l’un d’eux est mal transcrit, corrige-le à la main depuis sa fiche.",
                    "D’autres langues arriveront plus tard.",
                ]
            ),
            FaqEntry(
                id: "faq.raconter.plusieurs-voix",
                question: "On peut être plusieurs à raconter le même voyage ?",
                answer: [
                    "Oui. Invite tes co-voyageurs depuis les paramètres du voyage : tout le monde raconte dans la même conversation.",
                    "Quand le voyage compte plusieurs voyageurs, le prénom des autres s’affiche au-dessus de leurs messages, et chaque message porte la photo ou les initiales de celui qui parle.",
                    "Dans le carnet imprimé, les récits de tous sont réunis en une seule voix, du début à la fin.",
                ]
            ),
            FaqEntry(
                id: "faq.raconter.ecrire-au-clavier",
                question: "Je peux écrire au clavier plutôt que parler ?",
                answer: [
                    "Oui. Dans la conversation, le clavier est toujours à côté du micro, et le résultat est identique.",
                    "L’enregistrement rapide de l’accueil, lui, ne prend que la voix : pour écrire, ouvre la conversation de ton voyage.",
                    "Pour le crédit du jour, {{caracteres_par_minute}} écrits valent une minute de vocal.",
                ]
            ),
            FaqEntry(
                id: "faq.raconter.supprimer",
                question: "Je peux supprimer un souvenir que je regrette ?",
                answer: [
                    "Oui. Dans l’accueil de ton voyage, fais glisser la carte de son étape vers la gauche, puis touche la croix.",
                    "Le souvenir quitte ton carnet. Une commande déjà passée, elle, est imprimée telle que tu l’as validée.",
                ]
            ),
        ]
    )

    // MARK: - 3. Photos

    public static let photos = FaqCategory(
        id: "faq.photos",
        title: "Photos",
        entries: [
            FaqEntry(
                id: "faq.photos.combien",
                question: "Combien de photos par étape ?",
                answer: [
                    "Cela dépend de la longueur du texte de ton étape.",
                    "Quand tu valides ton texte, MEMO te dit combien de photos remplissent sa page : davantage pour un récit long, qui s’étend sur deux pages.",
                    "Tu peux en mettre moins : la mise en page s’adapte.",
                ]
            ),
            FaqEntry(
                id: "faq.photos.pourquoi-minimum",
                question: "Pourquoi MEMO me demande un nombre précis de photos ?",
                answer: [
                    "C’est le nombre qui remplit la page de ton étape sans laisser de blanc, d’après la longueur de ton texte.",
                    "Ce n’est pas une obligation : si tu en as moins, envoie celles que tu as, la mise en page s’adapte.",
                ]
            ),
            FaqEntry(
                id: "faq.photos.qualite",
                question: "Quelle qualité de photo faut-il pour l’impression ?",
                answer: [
                    "Les photos prises avec un téléphone récent conviennent.",
                    "Choisis toujours la version la plus grande que tu as : une photo récupérée d’une messagerie ou d’une capture d’écran est souvent trop compressée. Feuillette l’aperçu avant de commander pour vérifier qu’elle rend bien.",
                ]
            ),
            FaqEntry(
                id: "faq.photos.provenance",
                question: "Je peux importer des photos prises avec un appareil photo ?",
                answer: [
                    "Oui, dès qu’elles sont dans la photothèque de ton téléphone.",
                    "Pour retrouver celles d’un jour précis, utilise la recherche du sélecteur de photos de ton iPhone.",
                ]
            ),
            FaqEntry(
                id: "faq.photos.ordre",
                question: "Je peux choisir l’ordre et le cadrage ?",
                answer: [
                    "Pas pour l’instant. Les photos sont placées automatiquement par la mise en page, qui les répartit pour que la page reste équilibrée.",
                    "Ce que tu choisis, ce sont les photos elles-mêmes : tu peux en ajouter à tout moment depuis la conversation. Pour en retirer une déjà envoyée, écris-nous avec « Écris à notre équipe », en bas de cette page : on l’enlève pour toi.",
                ]
            ),
        ]
    )

    // MARK: - 4. Le rôle de l'IA

    public static let ai = FaqCategory(
        id: "faq.ia",
        title: "Le rôle de l’IA",
        entries: [
            FaqEntry(
                id: "faq.ia.ce-quelle-fait",
                question: "Qu’est-ce que l’IA fait exactement sur mon texte ?",
                answer: [
                    "Elle transcrit ta voix, corrige la ponctuation, structure le récit et le rend agréable à lire.",
                    "Elle ne remplace pas ton histoire, elle la met en forme.",
                ]
            ),
            FaqEntry(
                id: "faq.ia.invente",
                question: "Est-ce que l’IA invente des choses ?",
                answer: [
                    "Dans ton récit, elle n’ajoute ni lieux, ni dates, ni moments que tu n’as pas racontés. Les seuls ajouts sont les encarts « Fun fact » : une info de culture générale sur un lieu que tu as visité, toujours à part de ton récit.",
                    "Si une formulation ne te ressemble pas, tu modifies le texte directement : ta version prime toujours.",
                ]
            ),
            FaqEntry(
                id: "faq.ia.ton",
                question: "Je peux choisir le ton du récit ?",
                answer: [
                    "Pas directement : MEMO reprend le ton de tes vocaux — ton humour, tes mots — et le garde d’un bout à l’autre du carnet.",
                    "Pour orienter le vocabulaire des prochaines étapes, choisis le thème de ton aventure dans les paramètres du voyage. Et si une phrase ne te ressemble pas, corrige-la à la main : ta version prime.",
                ]
            ),
            FaqEntry(
                id: "faq.ia.texte-brut",
                question: "Je veux garder mes mots exacts, sans réécriture",
                answer: [
                    "Il n’y a pas d’option pour garder la transcription brute : chaque étape est relue et mise en forme pour se lire sur papier.",
                    "Pour garder tes mots exacts, corrige le texte à la main depuis sa fiche : c’est ta version qui entre dans le carnet, et MEMO n’y retouche plus.",
                ]
            ),
        ]
    )

    // MARK: - 5. Le carnet imprimé

    public static let printedBook = FaqCategory(
        id: "faq.carnet",
        title: "Le carnet imprimé",
        entries: [
            FaqEntry(
                id: "faq.carnet.apercu",
                question: "Je peux voir mon carnet avant de le commander ?",
                answer: [
                    "Oui. L’aperçu s’ouvre à tout moment depuis la conversation, l’accueil de ton voyage ou ses paramètres, et ton carnet se recompose avec tes dernières étapes à chaque ouverture.",
                    "Tu vois exactement les pages qui seront imprimées.",
                ]
            ),
            FaqEntry(
                id: "faq.carnet.pages",
                question: "Combien de pages fait un carnet ?",
                answer: [
                    "Cela dépend d’abord de la durée de ton voyage, qui conditionne en grande partie le nombre d’étapes racontées et de photos ajoutées.",
                    "La reliure impose un minimum de {{nb_pages_min}} pages : feuillette l’aperçu avant de commander, et ajoute des étapes si ton carnet est encore trop court.",
                    "Chaque étape tient sur une ou deux pages.",
                ]
            ),
            FaqEntry(
                id: "faq.carnet.densite",
                question: "C’est quoi la densité de mise en page ?",
                answer: [
                    "C’est la quantité de contenu par page.",
                    "Aujourd’hui, chaque étape est mise en page en format compact : une page au minimum, deux au maximum.",
                    "Le format aéré, plus contemplatif, arrivera dans une prochaine version de l’app.",
                ]
            ),
            FaqEntry(
                id: "faq.carnet.couverture",
                question: "Je choisis la couverture ?",
                answer: [
                    "Oui. Tu composes la première et la quatrième de couverture : titre, visuel et texte de dos.",
                ]
            ),
            FaqEntry(
                id: "faq.carnet.modifier-apres",
                question: "Je peux modifier mon carnet après l’avoir commandé ?",
                answer: [
                    "Ton carnet est imprimé tel que tu l’as vu dans l’aperçu au moment de commander : ce que tu modifies ensuite n’entre pas dans cette commande.",
                    "Continue à raconter et à corriger, puis commande un nouvel exemplaire avec la version à jour.",
                ]
            ),
            FaqEntry(
                id: "faq.carnet.exemplaires",
                question: "Je peux en commander plusieurs exemplaires ?",
                answer: [
                    "Oui, en une seule commande ou plus tard.",
                    "Chaque exemplaire est au même prix, affiché avant le paiement. Regroupés dans une même commande, ils partent ensemble, en une seule livraison.",
                ]
            ),
            FaqEntry(
                id: "faq.carnet.livraison",
                question: "Quels sont les délais et les frais de livraison ?",
                answer: [
                    "Avant de payer, tu choisis entre la livraison standard, incluse, et une livraison rapide en supplément : le délai estimé et le montant exact s’affichent avant le paiement.",
                    "Ensuite, tu retrouves le délai annoncé de chaque commande dans ton profil, à « Suivi des commandes ».",
                ]
            ),
            FaqEntry(
                id: "faq.carnet.abime",
                question: "Mon carnet est arrivé abîmé ou avec un défaut d’impression",
                answer: [
                    "Écris-nous avec « Écris à notre équipe », en bas de cette page, en décrivant le problème : on te répond par e-mail, et tu pourras alors nous envoyer une photo ou une courte vidéo.",
                    "Sur présentation de cette preuve, un nouvel exemplaire est réimprimé et réexpédié sans frais.",
                ]
            ),
        ]
    )

    // MARK: - 6. Partage numérique

    public static let sharing = FaqCategory(
        id: "faq.partage",
        title: "Partage numérique",
        entries: [
            FaqEntry(
                id: "faq.partage.comment",
                question: "Je peux partager mon carnet sans l’imprimer ?",
                answer: [
                    "Oui, de deux façons.",
                    "Le lien de prévisualisation ouvre une page web, sans avoir l’app MemoBook : le titre de ton carnet, sa couverture, ses étapes et les premières lignes de ton récit, à jour au moment où on l’ouvre. La copie du PDF montre le carnet entier, mais le fige tel qu’il était au moment du partage.",
                ]
            ),
            FaqEntry(
                id: "faq.partage.pendant-le-voyage",
                question: "Je peux partager mon voyage en cours de route ?",
                answer: [
                    "Oui, avec le lien de prévisualisation : la page suit chaque nouvelle étape, sans que tu aies à renvoyer le lien. Une copie du PDF reste figée à la date à laquelle tu l’as partagée.",
                ]
            ),
            FaqEntry(
                id: "faq.partage.qui-voit",
                question: "Qui peut voir ce que je partage ?",
                answer: [
                    "Uniquement les personnes à qui tu transmets le lien ou le PDF.",
                    "Rien n’est public par défaut : ton carnet n’apparaît dans la galerie de la communauté que si tu l’actives dans les paramètres du voyage, et tu peux l’en retirer à tout moment.",
                ]
            ),
            FaqEntry(
                id: "faq.partage.pdf",
                question: "Je peux récupérer un fichier de mon carnet ?",
                answer: [
                    "Oui, tu peux exporter ton carnet pour le conserver ou l’archiver de ton côté.",
                ]
            ),
        ]
    )

    // MARK: - 7. Carte et voyages

    /// Sans la carte : « À quoi sert la carte ? » et « MemoBook suit ma position
    /// en continu ? » attendent la V2 avec elle. Le paquet garde son titre —
    /// c'est celui de la page — et sa seule question sur les voyages.

    public static let mapAndTrips = FaqCategory(
        id: "faq.carte",
        title: "Carte et voyages",
        entries: [
            FaqEntry(
                id: "faq.voyages.plusieurs",
                question: "Je peux avoir plusieurs voyages en même temps ?",
                answer: [
                    "Oui, autant que tu le souhaites.",
                    "Chaque voyage a sa conversation, son carnet et son propre crédit du jour.",
                ]
            ),
        ]
    )

    // MARK: - 8. Compte, données et confidentialité

    public static let privacy = FaqCategory(
        id: "faq.donnees",
        title: "Compte, données et confidentialité",
        entries: [
            FaqEntry(
                id: "faq.donnees.qui-y-accede",
                question: "Qui a accès à mes souvenirs ?",
                answer: [
                    "Toi, et les personnes que tu invites sur un voyage partagé.",
                    "Si tu actives « Partager sur la galerie de la communauté », son titre, sa photo de couverture et ses destinations deviennent visibles des autres voyageurs MemoBook ; ton récit, lui, reste privé, et tu peux couper ce partage à tout moment.",
                    "Tes récits ne sont jamais utilisés à des fins publicitaires.",
                ]
            ),
            FaqEntry(
                id: "faq.donnees.ia-entrainement",
                question: "Mes récits servent-ils à entraîner des IA ?",
                answer: [
                    "Non. Tes contenus sont traités uniquement pour produire ton carnet.",
                    "Les prestataires techniques utilisés pour la transcription et la mise en forme sont engagés contractuellement à ne pas les réutiliser.",
                ]
            ),
            FaqEntry(
                id: "faq.donnees.conservation",
                question: "Combien de temps mes souvenirs sont-ils conservés ?",
                answer: [
                    "Tes souvenirs, tes photos et tes enregistrements restent accessibles pendant {{duree_conservation}} après ton voyage.",
                    "Passé ce délai, ils sont archivés, et seule la version imprimable de ton carnet est conservée à vie : tu peux en recommander un exemplaire même des années plus tard.",
                    "Tu peux supprimer un souvenir depuis l’accueil de ton voyage, un voyage que tu as créé depuis ses paramètres, ou toutes tes données en supprimant ton compte depuis ton profil.",
                ]
            ),
            FaqEntry(
                id: "faq.donnees.export",
                question: "Je peux récupérer toutes mes données ?",
                answer: [
                    "Oui, depuis ton profil, en touchant « Exporter mes données » : on t’envoie par e-mail un lien pour télécharger une archive avec tes textes, tes photos, tes vocaux et tes carnets en PDF.",
                ]
            ),
            FaqEntry(
                id: "faq.donnees.suppression-compte",
                question: "Comment supprimer mon compte ?",
                answer: [
                    "Depuis ton profil, à « Supprimer mon compte ».",
                    "La suppression est définitive : tes voyages, souvenirs, photos et enregistrements sont effacés, mais les voyages que tu partages restent à tes co-voyageurs, avec ce que tu y as raconté.",
                    "Ton abonnement, lui, se résilie dans les réglages de ton iPhone. Pour seulement faire une pause, supprime plutôt un voyage précis depuis ses paramètres.",
                ]
            ),
            FaqEntry(
                id: "faq.donnees.changement-telephone",
                question: "Je change de téléphone, je perds tout ?",
                answer: [
                    "Non. Tes voyages sont rattachés à ton compte et tu les retrouves en te reconnectant.",
                    "Avant de changer d’appareil, ouvre l’app connecté à internet et vérifie qu’aucun message n’attend encore dans tes conversations : ce qui n’est pas parti reste sur l’ancien téléphone.",
                ]
            ),
        ]
    )

    // MARK: - 9. Prix et paiement

    public static let pricing = FaqCategory(
        id: "faq.prix",
        title: "Prix et paiement",
        entries: [
            FaqEntry(
                id: "faq.prix.app",
                question: "L’application est payante ?",
                answer: [
                    "Non, l’app est gratuite : {{credit_jour}} peuvent être racontées par jour pour chaque voyage, à partager entre ses co-voyageurs qui ne sont pas abonnés.",
                    "Ça compte à l’oral comme à l’écrit. Tes photos, elles, ne comptent jamais.",
                    "Pour raconter sans compter, l’abonnement à {{prix_abo_mensuel}} par mois rend ton récit illimité.",
                    "Le carnet imprimé se paie à part, au moment de la commande.",
                ]
            ),
            FaqEntry(
                id: "faq.prix.credit-du-jour",
                question: "Comment marche le crédit du jour ?",
                answer: [
                    "Chaque voyage dispose de {{credit_jour}} de récit par jour, à partager entre les co-voyageurs qui ne sont pas abonnés.",
                    "Un message vocal consomme sa durée, et {{caracteres_par_minute}} écrits valent une minute. Les photos ne consomment rien.",
                    "Tu suis ce qu’il reste dans les réglages du voyage, à la ligne « Crédit du jour ». Trente secondes avant la fin, un message te prévient au-dessus du micro, et ce que tu as déjà dit est toujours gardé.",
                    "Le crédit se recharge chaque nuit à minuit : tu reprends le lendemain, ou tu passes en illimité pour {{prix_abo_mensuel}} par mois et tu continues tout de suite.",
                ]
            ),
            FaqEntry(
                id: "faq.prix.abonnement",
                question: "Comment marche l’abonnement ?",
                answer: [
                    "Il coûte {{prix_abo_mensuel}} par mois et rend ton récit illimité, à l’oral comme à l’écrit, sur tous tes voyages.",
                    "Il est personnel : ce que tu racontes ne prend plus rien au crédit du jour, et tes co-voyageurs qui ne sont pas abonnés continuent de partager le leur.",
                    "Il se renouvelle chaque mois par ton identifiant Apple. Tu le résilies quand tu veux dans les réglages de ton iPhone, et l’illimité reste ouvert jusqu’à la fin du mois déjà payé.",
                    "À la fin de ton voyage, on te rappelle que tu peux le résilier en un geste.",
                ]
            ),
            FaqEntry(
                id: "faq.prix.combien",
                question: "Combien coûte un carnet ?",
                answer: [
                    "Le prix dépend du nombre de pages et des options choisies.",
                ]
            ),
            FaqEntry(
                id: "faq.prix.paiement",
                question: "Quels moyens de paiement sont acceptés ?",
                answer: [
                    "Ceux proposés à l’écran de paiement, dont les cartes bancaires.",
                ]
            ),
            FaqEntry(
                id: "faq.prix.facture",
                question: "Je peux obtenir une facture ?",
                answer: [
                    "Dès que ta commande est payée, un reçu t’est envoyé par e-mail, à l’adresse de ton compte.",
                    "S’il te faut une facture à ton nom ou à celui d’une société, écris-nous avec « Écris à notre équipe », en bas de cette page : on te l’envoie.",
                ]
            ),
        ]
    )

    // MARK: - 10. Aide et contact

    /// Le dixième paquet de la page Notion, que l'écran met à part : ses deux
    /// questions **mènent à nous écrire** au lieu de clore un sujet.
    public static let contact = FaqCategory(
        id: "faq.aide",
        title: "Aide et contact",
        entries: [
            FaqEntry(
                id: "faq.aide.probleme",
                question: "J’ai un problème qui n’est pas listé ici",
                answer: []
            ),
            FaqEntry(
                id: "faq.aide.suggestion",
                question: "J’ai une idée pour améliorer MemoBook",
                answer: []
            ),
        ]
    )
}
