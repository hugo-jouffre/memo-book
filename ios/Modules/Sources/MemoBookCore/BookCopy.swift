import Foundation

// Tout ce que le parcours « carnet » écrit : les paramètres du voyage, la
// composition du PDF, son aperçu et son partage.
//
// Un seul fichier pour ces écrans, comme ``ChatCopy`` en tient un pour le
// chat : ils se relisent d'un trait, et R8 (« tous les libellés passent par des
// constantes localisables ») n'a qu'un endroit à tenir.
//
// **Les conventions typographiques de l'app** : apostrophe typographique `’`
// (U+2019) partout, espace insécable avant `?` et `!`, points de suspension `…`
// (U+2026), guillemets français `«  »`.
//
// ⚠️ **Le vouvoiement de la maquette est corrigé ici, et plus recopié**
// (Hugo, 16/09/2026). R8 dit « la copie de Figma au caractère près », R9 dit
// « on tutoie l'utilisateur, toujours » : les deux s'opposaient sur une dizaine
// de phrases du carnet et du voyage, qui vouvoyaient au milieu
// d'une app qui tutoie. R9 l'emporte, comme il l'emportait déjà sur les cinq
// feuilles de l'abonnement (`SubscriptionCopy`). Chaque phrase corrigée le dit
// dans son commentaire, et la liste des écarts vit dans la fiche écran pour que
// Clara les reprenne **à la source**.
//
// Les trois coquilles qui restaient — « grace », « Prévisulation », « Défini »
// — sont corrigées dans Figma et ici (Hugo, 17/09/2026, T67). Et l'ordinal
// s'abrège « 1ère » partout, comme la maquette (T91).
public enum BookCopy {

    // MARK: - Paramètres du voyage

    public enum Settings {
        public static let title = "Paramètres du voyage"

        public static let adventureSection = "Gère ton aventure"
        public static let quickAccessSection = "Accès rapide"

        public static let name = "Nom de l’aventure"
        public static let dates = "Dates du voyage"
        public static let pace = "Rythme du récit"
        public static let notifications = "Notifications"
        public static let manageNotifications = "Gérer mes notifications"
        public static let companions = "Co-voyageur(s)"
        public static let theme = "Thème de l’aventure"
        public static let publicGallery = "Partager sur la galerie de la communauté"
        public static let style = "Style du carnet"
        /// « Manière d'être rédigé » — la ligne qui ouvre ``Redaction`` (T292).
        /// Juste sous « Style du carnet » : l'une dit comment le livre se
        /// dessine, l'autre comment il s'écrit.
        public static let redaction = "Manière d’être rédigé"

        /// **La manière d'être rédigé** (T292) — la feuille qui porte les trois
        /// manières, le champ d'indications, et « Tout faire reprendre ».
        ///
        /// Les clés sont dans ``RedactionManner`` ; les fiches qui pilotent
        /// vraiment le modèle sont dans `agents/redaction-manieres/`. Ce qui est
        /// ici est ce que le voyageur lit, et les deux n'ont pas à bouger
        /// ensemble.
        public enum Redaction {
            public static let title = "Manière d’être rédigé"
            public static let subtitle = "Choisis comment MemoBook écrit ton carnet. Tu peux changer d’avis : tout le carnet sera repris."

            public static let spoken = "Comme je parle"
            public static let spokenDetail = "Le carnet garde ta façon de raconter : tes mots, ton humour, tes images."
            public static let literary = "Récit littéraire"
            public static let literaryDetail = "Des phrases plus amples, moins d’oral, le souvenir raconté comme une page de livre."
            public static let factual = "Journal factuel"
            public static let factualDetail = "Ce qui s’est passé, dans l’ordre, en quelques phrases. Pas d’effets de style."

            /// La pastille sur la manière qu'on n'a pas choisie : c'est celle
            /// de tout le monde tant qu'on ne touche à rien.
            public static let byDefault = "Par défaut"

            public static let notesTitle = "Tes indications"
            public static let notesPlaceholder = "« Appelle-moi Max », « pas de surnoms », « garde mes expressions »…"
            /// Dit la limite **et** le rang : une indication ne passe pas
            /// devant les règles de rédaction, et le voyageur doit le savoir
            /// avant d'écrire « invente ce qui manque ».
            public static let notesHelp = "Quelques mots sur la façon de t’écrire. MemoBook n’inventera jamais ce que tu n’as pas raconté, même si tu le demandes."

            /// L'avertissement **avant** le changement : c'est là que le
            /// consentement est donné, le serveur ne le redemande pas.
            public enum Confirm {
                public static let title = "Reprendre tout le carnet ?"
                public static let body = "Chaque étape déjà écrite sera rédigée à nouveau dans cette manière. Ce que tu as corrigé à la main ne sera pas touché. Ça prend quelques minutes."
                public static let keep = "Annuler"
                public static let go = "Reprendre le carnet"
            }

            public static let rewrite = "Tout faire reprendre"
            public static let rewriteDetail = "Repasse le carnet dans la manière en cours, sans rien changer."

            /// La notice sous le réglage pâli : la cause **et** la sortie,
            /// comme le demande `ios/CLAUDE.md`.
            public static let needsUnlimited = "Changer de manière fait reprendre tout ton carnet, et c’est réservé à l’illimité. Passe en illimité pour choisir."
        }

        public static let tricountTitle = "Connecte ton Tricount"
        public static let tricountMessage =
            "MemoBook pourra déduire tes étapes et t’aider à raconter des souvenirs à partir de tes dépenses"

        public static let pdfPreview = "Prévisualisation PDF"
        public static let pdfPreviewDetail = "Aperçu et partage"

        public static let order = "Commander le carnet"
        public static let help = "Besoin d’aide ?"

        /// Le lien à l'encre juste au-dessus du rouge, sur le même dessin que
        /// « Me déconnecter » sur le profil : on efface le fil, pas le voyage
        /// (Hugo, 17/09/2026).
        public static let clearConversation = "Supprimer la conversation"

        /// Le lien rouge tout en bas de l'écran, sous « Besoin d'aide ? » —
        /// le même dessin que « Supprimer mon compte » sur le profil.
        public static let delete = "Supprimer ce voyage"

        /// La feuille de confirmation, sur le modèle de celle du voyage. Elle
        /// dit ce qui reste autant que ce qui part : le mot d'accueil de MEMO
        /// revient, et les souvenirs déjà dans le carnet n'y sont pour rien.
        public enum ClearConversation {
            public static let title = "Supprimer la conversation ?"
            public static let body = "Les messages échangés avec MEMO dans ce voyage seront effacés, et la conversation repartira de son mot d’accueil. Les souvenirs déjà enregistrés dans ton carnet sont conservés. C’est immédiat et sans retour."
            public static let keep = "Garder la conversation"

