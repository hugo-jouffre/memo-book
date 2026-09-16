import Foundation
import Testing
@testable import MemoBookDesign

/// Les règles du geste, telles qu'elles sont énoncées en tête de
/// `BrandRangeCalendar` : une case en cours, le jour touché va dedans, et ce
/// que fait un jour touché à contre-sens.
struct DateRangeSelectionTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ n: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: n, hour: 15))!
    }

    private func midnight(_ n: Int) -> Date { calendar.startOfDay(for: day(n)) }

    // MARK: - Case « Départ »

    @Test func poserLeDepartPasseAuRetour() {
        var selection = DateRangeSelection(calendar: calendar)
        selection.tap(day(18), calendar: calendar)

        #expect(selection.start == midnight(18))
        #expect(selection.end == nil)
        #expect(selection.editing == .end)
    }

    @Test func corrigerLeDepartGardeUnRetourQuiLeSuit() {
        var selection = DateRangeSelection(start: day(18), end: day(26), editing: .start, calendar: calendar)
        selection.tap(day(20), calendar: calendar)

        #expect(selection.start == midnight(20))
        #expect(selection.end == midnight(26))
    }

    @Test func corrigerLeDepartApresLeRetourEffaceLeRetour() {
        var selection = DateRangeSelection(start: day(18), end: day(26), editing: .start, calendar: calendar)
        selection.tap(day(28), calendar: calendar)

        #expect(selection.start == midnight(28))
        #expect(selection.end == nil)
    }

    // MARK: - Case « Retour »

    @Test func unJourApresLeDepartDevientLeRetour() {
        var selection = DateRangeSelection(start: day(18), editing: .end, calendar: calendar)
        selection.tap(day(26), calendar: calendar)

        #expect(selection.start == midnight(18))
        #expect(selection.end == midnight(26))
        #expect(selection.editing == .end)
    }

    @Test func unJourAvantLeDepartDevientLeDepart() {
        var selection = DateRangeSelection(start: day(18), end: day(26), editing: .end, calendar: calendar)
        selection.tap(day(10), calendar: calendar)

        #expect(selection.start == midnight(10))
        #expect(selection.end == nil)
    }

    @Test func toucherLeDepartEnReglantLeRetourNeFaitRien() {
        var selection = DateRangeSelection(start: day(18), editing: .end, calendar: calendar)
        selection.tap(day(18), calendar: calendar)

        #expect(selection.start == midnight(18))
        #expect(selection.end == nil)
    }

    @Test func pasDeRetourSansDepart() {
        var selection = DateRangeSelection(editing: .end, calendar: calendar)
        selection.tap(day(18), calendar: calendar)

        #expect(selection.start == midnight(18))
        #expect(selection.end == nil)
    }

    // MARK: - Effacer

    @Test func effacerLeRetourGardeLeDepart() {
        var selection = DateRangeSelection(start: day(18), end: day(26), calendar: calendar)
        selection.clear(.end)

        #expect(selection.start == midnight(18))
        #expect(selection.end == nil)
        #expect(selection.editing == .end)
    }

    @Test func effacerLeDepartEmporteLeRetour() {
        var selection = DateRangeSelection(start: day(18), end: day(26), editing: .end, calendar: calendar)
        selection.clear(.start)

        #expect(selection.isEmpty)
        #expect(selection.end == nil)
        #expect(selection.editing == .start)
    }

    // MARK: - Lecture

    @Test func lesDatesSontRameneesAMinuit() {
        let selection = DateRangeSelection(start: day(18), end: day(26), calendar: calendar)

        #expect(selection.start == midnight(18))
        #expect(selection.end == midnight(26))
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
