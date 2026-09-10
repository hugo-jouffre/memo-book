import Foundation

// Tout ce que le chat écrit : les libellés de l'interface **et** les phrases de
// MEMO, dans un seul fichier.
//
// Les deux ensemble, et non deux fichiers, parce que la frontière ne tient pas :
// « Ça me convient » est un libellé de puce que le voyageur envoie comme
// message, et « Retranscription du contexte » est un titre de fiche que le
// répondeur produit. Un seul endroit, donc, pour que la voix de MEMO se relise
// d'un trait — et pour que R8 (« tous les libellés passent par des constantes
// localisables ») ait un endroit unique à tenir.
//
// **Les conventions typographiques de l'app**, vérifiées dans les écrans déjà
// livrés : apostrophe typographique `’` (U+2019) partout, espace simple avant
// `?` et `!`, points de suspension `…` (U+2026).
//
// ⚠️ **Deux coquilles de la maquette sont recopiées telles quelles** dans
// ``opening`` : « pourrais tu » sans trait d'union, et « tous le long » pour
// « tout le long ». R8 interdit de corriger en silence — voir T49.
//
// Le vouvoiement de ``greetingMessage``, lui, est **corrigé** : Hugo a tranché
// (D9), et R9 l'emportait de toute façon sur R8 pour cette phrase.
public enum ChatCopy {

    // MARK: - La bannière « Aperçu en direct »

    public static let previewOverline = "Aperçu en direct"
    public static let previewTitle = "Votre Carnet prend forme"

    /// « 5 Souvenirs - 10 pages composées ».
    ///
    /// ⚠️ Le S majuscule de « Souvenirs » et le tiret entouré d'espaces sont
    /// ceux de la maquette (R8). Les pluriels, en revanche, sont accordés : la
    /// maquette ne montre qu'un carnet bien rempli, et « 1 Souvenirs » se verrait
    /// au premier lancement.
    public static func previewSubtitle(memories: Int, pages: Int) -> String {
        let souvenirs = memories == 1 ? "1 Souvenir" : "\(memories) Souvenirs"
        let composed = pages == 1 ? "1 page composée" : "\(pages) pages composées"
        return "\(souvenirs) - \(composed)"
    }

    // MARK: - L'accueil d'une conversation vide

    /// « Nouveau voyage à Rome ! 🇮🇹 » — le drapeau vient de ``Destination/flag``,
    /// jamais d'un emoji écrit en dur.
    public static func greetingTitle(place: String, flag: String?) -> String {
        let title = "Nouveau voyage à \(place) !"
        return flag.map { "\(title) \($0)" } ?? title
    }

    /// Le voyage n'a pas de destination nommée. La maquette ne le dessine pas —
    /// écart signalé dans la fiche écran.
    public static let greetingTitleWithoutPlace = "Nouveau carnet de voyage !"

    /// La maquette vouvoyait sur la dernière phrase (« Comment souhaitez-vous
    /// commencer aujourd’hui ? ») au milieu d'un paragraphe qui tutoie.
    /// **Corrigé sur arbitrage de Hugo** (D9) : R9 ne souffre pas d'exception,
    /// et la phrase se contredisait elle-même. À reprendre dans Figma.
    public static let greetingMessage = """
        Je suis là pour transformer tes anecdotes, photos et enregistrements \
        vocaux en un magnifique récit structuré. Comment souhaites-tu \
        commencer aujourd’hui ?
        """

    // MARK: - L'ouverture de MEMO

    /// La première bulle blanche, celle que la maquette dessine en entier.
    ///
    /// ⚠️ **Deux coquilles recopiées** (R8) : « pourrais tu » sans trait d'union,
    /// et « tous le long » au lieu de « tout le long ». Remontées à Clara — T49.
    public static let opening = """
        Bonjour 👋
        Je suis MEMO, ton assistant pour t’aider à construire ton carnet de voyage.

        Je suis là pour transformer ce que tu me racontes en un récit fluide.

        Je m’adapte à ton style : tu peux me dicter ta journée, ta semaine, ton \
        expérience à l’oral ou l’écrire, comme tu préfères.

        Avant de commencer pourrais tu me faire un contexte global de ton \
        voyage ? Cela m’aidera à garder de la cohérence tous le long du récit.
        """

