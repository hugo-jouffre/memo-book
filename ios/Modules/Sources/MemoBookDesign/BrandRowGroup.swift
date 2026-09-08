import SwiftUI
import UIKit

/// Une pile de lignes réunies dans une même carte, séparées par un filet : le
/// motif des écrans de réglages de MemoBook.
///
/// C'est **le** composant de ce motif. Il resservira partout où un écran range
/// des actions par paquets — profil, paramètres du voyage, personnalisations —
/// et c'est cette unicité qui fait qu'une ligne se touche, se lit et sonne
/// pareil d'un écran à l'autre.
///
/// ```swift
/// BrandRowGroup {
///     BrandRow("E-mail", value: account.email)
///     BrandRow("Adresse postale", value: address, action: openAddress)
///     BrandRow("Newsletter mensuelle MemoBook", isOn: $wantsNewsletter)
/// }
/// ```
///
/// Ce que le groupe prend en charge, et qu'aucun écran n'a donc à refaire :
/// la coque, les filets (posés **entre** les lignes, jamais aux extrémités),
/// la hauteur minimale de cible tactile, le passage en colonne aux tailles de
/// texte accessibles, et la manière dont VoiceOver lit chaque ligne.
public struct BrandRowGroup: View {
    /// Comment le groupe se cerne.
    public enum Tone {
        /// Le filet discret du motif courant : le groupe range des lignes, il
        /// ne les met pas en avant.
        case plain
        /// Le contour vert. Pour **un** groupe par écran, celui qu'on vient
        /// chercher du regard — les chiffres du profil. Deux groupes cerclés
        /// sur le même écran ne mettraient plus rien en avant.
        case highlighted
    }

    private let rows: [BrandRow]
    private let tone: Tone

    public init(tone: Tone = .plain, @BrandRowBuilder _ rows: () -> [BrandRow]) {
        self.rows = rows()
        self.tone = tone
    }

    public init(_ rows: [BrandRow], tone: Tone = .plain) {
        self.rows = rows
        self.tone = tone
    }

    /// Le filet qui sépare deux lignes suit le contour du groupe : un trait
    /// gris dans un cadre vert se lirait comme un oubli.
    private var separator: Color {
        switch tone {
        case .plain: MemoBookColor.hairline
        case .highlighted: MemoBookColor.action
        }
    }

    private var borderWidth: CGFloat {
        switch tone {
        case .plain: 1
        case .highlighted: 1.5
        }
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)

        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    // Le filet sépare, il n'encadre pas : il vit entre deux
                    // lignes et s'arrête aux marges du texte.
                    Rectangle()
                        .fill(separator)
                        .frame(height: 1)
                        .padding(.horizontal, MemoBookSpacing.s)
                        .accessibilityHidden(true)
                }
                row
            }
        }
        .background(MemoBookColor.surface, in: shape)
        .overlay { shape.strokeBorder(separator, lineWidth: borderWidth) }
        // Le rognage garde les coins arrondis sous une ligne pressée, dont
        // l'aplat de sélection déborderait sinon en haut et en bas du groupe.
        .clipShape(shape)
    }
}

/// Une ligne d'un ``BrandRowGroup``.
///
/// C'est une **description**, pas une vue libre : l'écran dit ce que la ligne
/// porte, le composant décide comment ça se dessine. C'est ce qui garantit que
/// deux écrans n'inventent pas deux hauteurs de ligne ni deux chevrons.
public struct BrandRow: View, Identifiable {
    /// Ce qui se pose à droite de la ligne, et qui décide de sa nature.
    public enum Accessory {
        /// Rien : la ligne se lit, elle ne se touche pas.
        case none
        /// Le chevron : la ligne mène ailleurs — un écran, une feuille.
        case disclosure
        /// L'interrupteur : la ligne **est** le réglage.
        case toggle(Binding<Bool>)
        /// Le crayon : la valeur se corrige **sur place**, sans quitter l'écran.
        case editable(Editable)
    }

