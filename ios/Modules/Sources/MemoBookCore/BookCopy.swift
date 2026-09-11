import Foundation

// Tout ce que le parcours « carnet » écrit : les paramètres du voyage, la
// composition du PDF, son aperçu, son partage, et la cagnotte.
//
// Un seul fichier pour les cinq écrans, comme ``ChatCopy`` en tient un pour le
// chat : ils se relisent d'un trait, et R8 (« tous les libellés passent par des
// constantes localisables ») n'a qu'un endroit à tenir.
//
// **Les conventions typographiques de l'app** : apostrophe typographique `’`
// (U+2019) partout, espace insécable avant `?` et `!`, points de suspension `…`
// (U+2026), guillemets français `«  »`.
//
// ⚠️ **Quatre coquilles de la maquette sont recopiées telles quelles** (R8
// interdit de corriger en silence) :
//   - `Wallet.emptyMessage` **vouvoie** — « Partagez votre cagnotte avec vos
//     proches ». R9 ne souffre pas d'exception dans l'app : la phrase est
//     recopiée et **signalée**, pas réécrite (voir la fiche de la cagnotte).
//   - `Wallet.subscriptionTile` écrit « grace » sans accent circonflexe.
//   - `Settings.pdfPreview` écrit « Prévisulation » pour « Prévisualisation ».
//   - `Preview.configureCover` écrit « Défini » pour « Définis ».
public enum BookCopy {

    // MARK: - Paramètres du voyage

    public enum Settings {
        public static let title = "Paramètres du voyage"

        public static let adventureSection = "Gère ton aventure"
        public static let quickAccessSection = "Accès rapide"

        public static let name = "Nom de l’aventure"
        public static let wallet = "Ma cagnotte"
        public static let dates = "Dates du voyage"
        public static let pace = "Rythme du récit"
        public static let notifications = "Notifications"
        public static let manageNotifications = "Gérer mes notifications"
        public static let companions = "Co-voyageur(s)"
        public static let theme = "Thème de l’aventure"
        public static let publicGallery = "Partager sur la galerie de la communauté"
        public static let style = "Style du carnet"

        public static let tricountTitle = "Connecte ton Tricount"
        public static let tricountMessage =
            "MemoBook pourra déduire tes étapes et t’aider à raconter des souvenirs à partir de tes dépenses"

        /// ⚠️ « Prévisulation » est la coquille de la maquette (R8).
        public static let pdfPreview = "Prévisulation PDF"
        public static let pdfPreviewDetail = "Aperçu et partage"

        public static let order = "Commander le carnet"
        public static let help = "Besoin d’aide ?"

        // MARK: Personnalisations du carnet

        /// La valeur d'une ligne dont le voyage n'a rien à dire. Un tiret cadratin
        /// et non une chaîne vide : une ligne sans valeur se lirait comme une
        /// valeur qui n'a pas chargé.
        public static let noValue = "—"
    }

    // MARK: - Personnalisations du carnet

    public enum Customisation {
        public static let title = "Personnalisations du carnet"

        /// ⚠️ **Cette phrase vouvoie**, et elle est recopiée telle quelle (R8) :
        /// R9 dit que l'app tutoie sans exception. Signalée — à réécrire dans
        /// Figma en « Ajuste les différentes options de MemoBook pour que ton
        /// carnet te ressemble de plus en plus ». La maquette écrit aussi
        /// « Ajuster les différents options » : un infinitif là où il faut un
        /// impératif, et un accord manquant.
        public static let intro =
            "Ajuster les différents options de MemoBook pour que votre carnet vous ressemble de plus en plus"

        public static let covers = "Couvertures (1re & 4e)"
        public static let coversDetail = "Aperçu et personnalisation"

        public static let photoTextRatio = "Ratio photo / texte"
        public static let targetPageCount = "Nombre de page cible"

        public static let funFacts = "Fun facts"
        public static let rules = "Pointillés"
        public static let decorations = "Décorations & stickers"

        public static let fontTitle = "Typographie des titres"
        public static let fontDisplay = "Typographie des sous-titres"
        public static let fontHand = "Typographie des textes"
        public static let fontFacts = "Typographie des fun facts"

        /// L'état d'un décor qu'on active ou non. Deux mots, pas un
        /// interrupteur : la maquette en fait une ligne qui **mène** à un choix,
        /// et le réglage aura plus de deux valeurs le jour où le gabarit les
        /// acceptera.
        public static func toggleValue(_ isOn: Bool) -> String {
            isOn ? "Activé" : "Désactivé"
        }

        public static let extrasSection = "Extras"

        public static let quizTitle = "Quiz intégrés à l’histoire"
        public static let quizDetail =
            "MemoBook génère des mini quiz au fur et à mesure du récit. Découvre-les et répond lors de la réception de ton carnet."

        public static let freeZonesTitle = "Zones libres"
        public static let freeZonesDetail =
            "Ajoute 1 zone blanche à la fin de chaque étape et 3 pages blanches à la fin du carnet"

