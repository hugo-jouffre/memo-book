import Foundation

// La foire aux questions de l'app, recopiée de la page Notion « FAQ in-app
// MemoBook » (version 1.0) qui en est la source de vérité rédactionnelle.
//
// **Les règles de rédaction de cette page tiennent dans le temps**, et elles
// expliquent la forme de ce fichier :
//
//   - Tutoiement partout, même ton que MEMO dans la conversation.
//   - Vocabulaire : **Carnet**, **souvenirs**, **voyageurs**. Jamais « livre »,
//     jamais « utilisateur », jamais « client ».
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
    /// Le nombre de pages minimum d'un Carnet relié.
    ///
    /// **Imposé par la reliure**, pas par nous : en dessous, l'imprimeur ne sait
    /// pas coudre le dos. À revoir si la reliure ou l'imprimeur change.
    public var minimumPageCount: Int

    public init(minimumPageCount: Int) {
        self.minimumPageCount = minimumPageCount
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
        text.replacingOccurrences(of: "{{nb_pages_min}}", with: String(minimumPageCount))
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
                    "MemoBook transforme ta voix en Carnet de voyage.",
                    "Tu racontes tes journées à l’oral, tu ajoutes tes photos, et ton Carnet se construit tout seul.",
                    "Tu peux le partager en version numérique tout le long de sa création, et le recevoir imprimé chez toi une fois terminé.",
                ]
            ),
            FaqEntry(
                id: "faq.decouvrir.pendant-ou-apres",
                question: "Je raconte pendant le voyage ou au retour ?",
                answer: [
                    "Pendant, idéalement le soir même ou le lendemain.",
                    "C’est là que les détails sont encore frais, et deux minutes de voix suffisent pour une étape.",
                    "Si tu es déjà rentré, tu peux tout raconter d’un coup : le Carnet se construira de la même façon.",
                ]
            ),
            FaqEntry(
                id: "faq.decouvrir.savoir-ecrire",
                question: "Il faut savoir écrire pour faire un beau Carnet ?",
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
                    "À noter qu’un Carnet imprimé fait au minimum {{nb_pages_min}} pages : un récit trop court génère un Carnet avec des pages blanches.",
                    "Pas d’inquiétude, tu es prévenu si ton récit est trop court, et invité à étoffer tes étapes avant l’impression.",
                ]
            ),
            FaqEntry(
                id: "faq.decouvrir.hors-voyage",
                question: "Je peux l’utiliser pour autre chose qu’un voyage ?",
                answer: [
                    "Oui. Beaucoup de Carnets racontent une année, une naissance, une rénovation, un projet.",
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
                    "Tu peux aussi lancer un enregistrement rapide depuis l’écran d’accueil : la conversation de ton voyage s’ouvre ensuite toute seule, et ton vocal s’y pose sous tes yeux.",
                    "Ton récit est transcrit automatiquement, puis mis en forme.",
                    "Tu peux relire, corriger et même supprimer une étape enregistrée dans un récit à tout moment.",
                ]
            ),
            FaqEntry(
                id: "faq.raconter.enregistrement-rapide",
                question: "Où va un enregistrement rapide si j’ai plusieurs récits en cours ?",
                answer: [
                    "Le plus souvent tu n’as qu’un seul récit en cours, et ton souvenir y est ajouté directement.",
                    "Si tu en as plusieurs, l’enregistrement est ajouté à chacun d’eux, et c’est la conversation du premier qui s’ouvre.",
                    "Tu ouvres ensuite les étapes de chaque récit et tu supprimes celle qui n’a rien à y faire, en une touche.",
                    "Pour éviter ce tri, lance l’enregistrement depuis la conversation du récit concerné : il n’est alors ajouté qu’à celui-ci.",
                ]
            ),
            FaqEntry(
                id: "faq.raconter.duree",
                question: "Combien de temps je dois parler ?",
                answer: [
                    "Autant que tu veux.",
                    "Une minute donne un récit court, cinq minutes donnent une étape bien remplie.",
                    "La longueur du texte détermine le nombre de photos nécessaires pour équilibrer la page.",
                ]
            ),
            FaqEntry(
                id: "faq.raconter.plusieurs-fois",
                question: "Je peux enregistrer plusieurs fois pour la même étape ?",
                answer: [
                    "Oui. Tu peux ajouter autant de messages vocaux que nécessaire à une même étape avant de la valider.",
                    "Tout est rassemblé dans un récit cohérent.",
                ]
            ),
            FaqEntry(
                id: "faq.raconter.hors-ligne",
                question: "Et si je n’ai pas de réseau ?",
                answer: [
                    "Tes enregistrements et tes photos sont conservés sur ton téléphone et se synchronisent dès que la connexion revient.",
                    "Tu peux donc continuer à raconter en avion, en montagne ou sans forfait local.",
                ]
            ),
            FaqEntry(
                id: "faq.raconter.bruit",
                question: "Il y a du bruit autour de moi, ça pose problème ?",
                answer: [
                    "Rarement. La transcription tolère bien les environnements sonores courants.",
                    "Si un passage ressort mal, il apparaît en surbrillance dans le texte pour que tu le corriges en deux touches.",
                ]
            ),
            FaqEntry(
                id: "faq.raconter.langue",
                question: "Je peux raconter dans une autre langue ?",
                answer: [
                    "Oui, dans les langues prises en charge par l’app.",
                    "Ton Carnet est ensuite produit dans la langue que tu as choisie pour ton voyage.",
                ]
            ),
            FaqEntry(
                id: "faq.raconter.plusieurs-voix",
                question: "On peut être plusieurs à raconter le même voyage ?",
                answer: [
                    "Oui, chaque voyageur peut contribuer à un voyage partagé, et ses récits sont attribués à son prénom dans le Carnet.",
                    "Si tu préfères une voix unique, une option permet d’unifier le ton du Carnet entier.",
                ]
            ),
            FaqEntry(
                id: "faq.raconter.ecrire-au-clavier",
                question: "Je peux écrire au clavier plutôt que parler ?",
                answer: [
                    "Oui. Le clavier est disponible partout où le micro l’est.",
                    "Le résultat est identique, seule la façon de saisir change.",
                ]
            ),
            FaqEntry(
                id: "faq.raconter.supprimer",
                question: "Je peux supprimer un souvenir que je regrette ?",
                answer: [
                    "Oui, à tout moment tant que ton Carnet n’est pas parti à l’impression.",
                    "Supprimer un souvenir supprime aussi son enregistrement audio.",
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
                    "Cela dépend de la longueur de ton récit.",
                    "Plus le texte est long, plus il faut de photos pour remplir la page harmonieusement.",
                    "L’app t’indique toujours combien il en manque pour valider l’étape en cours.",
                ]
            ),
            FaqEntry(
                id: "faq.photos.pourquoi-minimum",
                question: "Pourquoi un minimum de photos est demandé ?",
                answer: [
                    "Parce que la mise en page est calculée pour que texte et images s’équilibrent.",
                    "Sans ce minimum, la page imprimée aurait de grands vides.",
                    "Si tu n’as vraiment pas assez de photos, raccourcis le récit de l’étape : le nombre demandé baisse aussitôt.",
                ]
            ),
            FaqEntry(
                id: "faq.photos.qualite",
                question: "Quelle qualité de photo faut-il pour l’impression ?",
                answer: [
                    "Les photos prises avec un téléphone récent conviennent.",
                    "Une photo trop petite ou trop compressée est signalée avant validation, avec la possibilité de la remplacer ou de la placer en plus petit format.",
                ]
            ),
            FaqEntry(
                id: "faq.photos.provenance",
                question: "Je peux importer des photos prises avec un appareil photo ?",
                answer: [
                    "Oui, dès qu’elles sont dans la photothèque de ton téléphone.",
                    "Tu peux aussi retrouver facilement les photos prises pendant les dates de ton étape.",
                ]
            ),
            FaqEntry(
                id: "faq.photos.ordre",
                question: "Je peux choisir l’ordre et le cadrage ?",
                answer: [
                    "Oui. Tu réorganises les photos d’une étape, et tu ajustes le cadrage de chacune avant impression.",
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
                    "Elle n’ajoute ni lieux, ni dates, ni anecdotes que tu n’as pas racontés.",
                    "Si une formulation ne te ressemble pas, tu modifies le texte directement : ta version prime toujours.",
                ]
            ),
            FaqEntry(
                id: "faq.ia.ton",
                question: "Je peux choisir le ton du récit ?",
                answer: [
                    "Oui. Tu choisis un ton pour l’ensemble du Carnet, et il s’applique à toutes les étapes.",
                    "Tu peux le changer tant que ton Carnet n’est pas envoyé à l’impression.",
                ]
            ),
            FaqEntry(
                id: "faq.ia.texte-brut",
                question: "Je veux garder mes mots exacts, sans réécriture",
                answer: [
                    "C’est possible : une option conserve la transcription telle quelle, sans enrichissement.",
                    "Tu gardes la ponctuation automatique, mais aucun mot n’est ajouté ni reformulé.",
                ]
            ),
        ]
    )

    // MARK: - 5. Le Carnet imprimé

    public static let printedBook = FaqCategory(
        id: "faq.carnet",
        title: "Le Carnet imprimé",
        entries: [
            FaqEntry(
                id: "faq.carnet.apercu",
                question: "Je peux voir mon Carnet avant de le commander ?",
                answer: [
                    "Oui. L’aperçu est accessible à tout moment depuis la conversation et se met à jour à chaque étape validée.",
                    "Tu vois exactement les pages qui seront imprimées.",
                ]
            ),
            FaqEntry(
                id: "faq.carnet.pages",
                question: "Combien de pages fait un Carnet ?",
                answer: [
                    "Cela dépend de la quantité de récits et de photos.",
                    "La reliure impose un minimum de {{nb_pages_min}} pages : en dessous, ton Carnet comporterait des pages blanches, et l’app t’invite alors à étoffer tes étapes.",
                    "Tu peux aussi choisir une densité plus aérée ou plus compacte pour ajuster le volume.",
                ]
            ),
            FaqEntry(
                id: "faq.carnet.densite",
                question: "C’est quoi la densité de mise en page ?",
                answer: [
                    "C’est la quantité de contenu par page.",
                    "Une densité aérée donne un Carnet plus épais et plus contemplatif, une densité compacte un Carnet plus fin.",
                    "Le contenu reste identique, seule la respiration change.",
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
                question: "Je peux modifier mon Carnet après l’avoir commandé ?",
                answer: [
                    "Une fois la commande envoyée en production, le contenu est figé pour être imprimé.",
                    "Avant cet envoi, tout reste modifiable. Après, tu peux éditer une nouvelle version puis en commander un exemplaire mis à jour.",
                ]
            ),
            FaqEntry(
                id: "faq.carnet.exemplaires",
                question: "Je peux en commander plusieurs exemplaires ?",
                answer: [
                    "Oui, en une seule commande ou plus tard.",
                    "Les exemplaires supplémentaires d’un même Carnet sont proposés à un tarif réduit.",
                ]
            ),
            FaqEntry(
                id: "faq.carnet.livraison",
                question: "Quels sont les délais et les frais de livraison ?",
                answer: [
                    "Le délai estimé et le montant exact te sont affichés avant le paiement, selon ton pays de livraison.",
                    "Tu reçois ensuite un suivi jusqu’à la remise du colis.",
                ]
            ),
            FaqEntry(
                id: "faq.carnet.abime",
                question: "Mon Carnet est arrivé abîmé ou avec un défaut d’impression",
                answer: [
                    "Signale-le depuis la commande concernée, avec une photo du problème.",
                    "Un nouvel exemplaire est réimprimé et réexpédié sans frais.",
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
                question: "Je peux partager mon Carnet sans l’imprimer ?",
                answer: [
                    "Oui. Tu partages une version numérique feuilletable, page après page, comme un vrai Carnet.",
                    "Le partage se fait via un lien ou directement vers tes applications de messagerie.",
                ]
            ),
            FaqEntry(
                id: "faq.partage.pendant-le-voyage",
                question: "Je peux partager mon voyage en cours de route ?",
                answer: [
                    "Oui. Tes proches peuvent suivre l’avancée de ton Carnet et la carte de ton trajet pendant que tu voyages.",
                ]
            ),
            FaqEntry(
                id: "faq.partage.qui-voit",
                question: "Qui peut voir ce que je partage ?",
                answer: [
                    "Uniquement les personnes à qui tu transmets le lien.",
                    "Rien n’est public par défaut, et tu peux désactiver un lien de partage à tout moment.",
                ]
            ),
            FaqEntry(
                id: "faq.partage.pdf",
                question: "Je peux récupérer un fichier de mon Carnet ?",
                answer: [
                    "Oui, tu peux exporter ton Carnet pour le conserver ou l’archiver de ton côté.",
                ]
            ),
        ]
    )

    // MARK: - 7. Carte et voyages

    public static let mapAndTrips = FaqCategory(
        id: "faq.carte",
        title: "Carte et voyages",
        entries: [
            FaqEntry(
                id: "faq.carte.trajet",
                question: "À quoi sert la carte ?",
                answer: [
                    "Elle affiche ton trajet et chaque étape validée sous forme de point.",
                    "C’est le résumé visuel de ton voyage, et elle est reprise dans le Carnet imprimé.",
                ]
            ),
            FaqEntry(
                id: "faq.carte.localisation",
                question: "MemoBook suit ma position en continu ?",
                answer: [
                    "Non. La position est associée à une étape au moment où tu la crées, pas suivie en arrière-plan.",
                    "Tu peux aussi saisir un lieu à la main, sans activer la localisation.",
                ]
            ),
            FaqEntry(
                id: "faq.voyages.plusieurs",
                question: "Je peux avoir plusieurs voyages en même temps ?",
                answer: [
                    "Oui, autant que tu le souhaites.",
                    "Chaque voyage a sa conversation, sa carte et son Carnet.",
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
                    "Toi seul, et les personnes que tu invites sur un voyage partagé.",
                    "Tes récits ne sont jamais publiés ni utilisés à des fins publicitaires.",
                ]
            ),
            FaqEntry(
                id: "faq.donnees.ia-entrainement",
                question: "Mes récits servent-ils à entraîner des IA ?",
                answer: [
                    "Non. Tes contenus sont traités uniquement pour produire ton Carnet.",
                    "Les prestataires techniques utilisés pour la transcription et la mise en forme sont engagés contractuellement à ne pas les réutiliser.",
                ]
            ),
            FaqEntry(
                id: "faq.donnees.conservation",
                question: "Combien de temps mes souvenirs sont-ils conservés ?",
                answer: [
                    "Tant que ton compte existe, pour que tu puisses rouvrir un ancien voyage des années plus tard.",
                    "Tu peux supprimer un voyage, un souvenir ou l’ensemble de tes données quand tu le décides.",
                ]
            ),
            FaqEntry(
                id: "faq.donnees.export",
                question: "Je peux récupérer toutes mes données ?",
                answer: [
                    "Oui, depuis les réglages du compte : tes textes, tes photos et tes Carnets te sont envoyés dans un format lisible.",
                ]
            ),
            FaqEntry(
                id: "faq.donnees.suppression-compte",
                question: "Comment supprimer mon compte ?",
                answer: [
                    "Depuis les réglages du compte, en quelques touches.",
                    "La suppression est définitive et efface tes souvenirs, tes photos et tes enregistrements.",
                    "Si tu veux seulement faire une pause, tu peux à la place supprimer un voyage précis et garder le reste.",
                ]
            ),
            FaqEntry(
                id: "faq.donnees.changement-telephone",
                question: "Je change de téléphone, je perds tout ?",
                answer: [
                    "Non. Tes voyages sont rattachés à ton compte et tu les retrouves en te reconnectant.",
                    "Pense simplement à synchroniser tes dernières étapes avant de changer d’appareil.",
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
                    "Non, elle est gratuite au téléchargement, et enregistrer tes souvenirs l’est aussi.",
                    "Tu paies uniquement au moment où tu commandes ton Carnet.",
                ]
            ),
            FaqEntry(
                id: "faq.prix.combien",
                question: "Combien coûte un Carnet ?",
                answer: [
                    "Le prix dépend du nombre de pages et des options choisies.",
                    "Il t’est affiché en clair avant le paiement, sans surprise à l’étape suivante.",
                ]
            ),
            FaqEntry(
                id: "faq.prix.paiement",
                question: "Quels moyens de paiement sont acceptés ?",
                answer: [
                    "Ceux proposés à l’écran de commande, dont les cartes bancaires et le paiement intégré à ton téléphone.",
                ]
            ),
            FaqEntry(
                id: "faq.prix.facture",
                question: "Je peux obtenir une facture ?",
                answer: [
                    "Oui, elle est disponible dans le détail de ta commande et téléchargeable à tout moment.",
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
                answer: [
                    "Écris-nous depuis l’app, en décrivant ce que tu faisais au moment du souci.",
                    "Le diagnostic technique est joint automatiquement, sans le contenu de tes souvenirs.",
                ]
            ),
            FaqEntry(
                id: "faq.aide.suggestion",
                question: "J’ai une idée pour améliorer MemoBook",
                answer: [
                    "Envoie-la depuis la même page de contact.",
                    "Les demandes récurrentes orientent directement les prochaines évolutions.",
                ]
            ),
        ]
    )
}
