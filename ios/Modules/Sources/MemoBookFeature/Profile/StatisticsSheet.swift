import MemoBookCore
import MemoBookDesign
import SwiftUI

/// Les chiffres du voyageur : tous ses voyages, puis celui en cours.
///
/// **La feuille ne calcule rien.** Chaque chiffre vient du relevé que l'agent
/// de rédaction pose sur un souvenir, additionné par le serveur ; elle les
/// dessine, les accorde, et **les relit tant que l'agent en relève** — voir
/// ``StatisticsModel/watch()``. Un vocal qui vient de partir se voit arriver
/// ici : la ligne du bas dit qu'il est en lecture, puis les chiffres bougent.
///
/// Une seule carte cerclée de vert, en deux volets qui se replient chacun :
/// c'est la carte de chiffres du profil, dépliée. Les deux volets s'ouvrent
/// par défaut — on vient les lire, pas les chercher.
struct StatisticsSheet: View {
    @State private var model: StatisticsModel

    /// Chaque volet se replie séparément, comme les deux chevrons de la
    /// maquette le promettent. L'état appartient à la feuille, et repart ouvert
    /// à chaque ouverture : un volet qu'on a replié hier n'a pas à l'être
    /// encore aujourd'hui.
    @State private var showsOverall = true
    @State private var showsCurrentTrip = true