            /// La notice sous le lien pâli, pour un co-voyageur : la cause et
            /// la sortie (`docs/conversation.md` § 7).
            public static let ownerOnly = "Seul le propriétaire du voyage peut supprimer la conversation. Tu peux continuer à raconter, et lui demander si tu veux repartir de zéro."
            public static let confirm = "Supprimer la conversation"
        }

        /// La feuille de confirmation, sur le modèle de celle du compte : ce
        /// que la suppression emporte, et les deux issues.
        public enum Delete {
            public static let title = "Tu es sûr de vouloir supprimer ce voyage ?"

            /// Ce qui part, dit avant plutôt qu'après. Les commandes passées
            /// pour ce carnet partent avec lui — c'est ce que fait
            /// `services/deletion.ts`.
            ///
            /// Sans nom — les réglages n'ont pas chargé, ou le voyage n'en a
            /// pas —, la phrase dit « Ce voyage » plutôt que d'ouvrir des
            /// guillemets sur du vide, ce qu'elle faisait (Hugo, 16/09/2026).
            public static func body(trip: String?) -> String {
                let trimmed = trip?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let subject = trimmed.isEmpty ? "Ce voyage" : "« \(trimmed) »"
                return "\(subject) disparaîtra pour toi comme pour tes co-voyageurs : ses souvenirs, ses photos, son carnet et les commandes passées pour lui. Tu pourras le récupérer pendant 30 jours, en bas de l’accueil ; après quoi il sera effacé pour de bon."
            }

            public static let keep = "Garder ce voyage"
            public static let confirm = "Mettre ce voyage à la corbeille"
        }

        // MARK: Personnalisations du carnet

        /// La valeur d'une ligne dont le voyage n'a rien à dire. Un tiret cadratin
        /// et non une chaîne vide : une ligne sans valeur se lirait comme une
        /// valeur qui n'a pas chargé.
        public static let noValue = "—"
    }

    // MARK: - Personnalisations du carnet

    public enum Customisation {
        public static let title = "Personnalisations du carnet"

        /// **Corrigée** : la maquette vouvoie (« Ajuster les différents
        /// options … votre carnet vous ressemble »), avec un infinitif là où il
        /// faut un impératif et un accord manquant. R9 — « on tutoie
        /// l'utilisateur, toujours » — l'emporte ici sur R8, tranché par Hugo
        /// le 16/09/2026 pour toute la copie du carnet et du voyage. L'écart
        /// est à reprendre à la source dans Figma.
        public static let intro =
            "Ajuste les différentes options de MemoBook pour que ton carnet te ressemble de plus en plus."

        public static let covers = "Couvertures (1ère & 4e)"
        public static let coversDetail = "Aperçu et personnalisation"

        public static let photoTextRatio = "Ratio photo / texte"
        public static let targetPageCount = "Nombre de page cible"

        public static let funFacts = "Fun facts"
        public static let rules = "Pointillés"
        public static let decorations = "Décorations & stickers"

        /// **Une seule ligne pour les quatre polices** (Hugo, 16/09/2026),
        /// rangée avec les décors : on règle l'allure du carnet d'un bloc.
        /// Elle remplace « Typographie des titres » et ses trois sœurs.
        public static let fonts = "Typographies"

        /// L'état d'un décor qu'on active ou non. Deux mots, pas un
        /// interrupteur : la maquette en fait une ligne qui **mène** à un choix,
        /// et le réglage aura plus de deux valeurs le jour où le gabarit les
        /// acceptera.
        public static func toggleValue(_ isOn: Bool) -> String {
            isOn ? "Activé" : "Désactivé"
        }

        public static let extrasSection = "Extras"

        /// Les cinq pastilles de la tête de l'écran (V3, `3595:23807`), **au
        /// caractère près** : « Typos » est une abréviation de la maquette, pas
        /// la nôtre (R8). « Nmb de pages » en était une aussi ; elle s'écrit
        /// en entier depuis le 06/10/2026 (Hugo, T214).
        public static let categoryRatio = "Ratio media"
        public static let categoryPages = "Nombre de pages"
        public static let categoryDecorations = "Décorations & stickers"
        public static let categoryFonts = "Typos"
        public static let categoryExtras = "Extras"

        public static let quizTitle = "Quiz intégrés à l’histoire"
        public static let quizDetail =
            "MemoBook génère des mini quiz au fur et à mesure du récit. Découvre-les et réponds lors de la réception de ton carnet."

        public static let freeZonesTitle = "Zones libres"
        public static let freeZonesDetail =
            "Ajoute 1 zone blanche à la fin de chaque étape et 3 pages blanches à la fin du carnet"

        public static let crosswordTitle = "Mot fléché à la fin du livre"
        public static let crosswordDetail =
            "MemoBook génère une grille de mot fléché automatiquement à partir de tes récits, au moment de commander ton livre et la place à la fin du carnet."
    }

    // MARK: - Les couvertures

    /// Ce qu'écrit le parcours des deux plats : le choix, le style, la photo,
    /// les textes et les chiffres du dos.
    ///
    /// ``matchedStyle`` vouvoyait dans la maquette — « Assortie à votre 1e de
    /// couverture » ; elle tutoie depuis, et l'ordinal s'écrit « 1ère » comme
    /// partout dans l'app (Hugo, 17/09/2026, T91).
    public enum Covers {
        public static let title = "Couvertures"

        /// Le sous-titre de l'en-tête, différent à chaque étape : il dit ce
        /// qu'on est en train de changer.
        public static let styleSubtitle = "Changer le style graphique"
        public static let photoSubtitle = "Changer la photo de couverture"
        public static let textsSubtitle = "Modifier le titre et sous-titre"

        /// Le titre du dos « Dessin » : celui de la maquette de Hugo
        /// (`assets/covers`, 08/10/2026). Le dos n'a pas de titre qu'on écrit
        /// — seulement son texte de quatrième.
        public static let drawingBackHeading = "La route continue…"

        /// Les trois lignes de l'écran d'accueil des couvertures. La première
        /// dit « Changer **de** style », la ligne de l'en-tête « Changer **le**
        /// style » : c'est la maquette, et les deux se lisent bien.
        public static let changeStyle = "Changer de style graphique"
        public static let changePhoto = "Changer la photo de couverture"
        public static let editTexts = "Modifier les textes"

