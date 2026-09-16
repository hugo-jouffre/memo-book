import SwiftUI

/// Un mois qu'on parcourt, et une plage de jours qu'on y pose en deux gestes :
/// le départ, puis le retour.
///
/// **Le sélecteur du système ne sait pas faire ça.** `DatePicker` choisit un
/// jour, et un seul ; deux sélecteurs côte à côte demandent quatre gestes et
/// deux calendriers pour une question que tout le monde se pose en une fois —
/// « du combien au combien ? ». Ce calendrier en est un seul, dessiné à la
/// main, où la plage se lit d'un coup : une bande entre les deux jours.
///
/// **Les règles du geste**, dans ``DateRangeSelection`` :
///
/// - rien de posé → le jour touché devient le départ ;
/// - un départ seul → un jour après lui devient le retour, un jour avant
///   devient le nouveau départ ;
/// - les deux posés → on recommence, le jour touché est le nouveau départ ;
/// - toucher le départ seul ne fait rien : la plage d'un jour, c'est un
///   retour posé sur le départ.
///
/// Un retour n'est jamais exigé : un voyage dont on ne connaît pas la fin
/// commence quand même.
public struct BrandRangeCalendar: View {
    @Binding private var selection: DateRangeSelection
    /// Le mois affiché : celui du départ à l'ouverture, ou celui d'aujourd'hui.
    @State private var visibleMonth: Date
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var daySide: CGFloat = 40

    public init(selection: Binding<DateRangeSelection>) {
        _selection = selection
        let anchor = selection.wrappedValue.start ?? .now
        _visibleMonth = State(initialValue: Calendar.current.startOfMonth(for: anchor))
    }

    public var body: some View {
        VStack(spacing: MemoBookSpacing.xs) {
            monthBar
            weekdayHeader
            daysGrid
        }
        .padding(MemoBookSpacing.snug)
        .background(MemoBookColor.surface, in: .rect(cornerRadius: MemoBookSpacing.largeCornerRadius))
    }

    // MARK: - Le mois

    private var monthBar: some View {
        HStack(spacing: MemoBookSpacing.xs) {
            monthButton("Mois précédent", icon: "chevron.left", offset: -1)

            Text(monthTitle)
                .font(MemoBookFont.sectionTitle)
                .foregroundStyle(MemoBookColor.ink)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())
                .accessibilityAddTraits(.isHeader)

            monthButton("Mois suivant", icon: "chevron.right", offset: 1)
        }
    }

    private func monthButton(_ label: String, icon: String, offset: Int) -> some View {
        Button(label, systemImage: icon) {
            guard let month = calendar.date(byAdding: .month, value: offset, to: visibleMonth) else { return }
            withAnimation(.smooth(duration: 0.2)) { visibleMonth = month }
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(MemoBookColor.action)
        .frame(width: MemoBookSpacing.minimumTapTarget, height: MemoBookSpacing.minimumTapTarget)
        .contentShape(.rect)
    }

    /// « septembre 2026 », avec sa majuscule : le format du système la laisse
    /// en minuscule, ce qui se lit comme un mot au milieu d'une phrase.
    private var monthTitle: String {
        let title = visibleMonth.formatted(.dateTime.month(.wide).year().locale(locale))
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    // MARK: - Les jours

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    }

    /// « L M M J V S D », dans l'ordre où la région compte les semaines.
    private var weekdayHeader: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let ordered = Array(symbols[first...] + symbols[..<first])

        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var daysGrid: some View {
        LazyVGrid(columns: columns, spacing: MemoBookSpacing.xs / 2) {
            ForEach(Array(calendar.monthGrid(for: visibleMonth).enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: daySide)
                }
            }
        }
        .animation(.smooth(duration: 0.2), value: selection)
    }

    private func dayCell(_ day: Date) -> some View {
        let role = selection.role(of: day, calendar: calendar)
        let isToday = calendar.isDateInToday(day)

        return Button {
            selection.tap(day, calendar: calendar)
        } label: {
            Text(day.formatted(.dateTime.day()))
                .font(role.isEndpoint ? MemoBookFont.bodySemibold : MemoBookFont.body)
                .foregroundStyle(role.isEndpoint ? MemoBookColor.onAction : MemoBookColor.ink)
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: daySide)
                .background { dayBackground(role) }
                .overlay {
                    if isToday, !role.isEndpoint {
                        Circle()
                            .strokeBorder(MemoBookColor.action, lineWidth: 1)
                            .frame(width: daySide, height: daySide)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(locale)))
        .accessibilityValue(role.accessibilityValue)
        .accessibilityAddTraits(role == .none ? [] : .isSelected)
    }

    /// La bande de la plage, et les deux ronds qui la bornent.
    ///
    /// Chaque case dessine **sa** part de bande : la moitié droite pour le
    /// départ, la gauche pour le retour, toute la largeur entre les deux. Les
    /// bords de semaine s'en trouvent réglés sans rien de plus : une case en
    /// bout de ligne s'arrête là où la grille s'arrête.
    @ViewBuilder
    private func dayBackground(_ role: DateRangeSelection.Role) -> some View {
        switch role {
        case .none:
            EmptyView()
        case .start(isClosed: let isClosed):
            ZStack {
                if isClosed { halfBand(.trailing) }
                endpoint
            }
        case .end:
            ZStack {
                halfBand(.leading)
                endpoint
            }
        case .inside:
            band.frame(height: daySide)
        }
    }

    private var endpoint: some View {
        Circle()
            .fill(MemoBookColor.action)
            .frame(width: daySide, height: daySide)
    }

    private var band: some View {
        Rectangle().fill(MemoBookColor.outline.opacity(0.45))
    }

    private func halfBand(_ side: HorizontalAlignment) -> some View {
        GeometryReader { proxy in
            band
                .frame(width: proxy.size.width / 2, height: daySide)
                .frame(maxWidth: .infinity, alignment: Alignment(horizontal: side, vertical: .center))
        }
        .frame(height: daySide)
    }
}