    /// Ce qu'il faut pour rendre une valeur modifiable en ligne.
    public struct Editable {
        let text: Binding<String>
        let placeholder: String?
        let keyboardType: UIKeyboardType
        let textContentType: UITextContentType?
        /// La correction vient d'être **enregistrée par le serveur**. Le crayon
        /// laisse alors la place à une coche verte, le temps qu'on la voie.
        let isConfirmed: Bool
    }

    /// Une ligne de plus, sous la ligne : soit une précision, soit un reproche.
    public enum Footnote {
        /// Une précision neutre — pourquoi la ligne ne se corrige pas, d'où
        /// vient sa valeur.
        case note(String)
        /// Ce qui ne va pas dans ce qui vient d'être saisi.
        case problem(String)
    }

    /// Comment l'intitulé s'écrit.
    public enum TitleTone {
        /// Le corps de texte : l'intitulé nomme une valeur qu'on lit à côté.
        case plain
        /// Le surtitre vert en capitales : l'intitulé **est** le sujet de la
        /// ligne, et la valeur n'en est que le chiffre. Réservé aux groupes
        /// ``BrandRowGroup/Tone/highlighted``, dont il reprend la couleur.
        case accent
    }

    /// Où se pose la valeur par rapport à l'intitulé.
    public enum ValuePlacement {
        /// Sur la même ligne, poussée à droite. Le cas courant.
        case trailing
        /// Sous l'intitulé, alignée à gauche : pour une valeur trop longue ou
        /// trop importante pour finir en bout de ligne — un numéro de carte.
        case below
    }

    private let title: String
    private let value: String?
    private let valuePlacement: ValuePlacement
    private let isValueProminent: Bool
    private let titleTone: TitleTone
    /// La valeur n'est pas encore arrivée : c'est une barre d'attente qui tient
    /// sa place, pas un vide. Voir ``BrandSkeleton``.
    private let isValueLoading: Bool
    /// La pastille posée en bout de ligne, après la valeur. Un mot, pas une
    /// phrase : « LOCKED », « BIENTÔT ».
    private let badge: String?
    private let accessory: Accessory
    private let footnote: Footnote?
    private let action: (() -> Void)?

    /// `nonisolated` : ``BrandRow`` est une `View`, donc isolée sur l'acteur
    /// principal, alors qu'`Identifiable` ne l'est pas. Une identité qui ne lit
    /// qu'une constante n'a besoin d'aucun acteur.
    public nonisolated var id: String { title }

    /// Une ligne qui montre une valeur, et qui mène quelque part si on lui
    /// donne une action.
    ///
    /// - Parameters:
    ///   - value: `nil` quand la ligne n'a qu'un intitulé.
    ///   - isValueProminent: la valeur passe en gras et en encre pleine. Pour
    ///     ce qu'on vient chercher du regard — un solde, un total.
    ///   - action: `nil` fait une ligne de lecture, sans chevron ni retour
    ///     tactile.
    ///   - note: une précision affichée sous la ligne, en petit. Pour dire ce
    ///     que la ligne ne dira pas d'elle-même — qu'une valeur vient d'ailleurs
    ///     et ne se corrige pas ici, par exemple.
    ///   - titleTone: ``TitleTone/accent`` pour les lignes d'un groupe cerclé
    ///     de vert, dont l'intitulé se lit comme un surtitre.
    ///   - badge: une pastille en bout de ligne, pour dire d'un mot ce que la
    ///     valeur ne dit pas — qu'elle est sous clé, par exemple.
    ///   - isValueLoading: la valeur est encore en route. **L'intitulé, lui,
    ///     s'affiche tout de suite** : il appartient à l'app, pas au serveur.
    public init(
        _ title: String,
        value: String? = nil,
        valuePlacement: ValuePlacement = .trailing,
        isValueProminent: Bool = false,
        titleTone: TitleTone = .plain,
        badge: String? = nil,
        isValueLoading: Bool = false,
        note: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.value = value
        self.valuePlacement = valuePlacement
        self.isValueProminent = isValueProminent
        self.titleTone = titleTone
        self.badge = badge
        self.isValueLoading = isValueLoading
        self.accessory = action == nil ? .none : .disclosure
        self.footnote = note.map(Footnote.note)
        self.action = action
    }