        public static let crosswordTitle = "Mot fléché à la fin du livre"
        public static let crosswordDetail =
            "MemoBook génère une grille de mot fléché automatiquement à partir de tes récits, au moment de commander ton livre et la place à la fin du carnet."
    }

    // MARK: - On compose ton Carnet

    public enum Composition {
        public static let title = "On compose ton Carnet"
        public static let message =
            "Images, Souvenirs, cartes et petits détails trouvent leur place dans une mise en page unique"

        /// Ce que VoiceOver annonce pendant la composition. L'animation, elle,
        /// est purement décorative et masquée : décrire une page qui se monte
        /// morceau par morceau ne dirait rien de plus que cette phrase.
        public static let voiceOverStatus = "Composition du carnet en cours"
    }

    // MARK: - Aperçu PDF

    public enum Preview {
        public static let title = "Aperçu PDF"

        /// Le titre de la **feuille** d'aperçu, celle qu'ouvrent les deux
        /// pastilles « Voir un aperçu » du parcours d'abonnement.
        ///
        /// Différent de ``title``, et c'est la maquette qui le veut : l'écran
        /// annonce un format (« Aperçu PDF »), la feuille annonce un geste
        /// (« Prévisualisation »). On ne vend pas un PDF, on montre un carnet.
        public static let sheetTitle = "Prévisualisation"

        /// Le retour, quand l'aperçu est une **étape** d'une autre feuille — la
        /// feuille d'abonnement. On est venu voir ce qu'on achète, on repart
        /// d'où l'on venait.
        public static let backToOffer = "Revenir à l’offre"

        /// « Rome et la Dolce Vita - 10 pages composées ».
        ///
        /// ⚠️ Le tiret entouré d'espaces est celui de la maquette (R8). Le
        /// pluriel, lui, est accordé : un carnet d'une seule page arrive au
        /// premier souvenir raconté.
        public static func subtitle(title: String, pages: Int) -> String {
            let composed = pages == 1 ? "1 page composée" : "\(pages) pages composées"
            return "\(title) - \(composed)"
        }

        /// « Page 4 / 10 ».
        public static func pageIndicator(_ index: Int, of total: Int) -> String {
            "Page \(index) / \(total)"
        }

        /// « 1 sur 24 » — le compteur de l'aperçu plein écran. Il compte les
        /// **feuilles du PDF**, là où l'indicateur du bas compte les pages du
        /// carnet : les deux diffèrent dès qu'une page tient sur deux feuilles.
        public static func sheetIndicator(_ index: Int, of total: Int) -> String {
            "\(index) sur \(total)"
        }

        public static let customise = "Personnaliser mon carnet"
        public static let order = "Commander ce carnet"

        /// ⚠️ « Défini » pour « Définis » : coquille de la maquette (R8).
        public static let configureCover = "Défini maintenant\nta 1ère et 4ème de couverture"
        public static let configureCoverAction = "Configurer"

        public static let offerTitle = "Fais-toi offrir ce carnet"
        public static let offerMessage =
            "Envoie un message à tes proches pour qu’ils t’offrent ce carnet, ou offre-le toi-même"
        public static let offerShare = "Partager ma cagnotte"
        public static let offerSee = "Voir ma cagnotte"

        public enum Voice {
            public static let previousPage = "Page précédente"
            public static let nextPage = "Page suivante"
            public static let enterFullScreen = "Afficher en plein écran"
            public static let exitFullScreen = "Quitter le plein écran"
            public static let share = "Partager mon carnet"
        }

        /// Le PDF n'a pas pu se charger. Le carnet existe, c'est le
        /// téléchargement qui a échoué : on propose donc de réessayer, pas de
        /// recomposer.
        public static let loadFailed = "L’aperçu n’a pas pu se charger."
        public static let retry = "Réessayer"
    }

    // MARK: - Un mot des fondateurs

    public enum Founders {
        public static let title = "Un mot des fondateurs"

        /// « Hello Margaux, » — le prénom vient du compte. Sans prénom, la
        /// phrase se contente du bonjour : « Hello , » serait pire que rien.
        public static func hello(_ firstName: String?) -> String {
            guard let firstName, !firstName.isEmpty else { return "Hello," }
            return "Hello \(firstName),"
        }

        public static let intro = "On a créé MemoBook avec une idée très simple :"

        /// La ligne manuscrite, en vert. C'est **la** phrase du mot, celle qui
        /// justifie d'avoir embarqué une police d'écriture à la main.
        public static let promise =
            "Tes souvenirs ont trop de valeur pour rester oubliés dans ton téléphone !"

        /// Les quatre paragraphes du mot, séparés par un blanc.
        ///
        /// Une liste et non une chaîne à `\n\n`, pour la même raison que
        /// ``BrandSheet`` : une ligne vide ne se lit pas à VoiceOver.
        public static let body = [
            "On espère que ce premier aperçu te donnera le sourire.",
            "Notre application est encore en plein développement.",
            "N’hésite pas à nous envoyer tes retours. On travaille en continu pour rendre ton expérience plus fluide.",
            "Merci de faire partie de l’aventure !",
            "À très vite,",
        ]

