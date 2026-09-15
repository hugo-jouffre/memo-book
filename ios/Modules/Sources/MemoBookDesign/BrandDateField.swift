import SwiftUI

/// Une date qui se règle : la ligne qui la montre, et le sélecteur du système
/// qui monte du bas pour la changer.
///
/// **Le sélecteur est celui d'iOS, et il monte du bas.** Il se dépliait
/// auparavant *dans* la ligne, comme à la création d'un voyage, et ça ne tient
/// plus ici : une feuille de réglages fait déjà sa hauteur, un
/// calendrier de 320 pt qui s'y ajoute la pousse au plafond et repousse le reste
/// hors de l'écran. Monté du bas, il se pose **par-dessus la feuille**, en pleine
/// largeur, là où le pouce l'attend.
///
/// **Il se referme dès qu'une date est choisie.** C'est un sélecteur, pas un
/// formulaire : il n'a rien à valider. Le seul cas où il reste ouvert est celui
/// où l'on retouche la date déjà affichée — rien n'a changé, il n'y a rien à
/// refermer —, et le glissé vers le bas le range alors comme n'importe quelle
/// feuille.
///
/// ```swift
/// BrandDateField(
///     "Date de début",
///     date: $start,
///     in: ...(end ?? .distantFuture)
/// )
/// ```
public struct BrandDateField: View {
    private let label: String
    @Binding private var date: Date?
    /// Les bornes. Deux formes parce qu'une date de début est bornée **au-delà**
    /// et une date de fin **en deçà** : `PartialRangeThrough` et
    /// `PartialRangeFrom` ne partagent pas de protocole commun que `DatePicker`
    /// accepterait.
    private let closedRange: PartialRangeThrough<Date>?
    private let openRange: PartialRangeFrom<Date>?

    public init(_ label: String, date: Binding<Date?>, in range: PartialRangeThrough<Date>) {
        self.label = label
        _date = date
        closedRange = range
        openRange = nil
    }

    public init(_ label: String, date: Binding<Date?>, in range: PartialRangeFrom<Date>) {
        self.label = label
        _date = date
        closedRange = nil
        openRange = range
    }

    @State private var isPicking = false
    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = MemoBookSpacing.m
    @ScaledMetric(relativeTo: .body) private var rowHeight = MemoBookSpacing.controlHeight

    /// Ce que la ligne affiche : la date choisie, ou l'intitulé en gris tant
    /// qu'il n'y en a pas.
    private var text: String {
        date?.formatted(.dateTime.day().month(.wide).year()) ?? label
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.controlCornerRadius)

        return Button {
            // Une date est posée **à l'ouverture** quand il n'y en avait pas :
            // le sélecteur doit s'ouvrir sur quelque chose, et c'est aussi ce
            // qui rend « aujourd'hui » choisissable d'un seul geste.
            if date == nil { date = .now }
            isPicking = true
        } label: {
            HStack(spacing: MemoBookSpacing.snug) {
                Image(brand: "IconLucideCalendar")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: iconSide, height: iconSide)
                    .foregroundStyle(MemoBookColor.ink)
                    .accessibilityHidden(true)

                Text(text)
                    .font(MemoBookFont.body)
                    .foregroundStyle(date == nil ? MemoBookColor.inkMuted : MemoBookColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: MemoBookSpacing.xs)

                if date != nil { clearButton }
            }
            .padding(.horizontal, MemoBookSpacing.s)
            .padding(.vertical, MemoBookSpacing.snug)
            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
            .background(MemoBookColor.surface, in: shape)
            .overlay { shape.strokeBorder(MemoBookColor.hairline, lineWidth: 1) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(date.map { $0.formatted(date: .long, time: .omitted) } ?? "Non définie")
        .accessibilityAddTraits(.isButton)
        // Une feuille du système, et non une ``BrandSheet`` : celle-ci
        // n'annonce rien au compteur de recul, donc la feuille de réglages
        // dessous ne rapetisse pas. Un sélecteur de date n'est pas une étape
        // de plus dans un chemin, c'est un accessoire de la ligne qu'on touche.
        .sheet(isPresented: $isPicking) { picker }
    }

    private var clearButton: some View {
        Button {
            date = nil
        } label: {
            Image(brand: "IconCross")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: MemoBookSpacing.snug + 2, height: MemoBookSpacing.snug + 2)
                .foregroundStyle(MemoBookColor.inkMuted)
                .frame(
                    width: MemoBookSpacing.minimumTapTarget,
                    height: MemoBookSpacing.minimumTapTarget
                )
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Effacer \(label)")
    }

    // MARK: - Le sélecteur

    /// Le calendrier du système, dans une feuille calée sur sa hauteur.
    ///
    /// `.graphical` et non `.wheel` : c'est le sélecteur que tout iOS montre
    /// depuis iOS 14 quand on touche une date, et surtout **le seul des deux où
    /// choisir est un geste unique** — on tape un jour, c'est fini. Une roue se
    /// fait tourner sans jamais rien valider, et « se refermer après le choix »
    /// n'y voudrait rien dire.
    private var picker: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(MemoBookColor.separator)
                .frame(width: 40, height: 5)
                .padding(.vertical, MemoBookSpacing.xs)
                .accessibilityHidden(true)

            Text(label)
                .font(MemoBookFont.sectionTitle)
                .foregroundStyle(MemoBookColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, MemoBookSpacing.screenMargin)
                .accessibilityAddTraits(.isHeader)

            datePicker
                .datePickerStyle(.graphical)
                .tint(MemoBookColor.action)
                .labelsHidden()
                .padding(.horizontal, MemoBookSpacing.s)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(MemoBookColor.surface)
        .presentationCornerRadius(MemoBookSpacing.sheetCornerRadius)
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private var datePicker: some View {
        // Le passage par une liaison à nous, et non `$date` directement : c'est
        // **elle** qui referme la feuille au moment où la valeur change. Un
        // `onChange` posé à côté ferait la même chose une image plus tard, et on
        // verrait le jour se sélectionner avant que la feuille parte.
        let bound = Binding(
            get: { date ?? .now },
            set: { picked in
                date = picked
                isPicking = false
            }
        )

        if let closedRange {
            DatePicker(label, selection: bound, in: closedRange, displayedComponents: .date)
        } else if let openRange {
            DatePicker(label, selection: bound, in: openRange, displayedComponents: .date)
        } else {
            DatePicker(label, selection: bound, displayedComponents: .date)
        }
    }
}

#Preview("Dates") {
    @Previewable @State var start: Date? = nil
    @Previewable @State var end: Date? = .now

    return VStack(spacing: MemoBookSpacing.snug) {
        BrandDateField("Date de début", date: $start, in: ...(end ?? .distantFuture))
        BrandDateField("Date de fin (optionnel)", date: $end, in: (start ?? .distantPast)...)
    }
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(MemoBookColor.surface)
    .environment(\.colorScheme, .light)
}