        public static let validate = "Valider"
        public static let choosePhoto = "Choisir la photo"
        public static let importPhoto = "Importer ma photo"

        public static let matchedStyle = "Assortie à ta 1ère de couverture"

        /// La photo choisie n'a pas pu être lue. Aucune maquette ne dessine cet
        /// état ; la phrase dit ce qui s'est passé et ce qu'on peut faire,
        /// plutôt que de laisser le carrousel inchangé sans explication.
        public static let importFailed =
            "Cette photo n’a pas pu être ouverte. Choisis-en une autre."

        // MARK: Ce qu'un style ne permet pas

        /// Pourquoi ce plat n'a pas de texte à écrire.
        ///
        /// **Elle nomme la cause et donne la sortie**, dans cet ordre : sans le
        /// second bout, on comprend qu'on ne peut pas sans savoir quoi faire —
        /// et le geste qui débloque est deux écrans plus haut.
        public static func noTextHere(_ face: CoverFace) -> String {
            "Le style choisi pour ta \(face.title) **ne porte aucun texte** : la photo occupe tout le plat. Change son style graphique pour pouvoir y écrire."
        }

        /// Pourquoi ce plat n'a pas de photo à choisir.
        public static func noPhotoHere(_ face: CoverFace) -> String {
            "Le style choisi pour ta \(face.title) **ne porte aucune photo** : c’est un aplat. Change son style graphique pour en ajouter une."
        }

        /// Le titre par défaut d'une première de couverture qu'on n'a pas encore
        /// écrite. Le nom du voyage, et non un texte d'invite : un plat vide se
        /// lirait comme un carnet raté.
        public static func defaultTitle(trip: String) -> String { trip }

        public enum Voice {
            public static let carousel = "Couvertures proposées"
            public static let selected = "Couverture sélectionnée"
            public static let photo = "Photo de couverture"
            public static func style(_ name: String) -> String { "Style \(name)" }
            public static let editTitle = "Modifier le titre"
            public static let editSubtitle = "Modifier le sous-titre"
            public static let editStats = "Modifier les chiffres du voyage"
            public static let previousCover = "Couverture précédente"
            public static let nextCover = "Couverture suivante"
        }

        // MARK: Les chiffres du dos

        public enum Stats {
            public static let title = "Choix des statistiques"

            /// « Choisis-en 3 ou 4 ». Les deux bornes viennent du gabarit —
            /// voir ``BookCovers/statRange``.
            public static let message = "Choisis-en 3 ou 4"

            /// Ce qui s'imprime au-dessus des chiffres, sur le plat.
            public static let heading = "Mon voyage en quelques chiffres"
        }
    }

    // MARK: - On compose ton Carnet

    public enum Composition {
        public static let title = "On compose ton carnet"
        public static let message =
            "Images, souvenirs, cartes et petits détails trouvent leur place dans une mise en page unique"

        /// Ce que VoiceOver annonce pendant la composition. L'animation, elle,
        /// est purement décorative et masquée : décrire une page qui se monte
        /// morceau par morceau ne dirait rien de plus que cette phrase.
        public static let voiceOverStatus = "Composition du carnet en cours"

        /// Sous la phrase de la phase, sur la page qui se monte (08/10/2026) :
        /// sans elle, une page qui se remonte pour la troisième fois se lirait
        /// comme une boucle cassée. **Sans maquette** : à relire (T253).
        public static let patience = "Ça peut prendre quelques minutes."

        /// La composition n'a pas bougé depuis plusieurs minutes : l'écran
        /// cesse d'attendre et propose de réessayer (19/10/2026). Le serveur
        /// relance de lui-même une composition restée en plan quand on
        /// réessaie. **Sans maquette** : à relire par Clara.
        public static let tooLong =
            "La composition prend plus de temps que prévu. Réessaie dans un moment."

        /// Ce que la composition fait en ce moment, sur la page qui se monte
        /// (06/10/2026 ; en carte par-dessus la page depuis le 08/10/2026). Une composition dure plusieurs minutes — la mise en
        /// page attend jusqu'à trois minutes les souvenirs encore en
        /// rédaction —, et une page montée en 2,6 s puis immobile se lirait
        /// comme un écran figé. **Sans maquette** : à relire par Clara (T143).
        ///
        /// `nil` avant le premier sondage, et sur un serveur qui ne dit pas la
        /// phase : la ligne reprend alors la plus générale.
        public static func phase(_ phase: BookRenderPhase?, pendingMemories: Int) -> String {
            switch phase {
            case .queued:
                return "Ton carnet attend son tour…"
            case .writing where pendingMemories == 1:
                return "On attend la fin de la rédaction d’un souvenir…"
            case .writing where pendingMemories > 1:
                return "On attend la fin de la rédaction de \(pendingMemories) souvenirs…"
            case .writing:
                return "On met tes souvenirs en pages…"
            case .composing, .ready:
                return "On fabrique le PDF de ton carnet…"
            case .failed, .unknown, nil:
                return "La composition de ton carnet est lancée…"
            }
        }
    }

    // MARK: - Aperçu PDF

    public enum Preview {
        public static let title = "Aperçu PDF"

        /// Le titre de la **feuille** d'aperçu, celle qu'ouvre la pastille
        /// « Voir un aperçu » du paywall.
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

        /// **Combien de fois le carnet a été composé** (T262, Hugo,
        /// 24/11/2026 — « savoir combien de carnets ont été générés »).
        ///
        /// Pas « édition n° 4 » : le mot *édition* promet un objet, et ce
        /// chiffre compte des fabrications, recompositions automatiques
        /// comprises. « Composé 4 fois » dit ce qu'il est.
        ///
        /// Le livre, lui, n'en porte rien — c'est l'écran qui le dit.
        public static func compositionCount(_ count: Int) -> String {
            count <= 1 ? "Composé une fois" : "Composé \(count) fois"
        }

        /// « 1 sur 24 » — le compteur de l'aperçu plein écran. Il compte les
        /// **feuilles du PDF**, là où l'indicateur du bas compte les pages du
        /// carnet : les deux diffèrent dès qu'une page tient sur deux feuilles.
        public static func sheetIndicator(_ index: Int, of total: Int) -> String {
            "\(index) sur \(total)"
        }

