import Foundation

// Les mots du tunnel de commande, au mot près de la maquette.
//
// Rangés sous ``BookCopy`` comme les autres écrans du carnet : le tunnel est
// une étape du carnet, pas un produit à part.

extension BookCopy {
    public enum Order {
        /// Le titre porté par les sept étapes. Il ne change pas en cours de
        /// route : c'est le sous-titre qui dit où on en est.
        public static let title = "Commander mon Carnet"

        public static let help = "Besoin d’aide ?"
        public static let next = "Continuer"
        public static let retry = "Réessayer"

        // MARK: Étape 1 — Démarrage

        public enum Start {
            public static let balance = "Montant disponible"
            public static let cta = "Commencer la commande"

            /// « Estimation : 80 pages ». Accordé, comme
            /// ``BookCustomisation/targetPageLabel``.
            public static func estimate(pages: Int) -> String {
                pages <= 1 ? "Estimation : \(pages) page" : "Estimation : \(pages) pages"
            }

            /// Le carnet n'a jamais été composé : il n'y a rien à commander.
            public static let notComposed = "Ce carnet n’est pas encore généré."
            public static let notComposedDetail =
                "Prévisualise-le d’abord : on ne commande pas un carnet qu’on n’a pas vu."
        }

        // MARK: Étape 2 — Livraison

        public enum Shipping {
            public static let title = "Adresse de livraison"
            public static let name = "Nom complet"
            public static let line1 = "Adresse"
            public static let line2 = "Complément d’adresse"
            public static let postalCode = "Code postal"
            public static let city = "Ville"
            public static let country = "Pays"
            public static let placeholder = "Clique ici"
        }

        // MARK: Étape 3 — Exemplaires

        public enum Copies {
            public static let title = "Nombre d’exemplaires"
            public static let subtitle = "Plusieurs carnets pour offrir à tes proches"
            public static let unitPrice = "Prix unitaire"

            public static let customiseTitle = "Personnaliser vos carnets"
            public static let customiseSubtitle = "Rendez chaque carnet unique"

            public static let decorations = "Décorations & stickers"
            public static let quiz = "Quiz intégrés à l’histoire"
            public static let freeZones = "Zones libres"
            public static let crossword = "Mot fléché à la fin du livre"

            public static let sameAsFirst =
                "Par défaut, nous appliquons la même version que ton 1er carnet"
            public static let differentFromFirst = "Choisir une version différente du 1er carnet"
            public static let backToSameAsFirst = "Reprendre la version du 1er carnet"

            /// Le rang, dit comme la maquette le dit — « 1er Carnet ».
            public static func copyTitle(_ position: Int) -> String {
                position == 1 ? "1er Carnet" : "\(position)e Carnet"
            }

            public static let minimumReached = "Il faut au moins un exemplaire."
            public static let maximumReached = "Vingt exemplaires au maximum par commande."
        }

        // MARK: Étape 4 — Rapidité

        public enum Speed {
            public static let title = "Rapidité de livraison"
            public static let included = "Inclus"
            public static let cta = "Voir le récapitulatif"
        }

        // MARK: Étape 5 — Récapitulatif

        public enum Summary {
            public static let title = "Vérifications finales avant impression"
            public static let total = "Total"
            public static let cta = "Valider la commande"

            /// « Carnet - Rome et la Dolce Vita ».
            public static func book(_ title: String) -> String { "Carnet - \(title)" }

            /// Ce qui coiffe la description du produit, posée sous son prix.
            /// Elle ne se choisit pas : c'est une fabrication et une seule.
            public static let specifications = "Ton carnet, en un seul format"
            public static let pricedByPages = "Le prix ne dépend que du nombre de pages."

            /// « Carnet · 80 pages », quand le serveur n'a pas donné de libellé.
            public static func bookLine(pages: Int) -> String {
                pages <= 1 ? "Carnet · \(pages) page" : "Carnet · \(pages) pages"
            }
        }

        // MARK: Étape 6 — Paiement