    /// Une ligne dont la valeur se corrige **sur place**.
    ///
    /// Le clavier s'ouvre sur cet écran, sans feuille ni écran intermédiaire, et
    /// la valeur est enregistrée quand le champ perd le focus — clavier refermé,
    /// défilement, passage à un autre champ, ou sortie de l'écran. C'est le
    /// comportement des Réglages d'iOS : on corrige une ligne, on ne « valide »
    /// pas un formulaire.
    ///
    /// **La ligne ne change pas d'apparence en se corrigeant** : ni cadre, ni
    /// aplat, ni déplacement. Seul le curseur apparaît. Une ligne qui se
    /// transforme en champ de saisie fait sursauter la page entière pour une
    /// information qu'on a déjà — le clavier vient de s'ouvrir.
    ///
    /// La valeur du modèle n'est touchée qu'**à la sortie du champ**, pas à
    /// chaque frappe : le jour où il y aura un serveur, c'est un appel réseau
    /// par correction et non un par caractère.
    ///
    /// - Parameter isConfirmed: la correction est **enregistrée côté serveur**.
    ///   Le crayon devient une coche verte le temps qu'on la voie. C'est le seul
    ///   accusé de réception d'une ligne qui s'enregistre toute seule : sans
    ///   lui, rien ne distingue « c'est parti » de « ça n'est jamais parti ».
    public init(
        _ title: String,
        text: Binding<String>,
        placeholder: String? = nil,
        error: String? = nil,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        isValueLoading: Bool = false,
        isConfirmed: Bool = false
    ) {
        self.title = title
        self.value = nil
        self.valuePlacement = .trailing
        self.isValueProminent = false
        self.titleTone = .plain
        self.badge = nil
        self.isValueLoading = isValueLoading
        self.footnote = error.map(Footnote.problem)
        self.accessory = .editable(
            Editable(
                text: text,
                placeholder: placeholder,
                keyboardType: keyboardType,
                textContentType: textContentType,
                isConfirmed: isConfirmed
            )
        )
        self.action = nil
    }

    /// Une ligne qui porte un interrupteur. Elle n'a pas d'action : c'est
    /// l'interrupteur qui agit, et lui seul.
    public init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self.value = nil
        self.valuePlacement = .trailing
        self.isValueProminent = false
        self.titleTone = .plain
        self.badge = nil
        self.isValueLoading = false
        self.accessory = .toggle(isOn)
        self.footnote = nil
        self.action = nil
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var minimumHeight = MemoBookSpacing.minimumTapTarget
    @ScaledMetric(relativeTo: .body) private var chevronSide: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var pencilSide: CGFloat = 16