        public static let customise = "Personnaliser mon carnet"
        /// La porte vers les couvertures, **toujours là** sous les boutons :
        /// l'invitation sur la page ne s'affiche que tant qu'elles ne sont pas
        /// choisies, et l'aperçu n'offrait plus aucun chemin pour y revenir
        /// (Clara, 17/09/2026). Aucune maquette : un lien vert, au corps des
        /// boutons, comme « Besoin d'aide ? ».
        /// ⚠️ Plus de bouton « Configurer mes couvertures » sous l'aperçu
        /// (Hugo, 19/09/2026) : les couvertures se choisissent en touchant le
        /// voile de la première ou de la dernière page. La phrase reste, elle
        /// intitule l'invitation posée sur la page.
        public static let configureCovers = "Configurer mes couvertures"

        #if DEBUG
            /// Le titre d'un aperçu en pages blanches, quand le serveur n'a
            /// rien dit du carnet — voir `BookPreviewModel.showsBlankPages`.
            /// Debug seulement.
            public static let blankTitle = "Carnet sans contenu"
        #endif

        /// Sous l'en-tête de l'aperçu, tant qu'une étape validée recompose le
        /// carnet en fond — voir `BookPreviewModel.isRecomposing`. Léger et
        /// temporaire : les pages déjà là restent feuilletables pendant ce
        /// temps.
        public static let recomposing = "On remet à jour ton carnet…"

        /// **Sous l'en-tête, quand il n'y a pas de carnet derrière la page**
        /// (T302) : le serveur annonce un carnet prêt, mais aucun PDF n'existe.
        ///
        /// L'écran ne doit pas se présenter comme prêt. La page crème de
        /// `BookSheetImage` ne dit rien d'elle-même — c'est le papier du
        /// carnet, et on la prend pour une page blanche composée.
        public static let notComposed =
            "Ce carnet n’est pas encore composé : **ses pages arrivent** dès que MemoBook a fini de les mettre en page."

        /// **Sous l'en-tête, quand le carnet affiché est celui que l'appareil
        /// gardait** et que le serveur n'a rien dit — sans réseau, le plus
        /// souvent (T299).
        ///
        /// Elle nomme une **date**, et pas « hors ligne » : ce qui compte pour
        /// quelqu'un qui feuillette son carnet n'est pas l'état du réseau, c'est
        /// de savoir si ce qu'il a raconté hier soir y est. La phrase dit donc
        /// jusqu'où va ce qu'il regarde.
        public static func keptVersion(_ date: Date) -> String {
            "Voici ton carnet tel qu’il était \(Self.moment(date)). **Ce que tu as raconté depuis** y entrera à la prochaine mise en page."
        }

        /// **Sous l'en-tête, après un appui sur la flèche** quand il n'y avait
        /// rien à régénérer (T299).
        ///
        /// Le geste doit recevoir une réponse : sans elle, une flèche qui
        /// tourne une seconde et s'arrête se lit comme une panne. Et la réponse
        /// est une bonne nouvelle — le carnet est à jour —, pas une erreur.
        public static let alreadyUpToDate =
            "**Ton carnet est déjà à jour** : tout ce que tu as raconté y est mis en page."

        /// **Sous l'en-tête, après un appui sur la flèche pâlie** : il n'y a
        /// pas encore de carnet à mettre à jour (T299).
        ///
        /// Elle ne renvoie nulle part, parce qu'il n'y a rien à faire : la
        /// composition tourne, et c'est l'écran lui-même qui l'annoncera.
        public static let nothingToRegenerate =
            "Il n’y a rien à mettre à jour tant que ton carnet n’est pas composé. **Sa première mise en page est en cours** — la flèche s’ouvrira dès qu’elle aboutit."

        /// « hier soir », « ce matin », « le 12 novembre ».
        ///
        /// Le jour et le moment plutôt qu'une heure : une date au quart
        /// d'heure près est illisible, et personne ne se souvient avoir
        /// composé son carnet à 21 h 47. ``RelativeDateTimeFormatter`` dirait
        /// « il y a 14 heures », ce qui demande un calcul mental pour la même
        /// information.
        ///
        /// ⚠️ **« Aujourd'hui » se compte depuis `now`, et non depuis
        /// l'horloge** (27/11/2026). Les deux `isDateInToday` et
        /// `isDateInYesterday` d'avant lisaient la vraie date du jour : le
        /// paramètre `now` était accepté puis ignoré, et son test ne passait
        /// que le 26 novembre — la CI l'a rougi le lendemain à minuit passé.
        /// Rien ne change pour l'app, dont `now` **est** l'horloge.
        public static func moment(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
            let heure = calendar.component(.hour, from: date)
            let moment =
                switch heure {
                case 0..<5: "cette nuit"
                case 5..<12: "matin"
                case 12..<18: "après-midi"
                default: "soir"
                }

            if calendar.isDate(date, inSameDayAs: now) {
                return moment == "cette nuit" ? moment : "ce \(moment)"
            }
            let hier = calendar.date(byAdding: .day, value: -1, to: now)
            if let hier, calendar.isDate(date, inSameDayAs: hier) {
                return moment == "cette nuit" ? "la nuit dernière" : "hier \(moment)"
            }

            let jour = date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_FR")))
            return "le \(jour)"
        }

        #if DEBUG
            /// Ce qu'on lit dans le PDF d'attente, celui que l'app compose
            /// quand le carnet du serveur n'est pas chargé — voir
            /// `BookPreviewModel`.
            ///
            /// ⚠️ **Debug seulement depuis T302** : ce fichier est celui que
            /// Hugo a reçu en croyant partager son carnet. Il ne reste que
            /// pour le bac à sable, dont le jeu d'essai n'a pas de PDF.
            public static let placeholderPdfBody = """
                Ce carnet n’est pas encore composé : ce fichier tient sa place, le temps que MemoBook mette en page tes souvenirs.
                """
        #endif

        public static let order = "Commander ce carnet"

        /// La porte de service, sous le bouton grisé : commander alors que le
        /// carnet n'est pas composé.
        ///
        /// ⚠️ **Elle est dans la version livrée**, et pas seulement en debug
        /// (Hugo, 16/09/2026) : le tunnel de commande ne se teste pas de bout
        /// en bout autrement — il faut un TestFlight, et un TestFlight ne
        /// compile pas `#if DEBUG`. Elle est écrite en **lien souligné**, à
        /// l'encre depuis le 06/10/2026 (T219 : le beige ne se lisait pas),
        /// pour que personne ne la prenne pour l'appel à l'action, et elle dit
        /// ce qu'elle fait plutôt que « Commander quand même ».
        public static let orderAnyway = "Commander sans attendre la composition"

        public static let configureCover = "Définis maintenant\nta 1ère et 4ème de couverture"
        public static let configureCoverAction = "Configurer"

