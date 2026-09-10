import SwiftUI
import UIKit

// Palette et typographie de la marque, reprises des variables Figma du fichier
// « MemoBook — Product ». Ce fichier est la seule source de vérité : aucune
// couleur ni police n'est codée en dur ailleurs dans l'app.
//
// Les couleurs sont volontairement **fixes** et non adaptatives. MemoBook est
// un carnet de papier crème : basculer en sombre retournerait la marque plutôt
// que de la servir. Les écrans qui utilisent cette palette forcent donc
// `.colorScheme(.light)`.

private extension Color {
    /// `#rrggbb` → couleur sRGB. Les valeurs viennent des variables Figma,
    /// autant les garder lisibles telles quelles dans le code.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Couleurs de l'app. Noms Figma en commentaire de chaque token.
public enum MemoBookColor {
    /// Couleur d'action : boutons primaires, liens, sélection, teinte de
    /// navigation. — Figma `Brand Colors/Green`.
    public static let action = Color(hex: 0x28654B)

    /// Vert clair de la marque : les signaux discrets, là où le vert du CTA
    /// serait trop appuyé. — Figma `Brand Colors/Green Lighter`, relevé sur le
    /// nœud de l'accueil.
    public static let actionLight = Color(hex: 0x3D9A6F)

    /// État « enregistrement en cours », et rien d'autre. Jamais un lien,
    /// jamais un CTA — c'est le voyant du micro qui s'allume. La convention
    /// iOS (Dictaphone) l'emporte ici sur la palette de marque.
    public static let recording = Color(uiColor: .systemRed)

    /// Texte principal, un noir chaud. — Figma `Brand Colors/Black`,
    /// aussi `Scheme/Text`.
    public static let ink = Color(hex: 0x2D231A)

    /// Texte secondaire, légendes. — Figma `Grays/Gray`.
    ///
    /// Le gris **système** d'iOS. Il tient sur les écrans d'entrée dans l'app,
    /// mais ce n'est pas le gris de la marque : voir ``inkMuted``.
    public static let inkSecondary = Color(hex: 0x8E8E93)

    /// Texte secondaire de la marque : l'encre à 50 %, pas un gris neutre. Un
    /// gris tiré du noir chaud se pose sur le crème sans le refroidir, ce que
    /// le gris système fait. — Figma `Brand Colors/Grey Typo` (`#2B231B80`),
    /// relevé sur le nœud de l'accueil.
    public static let inkMuted = Color(hex: 0x2B231B).opacity(0.5)

    /// La même encre, encore plus effacée : **les mentions**, celles qu'on lit
    /// une fois et jamais plus — la version de l'app, le droit d'auteur. Assez
    /// claire pour se fondre dans le crème, assez présente pour rester lisible.
    /// Ne jamais y poser autre chose : un texte qu'on doit lire n'est pas une
    /// mention.
    public static let inkFaint = Color(hex: 0x2B231B).opacity(0.3)

    /// Fond des écrans, le crème de la marque. — Figma
    /// `Scheme/Background Light`.
    public static let background = Color(hex: 0xFCF2E9)

    /// Cartes et zones de contenu. — Figma `Brand Colors/White`.
    public static let surface = Color(hex: 0xFFFCF8)

    /// Bordures des cartes et pastilles numérotées. — Figma
    /// `Brand Colors/Blue`.
    public static let outline = Color(hex: 0xAFD2F0)

    /// Le fond d'une bulle du voyageur, dans le chat. — Figma `Chat Bubble`.
    ///
    /// Le style Figma vaut exactement ``outline``, et l'alias existe quand même :
    /// une bulle de conversation n'est pas un contour de carte, et le jour où
    /// Clara sépare les deux, il n'y a qu'ici à changer. C'est aussi le rappel
    /// que ce bleu est un **aplat** : le texte qu'il porte est ``ink``, jamais du
    /// bleu — voir l'avertissement de ``blueText``.
    public static let bubbleTraveller = outline

    /// Le fond d'une bulle de MEMO. — Figma `Neutral/100` (#FFFFFF).
    ///
    /// La maquette dit le blanc pur ; l'app pose son blanc crème (``surface``,
    /// #FFFCF8). L'écart vaut trois points sur deux canaux, invisible sur le
    /// fond crème, et le blanc pur viendrait d'un kit iOS et non des variables
    /// de la marque : deux blancs presque identiques dans la même app coûtent
    /// plus cher que cet écart-là. Signalé — voir la fiche du chat.
    public static let bubbleMemo = surface

