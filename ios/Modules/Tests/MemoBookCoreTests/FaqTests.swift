import Testing

@testable import MemoBookCore

// La foire aux questions est du **contenu**, et le contenu se relit mal : une
// question ajoutée avec l'identifiant de sa voisine, une variable oubliée dans
// une phrase, un ordinal écrit à l'ancienne — rien de tout ça ne casse la
// compilation, et tout se voit en production.
//
// Ces règles-là viennent de la page Notion « FAQ in-app MemoBook », section
// « Notes d'implémentation ». Elles sont écrites ici parce que c'est le seul
// endroit qui puisse les tenir dans le temps.

@Suite("Foire aux questions")
struct FaqTests {
    // MARK: Les identifiants

    @Test("Chaque identifiant est unique")
    func identifiersAreUnique() {
        let ids = Faq.entries.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// « `faq.categorie.slug` immuable, porte les traductions, les deep links et
    /// les statistiques. » C'est la forme qui compte : un identifiant à deux
    /// segments ne saurait pas dire de quelle catégorie il vient.
    @Test("Chaque identifiant suit faq.categorie.slug")
    func identifiersFollowTheirShape() {
        for entry in Faq.entries {
            let parts = entry.id.split(separator: ".")
            #expect(parts.count == 3, "\(entry.id) n’a pas trois segments")
            #expect(parts.first == "faq", "\(entry.id) ne commence pas par faq")
            #expect(
                entry.id.allSatisfy { $0.isLowercase || $0 == "." || $0 == "-" || $0.isNumber },
                "\(entry.id) porte une capitale ou un caractère inattendu"
            )
        }
    }

    @Test("Un identifiant retrouve sa question")
    func entryIsFoundByIdentifier() {
        #expect(Faq.entry(id: "faq.carnet.pages")?.question == "Combien de pages fait un Carnet ?")
        #expect(Faq.entry(id: "faq.inconnue.jamais-ecrite") == nil)
    }

    // MARK: Les variables

    /// « Les valeurs qui bougent sont des variables `{{…}}`, résolues à
    /// l'affichage depuis une config distante, jamais écrites en dur. »
    @Test("Aucune réponse n’affiche une variable non résolue")
    func noAnswerLeaksAVariable() {
        for entry in Faq.entries {
            for paragraph in entry.answer(with: .current) {
                #expect(
                    !paragraph.contains("{{"),
                    "\(entry.id) laisse une variable non résolue : \(paragraph)"
                )
            }
        }
    }

    @Test("Le seuil de pages se résout à la valeur en vigueur")
    func minimumPageCountResolves() {
        let entry = Faq.entry(id: "faq.carnet.pages")
        let resolved = entry?.answer(with: FaqVariables(minimumPageCount: 24)) ?? []
        #expect(resolved.contains { $0.contains("minimum de 24 pages") })
    }

    /// Une variable qu'on ne sait pas résoudre reste **visible**. Une phrase
    /// amputée passerait inaperçue ; « {{delai}} » dans l'app se corrige.
    @Test("Une variable inconnue reste écrite plutôt qu’effacée")
    func unknownVariableIsLeftInPlace() {
        let text = "Compte {{delai_livraison}} jours."
        #expect(FaqVariables.current.resolve(text) == text)
    }

    // MARK: Le ton

    /// R9 : l'app tutoie, sans exception. Le vouvoiement se glisse par les
    /// formes en « vous » et « votre », qui sont les plus fréquentes.
    @Test("Aucune réponse ne vouvoie")
    func nothingIsFormal() {
        let formal = [" vous ", " votre ", " vos ", "Vous ", "Votre "]
        for entry in Faq.entries {
            let text = ([entry.question] + entry.answer).joined(separator: " ")
            for form in formal {
                #expect(!text.contains(form), "\(entry.id) vouvoie : \(text)")
            }
        }
    }

    /// Le vocabulaire de la page Notion : « Carnet », « souvenirs »,
    /// « voyageurs ». Jamais « livre », jamais « utilisateur », jamais
    /// « client ».
    @Test("Le vocabulaire interdit n’apparaît pas")
    func bannedVocabularyIsAbsent() {
        let banned = ["livre", "utilisateur", "client"]
        for entry in Faq.entries {
            let text = ([entry.question] + entry.answer).joined(separator: " ").lowercased()
            for word in banned {
                #expect(!text.contains(word), "\(entry.id) emploie « \(word) » : \(text)")
            }
        }
    }

    @Test("Les apostrophes sont typographiques")
    func apostrophesAreTypographic() {
        for entry in Faq.entries {
            let text = ([entry.question] + entry.answer).joined(separator: " ")
            #expect(!text.contains("'"), "\(entry.id) porte une apostrophe droite")
        }
    }

    // MARK: La structure

    @Test("Les neuf sujets courants sont là, et le contact à part")
    func sectionsAreComplete() {
        #expect(Faq.topics.count == 9)
        #expect(!Faq.topics.contains { $0.id == Faq.contact.id })
        #expect(Faq.contact.entries.count == 2)
    }

    @Test("Aucune catégorie n’est vide")
    func noCategoryIsEmpty() {
        for category in Faq.topics + [Faq.contact] {
            #expect(!category.entries.isEmpty, "\(category.id) est vide")
        }
    }

    @Test("Aucune réponse n’est vide")
    func noAnswerIsEmpty() {
        for entry in Faq.entries {
            #expect(!entry.answer.isEmpty, "\(entry.id) n’a pas de réponse")
            #expect(!entry.question.isEmpty)
        }
    }
}

