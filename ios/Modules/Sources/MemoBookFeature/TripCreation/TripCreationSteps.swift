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
            TripThemePicker(selection: $model.selectedTheme) { theme in
                if theme != .other { focus.wrappedValue = nil }
            }
            // La rangée va **jusqu'aux bords de l'écran**, contrairement au
            // reste de l'étape : c'est ce qui permet à la première et à la
            // dernière pastille d'atteindre le milieu, et au défilement de
            // sortir de la colonne de texte au lieu de s'y arrêter.
            .padding(.horizontal, -MemoBookSpacing.screenMargin)

            if model.selectedTheme == .other {
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

    /// Deux lignes qui se déplient. Le sélecteur s'ouvre **sous** la ligne
    /// qu'on touche plutôt que dans une feuille : les deux dates se lisent
    /// ensemble, et une feuille par-dessus cacherait celle qu'on vient de
    /// poser.
    private var dates: some View {
        VStack(spacing: MemoBookSpacing.xs + 4) {
            TripDateRow(
                label: "Date de début",
                date: $model.draft.startDate,
                // Une fin déjà posée borne le début : l'inverse n'a pas de sens
                // et le serveur le refuserait.
                range: ...(model.draft.endDate ?? .distantFuture)
            )

            TripDateRow(
                label: "Date de fin (optionnel)",
                date: $model.draft.endDate,
                range: (model.draft.startDate ?? .distantPast)...
            )
        }
    }

    // MARK: - 4. Notifications

    /// Le rythme des relances. Les libellés partent tels quels en base :
    /// `memos.narrationPace` est une consigne lue par un agent, pas une clé.
    private var notifications: some View {
        VStack(spacing: MemoBookSpacing.xs + 4) {
            ForEach(TripCreationStepContent.paces, id: \.self) { pace in
                TripCreationCard(isSelected: model.draft.narrationPace == pace) {
                    model.draft.narrationPace = pace
                } label: {
                    Text(pace)
                        .font(MemoBookFont.body)
                        .foregroundStyle(MemoBookColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    static let paces = ["Tous les jours", "Toutes les semaines", "Tous les mois"]

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
            .foregroundStyle(MemoBookColor.inkSecondary)
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

/// Les sept thèmes, en rangée qui défile, celui qui est choisi au milieu et
/// bien plus gros que les autres.
///
/// **C'est un carrousel et non une barre de pastilles**, et c'est ce que dit la
/// maquette : sept thèmes ne tiennent pas côte à côte à une taille lisible, et
/// celui qui est choisi y est deux fois plus grand que ses voisins. La rangée se
/// fait donc glisser, et le choix se pose au centre — d'où les marges latérales,
/// qui valent la moitié de ce qui reste : sans elles, ni le premier ni le
/// dernier thème ne pourraient atteindre le milieu.
///
/// **Glisser ne choisit pas.** On promène la rangée pour voir ce qu'il y a, on
/// touche pour choisir — et ce qu'on touche vient alors au centre. Un carrousel
/// qui choisirait en passant remplirait `memos.theme` de tout ce qu'on a
/// survolé, et rendrait « Passer » impossible à atteindre.
struct TripThemePicker: View {
    @Binding var selection: TripTheme?

    /// Prévenu du thème choisi, pour que l'étape range son clavier quand le
    /// champ libre disparaît.
    let onSelect: (TripTheme) -> Void

    /// La largeur d'une pastille. Fixe, parce que c'est elle qui règle le
    /// centrage : la marge latérale vaut la moitié de ce qui reste quand une
    /// pastille est au milieu.
    @ScaledMetric(relativeTo: .title) private var itemWidth: CGFloat = 72

    /// La hauteur réservée : l'émoji au plus gros, et la ligne du libellé. Elle
    /// ne bouge pas avec la sélection, sinon toute l'étape sauterait à chaque
    /// choix.
    @ScaledMetric(relativeTo: .title) private var rowHeight: CGFloat = 74

    var body: some View {
        GeometryReader { proxy in
            // Ce qu'il faut de chaque côté pour qu'une pastille de bord puisse
            // venir au milieu.
            let inset = max(0, (proxy.size.width - itemWidth) / 2)

            ScrollViewReader { scroll in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(TripTheme.all) { theme in
                            TripThemeButton(
                                theme: theme,
                                isSelected: selection == theme
                            ) {
                                choose(theme, scroll: scroll)
                            }
                            .frame(width: itemWidth)
                            .id(theme.id)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .safeAreaPadding(.horizontal, inset)
                // Le thème choisi revient au centre quand on repasse par
                // l'étape — la flèche de retour, par exemple. Sans choix, la
                // rangée s'ouvre sur son **milieu** et non sur son début :
                // c'est le cadrage de la maquette, et le seul qui montre des
                // thèmes des deux côtés au lieu d'une moitié d'écran vide.
                .onAppear {
                    scroll.scrollTo(selection?.id ?? TripTheme.middle.id, anchor: .center)
                }
            }
        }
        .frame(height: rowHeight)
    }

    private func choose(_ theme: TripTheme, scroll: ScrollViewProxy) {
        onSelect(theme)
        // Un seul bloc animé : la pastille grossit, la rangée se recentre et le
        // champ libre se déplie **du même mouvement**. Écrits séparément, les
        // trois se décalaient les uns des autres.
        withAnimation(.smooth(duration: 0.3)) {
            selection = theme
            scroll.scrollTo(theme.id, anchor: .center)
        }
    }
}

// MARK: - Un émoji de thème

/// Un thème : son émoji, et son nom seulement quand il est choisi.
///
/// C'est le dessin de la maquette, et il tient debout : sept libellés côte à
/// côte formeraient un mur de texte, alors qu'un seul dit ce qu'on vient de
/// choisir. VoiceOver, lui, entend toujours le nom — sans quoi la rangée serait
/// sept boutons sans étiquette.
///
/// L'agrandissement est un `scaleEffect` et non un changement de corps : une
/// taille de police ne s'anime pas, elle saute d'une valeur à l'autre.
struct TripThemeButton: View {
    let theme: TripTheme
    let isSelected: Bool
    let action: () -> Void

    /// Le rapport entre le thème choisi et ses voisins. Il est franc — presque
    /// du simple au double — parce que c'est **la seule** chose qui dit lequel
    /// est choisi : il n'y a ni pastille, ni contour, ni coche.
    private static let selectedScale: CGFloat = 1.7

    @ScaledMetric(relativeTo: .title) private var side: CGFloat = 25

    /// La boîte de l'émoji : la taille du plus gros, avec de quoi loger la
    /// hauteur de ligne que les polices d'émoji ajoutent autour du dessin.
    @ScaledMetric(relativeTo: .title) private var emojiBox: CGFloat = 46

    /// La boîte du libellé, réservée qu'il soit écrit ou non.
    @ScaledMetric(relativeTo: .subheadline) private var labelBox: CGFloat = 20

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(theme.emoji)
                    .font(.system(size: side))
                    .scaleEffect(isSelected ? Self.selectedScale : 1)
                    // La place du plus gros, toujours, et **la même pour
                    // tous** : c'est cette boîte, et non la hauteur du glyphe,
                    // qui pose la ligne médiane de la rangée. Sans elle, un
                    // émoji haut comme la bulle remontait ses voisins.
                    .frame(height: emojiBox)

                Text(isSelected ? theme.label : " ")
                    // Le corps des intitulés (14) et non celui des légendes
                    // (12) : c'est le seul mot qui nomme ce qu'on vient de
                    // choisir, il se lit sans se pencher.
                    .font(MemoBookFont.label)
                    .foregroundStyle(MemoBookColor.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    // Réservé pour tous, comme la boîte au-dessus : le libellé
                    // du thème choisi ne doit pas décaler la rangée.
                    .frame(height: labelBox)
            }
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

// MARK: - Une date

/// Une ligne de date qui se déplie sur son calendrier.
struct TripDateRow: View {
    let label: String
    @Binding var date: Date?
    let range: PartialRangeThrough<Date>?
    let openRange: PartialRangeFrom<Date>?

    init(label: String, date: Binding<Date?>, range: PartialRangeThrough<Date>) {
        self.label = label
        self._date = date
        self.range = range
        self.openRange = nil
    }

    init(label: String, date: Binding<Date?>, range: PartialRangeFrom<Date>) {
        self.label = label
        self._date = date
        self.range = nil
        self.openRange = range
    }

    @State private var isOpen = false

    /// Ce que la ligne affiche : la date choisie, ou l'intitulé en gris tant
    /// qu'il n'y en a pas.
    private var text: String {
        date?.formatted(.dateTime.day().month(.wide).year()) ?? label
    }

    var body: some View {
        VStack(spacing: 0) {
            TripCreationCard(isSelected: isOpen) {
                if date == nil { date = .now }
                withAnimation(.smooth(duration: 0.25)) { isOpen.toggle() }
            } label: {
                HStack(spacing: MemoBookSpacing.xs + 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 18))
                        .foregroundStyle(MemoBookColor.ink)

                    Text(text)
                        .font(MemoBookFont.body)
                        .foregroundStyle(date == nil ? MemoBookColor.inkSecondary : MemoBookColor.ink)

                    Spacer(minLength: 0)

                    if date != nil {
                        Button {
                            date = nil
                            withAnimation(.smooth(duration: 0.25)) { isOpen = false }
                        } label: {
                            Image(brand: "IconCross")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                                .foregroundStyle(MemoBookColor.inkSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Effacer \(label)")
                    }
                }
            }

            if isOpen {
                picker
                    .datePickerStyle(.graphical)
                    .tint(MemoBookColor.action)
                    .padding(.horizontal, MemoBookSpacing.xs)
                    .padding(.top, MemoBookSpacing.xs)
            }
        }
    }

    @ViewBuilder
    private var picker: some View {
        let bound = Binding(get: { date ?? .now }, set: { date = $0 })

        if let range {
            DatePicker(label, selection: bound, in: range, displayedComponents: .date)
                .labelsHidden()
        } else if let openRange {
            DatePicker(label, selection: bound, in: openRange, displayedComponents: .date)
                .labelsHidden()
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
                        .foregroundStyle(MemoBookColor.inkSecondary)

                    Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 15))
                        .foregroundStyle(hasCopied ? MemoBookColor.valid : MemoBookColor.inkSecondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copier le code d’accès \(code)")

            BrandButton(
                "Partager via Whatsapp",
                icon: Image(systemName: "message"),
                style: .secondary,
                fillsWidth: true,
                action: share
            )
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

        guard let root = scene?.keyWindow?.rootViewController else { return }

        let sheet = UIActivityViewController(activityItems: [invitation], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = root.view
        root.present(sheet, animated: true)
    }
}