    /// Accent du scheme, très saturé. Il souligne un chiffre, une pastille, et
    /// **il peut porter un fond de bouton** — mais à une condition, qui n'est
    /// pas négociable : le libellé et le filet sont alors ``action``, jamais
    /// l'encre. Le lime est trop clair pour porter du noir sans virer au
    /// surligneur, et trop clair pour porter du blanc tout court.
    ///
    /// C'est la règle qu'appliquent ``BrandButton/Style/accent`` et
    /// ``BrandTagPill/Tone/accentOutlined`` ; aucun autre emploi en aplat large
    /// n'est prévu. — Figma `Scheme/Accent` (Lime). Arbitrage D13 (T68).
    public static let accent = Color(hex: 0xE2F32B)

    /// Le filet qui sépare deux blocs dans une même carte : le noir de la
    /// marque à 10 %, pas un gris. — Figma `Scheme/Borders`.
    public static let hairline = Color(hex: 0x2B231B).opacity(0.1)

    /// Bleu assez soutenu pour porter du texte sur un aplat bleu clair.
    ///
    /// ⚠️ **Ce n'est pas encore une variable Figma.** `Brand Colors/Blue`
    /// (#AFD2F0) est un bleu d'aplat : posé en texte sur son propre fond clair,
    /// il tombe à 1,3:1 et devient illisible. Ces deux valeurs gardent sa
    /// teinte (209°) en montant la saturation et en baissant la clarté, ce qui
    /// donne 5,1:1 et 3,1:1 sur le fond de la carte de découverte. À faire
    /// entrer dans les variables Figma sous le nom qu'aura choisi Clara —
    /// voir T12 dans `docs/ui-development.md`.
    public static let blueText = Color(hex: 0x4780B3)
    public static let blueTextSoft = Color(hex: 0x74A6D0)

    /// Beige soutenu, pour les séparateurs et les aplats discrets. — Figma
    /// `Brand Colors/Beige Darker`.
    public static let separator = Color(hex: 0xCFBBAA)

    /// Bleu clair : **le fond des écrans où l'app écoute**. Aujourd'hui la
    /// feuille d'enregistrement, et rien d'autre. Le crème est le papier du
    /// carnet, celui sur lequel on lit ; ce bleu dit qu'on est passé de l'autre
    /// côté, en train de parler.
    ///
    /// ⚠️ **Pas encore une variable Figma** : relevé sur la maquette de
    /// l'enregistrement. C'est `Brand Colors/Blue` (#AFD2F0) éclairci — il doit
    /// porter du texte encre et une waveform verte, ce que le bleu d'aplat ne
    /// fait pas assez confortablement. À nommer par Clara.
    public static let listeningBackground = Color(hex: 0xC9DDF0)

    /// Beige clair : **l'aplat sur lequel se pose une illustration de marque**,
    /// et rien d'autre. Plus chaud et plus soutenu que le crème du fond, juste
    /// assez pour que la plaque se détache sans devenir une carte. — Figma
    /// `Brand Colors/Beige`.
    public static let beige = Color(hex: 0xF9E6D6)

    /// Aplat d'un contrôle désactivé. Volontairement gris et non teinté :
    /// « indisponible » ne doit pas ressembler à une couleur de marque.
    public static let disabled = Color(hex: 0xC3C3C7)

    /// Le contour d'un contrôle **indisponible** qui garde sa place — le bouton
    /// micro quand l'accès est refusé. — Figma `Brand Colors/Grey`.
    ///
    /// Distinct de ``disabled``, qui est un aplat : ici le pavé reste blanc et
    /// c'est son cerne qui perd le vert. Un bouton grisé en entier se lirait
    /// comme absent, alors qu'il a quelque chose à dire — d'où l'icône barrée
    /// qu'il porte.
    public static let disabledOutline = Color(hex: 0xC8C8C8)

    /// Le bleu du bouton d'envoi, une fois qu'il y a quelque chose à envoyer.
    /// — Figma `chat/toolbar/input-btn-active`.
    ///
    /// ⚠️ **Il n'est pas dans la palette de marque** : c'est un bleu-violet
    /// emprunté au kit de messagerie de la maquette. Il tient parce qu'un envoi
    /// n'est pas une action de marque mais un geste de système — le même que la
    /// flèche bleue d'iMessage —, et parce que le vert de MemoBook sert déjà à
    /// « c'est ici qu'on appuie » partout ailleurs. À faire entrer dans les
    /// variables sous le nom que choisira Clara — voir T59.
    public static let send = Color(hex: 0x5D6CF5)