    /// Quand le voyage porte déjà une relance (``TripDetail/prompt``), le chat
    /// ouvre **dessus** plutôt que sur son propre texte : les deux écrans
    /// doivent dire la même phrase.
    public static let openingWithoutPrompt =
        "Raconte-moi ta journée, à l’oral ou au clavier. Je m’occupe du reste."

    // MARK: - La fiche de retranscription

    public static let transcriptTitle = "Retranscription du contexte"

    /// La mention « généré par IA » qu'exige `docs/reglages-utilisateur.md`.
    public static let transcriptFootnote = "Texte proposé par MEMO — tu peux le corriger."

    /// La fiche s'affiche avec ce qu'on sait (date, lieu, durée) même sans
    /// récit : on ne cache pas une fiche réelle derrière une attente.
    public static let transcriptPending = "J’écoute ton vocal…"

    public static let transcriptUnavailable = """
        Je n’ai pas encore la transcription de ce vocal. Tu peux me le réécrire \
        ici, ou attendre que je l’aie.
        """

    public static let seeMore = "Voir plus"
    public static let seeLess = "Voir moins"

    /// La relance qui suit une fiche remplie.
    public static let afterTranscript = """
        Voilà ce que j’ai compris de ton vocal. Je le garde tel quel pour ton \
        carnet, ou tu veux le retoucher ?
        """

    // MARK: - Les relances de MEMO, par famille
    //
    // Une famille = un signal détecté dans le message du voyageur. La priorité
    // qui les départage vit dans ``LocalMemoResponder`` ; ici, seulement les
    // mots. Chaque phrase se termine par **une** question : `agents/agent-
    // conversation.md` interdit le formulaire déguisé.

    /// Le voyageur ne veut plus répondre. « Ne jamais insister » est la règle la
    /// plus dure du contrat de l'agent.
    public static let refusal = """
        Très bien, on s’arrête là. Ce que tu m’as raconté est gardé, tu \
        reprendras quand tu voudras.
        """

    public static let acknowledged = "C’est enregistré. Ton carnet compte une étape de plus."

    public static let handingOver = """
        Je te laisse la main. Ta version fait autorité sur la mienne, je n’y \
        retouche plus.
        """

    public static let listening = "Je t’écoute. Reprends-le comme tu le dirais à quelqu’un."

    /// Les six sujets sur lesquels MEMO sait légitimement répondre, plus le
    /// repli honnête. Répondre à une question par une question est le pire des
    /// aveux : il prouve que rien n'a été lu.
    public enum Answer {
        public static let book = """
            Ton carnet se met en page tout seul à partir de ce que tu racontes. \
            Tu le relis en aperçu, et rien ne part à l’impression sans que tu \
            l’aies validé.
            """

        public static let subscription = """
            Tu retrouves le prix et l’état de ton abonnement dans ton profil, à \
            la ligne « Mon abonnement ».
            """

        public static let photos =
            "Ajoute tes photos quand tu veux : je les range avec le souvenir du jour."

        public static let corrections = """
            Tout se corrige. Tu relis chaque texte avant l’impression, et ta \
            version fait autorité sur la mienne.
            """

        public static let pace = """
            Je te relance au rythme réglé pour ce voyage. Tu le changes dans les \
            paramètres du voyage.
            """

        public static let unknown = """
            Je ne sais pas répondre à ça pour l’instant. Ce que je sais faire, \
            c’est écouter ton voyage et en tirer ton carnet — tu me racontes la \
            suite ?
            """
    }

    /// Une émotion difficile s'accuse **avant** toute demande, et la demande
    /// reste optionnelle.
    public static let negativeMood = [
        """
        Ça n’a pas dû être simple. Si tu veux le garder dans le carnet, \
        raconte-moi ce qui t’a remis d’aplomb.
        """,
        """
        Je note la journée telle qu’elle a été, sans l’enjoliver. Tu veux qu’on \
        s’arrête là pour aujourd’hui ?
        """,
    ]

    public static let positiveMood = """
        On sent que tu y étais. Donne-moi le détail qui rendra bien à \
        l’impression : une odeur, un bruit, une phrase que quelqu’un a dite.
        """

    public static let tooShort = [
        "Je prends. Un détail de plus et j’en tire une page : c’était où, exactement ?",
        "D’accord. Qui était avec toi à ce moment-là ?",
    ]

    public static let missingPlace = "Tu me dis où ça se passait ? Un quartier ou un nom de rue me suffit."