        public static let signature = "Co-fondateurs de MemoBook"
        public static let signatureVoice = "Paul et Hugo"

        public static let feedback = "Partager mes retours"
        public static let carryOn = "Continuer à découvrir mon carnet"

        /// L'adresse où partent les retours. Un `mailto:` et non un formulaire :
        /// il n'y a pas de back-end derrière, et le courrier électronique laisse
        /// une trace des deux côtés.
        public static let feedbackAddress = "hello@memobook.fr"
        public static let feedbackSubject = "Mes retours sur MemoBook"
    }

    // MARK: - Partager son MemoBook

    public enum Share {
        public static let title = "Partager ton MemoBook"
        public static let message =
            "Partage un fichier PDF accessible hors connexion et sur l’outil de ton choix ou partage un lien de prévisualisation permettant de suivre l’avancée de ton carnet en direct."

        public static let sharePdf = "Partager le fichier pdf"
        public static let shareLink = "Partager le lien de prévisualisation"

        /// Le message pré-rempli dans WhatsApp, iMessage ou Snapchat.
        ///
        /// Il dit trois choses, dans cet ordre : ce qu'on prépare, où on en
        /// est, et comment aider. C'est la troisième qui compte — un lien de
        /// cagnotte sans le récit qui le précède se lit comme une quête.
        ///
        /// Le titre du carnet est entre guillemets **français** ; la
        /// spécification de Hugo employait des guillemets anglais fermants des
        /// deux côtés, ce qui est une glissade de clavier. Signalé.
        public static func invitation(title: String, steps: Int, link: URL) -> String {
            let written = steps == 1 ? "ma 1re étape" : "mes \(steps) premières étapes"
            return """
                Je prépare le carnet de mon voyage « \(title) ». J’ai déjà écrit \(written) ! \
                Il est possible de m’aider à financer la version imprimée en cliquant sur ce lien : \(link.absoluteString)
                """
        }

        /// Le sujet, quand l'app de destination en demande un — le courrier
        /// électronique, essentiellement.
        public static func subject(title: String) -> String {
            "Mon carnet de voyage « \(title) »"
        }

        /// Le lien de prévisualisation n'existe pas encore et n'a pas pu se
        /// créer. On le dit sans jargon : ce n'est pas la faute de
        /// l'utilisateur, et le PDF reste partageable.
        public static let linkFailed =
            "Le lien de prévisualisation n’a pas pu se créer. Le fichier PDF, lui, reste partageable."
    }

    // MARK: - Ma cagnotte

    public enum Wallet {
        public static let title = "Ma Cagnotte"

        /// « Finance ton carnet de Rome ». Sans destination nommée, la phrase
        /// reste vraie sans nommer le vide.
        public static func subtitle(trip: String?) -> String {
            guard let trip, !trip.isEmpty else { return "Finance ton carnet" }
            return "Finance ton carnet de \(trip)"
        }

        public static let available = "Montant disponible"

        /// « A ce rythme, ton carnet fera probablement 50 pages ».
        ///
        /// ⚠️ Le « A » sans accent est celui de la maquette (R8).
        public static func paceEstimate(pages: Int) -> String {
            "A ce rythme, ton carnet fera probablement \(pages) pages"
        }

        public static let estimatedCost = "coût estimé"

        public static let add = "Ajouter"
        public static let share = "Partager"

        public static let historySection = "Historique des contributions"

        /// ⚠️ **Cette phrase vouvoie** — c'est la maquette, et R9 dit que l'app
        /// tutoie sans exception. Recopiée telle quelle et signalée (R8 + R9) :
        /// à réécrire dans Figma en « Partage ta cagnotte avec tes proches pour
        /// recevoir tes premières contributions ! ».
        public static let emptyTitle = "Aucune contribution pour le moment"
        public static let emptyMessage =
            "Partagez votre cagnotte avec vos proches pour recevoir vos premières contributions !"
        public static let invite = "Inviter des proches"

        /// « 60 € offerts par tes proches ».
        public static let giftedTile = "offerts par tes proches"

        /// ⚠️ « grace » sans accent circonflexe : coquille de la maquette (R8).
        public static let subscriptionTile = "grace à ton abonnement"

        public static let faqTitle = "Si je n’utilise pas toute ma cagnotte ?"
        public static let faqMessage =
            "Ton solde restant est conservé précieusement sur ton compte. Utilise cette somme quand tu le souhaites pour imprimer des exemplaires supplémentaires ou pour financer tes prochains carnets."

        public static let previewBook = "Prévisualiser mon carnet"
        public static let help = "Besoin d’aide ?"

        /// Recharger sa cagnotte n'a pas encore d'encaissement derrière. On le
        /// dit plutôt que d'ouvrir un écran vide — voir T20.
        public static let addUnavailable =
            "Recharger ta cagnotte arrive bientôt : le paiement n’est pas encore branché."
    }
}