    /// Surfaces « carnet » : aperçu du livre, cartes de couverture.
    public static let paper = Color(hex: 0xFFFCF8)

    /// Texte posé sur `action` ou sur une surface sombre. — Figma
    /// `Brand Colors/White`.
    public static let onAction = Color(hex: 0xFFFCF8)

    // Couleurs sémantiques — retours système uniquement (statuts, messages),
    // jamais de la décoration. Reprises des variables Figma.
    //
    // Elles ne viennent plus des couleurs système d'iOS : celles-ci s'adaptent
    // au thème et à l'appareil, alors que la palette de la marque est fixe. Un
    // rouge système sur le crème de MemoBook ne tombait pas juste.

    /// Réussite. — Figma `Success`. Volontairement distinct du vert d'action :
    /// « c'est fait » n'est pas « c'est ici qu'on appuie ».
    public static let valid = Color(hex: 0x3FA673)

    /// Avertissement. — Figma `Warning`.
    public static let warning = Color(hex: 0xFF682C)

    /// Échec. — Figma `Error`.
    public static let error = Color(hex: 0xDE2B2E)

    /// Information neutre, sans jugement. — Figma `Information`.
    public static let information = Color(hex: 0x4A8FE0)
}

/// Échelle d'espacement de 8 pt, plus les marges de référence.
public enum MemoBookSpacing {
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 16
    public static let m: CGFloat = 24
    public static let l: CGFloat = 32
    public static let xl: CGFloat = 40

    /// **La** marge horizontale de l'app. Tout ce qui touche le bord d'un
    /// écran — texte, cartes, boutons, listes — s'aligne dessus, sans
    /// exception : c'est cet alignement unique qui fait qu'un écran se lit
    /// comme une colonne et pas comme un empilement de blocs.
    ///
    /// La changer ici la change partout. Aucun écran ne doit coder sa propre
    /// marge latérale.
    public static let screenMargin: CGFloat = 24

    /// Espacement interne serré — le cran de 0.75 rem de l'échelle de
    /// `docs/ui-development.md` (§2.2), entre ``xs`` et ``s``. Les marges d'une
    /// carte de texte posée dans une feuille.
    public static let snug: CGFloat = 12

    /// L'espacement entre deux entrées d'une même liste — les trois temps du
    /// mode d'emploi de l'abonnement, par exemple. Le cran de 1.25 rem de
    /// l'échelle de `docs/ui-development.md` (§2.2, « espacement de section
    /// court »), qui manquait entre ``s`` et ``m``.
    public static let sectionGap: CGFloat = 20

    /// Rayon des champs et des cartes.
    public static let cornerRadius: CGFloat = 14

    /// Rayon des cartes de la page d'accueil et du bouton principal.
    public static let largeCornerRadius: CGFloat = 20

    /// Rayon d'une vignette de la galerie — 1.5 rem.
    ///
    /// Entre la carte de l'accueil (20) et la feuille modale (28), et
    /// volontairement distinct des deux : les cartes de la galerie sont des
    /// **images pleines**, sans marge intérieure ni fond. Un coin plus rond y
    /// est ce qui les empêche de se lire comme des photos collées bord à bord.
    public static let galleryCornerRadius: CGFloat = 24

    /// Taille minimale d'une cible tactile.
    public static let minimumTapTarget: CGFloat = 44

    /// **Le** diamètre d'un avatar posé sur une ligne de titre — la vignette de
    /// l'accueil, celle de l'en-tête du chat.
    ///
    /// Volontairement **fixe**, hors Dynamic Type : une photo n'est pas du
    /// texte, et un avatar qui grandit avec le corps pousse le titre hors de sa
    /// ligne au lieu de l'accompagner.
    public static let avatarSide: CGFloat = 40

    /// Le rayon d'une bulle de conversation. — Figma dessine 11 ; R2 arrondit au
    /// cran de l'échelle (§2.2 de `docs/ui-development.md`).
    ///
    /// Plus serré que ``cornerRadius`` (14) et que ``largeCornerRadius`` (20),
    /// et c'est voulu : une bulle est une réplique, pas une carte. C'est ce
    /// rayon court qui fait qu'une suite de bulles se lit comme une
    /// conversation.
    public static let bubbleCornerRadius: CGFloat = 12

