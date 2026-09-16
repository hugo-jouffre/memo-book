import Foundation
import Testing
@testable import MemoBookDesign

/// Les règles du geste, telles qu'elles sont énoncées en tête de
/// `BrandRangeCalendar` : le départ, puis le retour, et ce que fait un jour
/// touché à contre-sens.
struct DateRangeSelectionTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ n: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: n, hour: 15))!
    }

    @Test func premierGestePoseLeDepart() {
        var selection = DateRangeSelection(calendar: calendar)
        selection.tap(day(18), calendar: calendar)

        #expect(selection.start == calendar.startOfDay(for: day(18)))
        #expect(selection.end == nil)
    }

    @Test func secondGesteApresLeDepartPoseLeRetour() {
        var selection = DateRangeSelection(start: day(18), calendar: calendar)
        selection.tap(day(26), calendar: calendar)

        #expect(selection.start == calendar.startOfDay(for: day(18)))
        #expect(selection.end == calendar.startOfDay(for: day(26)))
    }

    @Test func secondGesteAvantLeDepartLeRemplace() {
        var selection = DateRangeSelection(start: day(18), calendar: calendar)
        selection.tap(day(10), calendar: calendar)

        #expect(selection.start == calendar.startOfDay(for: day(10)))
        #expect(selection.end == nil)
    }

    @Test func toucherLeDepartSeulNeFaitRien() {
        var selection = DateRangeSelection(start: day(18), calendar: calendar)
        selection.tap(day(18), calendar: calendar)

        #expect(selection.start == calendar.startOfDay(for: day(18)))
        #expect(selection.end == nil)
    }

    @Test func plageCompleteRecommenceAuJourTouche() {
        var selection = DateRangeSelection(start: day(18), end: day(26), calendar: calendar)
        selection.tap(day(22), calendar: calendar)

        #expect(selection.start == calendar.startOfDay(for: day(22)))
        #expect(selection.end == nil)
    }

    @Test func lesDatesSontRameneesAMinuit() {
        let selection = DateRangeSelection(start: day(18), end: day(26), calendar: calendar)

        #expect(selection.start == calendar.startOfDay(for: day(18)))
        #expect(selection.end == calendar.startOfDay(for: day(26)))
    }

    @Test func chaqueJourConnaitSonRole() {
        let selection = DateRangeSelection(start: day(18), end: day(26), calendar: calendar)

        #expect(selection.role(of: day(17), calendar: calendar) == .none)
        #expect(selection.role(of: day(18), calendar: calendar) == .start(isClosed: true))
        #expect(selection.role(of: day(22), calendar: calendar) == .inside)
        #expect(selection.role(of: day(26), calendar: calendar) == .end)
        #expect(selection.role(of: day(27), calendar: calendar) == .none)
    }

    @Test func unDepartSeulEstUneBorneOuverte() {
        let selection = DateRangeSelection(start: day(18), calendar: calendar)

        #expect(selection.role(of: day(18), calendar: calendar) == .start(isClosed: false))
        #expect(selection.role(of: day(19), calendar: calendar) == .none)
    }

    @Test func laGrilleDuMoisCommenceDansSaColonne() {
        // Septembre 2026 commence un mardi : avec le lundi en tête de semaine,
        // une case vide devant le 1er.
        var monday = calendar
        monday.firstWeekday = 2
        let grid = monday.monthGrid(for: day(1))

        #expect(grid.count == 31)
        #expect(grid[0] == nil)
        #expect(grid[1] == monday.startOfDay(for: day(1)))
    }
}