        public enum Payment {
            public static let title = "Méthode de Paiement"
            public static let change = "Changer de mode de paiement"
            public static let choose = "Choisir un mode de paiement"
            public static let address = "Adresse de livraison"
            public static let total = "Total"
            public static let cta = "Payer"

            /// Quand la cagnotte couvre tout. Présenter une carte pour un débit
            /// de zéro ferait craindre un prélèvement.
            public static let free = "Ta cagnotte couvre la totalité"
            public static let freeCta = "Valider la commande"

            public static let sheetTitle = "Choisis ton mode de paiement"
            public static let sheetSubtitle =
                "Sélectionne une carte ou ajoute un nouveau moyen."
            public static let addCard = "Ajouter une carte"
            public static let confirm = "Valider"
            public static let applePay = "ApplePay"
            public static let applePayAvailable = "disponible"
            public static let defaultCard = "défaut"

            public static let failure =
                "Le paiement a échoué, merci de choisir une autre option."

            /// Le serveur a enregistré la commande mais n'a pas donné de quoi
            /// l'encaisser — il lui manque ses clés Stripe.
            ///
            /// Une panne de configuration, pas un geste à refaire : réessayer
            /// n'y changera rien tant que l'API déployée n'a pas ses clés. On le
            /// dit donc sans inviter à recommencer, et la commande reste en
            /// brouillon, reprenable telle quelle.
            public static let unavailable =
                "Le paiement est momentanément indisponible. Ta commande est "
                + "gardée : tu pourras la régler dès que possible."
        }

        // MARK: Étape 7 — Confirmation

        public enum Confirmation {
            public static let title = "Ton Carnet prend la route"
            public static let delivery = "Livraison"

            // MARK: Le suivi par WhatsApp

            public static let whatsapp = "Être informé par whatsapp"
            public static let whatsappOn = "Tu seras informé par whatsapp"
            public static let whatsappStop = "Ne plus être informé"

            public static let whatsappSheetTitle = "Ton numéro WhatsApp"
            public static let whatsappSheetSubtitle =
                "On te préviendra quand ton carnet part à l’impression, puis quand il prend la route."
            public static let whatsappField = "Numéro de téléphone"
            public static let whatsappPlaceholder = "+33 6 12 34 56 78"
            public static let whatsappConfirm = "Me prévenir"

            /// ⚠️ Ce que l'écran **ne promet pas**. Aucun message n'est encore
            /// envoyé : la commande retient qui prévenir, l'envoi viendra avec
            /// le suivi de l'imprimeur. Le dire, plutôt que de laisser croire
            /// qu'un message arrive demain.
            public static let whatsappNotLiveYet =
                "On garde ton numéro pour ce carnet. Les messages partiront dès que l’imprimeur nous donnera le suivi."

            public static let giftTitle = "Envie de l’offrir ?"
            public static let giftDetail =
                "Tu peux recommander un exemplaire depuis ton Carnet à tout moment"

            public static let share = "Partager le lien de prévisualisation"
            public static let home = "Retour à l’accueil"

            /// « Nous préparons Rome et la Dolce Vita avec soin. Tu recevras un
            /// email de confirmation sur ton email margaux@gmail.com »
            ///
            /// L'adresse est optionnelle : un compte entré par Apple peut ne
            /// pas en avoir donné, et promettre un email qu'on n'enverra nulle
            /// part serait pire que de ne rien promettre.
            public static func detail(book: String, email: String?) -> String {
                let opening = "Nous préparons \(book) avec soin."
                guard let email, !email.trimmed.isEmpty else {
                    return "\(opening) Tu recevras un email de confirmation."
                }
                return "\(opening) Tu recevras un email de confirmation sur ton email \(email)"
            }

            /// « 2 exemplaires - 50 pages ». Accordé des deux côtés.
            public static func summary(copies: Int, pages: Int?) -> String {
                let books = copies <= 1 ? "1 exemplaire" : "\(copies) exemplaires"
                guard let pages else { return books }
                return pages <= 1 ? "\(books) - \(pages) page" : "\(books) - \(pages) pages"
            }
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