    /// **La** taille d'une icône d'en-tête : la flèche de retour d'abord, et
    /// les boutons qui l'accompagnent en tête d'un écran.
    ///
    /// Elle existe pour une seule raison : la flèche de retour est le même
    /// geste sur tous les écrans, elle doit donc y avoir la même taille. Elle
    /// valait ``m`` (24) à trois endroits et se redessinait à la main au
    /// quatrième ; il suffisait d'un écran écrit un jour différent pour que la
    /// sortie change de taille en cours de route.
    ///
    /// Plus grande que les icônes de contenu (24) : c'est une **sortie**, elle
    /// se vise sans regarder. La cible tactile, elle, reste
    /// ``minimumTapTarget`` — l'icône grandit dedans, pas à sa place.
    public static let navigationIcon: CGFloat = 28

    /// **La** hauteur d'un appel à l'action. Tous les CTA de l'app la
    /// partagent — « Continuer », « Continuer avec Apple », « Continuer avec
    /// Google » — pour qu'une pile de boutons se lise comme une pile et non
    /// comme trois contrôles différents.
    ///
    /// La valeur est un compromis avec Apple. `SignInWithAppleButton` ne laisse
    /// choisir ni la taille de son libellé ni celle de sa pomme : il déduit les
    /// deux de la hauteur du bouton — environ 0,35 × pour le texte, 0,29 × pour
    /// le logo. Tout se tient donc à cette seule valeur.
    ///
    /// À 56 pt le texte d'Apple dépassait le nôtre de 40 %. À 44 pt les textes
    /// s'accordaient, mais sa pomme tombait à 12,7 pt contre 19 pour le logo
    /// Google. Amener la pomme à 19 pt demanderait un bouton de 66 pt, où le
    /// texte repartirait à 23 pt.
    ///
    /// 50 pt est le point d'équilibre : assez épais pour un appel à l'action,
    /// et c'est ``MemoBookFont/button`` et ``markSide`` qui viennent s'aligner
    /// dessus plutôt que l'inverse.
    public static let controlHeight: CGFloat = 50

    /// Hauteur d'un champ de saisie. Plus haute qu'un bouton, et découplée de
    /// lui : la hauteur des CTA est contrainte par le bouton d'Apple, dont on
    /// ne choisit pas la typographie. Un champ n'a pas à payer cette contrainte
    /// — il doit respirer autour de son texte et de son étiquette flottante.
    public static let fieldHeight: CGFloat = 56

    /// **Le** rayon des contrôles : boutons et champs de saisie. Les deux le
    /// partagent depuis toujours — cette constante ne fait que lui donner un
    /// nom, pour qu'un troisième contrôle ne parte pas sur une autre valeur.
    public static let controlCornerRadius: CGFloat = 16

    /// Rayon du panneau qui remonte par-dessus une photo pleine largeur, comme
    /// l'accueil d'un voyage. Plus grand que celui d'une feuille : il doit se
    /// lire comme une page qui recouvre l'image, pas comme une carte posée
    /// dessus.
    public static let overlayCornerRadius: CGFloat = 40

    /// Rayon du haut d'une feuille modale. Plus grand que celui d'une carte :
    /// c'est un écran qui monte par-dessus, pas un bloc posé dedans.
    public static let sheetCornerRadius: CGFloat = 28
}

/// Typographies de la marque : Sora pour les titres, General Sans pour tout le
/// reste. Les deux sont embarquées dans ce module (voir `BrandFonts`).
///
/// Chaque style passe par `relativeTo:` pour suivre le Dynamic Type : les
/// tailles ci-dessous sont celles de la maquette à la taille système par
/// défaut, et grandissent avec les réglages d'accessibilité.
public enum MemoBookFont {
    /// Interlettrage de la maquette : 1 % de la taille du corps.
    public static func tracking(_ size: CGFloat) -> CGFloat { size * 0.01 }

    /// Titre d'écran. — Figma `App/h1` (Sora SemiBold 32).
    public static let h1 = Font.custom(BrandFonts.soraSemiBold, size: 32, relativeTo: .largeTitle)

    /// La moitié courante d'un titre du paywall — même corps que ``h1``, en
    /// Regular. La phrase se termine en SemiBold, et c'est ce contraste qui
    /// porte la chute (« Ton carnet comptera environ **40 pages !** »).
    public static let h1Light = Font.custom(BrandFonts.soraRegular, size: 32, relativeTo: .largeTitle)

    /// Le surtitre d'un écran du paywall : une ligne de Sora au-dessus du
    /// titre, qui annonce sans peser. — Sora Regular 16.
    public static let eyebrow = Font.custom(BrandFonts.soraRegular, size: 16, relativeTo: .body)