    /// Le lieu est recopié **verbatim** du message : MEMO ne complète pas un nom
    /// propre, il le répète.
    public static func foundPlace(_ place: String) -> String {
        "\(place), je note. Qu’est-ce qui t’a marqué là-bas ?"
    }

    public static let missingDate = "Ça date de quand ? Si c’était hier, je le range à la bonne journée du carnet."

    /// Première apparition d'un prénom dans le fil. **Tournure sans genre** : le
    /// moteur ne sait pas si Camille est une femme ou un homme, et un accord
    /// faux se voit immédiatement.
    public static func newPerson(_ name: String) -> String {
        "\(name) apparaît pour la première fois dans ton carnet. Tu me dis en deux mots qui c’est ?"
    }

    public static func knownPerson(_ name: String) -> String {
        "Et \(name) ? Raconte-moi ce que vous avez fait ensemble."
    }

    /// Le chiffre est recopié tel quel. MEMO ne convertit ni n'additionne : une
    /// métadonnée fausse est pire qu'absente.
    public static func figure(_ figure: String) -> String {
        "\(figure), c’est noté : ça ira dans les compteurs du voyage. Ça t’a pris combien de temps ?"
    }

    /// Des photos viennent d'arriver. MEMO recompte ce qu'il a reçu — un
    /// chiffre se recopie — et demande ce qu'on y voit : il n'a pas regardé les
    /// images, et prétendre le contraire serait inventer un fait.
    public static func photosReceived(count: Int) -> String {
        count == 1
            ? "Une photo, je la range avec le souvenir du jour. Qu’est-ce qu’on y voit ?"
            : "\(count) photos, je les range avec le souvenir du jour. Qu’est-ce qu’on y voit ?"
    }

    public static let longMessage = """
        Il y a de quoi faire deux pages là-dedans. Je découpe en deux étapes, ou \
        tu préfères que ça reste d’un seul tenant ?
        """

    /// La rotation neutre, quand aucun signal ne ressort.
    ///
    /// Les trois premières sont la rose, l'épine et la graine, que
    /// `docs/reglages-utilisateur.md` veut « demandé dans le chat, pas imprimé
    /// comme bloc à remplir » ; les quatrième et cinquième sont recopiées mot
    /// pour mot des exemples de relances d'`agents/agent-conversation.md` ; les
    /// cinq dernières les complètent.
    ///
    /// **Dix et pas cinq**, parce que c'est le nombre de soirs ternes qu'un
    /// voyage peut compter. Le moteur écarte toute relance déjà dite dans le
    /// fil et descend d'un cran : une liste trop courte le force à se répéter
    /// avant la fin de la semaine, et rien ne trahit plus vite une machine.
    public static let rotation = [
        "Le meilleur moment de ta journée, c’était lequel ?",
        "Et ce qui t’a agacé aujourd’hui, tu veux qu’on le garde ou qu’on le laisse de côté ?",
        "Qu’est-ce que tu attends le plus, pour demain ?",
        "Tu as une photo de ce moment-là, ou on en cherche une qui lui ressemble dans ta pellicule ?",
        "On regroupe ce souvenir avec la journée d’avant, ou il mérite sa propre page ?",
        "Qu’est-ce que tu as mangé, et où ? Ça donne toujours de bonnes pages.",
        "Tu as croisé quelqu’un dont tu te souviendras ?",
        "Si tu devais donner un titre à cette journée, ce serait quoi ?",
        "Qu’est-ce qui t’a surpris, par rapport à ce que tu imaginais ?",
        "Il te reste quelque chose à raconter sur aujourd’hui, ou on s’arrête là ?",
    ]

    // MARK: - Les suggestions
    //
    // Une puce n'est pas un raccourci d'interface : c'est une phrase que le
    // voyageur envoie, et la maquette la montre bien posée en bulle bleue dans
    // le fil. Ce qui change d'une intention à l'autre, c'est l'outil qu'elle
    // ouvre derrière. Deux ou trois par tour, jamais quatre, et aucune
    // ponctuation finale.

    public enum Suggest {
        /// Le trio de la maquette, sous une fiche qui porte du **vrai** texte.
        public static let accept = "Ça me convient"
        public static let editByHand = "J’aimerais faire des modifications à la main"
        public static let editByVoice = "J’aimerais faire des modifications à l’oral"

        /// Sous une fiche sans récit : le trio n'a rien à valider.
        public static let rewrite = "Je te le réécris ici"
        public static let recordAgain = "Je réenregistre"