// MARK: - Les couvertures

@Suite("Couvertures")
struct BookCoversTests {
    /// Un jeu minimal, monté ici plutôt qu'importé : le jeu d'essai de l'app
    /// vit dans `MemoBookFeature`, que ces tests ne voient pas — c'est la règle
    /// de dépendance des modules, et elle est ce qui permet de tester `Core`
    /// sans simulateur.
    private static var covers: BookCovers {
        BookCovers(
            front: BookCover(styleId: "front-photo", photoId: "photo-1", title: "ROME"),
            back: BookCover(
                styleId: "back-framed",
                statIds: ["stat-days", "stat-km", "stat-countries"]
            ),
            frontStyles: [
                CoverStyle(id: "front-photo", name: "Photo", treatment: .photo, tint: .ink),
                CoverStyle(id: "front-sand", name: "Sable", treatment: .plain, tint: .sand),
            ],
            backStyles: [
                CoverStyle(id: "back-sand", name: "Sable", treatment: .plain, tint: .sand),
                CoverStyle(id: "back-framed", name: "Cadre", treatment: .framed, tint: .paper),
            ],
            photos: [CoverPhoto(id: "photo-1"), CoverPhoto(id: "photo-2")],
            stats: [
                CoverStat(id: "stat-days", value: "21", label: "jours\nde voyage"),
                CoverStat(id: "stat-km", value: "2,3k", label: "km\nparcourus"),
                CoverStat(id: "stat-countries", value: "1", label: "pays\nvisité"),
                CoverStat(id: "stat-people", value: "27", label: "personnes\nrencontrées"),
            ]
        )
    }

    @Test("Les ordinaux s’écrivent 1ère et 4e, comme la maquette (T91)")
    func facesUseTheMockupOrdinals() {
        #expect(CoverFace.front.title == "1ère de couverture")
        #expect(CoverFace.back.title == "4e de couverture")
    }

    @Test("L’indice lit et écrit le bon plat")
    func subscriptReachesBothFaces() {
        var covers = Self.covers
        covers[.back].title = "Dos"
        #expect(covers.back.title == "Dos")
        #expect(covers[.front].title != "Dos")
    }

    /// La contrainte vient du gabarit : sous trois, le bandeau imprimé a des
    /// colonnes vides ; au-delà de quatre, les chiffres ne se lisent plus.
    @Test("Le dos accepte trois ou quatre chiffres")
    func statRangeIsThreeOrFour() {
        #expect(BookCovers.statRange == 3...4)
        #expect(Self.covers.back.statIds.count == 3)
    }

    /// C'est l'ordre de sélection qui s'imprime, de gauche à droite.
    @Test("Les chiffres retenus sortent dans l’ordre choisi")
    func statSelectionKeepsItsOrder() {
        var covers = Self.covers
        covers.back.statIds = ["stat-km", "stat-days", "stat-people"]
        #expect(covers.statSelection.map(\.id) == ["stat-km", "stat-days", "stat-people"])
    }

    @Test("Un chiffre qui n’existe plus est simplement ignoré")
    func unknownStatIsDropped() {
        var covers = Self.covers
        covers.back.statIds = ["stat-days", "stat-supprimee", "stat-km"]
        #expect(covers.statSelection.map(\.id) == ["stat-days", "stat-km"])
    }

    @Test("Chaque plat propose des styles, et son style est dedans")
    func everyFaceHasItsStyles() {
        let covers = Self.covers
        for face in CoverFace.allCases {
            let styles = covers.styles(for: face)
            #expect(!styles.isEmpty)
            #expect(
                styles.contains { $0.id == covers[face].styleId },
                "le style du plat \(face.rawValue) n’est pas dans son catalogue"
            )
        }
    }

    @Test("La pastille « assortie » suit le style choisi sur l’autre plat")
    func matchedStyleFollowsTheOtherFace() {
        var covers = Self.covers

        // Devant en photo pleine page : aucune quatrième ne s'accorde.
        covers.front.styleId = "front-photo"
        #expect(covers.backStyles.filter { covers.isMatched($0, on: .back) }.isEmpty)

        // Devant en sable : c'est « Sable » au dos qui devient assortie — et
        // une seule.
        covers.front.styleId = "front-sand"
        let matched = covers.backStyles.filter { covers.isMatched($0, on: .back) }
        #expect(matched.map(\.id) == ["back-sand"])

        // Et dans l'autre sens, le devant en sable s'annonce assorti au dos
        // en sable.
        covers.back.styleId = "back-sand"
        #expect(covers.isMatched(covers.frontStyles[1], on: .front))
        #expect(!covers.isMatched(covers.frontStyles[0], on: .front))
    }
}