    /// Le lien discret d'une barre de navigation — « Besoin d'aide ? ». —
    /// Figma `App/h3` (Sora Regular 14).
    public static let h3 = Font.custom(BrandFonts.soraRegular, size: 14, relativeTo: .subheadline)

    /// Titre d'un écran secondaire, et nom propre affiché comme un titre. Plus
    /// petit qu'un ``h1`` : le profil, les réglages, une feuille modale
    /// s'annoncent, ils n'ouvrent pas l'app.
    ///
    /// ⚠️ **Pas encore une variable Figma** : relevé sur la maquette du profil
    /// (Sora SemiBold 24), entre `App/h1` (32) et `Heading 6` (20). À faire
    /// entrer dans les variables sous le nom que choisira Clara.
    public static let h2 = Font.custom(BrandFonts.soraSemiBold, size: 24, relativeTo: .title)

    /// Pastille d'accroche. — Figma `App/pastille notes` (General Sans Semibold 14).
    public static let tagline = Font.custom(BrandFonts.generalSansSemibold, size: 14, relativeTo: .subheadline)

    /// Même accroche, en graisse courante : pour les intitulés qui séparent
    /// deux blocs sans devoir peser autant qu'un titre (« Ou continue avec »).
    public static let taglineRegular = Font.custom(BrandFonts.generalSansRegular, size: 14, relativeTo: .subheadline)

    /// Corps de texte accentué. — Figma `App/body semibold` (General Sans Semibold 16).
    public static let bodySemibold = Font.custom(BrandFonts.generalSansSemibold, size: 16, relativeTo: .body)

    /// Corps de texte courant (General Sans Regular 16).
    public static let body = Font.custom(BrandFonts.generalSansRegular, size: 16, relativeTo: .body)

    /// Texte secondaire des cartes (General Sans Regular 12).
    public static let caption = Font.custom(BrandFonts.generalSansRegular, size: 12, relativeTo: .caption)

    /// Le texte d'une bulle de conversation (General Sans Regular 17).
    ///
    /// Un point de plus que ``body``, et l'écart est du dessin, pas un
    /// arrondi : la maquette du chat reprend la taille de message d'iOS, qui
    /// est celle qu'on lit en tenant son téléphone d'une main dans un train.
    /// Un fil entier en 16 se lit moins bien qu'un paragraphe de carte en 16.
    ///
    /// ⚠️ **Pas encore une variable Figma** : relevé sur les nœuds du chat
    /// (General Sans Regular 17). À faire entrer dans les variables sous le nom
    /// que choisira Clara.
    public static let bubble = Font.custom(BrandFonts.generalSansRegular, size: 17, relativeTo: .body)

    /// L'action posée **dans** une bulle — « Voir plus ». Même taille que
    /// ``bubble``, une graisse au-dessus : elle se distingue du récit sans
    /// changer de corps, donc sans casser la ligne.
    public static let bubbleAction = Font.custom(BrandFonts.generalSansMedium, size: 17, relativeTo: .body)

    /// Ce qu'on tape dans la barre d'envoi, et le libellé « Record » à côté.
    /// (General Sans Regular 21.)
    ///
    /// Plus gros que le texte des bulles, et c'est voulu : on écrit d'une main,
    /// souvent en marchant, et c'est la seule ligne de l'app qu'on relit
    /// pendant qu'on la produit.
    ///
    /// ⚠️ **Pas encore une variable Figma** : relevé sur le nœud des états de
    /// la barre d'envoi (General Sans Regular 21).
    public static let composer = Font.custom(BrandFonts.generalSansRegular, size: 21, relativeTo: .body)

    /// Les mentions de bas de page : version de l'app, droit d'auteur. Le plus
    /// petit corps de la marque, et le seul en dessous de la légende — il ne
    /// porte jamais rien qu'on demande de lire.
    public static let mention = Font.custom(BrandFonts.generalSansRegular, size: 11, relativeTo: .caption2)

    /// Messages adressés à l'utilisateur : erreurs, réussites, avertissements.
    /// Ils ont la taille du corps de texte et non celle d'une légende — une
    /// notification qu'on doit chercher pour la lire a raté son travail.
    public static let notification = body

    /// Libellé des boutons. Le design system dit Sora SemiBold 16 ; on est à 18.
    ///
    /// L'écart vient du bouton d'Apple, dont la typographie n'est pas
    /// négociable : à la hauteur d'appel à l'action de l'app, son libellé fait
    /// 17,4 pt d'encre. Rester à 16 laissait un écart d'un quart entre deux
    /// boutons empilés, qu'on lisait immédiatement. C'est la seule valeur du
    /// design system qu'une contrainte extérieure nous fait bouger.
    public static let button = Font.custom(BrandFonts.soraSemiBold, size: 18, relativeTo: .body)