        public enum Voice {
            public static let previousPage = "Page précédente"
            public static let nextPage = "Page suivante"
            public static let enterFullScreen = "Afficher en plein écran"
            public static let exitFullScreen = "Quitter le plein écran"
            public static let share = "Partager mon carnet"
            /// La flèche de T299. « Mettre à jour » et non « Régénérer » :
            /// c'est ce qu'elle fait pour la personne qui appuie, et le mot du
            /// ticket — régénérer — est celui du serveur.
            public static let regenerate = "Mettre mon carnet à jour"
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

        /// **La réponse à un appui sur « Partager » fermé** (T302).
        ///
        /// Le bouton pâlit et reste tapable — « ce qu'on ne peut pas faire
        /// pâlit, ça ne se désactive pas » (`ios/CLAUDE.md`) —, et voilà ce
        /// qu'il répond. La sortie qu'il nomme est vraie : il n'y a rien
        /// d'autre à faire qu'attendre, et surtout rien à aller chercher
        /// ailleurs.
        ///
        /// ⚠️ **Elle ne dit plus « la composition repart à chaque ouverture »**
        /// (T299) : ce n'est plus vrai d'un carnet composé — l'ouverture montre
        /// celui qu'on garde, et c'est la flèche de l'en-tête qui demande une
        /// mise en page. Ça reste vrai d'un carnet qui n'en a jamais eu, le cas
        /// que cette phrase couvre, mais le dire ainsi apprendrait à sortir de
        /// l'écran et à y revenir pour rien.
        public static let notComposedYet =
            "Il n’y a rien à partager tant que ton carnet n’est pas composé. **Sa mise en page est en cours** — « Partager » s’ouvrira dès qu’elle aboutit."

        // MARK: Choisir les étapes (T285, 21/11/2026)

        /// La feuille qui précède le partage du fichier, quand le carnet a
        /// plus d'une étape. Tout est coché en arrivant : « tout depuis le
        /// début » n'est pas un choix à faire, c'est l'état de départ.
        public static let chooseTitle = "Qu'est-ce que tu envoies ?"
        public static let chooseLead =
            "Tout le carnet, ou seulement les étapes que tu choisis. La couverture part dans tous les cas."
        public static let chooseAll = "Tout le carnet"
        public static let chooseNone = "Tout décocher"

        /// « 2 pages », sous le titre de l'étape.
        public static func chapterPages(_ count: Int) -> String {
            count <= 1 ? "1 page" : "\(count) pages"
        }

        /// Le bouton qui envoie — il dit **ce qui part**, pour qu'on n'ait pas
        /// à recompter les coches.
        public static func chooseConfirm(chapters: Int, total: Int) -> String {
            if chapters >= total { return "Partager tout le carnet" }
            return chapters <= 1 ? "Partager 1 étape" : "Partager \(chapters) étapes"
        }
        public static let shareLink = "Partager le lien de prévisualisation"

        /// Le message pré-rempli dans WhatsApp, iMessage ou Snapchat.
        ///
        /// Il dit trois choses, dans cet ordre : ce qu'on prépare, où on en
        /// est, et où le suivre. Il demandait d'aider à financer la version
        /// imprimée, par la cagnotte ; elle est partie (Hugo, 06/10/2026,
        /// T230), et le lien ne mène plus qu'au carnet.
        ///
        /// **Il compte des pages, et le dit** (07/10/2026). Il annonçait « mes
        /// 10 premières étapes » en comptant les pages du carnet : l'aperçu et
        /// la commande ne connaissent pas les étapes, seulement les pages
        /// composées. Sans page — un carnet pas encore composé —, la phrase du
        /// compte se tait plutôt que d'annoncer « 0 page ».
        ///
        /// Le titre du carnet est entre guillemets **français** ; la
        /// spécification de Hugo employait des guillemets anglais fermants des
        /// deux côtés, ce qui est une glissade de clavier. Signalé.
        public static func invitation(title: String, pages: Int, link: URL) -> String {
            let opening = "Je prépare le carnet de mon voyage « \(title) »."
            let follow = "Tu peux suivre son avancée en direct sur ce lien : \(link.absoluteString)"
            guard pages > 0 else { return "\(opening) \(follow)" }
            let count = pages == 1 ? "1 page" : "\(pages) pages"
            return "\(opening) Il compte déjà \(count) ! \(follow)"
        }

        /// **Le message qui accompagne le PDF seul** (Hugo, 10/11/2026) :
        /// « c'est soit on partage direct le fichier PDF, soit on partage le
        /// lien de prévisualisation ». Le fichier part donc sans adresse à
        /// suivre — mais pas sans un mot, sans quoi WhatsApp n'affiche qu'une
        /// pièce jointe anonyme.
        public static func file(title: String, pages: Int) -> String {
            let opening = "Voici le carnet de mon voyage « \(title) »."
            guard pages > 0 else { return opening }
            return "\(opening) Il compte \(pages == 1 ? "1 page" : "\(pages) pages")."
        }

        /// Le sujet, quand l'app de destination en demande un — le courrier
        /// électronique, essentiellement.
        public static func subject(title: String) -> String {
            "Mon carnet de voyage « \(title) »"
        }

        /// Les deux gestes que la feuille du système ajoute à ses apps
        /// (`3551:26331`), recopiés tels quels (R8).
        public static let orderAction = "Commander"
        public static let whatsAppAction = "Partager sur Whatsapp"

        /// Le lien de prévisualisation n'existe pas encore et n'a pas pu se
        /// créer. On le dit sans jargon : ce n'est pas la faute de
        /// l'utilisateur, et le PDF reste partageable.
        public static let linkFailed =
            "Le lien de prévisualisation n’a pas pu se créer. Le fichier PDF, lui, reste partageable."
    }

    // MARK: - Les feuilles des réglages du voyage
    //
    // Copie reprise des nœuds de la page « 🤖 Claude Import » (section « Trip
    // settings ») — R8 pour tout ce qui n'est pas une adresse à la personne, et
    // R9 pour ce qui l'est : les phrases qui vouvoyaient sont **corrigées** et
    // le disent, au lieu d'être recopiées (voir l'en-tête du fichier).

    /// « Dates » — `3443:9881`.
    public enum Dates {
        public static let title = "Dates"
        public static let start = "Date de début"
        public static let end = "Date de fin (optionnel)"
    }

    /// « Rythme du récit » — `3443:9841`.
    public enum Pace {
        public static let title = "Rythme du récit"

        /// **Corrigée au tutoiement** — voir ``Customisation/intro``.
        public static let subtitle =
            "Ajuste le style de narration généré par l’IA pour refléter au mieux tes émotions et ta personnalité."
    }

