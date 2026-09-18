import MemoBookCore
import MemoBookDesign
import SwiftUI
import UIKit

/// Les champs de la création. Le focus appartient à l'écran, pas au champ —
/// voir `ios/CLAUDE.md`, « Design system ».
enum TripCreationField: Hashable {
    case freeTheme
    case title
}

/// Le milieu de l'écran : ce que l'étape courante demande, et rien d'autre.
///
/// Une seule vue pour les six cas plutôt que six fichiers : elles partagent la
/// même largeur, la même colonne et le même modèle, et les mettre côte à côte
/// est la seule façon de voir qu'elles se ressemblent autant.
struct TripCreationStepContent: View {
    @Bindable var model: TripCreationModel
    var focus: FocusState<TripCreationField?>.Binding

    var body: some View {
        switch model.step {
        case .theme: theme
        case .name: name
        case .dates: dates
        case .notifications: notifications
        case .ratio: ratio
        case .companions: companions
        }
    }

    // MARK: - 1. Contexte

    /// La rangée d'émojis, et le champ libre quand on choisit « Autre ».
    ///
    /// Le champ n'apparaît **que** derrière « Autre », et c'est exactement
    /// l'état que montre la maquette : un thème choisi et un thème écrit sont
    /// deux réponses à la même question, les afficher ensemble laisserait
    /// croire qu'on peut donner les deux.
    private var theme: some View {
        VStack(spacing: MemoBookSpacing.m) {
            if model.themes.isEmpty {
                // Les thèmes viennent du serveur : le temps qu'ils arrivent, la
                // rangée tient sa place — une barre d'attente, pas des émojis
                // inventés. Si la lecture a échoué, on le dit, et « Passer »
                // reste là.
                if let failure = model.themesFailure {
                    ErrorBanner(message: failure) {
                        Task { await model.loadThemes() }
                    }
                } else {
                    TripThemePickerPlaceholder()
                }
            } else {
                TripThemePicker(themes: model.themes, selection: $model.selectedTheme) { theme in
                    if !theme.isOther { focus.wrappedValue = nil }
                }
                // La rangée va **jusqu'aux bords de l'écran**, contrairement au
                // reste de l'étape : c'est ce qui permet à la première et à la
                // dernière pastille d'atteindre le milieu, et au défilement de
                // sortir de la colonne de texte au lieu de s'y arrêter.
                .padding(.horizontal, -MemoBookSpacing.screenMargin)
            }

            if model.isFreeThemeChosen {
                // Il **arrive**, il n'apparaît pas : le champ se déplie sous la
                // rangée en même temps que « Autre » grossit, et repart de même.
                // Sans transition, il claque à l'écran au milieu d'un mouvement.
                BrandTextField(
                    "Thème de ton voyage",
                    text: $model.freeTheme,
                    field: TripCreationField.freeTheme,
                    focus: focus,
                    labelPlacement: .hidden,
                    placeholder: "Entre le thème de ton voyage ici"
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - 2. Nom

    private var name: some View {
        BrandTextField(
            "Nom de ton voyage",
            text: $model.draft.title,
            field: TripCreationField.title,
            focus: focus,
            labelPlacement: .hidden,
            placeholder: "Entre le nom de ton voyage ici"
        )
    }

    // MARK: - 3. Dates

    /// Deux cases, « Départ » et « Retour », et un seul calendrier qui se
    /// déplie dessous.
    ///
    /// Une seule ligne « Du … au … » promettait deux dates, et le retour n'est
    /// pas exigé : la case « Retour » dit « Facultatif » tant qu'elle est vide,
    /// l'écran le dit lui-même. Le calendrier s'ouvre **sous** les cases plutôt
    /// que dans une feuille : ce qu'on vient de poser reste lisible au-dessus.
    private var dates: some View {
        TripDateRangeRow(start: $model.draft.startDate, end: $model.draft.endDate)
    }

    // MARK: - 4. Notifications

    /// Le rythme des relances — **les mêmes que les réglages du voyage**
    /// (``NarrationPace``), dont on ne propose ici que trois : on va vite à
    /// la création, on ajuste finement plus tard (Hugo, 17/09/2026, T122).
    /// C'est la clé du rythme qui part en base, comme depuis la feuille des
    /// réglages ; trois libellés libres y écrivaient une autre langue.
    private var notifications: some View {
        VStack(spacing: MemoBookSpacing.xs + 4) {
            ForEach(TripCreationStepContent.paces, id: \.self) { pace in
                TripCreationCard(isSelected: model.draft.narrationPace == pace.rawValue) {
                    model.draft.narrationPace = pace.rawValue
                } label: {
                    Text(pace.displayName)
                        .font(MemoBookFont.body)
                        .foregroundStyle(MemoBookColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    static let paces: [NarrationPace] = [.daily, .everyTwoDays, .weekly]

    // MARK: - 5. Ratio image / texte

    /// Un curseur entre deux bornes nommées, et le pourcentage sous la poignée.
    ///
    /// Par pas de 10 : la maquette montre « 50 % », et le réglage pilote le
    /// choix des gabarits de page, pas une largeur au pixel. Un curseur continu
    /// donnerait « 47 % », qui ne veut rien dire de plus que « 50 % ».
    private var ratio: some View {
        VStack(spacing: MemoBookSpacing.xs) {
            Slider(
                value: Binding(
                    get: { Double(model.draft.photoTextRatio) },
                    set: { model.draft.photoTextRatio = Int($0.rounded()) }
                ),
                in: 0...100,
                step: 10
            )
            .tint(MemoBookColor.action)

            HStack(alignment: .top) {
                Text("Beaucoup\nde texte")
                    .multilineTextAlignment(.leading)
                Spacer()
                Text("\(model.draft.photoTextRatio) %")
                    // La valeur du réglage, et donc ce qu'on lit en poussant le
                    // curseur : elle prend le corps d'un titre. En légende, on
                    // ne voyait pas ce qu'on était en train de changer.
                    .font(MemoBookFont.h2)
                    .foregroundStyle(MemoBookColor.action)
                    // Les chiffres ne dansent pas : sans chasse fixe, la valeur
                    // se décale à chaque pas du curseur.
                    .monospacedDigit()
                Spacer()
                Text("Beaucoup\nd’image")
                    .multilineTextAlignment(.trailing)
            }
            // Les deux bornes disent ce que le curseur fait : elles se lisent
            // d'un coup d'œil, pas en s'approchant de l'écran.
            .font(MemoBookFont.body)
            .foregroundStyle(MemoBookColor.inkMuted)
        }
    }

    // MARK: - 6. Co-voyageurs

    /// Le code d'accès, et de quoi l'envoyer. Rien à valider ici : le voyage
    /// existe déjà, c'est la validation de l'étape précédente qui l'a créé.
    @ViewBuilder
    private var companions: some View {
        if let created = model.created {
            TripAccessCode(code: created.accessCode, tripTitle: created.trip.title)
        }
    }
}

// MARK: - Le carrousel des thèmes

/// Les thèmes, en rangée qui défile : celui du milieu est **celui qu'on
/// choisit**, plus gros et à pleine encre ; ses voisins s'effacent à 60 %.
///
/// **C'est un carrousel et non une barre de pastilles**, et c'est ce que dit la
/// maquette : les thèmes ne tiennent pas côte à côte à une taille lisible, et
/// celui qui est choisi y est presque deux fois plus grand que ses voisins. La
/// rangée se fait donc glisser, et le choix se pose au centre — d'où les marges
/// latérales, qui valent la moitié de ce qui reste : sans elles, ni le premier
/// ni le dernier thème ne pourraient atteindre le milieu.
///
/// **Glisser choisit.** La rangée s'arrête d'elle-même sur un thème
/// (`viewAligned`), et celui qui s'arrête au centre est le choix — Hugo,
/// 14/09/2026 : « l'émoji qui se retrouve au centre est celui sélectionné ».
/// Toucher un thème l'amène au centre, ce qui revient au même. La rangée a
/// d'abord été écrite pour ne choisir qu'au toucher, de peur qu'un survol ne
/// remplisse `memos.theme` de tout ce qu'on avait dépassé : ce n'est pas ce qui
/// se passe, la position ne se pose qu'à l'arrêt.
///
/// **Le nom du thème s'écrit sous la rangée**, en entier et centré, et non sous
/// chaque émoji : dans la boîte d'un émoji, « Vacances au soleil » et « Voyage
/// d'affaires » se faisaient rogner (Hugo, 14/09/2026).
struct TripThemePicker: View {
    /// Les thèmes, dans l'ordre du serveur — « Autre » en dernier.
    let themes: [TripTheme]
    @Binding var selection: TripTheme?

    /// Prévenu du thème choisi, pour que l'étape range son clavier quand le
    /// champ libre disparaît.
    let onSelect: (TripTheme) -> Void

    /// La largeur d'une pastille. Fixe, parce que c'est elle qui règle le
    /// centrage : la marge latérale vaut la moitié de ce qui reste quand une
    /// pastille est au milieu.
    @ScaledMetric(relativeTo: .title) private var itemWidth: CGFloat = 72

    /// La hauteur de la rangée : l'émoji au plus gros. Elle ne bouge pas avec
    /// la sélection, sinon toute l'étape sauterait à chaque glissé.
    @ScaledMetric(relativeTo: .title) private var rowHeight: CGFloat = 54

    /// La boîte du nom, réservée qu'il soit écrit ou non : le libellé arrive
    /// et repart sans décaler ce qui est dessous.
    @ScaledMetric(relativeTo: .subheadline) private var labelBox: CGFloat = 20

    /// Le thème arrêté au centre de la rangée. C'est la position de défilement
    /// elle-même, que SwiftUI pose à l'arrêt ; ``selection`` la suit.
    @State private var centered: TripTheme.ID?

    var body: some View {
        VStack(spacing: MemoBookSpacing.xs) {
            GeometryReader { proxy in
                // Ce qu'il faut de chaque côté pour qu'une pastille de bord
                // puisse venir au milieu.
                let inset = max(0, (proxy.size.width - itemWidth) / 2)

                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(themes) { theme in
                            TripThemeButton(theme: theme, isSelected: selection == theme) {
                                choose(theme)
                            }
                            .frame(width: itemWidth)
                            .id(theme.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                // Une marge de contenu et non un `padding` : c'est elle que
                // l'alignement sur les pastilles prend en compte pour poser la
                // première et la dernière au centre.
                .contentMargins(.horizontal, inset, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $centered, anchor: .center)
            }
            .frame(height: rowHeight)

            Text(selection?.label ?? " ")
                // Le corps des intitulés (14) et non celui des légendes (12) :
                // c'est le seul mot qui nomme ce qu'on vient de choisir, il se
                // lit sans se pencher.
                .font(MemoBookFont.label)
                .foregroundStyle(MemoBookColor.inkMuted)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: labelBox)
                .contentTransition(.opacity)
                .animation(.smooth(duration: 0.3), value: selection)
                .accessibilityHidden(true)
        }
        // La rangée s'ouvre sur le thème choisi, ou sur son **milieu** — c'est
        // le cadrage de la maquette, celui qui montre des thèmes des deux côtés
        // au lieu d'une moitié d'écran vide — et ce qui est au milieu devient
        // le choix, comme pour n'importe quel glissé. « Autre » étant dernier,
        // le milieu est toujours un thème précis.
        .onAppear { centered = (selection ?? middle)?.id }
        .onChange(of: centered) { _, id in
            guard let theme = themes.first(where: { $0.id == id }), theme != selection else { return }
            select(theme)
        }
        // La sélection peut changer sans la rangée — revenir sur l'étape après
        // « Passer », par exemple : la rangée la rejoint.
        .onChange(of: selection) { _, theme in
            guard let theme, centered != theme.id else { return }
            withAnimation(.smooth(duration: 0.3)) { centered = theme.id }
        }
    }

    /// Le thème du milieu de la rangée. Ce n'est pas un choix, c'est un
    /// **cadrage** : c'est là que le carrousel s'ouvre.
    private var middle: TripTheme? {
        themes.isEmpty ? nil : themes[themes.count / 2]
    }

    /// Toucher un thème l'amène au centre ; c'est l'arrêt au centre qui choisit,
    /// le même chemin que le glissé.
    private func choose(_ theme: TripTheme) {
        withAnimation(.smooth(duration: 0.3)) { centered = theme.id }
        select(theme)
    }

    private func select(_ theme: TripTheme) {
        onSelect(theme)
        // Un seul bloc animé : la pastille grossit et le champ libre se déplie
        // **du même mouvement**. Écrits séparément, les deux se décalaient.
        withAnimation(.smooth(duration: 0.3)) {
            selection = theme
        }
    }
}

/// La rangée, le temps que les thèmes arrivent : cinq ronds effacés à la place
/// des émojis, et une barre à la place du nom. Les mêmes hauteurs que la vraie
/// rangée, pour que rien ne saute quand elle se remplit.
struct TripThemePickerPlaceholder: View {
    @ScaledMetric(relativeTo: .title) private var rowHeight: CGFloat = 54
    @ScaledMetric(relativeTo: .title) private var dot: CGFloat = 25
    @ScaledMetric(relativeTo: .subheadline) private var labelBox: CGFloat = 20

    var body: some View {
        VStack(spacing: MemoBookSpacing.xs) {
            HStack(spacing: MemoBookSpacing.l) {
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(MemoBookColor.ink.opacity(index == 2 ? 0.12 : 0.07))
                        .frame(width: index == 2 ? dot * 1.7 : dot, height: index == 2 ? dot * 1.7 : dot)
                }
            }
            .frame(height: rowHeight)

            BrandSkeleton(width: 120)
                .frame(height: labelBox)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("Chargement des thèmes")
    }
}

// MARK: - Un émoji de thème

/// Un thème : son émoji, gros et à pleine encre quand il est choisi, plus petit
/// et effacé sinon. Son nom, lui, s'écrit sous la rangée — voir
/// ``TripThemePicker``. VoiceOver, en revanche, entend toujours le nom : sans
/// quoi la rangée serait sept boutons sans étiquette.
///
/// L'agrandissement est un `scaleEffect` et non un changement de corps : une
/// taille de police ne s'anime pas, elle saute d'une valeur à l'autre.
struct TripThemeButton: View {
    let theme: TripTheme
    let isSelected: Bool
    let action: () -> Void

    /// Le rapport entre le thème choisi et ses voisins. Il est franc — presque
    /// du simple au double — parce que c'est, avec l'opacité, ce qui dit lequel
    /// est choisi : il n'y a ni pastille, ni contour, ni coche.
    private static let selectedScale: CGFloat = 1.7

    /// L'opacité des voisins : 60 %, la valeur de la maquette (Hugo,
    /// 14/09/2026). Le choisi est à 100 %.
    private static let unselectedOpacity: Double = 0.6

    @ScaledMetric(relativeTo: .title) private var side: CGFloat = 25

    /// La boîte de l'émoji : la taille du plus gros, avec de quoi loger la
    /// hauteur de ligne que les polices d'émoji ajoutent autour du dessin.
    @ScaledMetric(relativeTo: .title) private var emojiBox: CGFloat = 46

    var body: some View {
        Button(action: action) {
            Text(theme.emoji)
                .font(.system(size: side))
                .scaleEffect(isSelected ? Self.selectedScale : 1)
                .opacity(isSelected ? 1 : Self.unselectedOpacity)
                // La place du plus gros, toujours, et **la même pour tous** :
                // c'est cette boîte, et non la hauteur du glyphe, qui pose la
                // ligne médiane de la rangée. Sans elle, un émoji haut comme la
                // bulle remontait ses voisins.
                .frame(height: emojiBox)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.3), value: isSelected)
        .accessibilityLabel(theme.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Une ligne blanche

/// La ligne des étapes qui listent : un aplat blanc, un grand rayon, aucun
/// contour.
///
/// ⚠️ La maquette ne montre **aucune ligne choisie** — ni coche, ni teinte. Le
/// vert et le contour de l'état sélectionné sont ajoutés ici : sans eux, on ne
/// verrait pas ce qu'on vient de toucher. À confirmer avec Clara.
struct TripCreationCard<Label: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: Label

    private var shape: RoundedRectangle {
        .rect(cornerRadius: MemoBookSpacing.largeCornerRadius)
    }

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, MemoBookSpacing.s)
                .padding(.vertical, MemoBookSpacing.s - 2)
                .frame(minHeight: MemoBookSpacing.fieldHeight)
                .background(MemoBookColor.surface, in: shape)
                .overlay {
                    shape.strokeBorder(
                        isSelected ? MemoBookColor.action : .clear,
                        lineWidth: 1.5
                    )
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Les dates

/// « Départ · 18 sept. 2026 » et « Retour · Facultatif », côte à côte, et le
/// calendrier de plage qui se déplie dessous.
///
/// La case cerclée de vert est celle que le prochain jour touché remplit.
/// Toucher une case la choisit : on revient corriger le départ sans perdre le
/// retour. Toucher la case déjà en cours replie le calendrier.
struct TripDateRangeRow: View {
    @Binding var start: Date?
    @Binding var end: Date?

    @State private var isOpen = false
    /// La case en cours — celle que le calendrier remplit. Elle vit ici et non
    /// dans le brouillon : c'est un état de l'écran, pas du voyage.
    @State private var editing: DateRangeSelection.Slot = .start
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Le calendrier travaille sur une plage ; le brouillon garde deux dates.
    /// La liaison fait le pont dans les deux sens.
    private var selection: Binding<DateRangeSelection> {
        Binding(
            get: { DateRangeSelection(start: start, end: end, editing: editing) },
            set: { picked in
                start = picked.start
                end = picked.end
                editing = picked.editing
            }
        )
    }

    var body: some View {
        VStack(spacing: MemoBookSpacing.xs) {
            // Deux cases côte à côte, empilées aux tailles accessibles.
            if typeSize.isAccessibilitySize {
                VStack(spacing: MemoBookSpacing.xs) { slots }
            } else {
                HStack(spacing: MemoBookSpacing.xs) { slots }
            }

            if isOpen {
                BrandRangeCalendar(selection: selection)

                Text(hint)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .contentTransition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var slots: some View {
        slot(.start, title: "Départ", date: start, placeholder: "À choisir")
        slot(.end, title: "Retour", date: end, placeholder: "Facultatif")
    }

    // MARK: - Une case

    private func slot(_ slot: DateRangeSelection.Slot, title: String, date: Date?, placeholder: String) -> some View {
        let isActive = isOpen && editing == slot

        return TripCreationCard(isSelected: isActive) {
            withAnimation(.smooth(duration: 0.25)) {
                if isActive {
                    isOpen = false
                } else {
                    editing = slot
                    isOpen = true
                }
            }
        } label: {
            HStack(spacing: MemoBookSpacing.xs / 2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MemoBookFont.overline)
                        .foregroundStyle(isActive ? MemoBookColor.action : MemoBookColor.inkMuted)

                    // Sur une ligne, quoi qu'il arrive : « 20 sept. 2026 » et
                    // la croix tiennent tout juste dans une demi-largeur, et
                    // une date qui se replie sur deux lignes déséquilibre les
                    // deux cases.
                    Text(date?.formatted(.dateTime.day().month(.abbreviated).year()) ?? placeholder)
                        .font(MemoBookFont.body)
                        .foregroundStyle(date == nil ? MemoBookColor.inkMuted : MemoBookColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                if date != nil {
                    Button {
                        var picked = selection.wrappedValue
                        picked.clear(slot)
                        selection.wrappedValue = picked
                    } label: {
                        Image(brand: "IconCross")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                            .foregroundStyle(MemoBookColor.inkMuted)
                            .frame(width: MemoBookSpacing.m + 4, height: MemoBookSpacing.m + 4)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(slot == .start ? "Effacer les dates" : "Effacer le retour")
                }
            }
        }
        .accessibilityLabel(slot == .start ? "Date de départ" : "Date de retour")
        .accessibilityValue(
            date.map { $0.formatted(date: .long, time: .omitted) }
                ?? (slot == .start ? "Non définie" : "Facultative, non définie")
        )
    }

    /// Ce qu'il reste à faire, dit sous le calendrier.
    private var hint: String {
        switch (editing, start, end) {
        case (.start, _, _): "Touche ton jour de départ"
        case (.end, nil, _): "Touche d'abord ton jour de départ"
        case (.end, _, nil): "Touche ton jour de retour — ou valide sans"
        default: "Touche une case pour corriger une date"
        }
    }
}

// MARK: - Le code d'accès

/// « Code d'accès : JHKFDA », et de quoi l'envoyer.
///
/// Le code se **copie** d'un geste — c'est ce que dit le petit pictogramme de
/// la maquette — et se partage par le sélecteur du système. Le bouton nomme
/// WhatsApp parce que la maquette le nomme, et il l'ouvre vraiment quand il est
/// installé ; sinon il retombe sur le partage du système, qui propose tout le
/// reste. Un bouton qui promet WhatsApp et ouvre autre chose sans le dire
/// serait pire qu'un bouton générique.
struct TripAccessCode: View {
    let code: String
    let tripTitle: String

    /// Le second bouton, « Partager », qui ouvre le sélecteur du système.
    ///
    /// Absent de la dernière étape de la création — la maquette n'y met que
    /// WhatsApp —, présent sur la feuille « Inviter un proche », qui les pose
    /// tous les deux. Le même bloc sert les deux écrans : c'est le même code
    /// d'accès, le même presse-papiers et la même invitation.
    var showsSystemShare = false

    @State private var hasCopied = false

    private var invitation: String {
        "Rejoins-moi sur MemoBook pour raconter « \(tripTitle) ». Code d’accès : \(code)"
    }

    var body: some View {
        VStack(spacing: MemoBookSpacing.l) {
            Button(action: copy) {
                HStack(spacing: MemoBookSpacing.xs) {
                    Text("Code d’accès : \(code)")
                        .font(MemoBookFont.body)
                        .foregroundStyle(MemoBookColor.inkMuted)

                    Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 15))
                        .foregroundStyle(hasCopied ? MemoBookColor.valid : MemoBookColor.inkMuted)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copier le code d’accès \(code)")

            VStack(spacing: MemoBookSpacing.s) {
                BrandButton(
                    "Partager via WhatsApp",
                    // Le logo WhatsApp, en **vert foncé** : `BrandButton` le
                    // teinte comme n'importe quelle icône de la marque (Hugo,
                    // 17/09/2026, T121). Il vient de `assets/logos/whatsapp.svg`
                    // par `import-brand-logos.py`.
                    icon: Image(brand: "LogoWhatsApp"),
                    style: showsSystemShare ? .primary : .secondary,
                    fillsWidth: true,
                    action: share
                )

                if showsSystemShare {
                    BrandButton(
                        "Partager",
                        icon: Image(brand: "IconShareSystem"),
                        style: .secondary,
                        fillsWidth: true,
                        action: presentSystemShare
                    )
                }
            }
        }
    }

    private func copy() {
        UIPasteboard.general.string = code
        withAnimation(.smooth(duration: 0.2)) { hasCopied = true }
    }

    /// WhatsApp s'il est là, le partage du système sinon.
    private func share() {
        let encoded =
            invitation.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""

        if let whatsapp = URL(string: "whatsapp://send?text=\(encoded)"),
            UIApplication.shared.canOpenURL(whatsapp)
        {
            UIApplication.shared.open(whatsapp)
            return
        }

        presentSystemShare()
    }

    private func presentSystemShare() {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        guard var presenter = scene?.keyWindow?.rootViewController else { return }

        // **On présente depuis le contrôleur le plus haut**, pas depuis la
        // racine. Ce bloc vit aussi dans la feuille « Inviter un proche », qui
        // est elle-même une feuille présentée : demander à la racine de
        // présenter pendant qu'elle présente déjà ne fait rien du tout, et la
        // console dit seulement « which is already presenting ».
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }

        let sheet = UIActivityViewController(activityItems: [invitation], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = presenter.view
        presenter.present(sheet, animated: true)
    }
}