        /// L'écran vide, tel que la maquette l'écrit — emoji de tête compris,
        /// porté séparément pour qu'il ne partre pas dans le message.
        public static let start = "Commencer mon carnet"
        public static let startSymbol = "🚀"
        public static let importPhotos = "Importer des photos"
        public static let importPhotosSymbol = "📷"
        public static let dictate = "Raconter à l’oral"
        public static let dictateSymbol = "🎙"

        public static let tellByVoice = "Je te raconte à l’oral"
        public static let preferWriting = "Je préfère écrire"
        public static let later = "Plus tard"
        public static let tomorrow = "On en reparle demain"
        public static let somethingElse = "Je te raconte autre chose"
        public static let clear = "C’est clair, merci"
        public static let anotherQuestion = "J’ai une autre question"
        public static let resume = "Je reprends mon récit"
        public static let splitInTwo = "Découpe en deux étapes"
        public static let keepAsOne = "Garde d’un seul tenant"
    }

    // MARK: - Les commandes de l'écran

    public static let backToBottom = "Retourner en bas"

    /// ⚠️ **En anglais dans la maquette**, au milieu d'une app française. Recopié
    /// tel quel (R8) et remonté — T51.
    public static let record = "Record"

    public static let composerPlaceholder = "Raconte-moi…"

    // MARK: - Les photos

    /// Ce que le sélecteur de photos propose. Les libellés d'une
    /// `confirmationDialog` iOS, en français comme le reste de l'app.
    public enum Photos {
        public static let title = "Ajouter une photo"
        public static let takeOne = "Prendre une photo"
        public static let fromLibrary = "Choisir dans la galerie"
        public static let cancel = "Annuler"

        /// L'appareil photo n'existe pas — un simulateur, un iPad sans caméra.
        public static let cameraUnavailable =
            "Cet appareil n’a pas d’appareil photo. Choisis une image dans ta galerie."

        /// L'accès aux photos a été refusé. Comme pour le micro, iOS ne
        /// redemande pas : le seul recours est l'app Réglages.
        public static let libraryDenied = """
            MemoBook a besoin de tes photos pour les ranger dans ton carnet. \
            Autorise l’accès dans Réglages.
            """

        public static let cameraDenied = """
            MemoBook a besoin de l’appareil photo pour prendre une photo. \
            Autorise l’accès dans Réglages.
            """
    }

    // MARK: - Les échecs

    /// Les images choisies n'ont pas pu être écrites sur l'appareil — disque
    /// plein, ou fichier illisible.
    public static let photosUnreadable =
        "Je n’ai pas réussi à ouvrir ces photos. Réessaie, ou choisis-en d’autres."

    public static let notSent = "Non envoyé"
    public static let retry = "Réessayer"

    // MARK: - Ce que VoiceOver annonce
    //
    // Tout élément interactif sans libellé visible en porte un, en français et
    // en tutoiement (R7, R9).

    public enum Voice {
        public static let back = "Revenir au voyage"
        public static let settings = "Paramètres du voyage"
        public static let map = "Voir le voyage sur la carte"
        public static let openPreview = "Ouvrir l’aperçu de ton carnet"
        public static let readAloud = "Lire ce message à voix haute"
        public static let stopReading = "Arrêter la lecture à voix haute"
        public static let copy = "Copier ce message"
        public static let copied = "Message copié"
        public static let edit = "Modifier ce message"
        public static let menu = "Plus d’actions"
        public static let collapse = "Revenir aux trois boutons"
        public static let camera = "Ajouter une photo"
        public static let keyboard = "Écrire au clavier"
        public static let microphone = "Enregistrer un vocal"
        public static let microphoneDenied = "Micro refusé — ouvrir les Réglages"
        public static let pauseRecording = "Mettre l’enregistrement en pause"
        public static let resumeRecording = "Reprendre l’enregistrement"
        public static let discardRecording = "Jeter cet enregistrement"
        public static let stopRecording = "Arrêter l’enregistrement"
        public static let send = "Envoyer"
        public static let thinking = "MEMO réfléchit"
        public static let play = "Écouter ce vocal"
        public static let pause = "Mettre ce vocal en pause"

        public static func voiceNote(duration: String) -> String {
            "Vocal de \(duration)"
        }

        public static func transcript(day: String) -> String {
            "Retranscription du contexte, \(day)"
        }

        public static func photos(count: Int) -> String {
            count == 1 ? "Une photo" : "\(count) photos"
        }
    }
}