    /// « Notifications » — `3443:9895`.
    public enum Notifications {
        public static let title = "Notifications"

        /// **Corrigée au tutoiement** — voir ``Customisation/intro``. Le nom
        /// du voyage est glissé dedans : la maquette écrit « Rome » en dur,
        /// l'app met celui qu'on regarde.
        public static func subtitle(trip: String) -> String {
            "Active ou désactive les alertes d’écriture du voyage à « \(trip) » pour ne rien rater sans être dérangé non plus."
        }

        /// Le second paragraphe du chapeau, sur un voyage partagé : ces
        /// alertes ne valent que pour qui les règle (D13, Hugo, 19/10/2026).
        /// Elles valaient pour tout le monde, et couper la sienne coupait
        /// celle des autres sans qu'ils le sachent.
        ///
        /// ⚠️ **Pas dans la maquette** — texte à relire par Clara.
        public static let personalNote =
            "Ces réglages ne valent que pour toi : tes co-voyageurs choisissent les leurs."

        public static let writingReminder = "Rappel d’écriture"
        public static let writingReminderDetail = "Alerte selon le rythme du récit choisi"
        public static let newStory = "Nouveau récit"
        public static let newStoryDetail = "Lorsqu’un proche alimente le carnet"
        public static let weeklyDigest = "Résumé hebdomadaire"
        public static let weeklyDigestDetail = "Un point sur les souvenirs capturés"
        public static let tripEnd = "Rappel de fin de voyage"
        public static let tripEndDetail = "Alerte pour valider l’impression finale"

        /// Ce que la feuille dit quand l'interrupteur maître est baissé : les
        /// quatre alertes restent lisibles, mais aucune ne partira.
        public static let mutedNotice =
            "Les notifications de ce voyage sont coupées : ces alertes reprendront quand tu les rallumeras."

        /// Ce que la feuille dit quand iOS refuse tout — la personne a dit non
        /// à la question du système, ou a tout coupé dans les Réglages. Les
        /// alertes s'enregistrent, mais aucune n'arrivera.
        ///
        /// ⚠️ **Pas dans la maquette** : la feuille `3023:15042` ne dessine que
        /// les quatre cartes. Texte à relire par Clara.
        public static let systemDeniedNotice =
            "Les notifications de MemoBook sont coupées dans les réglages de ton iPhone : aucune de ces alertes ne t’arrivera."
        public static let openSettings = "Ouvrir les réglages"
    }

    /// « Thème de l’aventure » — `3443:9937`.
    public enum Theme {
        public static let title = "Thème de l’aventure"

        /// **Corrigée au tutoiement** — voir ``Customisation/intro``.
        public static let subtitle =
            "Le thème ajuste le vocabulaire de l’IA et l’agencement graphique de tes souvenirs imprimés."

        public static let placeholder = "Trek entre amis"
        public static let validate = "Valider"
    }

    /// « Inviter un proche » — `3443:9805`.
    public enum Invite {
        public static let title = "Inviter un proche"

        /// **Corrigée au tutoiement** — voir ``Customisation/intro``.
        public static let subtitle =
            "Invite tes proches à participer au récit, à ajouter leurs médias et à co-valider les étapes."

        public static let listTitle = "Co-voyageur(s) actuels"
        /// Sous la ligne de **celui qui lit**, propriétaire ou non (18/10/2026).
        public static let me = "Moi"
        /// Sous les autres lignes, propriétaire compris.
        public static let companion = "Co-voyageur"
        public static let owner = "Propriétaire\ndu voyage"
        public static let pending = "Invitation envoyée"

        /// Le message d'invitation : le lien, puis le code pour l'entrer à la main.
        public static func invitation(tripTitle: String, code: String, link: URL?) -> String {
            let intro = "Rejoins-moi sur MemoBook pour raconter « \(tripTitle) »."
            guard let link else { return "\(intro) Code d’accès : \(code)" }
            return "\(intro) \(link.absoluteString)\nCode d’accès : \(code)"
        }

        /// **Ce que le message fugitif dit en arrivant sur le voyage** (Hugo,
        /// 10/11/2026) : « un popup temporaire de 3 sec devrait indiquer "Tu
        /// as rejoins le voyage de [nom_proprietaire] et il est ajouté à tes
        /// voyages" ».
        ///
        /// « rejoint » et non « rejoins » : la spécification porte une
        /// glissade de clavier, signalée. Et un point-virgule plutôt qu'un
        /// « et » : la phrase dit deux choses — ce qui vient de se passer, et
        /// où le retrouver.
        public static func joined(owner: String) -> String {
            owner.isEmpty
                ? "Tu as rejoint ce voyage ; il est ajouté à tes voyages."
                : "Tu as rejoint le voyage de \(owner) ; il est ajouté à tes voyages."
        }

        /// Un lien d'invitation dont le code ne mène à aucun voyage.
        public static let linkNotFound =
            "Ce lien d’invitation ne mène à aucun voyage. Demande à celui qui t’a invité de te le renvoyer."

        public static func accessCode(_ code: String) -> String { "Code d’accès : \(code)" }
        public static let copied = "Code copié"
        public static let whatsapp = "Partager via Whatsapp"
        public static let share = "Partager"

        public static let remove = "Retirer"
        public static let resend = "Renvoyer"
        public static func resent(_ name: String) -> String { "Invitation renvoyée à \(name)." }

        /// Ce que la liste dit quand on voyage seul. La maquette ne le dessine
        /// pas — écart signalé, et une liste vide sous un titre se lirait comme
        /// un chargement qui n'a pas abouti.
        public static let empty = "Tu racontes ce voyage seul pour l’instant."

        public static func removeConfirmation(_ name: String) -> String {
            "Retirer \(name) de ce voyage ?"
        }
        public static let removeMessage =
            "Cette personne ne pourra plus raconter ni ajouter de photos. Ses souvenirs, eux, restent dans le carnet."
        public static let cancel = "Annuler"

        /// Le geste que la note « Logique » décrit : maintenir ou glisser vers
        /// la gauche ouvre les deux actions.
        public static let gestureHint = "Glisse une ligne vers la gauche pour la retirer."
    }

    // MARK: - Les feuilles de la personnalisation du carnet

    /// « Ratio média » — `3443:10212`.
    public enum Ratio {
        public static let title = "Ratio média"

        /// **Corrigée au tutoiement** — voir ``Customisation/intro``.
        public static let subtitle =
            "Détermine l’importance visuelle des images par rapport aux textes générés au sein des chapitres."

