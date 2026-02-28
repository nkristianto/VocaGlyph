import XCTest
@testable import VocaGlyph

// MARK: - HistoryDateHeaderTests
//
// Tests the date-section header label produced by HistorySettingsView.sectionTitle(for:).
// AC #1 (Story 10.2): "TODAY — Sunday, 1 March 2026", "YESTERDAY — ...", full date for older.

final class HistoryDateHeaderTests: XCTestCase {

    private let calendar = Calendar.current

    // MARK: - TODAY

    func test_sectionTitle_today_hasTodayPrefixAndFullDate() {
        let today = Date()
        let result = HistorySettingsView.sectionTitle(for: today)

        XCTAssertTrue(
            result.hasPrefix("TODAY — "),
            "Today's header should start with 'TODAY — ', got: \(result)"
        )

        // Verify the date portion matches "EEEE, d MMMM yyyy"
        let datePart = result.replacingOccurrences(of: "TODAY — ", with: "")
        assertMatchesFullDateFormat(datePart, for: today)
    }

    // MARK: - YESTERDAY

    func test_sectionTitle_yesterday_hasYesterdayPrefixAndFullDate() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let result = HistorySettingsView.sectionTitle(for: yesterday)

        XCTAssertTrue(
            result.hasPrefix("YESTERDAY — "),
            "Yesterday's header should start with 'YESTERDAY — ', got: \(result)"
        )

        let datePart = result.replacingOccurrences(of: "YESTERDAY — ", with: "")
        assertMatchesFullDateFormat(datePart, for: yesterday)
    }

    // MARK: - Older dates (no prefix)

    func test_sectionTitle_olderDate_showsOnlyFullDate() {
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: Date())!
        let result = HistorySettingsView.sectionTitle(for: twoDaysAgo)

        XCTAssertFalse(
            result.hasPrefix("TODAY"),
            "Older date should not start with 'TODAY', got: \(result)"
        )
        XCTAssertFalse(
            result.hasPrefix("YESTERDAY"),
            "Older date should not start with 'YESTERDAY', got: \(result)"
        )

        assertMatchesFullDateFormat(result, for: twoDaysAgo)
    }

    func test_sectionTitle_oneWeekAgo_showsOnlyFullDate() {
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        let result = HistorySettingsView.sectionTitle(for: oneWeekAgo)

        assertMatchesFullDateFormat(result, for: oneWeekAgo)
    }

    // MARK: - Format correctness — AC spec: "EEEE, d MMMM yyyy" → "Sunday, 1 March 2026"

    func test_sectionTitle_format_includesDayOfWeekAndDayAndMonthAndYear() {
        // Use a fixed date: Sunday 1 March 2026 00:00 local time
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 3
        comps.day = 1
        guard let fixedDate = calendar.date(from: comps) else {
            XCTFail("Could not create fixed date")
            return
        }

        // Build the expected formatter output for that date
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        let expectedDatePart = formatter.string(from: fixedDate) // locale-sensitive full date

        // The fixed date is in the past (not today/yesterday), so no prefix expected
        let result = HistorySettingsView.sectionTitle(for: fixedDate)
        XCTAssertEqual(
            result, expectedDatePart,
            "Expected full date '\(expectedDatePart)', got: \(result)"
        )
    }

    // MARK: - No TODAY/YESTERDAY prefix for dates far in the past

    func test_sectionTitle_thirtyDaysAgo_noRelativePrefix() {
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date())!
        let result = HistorySettingsView.sectionTitle(for: thirtyDaysAgo)

        XCTAssertFalse(result.contains("TODAY"), "30 days ago must not contain 'TODAY'")
        XCTAssertFalse(result.contains("YESTERDAY"), "30 days ago must not contain 'YESTERDAY'")
    }

    // MARK: - Helpers

    /// Asserts that `string` matches "EEEE, d MMMM yyyy" round-trip for `date`.
    private func assertMatchesFullDateFormat(_ string: String, for date: Date, file: StaticString = #file, line: UInt = #line) {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        let expected = formatter.string(from: date)
        XCTAssertEqual(string, expected, "Date part '\(string)' does not match expected '\(expected)'", file: file, line: line)
    }
}