// MARK: - La plage

/// Un départ, un retour éventuel, et le geste qui les pose.
///
/// Les jours sont ramenés à minuit à l'entrée : deux dates du même jour sont
/// alors **égales**, ce qui simplifie chaque comparaison qui suit, et c'est de
/// toute façon ce qu'un voyage sait — un jour de départ, pas une heure.
public struct DateRangeSelection: Equatable, Sendable {
    public var start: Date?
    public var end: Date?

    public init(start: Date? = nil, end: Date? = nil, calendar: Calendar = .current) {
        self.start = start.map(calendar.startOfDay)
        self.end = end.map(calendar.startOfDay)
    }

    public var isEmpty: Bool { start == nil }

    /// Le geste — voir les règles en tête de ``BrandRangeCalendar``.
    public mutating func tap(_ date: Date, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)

        switch (start, end) {
        case (nil, _):
            start = day
        case (let start?, nil) where day > start:
            end = day
        case (let start?, nil) where day == start:
            break
        default:
            start = day
            end = nil
        }
    }

    public mutating func clear() {
        start = nil
        end = nil
    }

    /// Ce qu'un jour est pour la plage : rien, une borne, ou dedans.
    public enum Role: Equatable {
        case none
        /// `isClosed` : un retour existe, la bande part de cette case.
        case start(isClosed: Bool)
        case end
        case inside

        var isEndpoint: Bool {
            switch self {
            case .start, .end: true
            case .none, .inside: false
            }
        }

        var accessibilityValue: String {
            switch self {
            case .none: ""
            case .start: "Départ"
            case .end: "Retour"
            case .inside: "Pendant le voyage"
            }
        }
    }

    public func role(of date: Date, calendar: Calendar = .current) -> Role {
        let day = calendar.startOfDay(for: date)
        guard let start else { return .none }
        if day == start { return .start(isClosed: end != nil && end != start) }
        guard let end else { return .none }
        if day == end { return .end }
        return day > start && day < end ? .inside : .none
    }
}

// MARK: - Le mois en grille

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }

    /// Les jours du mois, précédés d'autant de `nil` qu'il faut pour que le
    /// premier tombe dans sa colonne de semaine.
    func monthGrid(for month: Date) -> [Date?] {
        let first = startOfMonth(for: month)
        guard let count = range(of: .day, in: .month, for: first)?.count else { return [] }
        let leading = (component(.weekday, from: first) - firstWeekday + 7) % 7

        let days = (0..<count).compactMap { offset -> Date? in
            date(byAdding: .day, value: offset, to: first)
        }
        return Array(repeating: nil, count: leading) + days
    }
}

#Preview("Plage") {
    @Previewable @State var selection = DateRangeSelection(
        start: .now,
        end: Calendar.current.date(byAdding: .day, value: 9, to: .now)
    )

    return VStack(spacing: MemoBookSpacing.s) {
        BrandRangeCalendar(selection: $selection)
        Text("\(selection.start?.formatted(date: .abbreviated, time: .omitted) ?? "—") → \(selection.end?.formatted(date: .abbreviated, time: .omitted) ?? "—")")
            .font(MemoBookFont.caption)
    }
    .padding(MemoBookSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(MemoBookColor.background)
    .environment(\.colorScheme, .light)
}