        public static let more = "Plus de photos"
        public static let less = "Plus de texte"

        /// « 50 / 50 », la valeur en grand au-dessus du curseur.
        public static func value(_ photos: Int) -> String { "\(photos) / \(100 - photos)" }

        /// La ligne bleue sous la valeur. Elle **qualifie** l'équilibre choisi
        /// plutôt que de le répéter en chiffres.
        public static func quality(_ photos: Int) -> String {
            switch photos {
            case ..<25: "Le récit avant tout"
            case 25..<50: "Surtout du texte"
            case 50: "Équilibre parfait"
            case 51...75: "Surtout des photos"
            default: "Un album avant tout"
            }
        }
    }

    /// « Nombre de page » — `3443:10177`.
    public enum Pages {
        // MARK: La cible hors d'atteinte (Hugo, 18/10/2026)

        public static let reachTitle = "Cette cible est hors d’atteinte"

        /// Ce que le carnet peut faire aujourd'hui, avec les réglages du moment.
        public static func reachToday(_ reach: PageTargetReach) -> String {
            "Avec tes réglages actuels (\(reach.ratio) % de photos), ton carnet peut faire entre "
                + "\(reach.range.min) et \(reach.range.max) pages. \(reach.target) pages ne sont pas atteignables pour l’instant."
        }

        /// Comment aller chercher la cible voulue.
        public static func reachLevers(_ reach: PageTargetReach) -> String {
            if reach.isTooLong {
                let ratio = reach.ratioThatReaches.map { ", ou monte le ratio photo / texte à \($0) %" } ?? ""
                return "Pour atteindre \(reach.target) pages : raconte plus de souvenirs, envoie plus de photos quand je te les demande\(ratio)."
            }
            return "Pour descendre à \(reach.target) pages : raconte moins d’étapes, ou des souvenirs plus courts. "
                + "Le texte que tu as validé n’est jamais coupé."
        }

        public static func chooseReachable(_ pages: Int) -> String { "Choisir \(pages) pages" }

        /// **Ce que coûtera le carnet à la cible proposée** (Hugo,
        /// 04/11/2026 : « le changement de prix du carnet doit être très
        /// clair »). La feuille applique le changement d'un seul appui : le
        /// prix doit donc se lire **avant**, pas après.
        ///
        /// Le prix du palier de `cible + tolérance`, comme les options de
        /// l'écran — annoncer le haut de la fourchette, c'est promettre un
        /// prix qu'on ne dépassera pas. `nil` sans grille servie : la phrase
        /// ne paraît pas, mieux vaut pas de prix qu'un prix faux.
        public static func reachPrice(pages: Int, price: String) -> String {
            "À \(pages) pages, ton carnet coûtera \(price)."
        }

        /// Ce que l'appui consomme. Il remplace la confirmation qui s'ouvrait
        /// derrière le bouton (Hugo, 04/11/2026) : sans elle, c'est ici que
        /// la règle des deux changements doit se dire.
        public static func reachCountsAsChange(changesLeft: Int) -> String {
            changesLeft <= 1
                ? "C’est ton dernier changement de nombre de pages cible pour ce voyage."
                : "C’est l’un des deux changements de nombre de pages cible du voyage : il t’en restera \(changesLeft - 1)."
        }
        public static func raiseRatio(_ ratio: Int) -> String { "Passer à \(ratio) % de photos" }
        public static func keepAnyway(_ pages: Int) -> String { "Garder \(pages) pages quand même" }

        public static let title = "Nombre de page"

        /// La phrase de la V3 (`3595:23920`), telle quelle : elle tutoie
        /// désormais dans Figma. « plus de page » au singulier est celui de la
        /// maquette (R8).
        public static let subtitle =
            "Gère le niveau de détails de ton carnet en permettant à notre outil d’utiliser plus de page."

        /// La ligne verte sous le chapeau. Elle dit **sur quoi** les
        /// projections sont faites — la maquette écrit « 2 mois » en dur, l'app
        /// met la durée du voyage qu'on regarde.
        public static func estimates(for duration: String) -> String {
            "Estimations pour un voyage de \(duration)"
        }

        public static let customTitle = "Nombre de pages cible"
        public static let validate = "Valider"

        // MARK: Changer la cible (Hugo, 15/10/2026)

        /// Le titre de la feuille qui accompagne un changement de cible — une
        /// seule feuille, dont le contenu change d'étape en étape.
        public static let changeTitle = "Nombre de pages cible"

        /// Ce qu'on dit **avant** de changer, quand le changement compte. Les
        /// deux phrases de Hugo : la règle quand on a encore les deux, et ce
        /// qui reste quand il n'y en a plus qu'un. Sans balisage : c'est le
        /// chapeau d'une ``BrandSheet``, qui ne lit pas le gras.
        public static func changeWarning(changesLeft: Int) -> String {
            changesLeft <= 1
                ? "Il ne te reste plus qu’un seul changement de nombre de pages cible pour ce voyage."
                : "Tu peux changer le nombre de pages cible deux fois pendant ce voyage : chaque changement peut réécrire tout ton carnet."
        }

        public static let confirmChange = "Changer le nombre de pages cible"
        public static let cancelChange = "Annuler"

        /// Les deux changements sont faits. Dit à l'orange, sur la feuille
        /// comme sous les paliers pâlis.
        public static let limitReached =
            "Tu as utilisé tes deux changements : **le nombre de pages cible ne peut plus changer** pour ce voyage."
        public static let understood = "Compris"

        /// **La cible personnalisée que le ratio vient de mettre hors
        /// d'atteinte** (T283, 20/11/2026). Dite sous les paliers, à l'orange,
        /// et elle **reste** tant que les deux réglages se contredisent : ce
        /// n'est pas la réponse à un appui, c'est l'état des deux réglages.
        ///
        /// Elle ne pose aucune question — elle en posait une, en feuille
        /// modale, au milieu d'un geste sur le ratio. Elle dit ce que le
        /// carnet fera, et ce qui le changerait.
        public static func targetOutOfReach(target: Int, limit: Int, isTooLong: Bool) -> String {
            let sens = isTooLong
                ? "ton carnet ira jusqu’à **\(limit) pages**"
                : "ton carnet fera au moins **\(limit) pages**"
            return "Avec ce ratio, \(target) pages n’est plus atteignable : \(sens). Touche un palier pour choisir une autre cible, ou remonte les photos."
        }