    /// Ce qu'on est en train de taper. La valeur du modèle ne bouge qu'à la
    /// sortie du champ ; entre les deux, c'est ce brouillon qui vit.
    @State private var draft = ""
    @FocusState private var isEditing: Bool

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            footnoteLine
        }
    }

    @ViewBuilder
    private var row: some View {
        switch accessory {
        case .editable(let field):
            editableRow(field)

        case .toggle(let isOn):
            // Un vrai `Toggle` et non un dessin : c'est lui qui apporte le
            // geste de balayage, l'annonce « activé / désactivé » et le
            // comportement attendu par VoiceOver.
            //
            // **Toute la ligne bascule le réglage**, et pas seulement
            // l'interrupteur. C'est le comportement des Réglages d'iOS, et
            // c'est aussi une question de taille de cible : viser un rail de
            // 51 pt en bout de ligne, ou viser la ligne entière, ce n'est pas
            // le même geste. Le tapotis est posé sur l'étiquette, qui occupe
            // toute la largeur restante — pas sur la ligne entière, où il
            // ferait basculer deux fois un tapotis sur l'interrupteur lui-même.
            Toggle(isOn: isOn) {
                titleText
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .onTapGesture { isOn.wrappedValue.toggle() }
            }
            .toggleStyle(.switch)
                .tint(MemoBookColor.action)
                .padding(.horizontal, MemoBookSpacing.s)
                .padding(.vertical, MemoBookSpacing.xs + 4)
                .frame(minHeight: minimumHeight)

        case .disclosure, .none:
            if let action {
                Button(action: action) { content }
                    .buttonStyle(RowPressStyle())
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
            } else {
                content
                    .accessibilityElement(children: .combine)
            }
        }
    }

    /// La ligne de dessous. Elle occupe les mêmes marges que la ligne, pour se
    /// lire comme sa suite et non comme un bloc à part.
    @ViewBuilder
    private var footnoteLine: some View {
        if let footnote {
            let (text, tint): (String, Color) = switch footnote {
            case .note(let message): (message, MemoBookColor.inkMuted)
            case .problem(let message): (message, MemoBookColor.error)
            }

            Text(text)
                .font(MemoBookFont.caption)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, MemoBookSpacing.s)
                .padding(.bottom, MemoBookSpacing.xs + 4)
                // Elle appartient à la ligne du dessus : VoiceOver la lit à la
                // suite plutôt que comme un élément isolé.
                .accessibilityHidden(false)
        }
    }

    /// Une ligne qu'on corrige sur place. Elle a **exactement** le dessin d'une
    /// ligne de lecture : mêmes marges, même typographie, même hauteur. Rien ne
    /// bouge quand le champ prend le focus.
    private func editableRow(_ field: Editable) -> some View {
        HStack(spacing: MemoBookSpacing.xs) {
            titleAndEditor(field)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailingMark(field)
        }
        // La coche remplace le crayon en fondu : apparue net, elle ressemblerait
        // à un changement d'icône plutôt qu'à une confirmation.
        .animation(.snappy(duration: 0.25), value: field.isConfirmed)
        .padding(.horizontal, MemoBookSpacing.s)
        .padding(.vertical, MemoBookSpacing.xs + 4)
        .frame(minHeight: minimumHeight)
        .contentShape(.rect)
        // Toute la ligne ouvre le champ, pas seulement les quelques caractères
        // de la valeur — et une ligne vide s'ouvre aussi. Tant que la valeur
        // n'est pas arrivée, en revanche, il n'y a rien à corriger : ouvrir le
        // clavier sur un champ vide écraserait ce qui est encore en route.
        .onTapGesture { if !isValueLoading { isEditing = true } }
        .onAppear { draft = field.text.wrappedValue }
        // La valeur peut changer sous le champ (un rechargement) : on la reprend
        // tant qu'on n'est pas en train de taper dedans.
        .onChange(of: field.text.wrappedValue) { _, value in
            if !isEditing { draft = value }
        }
        // **L'enregistrement.** Sortir du champ suffit : refermer le clavier,
        // faire défiler la page, toucher un autre champ. Rien à valider.
        .onChange(of: isEditing) { _, editing in
            if !editing { field.text.wrappedValue = draft }
        }
        // Quitter l'écran clavier ouvert compte aussi comme une sortie.
        .onDisappear {
            if isEditing { field.text.wrappedValue = draft }
        }
    }

    @ViewBuilder
    private func titleAndEditor(_ field: Editable) -> some View {
        let editor = TextField(field.placeholder ?? "", text: $draft)
            .font(MemoBookFont.body)
            // La même encre que la valeur d'une ligne de lecture : le champ ne
            // s'annonce pas, il prend la place du texte.
            .foregroundStyle(MemoBookColor.inkMuted)
            .tint(MemoBookColor.action)
            .focused($isEditing)
            .keyboardType(field.keyboardType)
            .textContentType(field.textContentType)
            .textInputAutocapitalization(field.keyboardType == .emailAddress ? .never : .sentences)
            .autocorrectionDisabled(field.keyboardType == .emailAddress)
            .submitLabel(.done)
            .onSubmit { isEditing = false }
            .accessibilityLabel(title)

        if isValueLoading {
            HStack(alignment: .firstTextBaseline, spacing: MemoBookSpacing.s) {
                titleText
                Spacer(minLength: 0)
                BrandSkeleton(width: 120)
            }
        } else if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                titleText
                editor.multilineTextAlignment(.leading)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: MemoBookSpacing.s) {
                titleText
                editor.multilineTextAlignment(.trailing)
            }
        }
    }

    /// Le crayon, ou la coche qui le remplace le temps d'un accusé de
    /// réception.
    ///
    /// Le crayon : sans lui, rien ne dirait qu'une ligne se corrige. Il prend la
    /// place du chevron, à la même distance du bord — les deux disent « cette
    /// ligne se touche », l'un mène ailleurs, l'autre ouvre le clavier ici.
    ///
    /// La coche : une ligne qui s'enregistre en perdant le focus ne dit rien de
    /// ce qui s'est passé. Le symbole système et non le jeu de marque, qui n'a
    /// pas de coche — même parti pris que le chevron, un seul endroit à changer
    /// le jour où elle arrive.
    @ViewBuilder
    private func trailingMark(_ field: Editable) -> some View {
        if field.isConfirmed {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: pencilSide, weight: .semibold))
                .foregroundStyle(MemoBookColor.valid)
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
                .accessibilityLabel("Enregistré")
        } else {
            pencil
        }
    }

    private var pencil: some View {
        Image(brand: "IconPen")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: pencilSide, height: pencilSide)
            .foregroundStyle(isEditing ? MemoBookColor.action : MemoBookColor.inkMuted)
            .accessibilityHidden(true)
    }

    private var content: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            labelAndValue
                .frame(maxWidth: .infinity, alignment: .leading)
            badgeView
            if case .disclosure = accessory { chevron }
        }
        .padding(.horizontal, MemoBookSpacing.s)
        .padding(.vertical, MemoBookSpacing.xs + 4)
        .frame(minHeight: minimumHeight)
        .contentShape(.rect)
    }

    /// L'intitulé et sa valeur. Ils partagent une ligne tant qu'ils y tiennent :
    /// en taille accessible, la valeur passe dessous plutôt que de rogner l'un
    /// ou l'autre.
    @ViewBuilder
    private var labelAndValue: some View {
        if valuePlacement == .below || typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                titleText
                valueText
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: MemoBookSpacing.s) {
                titleText
                Spacer(minLength: 0)
                valueText
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    @ViewBuilder
    private var titleText: some View {
        switch titleTone {
        case .plain:
            Text(title)
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        case .accent:
            Text(title.uppercased())
                .font(MemoBookFont.overline)
                .tracking(MemoBookFont.tracking(12))
                .foregroundStyle(MemoBookColor.action)
                .fixedSize(horizontal: false, vertical: true)
                // Les capitales sont un dessin, pas une manière de crier :
                // VoiceOver lit l'intitulé tel qu'il est écrit.
                .accessibilityLabel(title)
        }
    }

    /// La pastille de bout de ligne. Elle passe **après** la valeur : c'est un
    /// commentaire sur elle, pas un second intitulé.
    @ViewBuilder
    private var badgeView: some View {
        if let badge {
            BrandTagPill(badge, isUppercased: true)
        }
    }

    @ViewBuilder
    private var valueText: some View {
        if isValueLoading {
            // Une barre de la largeur d'une valeur courante, pas de la ligne
            // entière : elle doit se lire comme « la valeur arrive », pas comme
            // « la ligne est vide ».
            BrandSkeleton(width: valuePlacement == .below ? 180 : 120)
                .frame(maxWidth: valuePlacement == .below ? .infinity : nil, alignment: .leading)
        } else if let value {
            Text(value)
                .font(isValueProminent ? MemoBookFont.bodySemibold : MemoBookFont.body)
                .foregroundStyle(isValueProminent ? MemoBookColor.ink : MemoBookColor.inkMuted)
                // Une valeur trop longue s'abrège par la fin quand elle est en
                // bout de ligne — la fin d'une adresse en dit autant que son
                // début.
                //
                // **Elle ne rapetisse que dans un groupe mis en avant.** Une
                // adresse écrite un poil plus petit que le téléphone au-dessus
                // se remarque immédiatement, et se lit comme un défaut : dans
                // une pile de lignes, la régularité prime sur le mot qui
                // manque. Les chiffres d'un groupe cerclé, eux, sont le sujet
                // de la ligne et doivent se lire entiers : une fourchette de
                // dates coupée au milieu ne dit plus rien.
                .lineLimit(valuePlacement == .trailing && !typeSize.isAccessibilitySize ? 1 : nil)
                .minimumScaleFactor(titleTone == .accent ? 0.85 : 1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Le chevron n'existe pas dans le jeu d'icônes de la marque, dont la
    /// flèche est un tracé dessiné, bien trop présent en bout de ligne. On
    /// reste donc sur le symbole système — comme le calendrier et l'itinéraire
    /// de l'accueil, et pour la même raison. Un seul endroit à changer le jour
    /// où le jeu en gagne un.
    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: chevronSide, weight: .medium))
            .foregroundStyle(MemoBookColor.inkMuted)
            .accessibilityHidden(true)
    }

    /// Une ligne pressée s'éclaire, elle ne s'enfonce pas : elle est solidaire
    /// de la carte qui la porte, et une carte ne se plie pas ligne par ligne.
    private struct RowPressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(configuration.isPressed ? MemoBookColor.background : Color.clear)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

/// De quoi écrire les lignes d'un ``BrandRowGroup`` les unes sous les autres,
/// avec les `if` qu'un écran a le droit d'avoir (une ligne qui n'apparaît que
/// si la donnée existe).
@resultBuilder
public enum BrandRowBuilder {
    public static func buildBlock(_ components: [BrandRow]...) -> [BrandRow] {
        components.flatMap(\.self)
    }
    public static func buildExpression(_ expression: BrandRow) -> [BrandRow] { [expression] }
    public static func buildExpression(_ expression: [BrandRow]) -> [BrandRow] { expression }
    public static func buildOptional(_ component: [BrandRow]?) -> [BrandRow] { component ?? [] }
    public static func buildEither(first component: [BrandRow]) -> [BrandRow] { component }
    public static func buildEither(second component: [BrandRow]) -> [BrandRow] { component }
    public static func buildArray(_ components: [[BrandRow]]) -> [BrandRow] { components.flatMap(\.self) }
    public static func buildLimitedAvailability(_ component: [BrandRow]) -> [BrandRow] { component }
}

#Preview("Lignes groupées") {
    ScrollView {
        VStack(spacing: MemoBookSpacing.s) {
            BrandRowGroup {
                BrandRow("E-mail", value: "maylis.garde@icloud.com")
                BrandRow("Téléphone", value: "+33 6 98 69 34 48")
                BrandRow("Adresse postale", value: "7 Rue Simon Fryd, Lyon, France") {}
                BrandRow("Newsletter mensuelle MemoBook", isOn: .constant(true))
            }

            BrandRowGroup {
                BrandRow("Ma cagnotte", value: "67,88 €", isValueProminent: true) {}
                BrandRow("Mon abonnement") {}
                BrandRow("Partager sur la galerie", isOn: .constant(false))
            }

            BrandRowGroup {
                BrandRow(
                    "Carte bancaire enregistrée",
                    value: "XXXX XXXX XXXX 1820",
                    valuePlacement: .below
                ) {}
            }
        }
        .padding(MemoBookSpacing.screenMargin)
    }
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}

#Preview("Lignes groupées — AX3") {
    ScrollView {
        BrandRowGroup {
            BrandRow("E-mail", value: "maylis.garde@icloud.com")
            BrandRow("Adresse postale", value: "7 Rue Simon Fryd, Lyon, France") {}
            BrandRow("Newsletter mensuelle MemoBook", isOn: .constant(true))
        }
        .padding(MemoBookSpacing.screenMargin)
    }
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
    .environment(\.dynamicTypeSize, .accessibility3)
}