    /// Titres de section dans les écrans système.
    public static let sectionTitle = Font.custom(BrandFonts.generalSansSemibold, size: 17, relativeTo: .headline)

    /// Salutation de l'accueil : « Bienvenue Camille ». Plus petite qu'un
    /// titre d'écran, parce qu'elle partage sa ligne avec l'avatar. —
    /// `Heading 5` (24).
    ///
    /// General Sans **Regular** et non Sora : la salutation s'adresse, elle ne
    /// titre pas. Sora reste aux titres de section et de carte.
    public static let greeting = Font.custom(BrandFonts.generalSansRegular, size: 24, relativeTo: .title2)

    /// Titre d'une section de l'accueil, et titre d'une carte de voyage. —
    /// `Heading 6` / `Text Large` (20).
    public static let heading = Font.custom(BrandFonts.soraSemiBold, size: 20, relativeTo: .title3)

    /// Titre d'une carte posée **dans** une feuille — « Comment résilier ? ».
    /// Sora, comme les titres, mais à la taille du corps de texte : la carte
    /// s'annonce sans concurrencer le titre de la feuille.
    ///
    /// ⚠️ **Pas encore une variable Figma** : relevé sur le nœud des modales
    /// d'abonnement (Sora SemiBold 16).
    public static let cardTitle = Font.custom(BrandFonts.soraSemiBold, size: 16, relativeTo: .body)

    /// Titre d'un encadré de texte — « Résiliation automatique à la fin de ton
    /// voyage à Rome. » General Sans et non Sora : c'est une phrase qu'on lit,
    /// pas un intitulé de section. C'est ce qui le distingue de ``heading``,
    /// qui a la même taille en Sora.
    ///
    /// ⚠️ **Pas encore une variable Figma** : relevé sur le nœud des modales
    /// d'abonnement (General Sans Semibold 20).
    public static let calloutTitle = Font.custom(BrandFonts.generalSansSemibold, size: 20, relativeTo: .title3)

    /// Ligne de métadonnées : dates, compteurs, sous-titres de carte. —
    /// `Text Small` (14).
    public static let label = Font.custom(BrandFonts.generalSansMedium, size: 14, relativeTo: .subheadline)

    /// Surtitre en capitales et pastilles d'état. — `Text Tiny` (12).
    public static let overline = Font.custom(BrandFonts.generalSansSemibold, size: 12, relativeTo: .caption)

    /// Titres de **carnet** uniquement, jamais les titres d'écran système.
    public static func bookTitle(_ size: CGFloat = 28) -> Font {
        .custom(BrandFonts.soraSemiBold, size: size, relativeTo: .title)
    }

    public static let screenTitle = h1

    /// Transcription brute : le monospace signale « pas encore mis en forme ».
    public static let transcript = Font.system(.callout, design: .monospaced)
}

/// Les deux ombres de la marque, reprises des effets nommés du fichier Figma.
///
/// Deux, et pas plus. Une app qui empile cinq élévations perd la seule chose
/// qu'une ombre sait dire : ce qui est posé sur la page, et ce qui flotte
/// au-dessus d'elle.
public enum MemoBookShadow {
    /// Ce qui est posé sur la page : une pastille, un pavé de barre d'outils.
    /// — Figma `medium shadow` (0, 1, rayon 2, noir à 10 %).
    case soft

    /// Ce qui flotte au-dessus de la page : les commandes de la barre d'envoi
    /// du chat, qui doivent se détacher du fil qui défile dessous.
    /// — Figma `Elevation-200` (0, 4, rayon 12, noir à 15 %).
    case raised

    fileprivate var color: Color {
        switch self {
        case .soft: .black.opacity(0.1)
        case .raised: .black.opacity(0.15)
        }
    }

    fileprivate var radius: CGFloat {
        switch self {
        case .soft: 2
        case .raised: 12
        }
    }

    fileprivate var offset: CGFloat {
        switch self {
        case .soft: 1
        case .raised: 4
        }
    }
}

extension View {
    /// Pose l'une des deux ombres de la marque. — voir ``MemoBookShadow``.
    public func brandShadow(_ level: MemoBookShadow) -> some View {
        shadow(color: level.color, radius: level.radius, y: level.offset)
    }
}