        /// Sans date de fin, l'app ne sait pas où en est le voyage : elle le
        /// demande.
        public static let stageTitle = "À quel stade de ton voyage en es-tu ?"
        public static let stageBeginning = "Plutôt au début"
        public static let stageMiddle = "Environ à la moitié"
        public static let stageEnd = "Plutôt à la fin"

        public static let doneTitle = "C’est noté"

        /// « récit compact », « récit de 70 pages » — le nom du récit qu'une
        /// cible donne, pour la phrase de ``doneSummary(from:to:)``.
        ///
        /// `withPageCount` ajoute le nombre au palier nommé (« récit détaillé
        /// de 40 pages ») : face à une cible personnalisée, le nom seul peut
        /// contredire le sens — 60 pages vers « Détaillé » sur un voyage de
        /// trois semaines, c'est condenser.
        public static func storyName(pageCount: Int, tripDays: Int?, ratio: Int = 50, withPageCount: Bool = false) -> String {
            let name: String
            switch BookPageTarget.matching(pageCount: pageCount, tripDays: tripDays, ratio: ratio) {
            case .compact: name = "récit compact"
            case .standard: name = "récit standard"
            case .detailed: name = "récit détaillé"
            case .custom: return "récit de \(pageCount) pages"
            }
            return withPageCount ? "\(name) de \(pageCount) pages" : name
        }

        /// « On passe d'un récit compact à un récit détaillé. Les prochaines
        /// étapes seront donc plus étoffées. » Le sens se lit dans les
        /// nombres, pas dans les noms : deux cibles personnalisées n'ont pas
        /// d'ordre à elles.
        public static func doneSummary(from: Int, to: Int, tripDays: Int?, ratio: Int = 50) -> String {
            let custom = [from, to].contains { BookPageTarget.matching(pageCount: $0, tripDays: tripDays, ratio: ratio) == .custom }
            let before = storyName(pageCount: from, tripDays: tripDays, ratio: ratio, withPageCount: custom)
            let after = storyName(pageCount: to, tripDays: tripDays, ratio: ratio, withPageCount: custom)
            let next = to > from ? "plus étoffées" : "moins étoffées"
            return "On passe d’un \(before) à un \(after). Les prochaines étapes seront donc \(next)."
        }

        /// Vers la fin du voyage seulement : ce qui est écrit pèse plus que
        /// ce qui reste, et le carnet serait coupé en deux.
        public static func rewriteOffer(isLonger: Bool) -> String {
            let verb = isLonger ? "étoffe" : "condense"
            return "Si tu veux que l’on \(verb) le récit des étapes déjà écrites pour qu’il soit homogène avec la suite de ton carnet, c’est juste en dessous."
        }

        public static func rewriteAction(isLonger: Bool) -> String {
            isLonger ? "Étoffer les étapes déjà écrites" : "Condenser les étapes déjà écrites"
        }

        public static let later = "Plus tard"
        public static let ok = "OK"

        /// Le lien sous les paliers, tant que la réécriture reste ouverte —
        /// pour qui a répondu « Plus tard ». Il ne sait plus dans quel sens la
        /// cible a bougé : il dit ce qu'il fait, sans le sens.
        public static let rewriteLink = "Mettre les étapes déjà écrites à la nouvelle cible"

        /// Ce que dit le panneau une fois la réécriture lancée.
        public static let rewriteStarted =
            "**On réécrit les étapes déjà écrites** à ton nouveau nombre de pages. Ça se fait en arrière-plan : tu peux continuer."
    }

    /// « Fun Facts » — `3443:10105`.
    public enum FunFacts {
        public static let title = "Fun facts"
        public static let toggle = "Insérer des Fun facts"

        /// **Corrigée au tutoiement** — voir ``Customisation/intro``.
        public static let detail =
            "Encarts de culture générale toutes les 3 pages pour agrémenter tes récits."
    }

    /// « Pointillés » — `3443:10126`.
    public enum Rules {
        public static let title = "Pointillés"
        public static let toggle = "Pointillés"

        /// **Corrigée au tutoiement** — voir ``Customisation/intro``.
        public static let detail = "Lignes en pointillé sous le texte dans ton carnet"

        /// Ce que dit l'interrupteur grisé quand on le touche : la cause, et la
        /// sortie (Hugo, 02/10/2026). Il nomme l'assortiment par défaut et la
        /// pastille des typographies — un test vérifie que les deux noms
        /// suivent ``BookFontCombo/travelJournal`` et
        /// ``Customisation/categoryFonts``.
        public static let locked =
            "Les pointillés ne s’impriment qu’avec la typographie Carnet de voyage. Choisis-la dans Typos pour les retrouver."

        /// Ce que dit la feuille des typographies, quand l'assortiment qu'on
        /// vient de choisir a éteint des pointillés allumés (Hugo, 02/10/2026).
        /// L'interrupteur est dans une autre pastille : sans cette phrase, le
        /// voyageur ne saurait pas qu'il a perdu quelque chose.
        public static func withdrawn(by combo: BookFontCombo) -> String {
            "\(combo.name) s’imprime sans pointillés : on les a retirés. Ils reviendront si tu repasses sur \(BookFontCombo.travelJournal.name)."
        }
    }

    /// « Typographies du carnet » — l'héritière de « Titres du carnet »
    /// (`3443:10073`).
    ///
    /// ⚠️ **L'écran ne suit plus la maquette ici** (Hugo, 16/09/2026) : celle-ci
    /// dessine une feuille par rôle, où l'on marie librement trois familles. On
    /// propose désormais quatre assortiments — voir ``BookFontCombo`` — parce
    /// qu'un carnet imprimé ne se rattrape pas et que la plupart des mariages
    /// libres sont ratés. À reprendre dans Figma.
    public enum Fonts {
        public static let title = "Typographies du carnet"
        /// La phrase de la V3 (`3595:24009`).
        public static let subtitle =
            "Choisis la typographie de tes titres, sous-titres, paragraphes et fun facts"

        /// Ce que la ligne de l'écran affiche quand le carnet ne porte aucun
        /// des quatre assortiments — un carnet composé police par police avant
        /// cette feuille. On ne coche pas de force, on le nomme.
        public static let custom = "Personnalisé"
    }

    /// « Décorations & stickers » — `3443:10147`.
    public enum Decorations {
        public static let title = "Décorations\n& stickers "

        /// **Corrigée au tutoiement** — voir ``Customisation/intro``.
        public static let subtitle = "Détermine la quantité de décorations dans tes pages"
        /// « par étape » et non plus « par paragraphe ou image » : c'est ce
        /// que le carnet compte (Hugo, 14/10/2026).
        public static let sliderLabel = "Quantité de décorations par étape"
    }
}