    init(model: StatisticsModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        BrandSheet("Statistiques") {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                card

                if let message = model.errorMessage {
                    ErrorBanner(message: message) {
                        Task { await model.load() }
                    }
                }
            }
            // Ce que la feuille montre change sous les yeux, et elle le dit :
            // le même balayage que l'accueil, seulement quand un chiffre a
            // vraiment bougé — jamais à la relance d'une veille immobile.
            .brandRefreshFlash(model.freshness.isUpdated)
        }
        // La veille : lit, puis relit tant qu'un relevé est attendu. La tâche
        // meurt avec la feuille, et **repart** à chaque vocal livré — c'est
        // l'identifiant qui le fait, sans minuterie ni notification.
        .task(id: model.deliveries) { await model.watch() }
    }

    // MARK: - La carte

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: MemoBookSpacing.largeCornerRadius)

        return VStack(alignment: .leading, spacing: 0) {
            overallSection
            divider
            currentTripSection
            detectingLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MemoBookColor.surface, in: shape)
        .overlay { shape.strokeBorder(MemoBookColor.action, lineWidth: 1.5) }
        .clipShape(shape)
        // Un seul ressort pour tout ce qui bouge dans la carte : les volets, les
        // chiffres, la ligne du bas. Deux animations de durées différentes sur
        // la même carte se lisent comme un défaut de synchronisation.
        .animation(.snappy(duration: 0.32), value: showsOverall)
        .animation(.snappy(duration: 0.32), value: showsCurrentTrip)
        .animation(.snappy(duration: 0.32), value: model.statistics)
    }

    /// Le filet entre les deux volets suit le contour de la carte, comme dans
    /// ``BrandRowGroup`` : un trait gris dans un cadre vert se lirait comme un
    /// oubli.
    private var divider: some View {
        Rectangle()
            .fill(MemoBookColor.action)
            .frame(height: 1)
            .padding(.horizontal, MemoBookSpacing.s)
            .accessibilityHidden(true)
    }

    // MARK: Tous les voyages

    private var overallSection: some View {
        let statistics = model.statistics

        return VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
            SectionHeader(
                title: "Statistiques",
                detail: statistics?.tripCountLabel,
                isExpanded: $showsOverall
            )

            if showsOverall {
                VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                    StatisticLine("Étapes", value: statistics?.overall.placesLabel)
                    StatisticLine("Rencontres", value: statistics?.overall.encountersLabel)
                    StatisticLine("Km parcourus", value: statistics?.overall.distanceLabel)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(MemoBookSpacing.s)
    }

    // MARK: Le voyage en cours

    @Environment(\.dynamicTypeSize) private var typeSize

    private var currentTripSection: some View {
        let statistics = model.statistics
        let trip = statistics?.currentTrip

        return VStack(alignment: .leading, spacing: MemoBookSpacing.snug) {
            SectionHeader(
                title: "Voyage en cours",
                // Sans voyage en cours, la carte reste et le dit — sa
                // disparition ferait sauter la feuille d'une hauteur de volet.
                detail: statistics.map { $0.currentTrip?.dateRangeLabel ?? "Aucun pour l’instant" },
                isExpanded: $showsCurrentTrip
            )

            if showsCurrentTrip, statistics == nil || trip != nil {
                currentTripBody(trip, overall: statistics?.overall)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(MemoBookSpacing.s)
    }

    /// Les deux anneaux à gauche, les phrases et les lignes à droite. Aux
    /// tailles accessibles, les anneaux passent au-dessus : deux colonnes de
    /// texte de 30 pt ne tiennent pas côte à côte.
    @ViewBuilder
    private func currentTripBody(_ trip: CurrentTripStatistics?, overall: TravelFigures?) -> some View {
        let writtenRing = StatisticRing(
            fraction: trip?.writtenFraction ?? 0,
            value: trip?.writtenPercentLabel,
            caption: "du voyage",
            accessibilityLabel: "Part du voyage écrite"
        )
        let countryRing = StatisticRing(
            fraction: trip.map { $0.countryFraction(of: overall ?? .empty) } ?? 0,
            value: trip.map { "\($0.figures.countries)" },
            caption: "pays",
            accessibilityLabel: "Pays de ce voyage"
        )

        let text = VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
            whereabouts(trip)

            StatisticLine("Étapes", value: trip?.figures.placesLabel)
            StatisticLine("Rencontres", value: trip?.figures.encountersLabel)
            StatisticLine("Km parcourus", value: trip?.figures.distanceLabel)
            StatisticLine("Enregistrements", value: trip?.recordingsLabel)
            StatisticLine("Transports", value: trip?.transportsLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // Les anneaux grandissent avec le texte, mais pas jusqu'aux tailles
        // accessibles : à AX3, deux anneaux au corps de 53 pt feraient 240 pt
        // chacun et débordaient de l'écran — en emmenant toute la feuille. Ils
        // s'arrêtent à xxLarge ; le texte qu'ils accompagnent, lui, continue.
        // Posé **ici** et non dans l'anneau : `@ScaledMetric` lit
        // l'environnement reçu du parent, pas celui que la vue se donne.
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MemoBookSpacing.s) {
                HStack(spacing: MemoBookSpacing.s) {
                    writtenRing
                    countryRing
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                text
            }
        } else {
            HStack(alignment: .top, spacing: MemoBookSpacing.s) {
                VStack(spacing: MemoBookSpacing.s) {
                    writtenRing
                    countryRing
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                text
            }
        }
    }

    /// « Tu es actuellement à Rome. » puis « 9 % écrit (2 jours validés sur
    /// 21) ». Les deux phrases de la maquette, l'une à l'encre, l'autre au vert
    /// d'action : la seconde commente la première.
    @ViewBuilder
    private func whereabouts(_ trip: CurrentTripStatistics?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let trip {
                if let place = trip.whereaboutsLabel {
                    Text(place)
                        .font(MemoBookFont.bodySemibold)
                        .foregroundStyle(MemoBookColor.ink)
                        .contentTransition(.numericText())
                }
                Text(trip.writtenLabel)
                    .font(MemoBookFont.label)
                    .foregroundStyle(MemoBookColor.action)
                    .contentTransition(.numericText())
            } else {
                BrandSkeleton(width: 200)
                BrandSkeleton(width: 150)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, MemoBookSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    // MARK: L'agent travaille

    /// La ligne qui dit que des souvenirs sont en lecture. Elle n'existe que
    /// pendant : la faire rester à « 0 souvenir » serait une ligne de plus à
    /// lire pour rien.
    @ViewBuilder
    private var detectingLine: some View {
        if let label = model.statistics?.detectingLabel {
            HStack(spacing: MemoBookSpacing.xs) {
                ProgressView()
                    .controlSize(.small)
                    .tint(MemoBookColor.action)
                Text(label)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, MemoBookSpacing.s)
            .padding(.bottom, MemoBookSpacing.snug)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Morceaux de la carte

/// La ligne de tête d'un volet : le surtitre en capitales vertes, le détail à
/// droite, et le chevron qui dit si le volet est ouvert. **Toute la ligne se
/// touche**, pas seulement le chevron.
private struct SectionHeader: View {
    let title: String
    /// « 5 voyages », « 10/12/2026 - 02/01/2027 ». `nil` tant que ça n'est pas
    /// arrivé : la barre d'attente prend la place.
    let detail: String?
    @Binding var isExpanded: Bool

    @ScaledMetric(relativeTo: .body) private var chevronSide: CGFloat = 22
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            Group {
                // Aux tailles accessibles, le détail passe sous le surtitre :
                // « 26/08/2026 - 15/09/2026 » ne tient plus à côté de « VOYAGE
                // EN COURS », et le tronquer effacerait la moitié de la date.
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: MemoBookSpacing.xs) {
                        HStack(alignment: .top, spacing: MemoBookSpacing.xs) {
                            overline
                            Spacer(minLength: MemoBookSpacing.xs)
                            chevron
                        }
                        detailText
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: MemoBookSpacing.xs) {
                        overline
                        Spacer(minLength: MemoBookSpacing.xs)
                        detailText
                        chevron
                    }
                }
            }
            .frame(minHeight: MemoBookSpacing.minimumTapTarget - MemoBookSpacing.s)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(detail.map { "\($0), " + (isExpanded ? "déplié" : "replié") } ?? "")
        .accessibilityAddTraits(.isHeader)
    }

    private var overline: some View {
        Text(title.uppercased())
            .font(MemoBookFont.sectionOverline)
            .foregroundStyle(MemoBookColor.action)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var detailText: some View {
        if let detail {
            Text(detail)
                .font(MemoBookFont.label)
                .foregroundStyle(MemoBookColor.action)
                // Une ligne à côté du surtitre, où il se resserre plutôt que
                // de renvoyer le chevron ; sous le surtitre, aux tailles
                // accessibles, il a toute la largeur et s'enroule.
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())
        } else {
            BrandSkeleton(width: 96)
        }
    }

    /// Le chevron du jeu de marque, tourné comme celui d'une
    /// ``BrandDisclosureCard`` : vers le bas quand le volet est replié, vers
    /// le haut quand il est ouvert.
    private var chevron: some View {
        Image(brand: "IconChevron")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: chevronSide, height: chevronSide)
            .foregroundStyle(MemoBookColor.action)
            .rotationEffect(.degrees(isExpanded ? -90 : 90))
            .animation(.snappy(duration: 0.32), value: isExpanded)
            .accessibilityHidden(true)
    }
}

/// Une ligne de la carte : l'intitulé effacé à gauche, la valeur à l'encre à
/// droite. Plus serrée qu'une ``BrandRow`` — on lit une liste de chiffres, on
/// ne touche rien —, et la valeur **roule** quand elle change.
private struct StatisticLine: View {
    let title: String
    /// `nil` tant que la valeur n'est pas arrivée.
    let value: String?

    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ title: String, value: String?) {
        self.title = title
        self.value = value
    }

    var body: some View {
        // Aux tailles accessibles la valeur passe sous son intitulé : « 1 avion,
        // 2 trains, scooter » à 30 pt ne tient sur aucune ligne.
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                label
                valueText
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: MemoBookSpacing.xs) {
                // L'intitulé garde sa ligne : c'est la valeur qui s'enroule,
                // jamais « Enregistrements » coupé en deux parce que « Pas
                // encore relevé » est large. Seulement côte à côte : en
                // colonne, aux tailles accessibles, un intitulé qui refuse de
                // s'enrouler déborde de l'écran et emmène la feuille avec lui.
                label
                    .fixedSize()
                    .layoutPriority(1)
                Spacer(minLength: MemoBookSpacing.xs)
                valueText
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var label: some View {
        Text(title)
            .font(MemoBookFont.body)
            .foregroundStyle(MemoBookColor.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var valueText: some View {
        if let value {
            Text(value)
                .font(MemoBookFont.body)
                .foregroundStyle(MemoBookColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                // Le chiffre roule vers sa nouvelle valeur au lieu de sauter :
                // c'est ce qui fait voir qu'un relevé vient d'arriver.
                .contentTransition(.numericText())
        } else {
            BrandSkeleton(width: 120)
        }
    }
}

/// Un anneau de progression : l'arc vert sur un rail effacé, le chiffre au
/// centre et son mot dessous. Il se lit, il ne se règle pas — comme
/// ``BrandGauge``, dont il reprend les deux couleurs.
///
/// **L'arc se dessine à l'arrivée du chiffre**, de zéro à sa valeur, puis suit
/// chaque changement : c'est l'animation la plus visible de la feuille, et
/// elle ne coûte qu'un `trim`.
private struct StatisticRing: View {
    let fraction: Double
    /// « 9 % », « 2 ». `nil` tant que ça n'est pas arrivé.
    let value: String?
    let caption: String
    let accessibilityLabel: String

    /// Ce que l'arc montre, distinct de ce qu'il devrait montrer : c'est
    /// l'écart entre les deux qui s'anime.
    @State private var drawn: Double = 0

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 76
    @ScaledMetric(relativeTo: .body) private var stroke: CGFloat = 7

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(MemoBookColor.separator.opacity(0.35), lineWidth: stroke)

            Circle()
                .trim(from: 0, to: drawn)
                .stroke(MemoBookColor.action, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                // Le zéro en haut, et l'arc qui tourne dans le sens d'une
                // montre : c'est ce qu'on attend d'un anneau qui compte.
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                if let value {
                    Text(value)
                        .font(MemoBookFont.figure)
                        .foregroundStyle(MemoBookColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                } else {
                    BrandSkeleton(width: 28)
                }
                Text(caption)
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(stroke + 4)
        }
        .frame(width: side, height: side)
        .onAppear { draw(fraction, animated: true) }
        .onChange(of: fraction) { _, next in draw(next, animated: true) }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(value ?? "en attente")
    }

    private func draw(_ target: Double, animated: Bool) {
        let bounded = min(1, max(0, target))
        guard animated, !reduceMotion else {
            drawn = bounded
            return
        }
        // Plus lent que le reste de la carte, et c'est voulu : un arc qui se
        // dessine est le geste qu'on regarde en ouvrant la feuille.
        withAnimation(.smooth(duration: 0.8)) { drawn = bounded }
    }
}

// MARK: - Aperçus

#Preview("Statistiques") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            StatisticsSheet(model: StatisticsModel())
        }
}

#Preview("Statistiques — l'agent relit") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            StatisticsSheet(model: StatisticsModel(source: { .detectingFixture }))
        }
}

#Preview("Statistiques — sans voyage en cours") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            StatisticsSheet(model: StatisticsModel(source: { .restingFixture }))
        }
}

#Preview("Statistiques — en chargement") {
    Color.clear
        .background(MemoBookColor.background)
        .sheet(isPresented: .constant(true)) {
            StatisticsSheet(
                model: StatisticsModel(source: {
                    try await Task.sleep(for: .seconds(60))
                    return .fixture
                })
            )
        }
}
