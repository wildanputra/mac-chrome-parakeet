import XCTest
import GRDB
@testable import MacParakeetCore

/// Tests for the daily_dictation_stats rollup that survives history deletion
/// and powers the Stats-tab heatmap + streaks.
final class DailyDictationStatsTests: XCTestCase {
    var manager: DatabaseManager!
    var repo: DictationRepository!

    override func setUp() async throws {
        manager = try DatabaseManager()
        repo = DictationRepository(dbQueue: manager.dbQueue)
    }

    // MARK: - dayKey

    func testDayKeyFormatsAsLocalISODate() {
        // Build a date in a fixed local calendar so the test is timezone-independent.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = cal.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 23, minute: 30))!
        XCTAssertEqual(DictationRepository.dayKey(for: date, calendar: cal), "2026-05-11")
    }

    // MARK: - Save path → daily rollup

    func testSavingDictationIncrementsTodayRow() throws {
        try repo.save(Dictation(durationMs: 2000, rawTranscript: "hello world", wordCount: 2))
        let stats = try repo.dailyStats(daysBack: 1)
        XCTAssertEqual(stats.count, 1)
        XCTAssertEqual(stats[0].count, 1)
        XCTAssertEqual(stats[0].words, 2)
        XCTAssertEqual(stats[0].durationMs, 2000)
    }

    func testMultipleSavesSameDayAggregate() throws {
        try repo.save(Dictation(durationMs: 1000, rawTranscript: "one", wordCount: 1))
        try repo.save(Dictation(durationMs: 2000, rawTranscript: "two two", wordCount: 2))
        try repo.save(Dictation(durationMs: 3000, rawTranscript: "three three three", wordCount: 3))

        let stats = try repo.dailyStats(daysBack: 1)
        XCTAssertEqual(stats[0].count, 3)
        XCTAssertEqual(stats[0].words, 6)
        XCTAssertEqual(stats[0].durationMs, 6000)
    }

    func testDailyStatsSurviveDeleteAll() throws {
        try repo.save(Dictation(durationMs: 1000, rawTranscript: "one", wordCount: 1))
        try repo.save(Dictation(durationMs: 2000, rawTranscript: "two two", wordCount: 2))

        try repo.deleteAll()

        let stats = try repo.dailyStats(daysBack: 1)
        XCTAssertEqual(stats[0].count, 2, "daily rollup survives deleteAll (the whole point of this table)")
        XCTAssertEqual(stats[0].words, 3)
    }

    func testRecordingStatusDoesNotIncrementDaily() throws {
        try repo.save(Dictation(durationMs: 5000, rawTranscript: "wip", status: .recording, wordCount: 3))

        let stats = try repo.dailyStats(daysBack: 1)
        XCTAssertEqual(stats[0].count, 0)
    }

    func testStatusTransitionToCompletedIncrementsDailyExactlyOnce() throws {
        var d = Dictation(durationMs: 1000, rawTranscript: "hi", status: .recording, wordCount: 1)
        try repo.save(d)
        XCTAssertEqual(try repo.dailyStats(daysBack: 1)[0].count, 0)

        d.status = .completed
        try repo.save(d)

        let stats = try repo.dailyStats(daysBack: 1)
        XCTAssertEqual(stats[0].count, 1)
        XCTAssertEqual(stats[0].words, 1)
    }

    func testEditingCompletedDictationAppliesDelta() throws {
        var d = Dictation(durationMs: 2000, rawTranscript: "hello", wordCount: 5)
        try repo.save(d)

        d.wordCount = 8
        d.durationMs = 3000
        try repo.save(d)

        let stats = try repo.dailyStats(daysBack: 1)
        XCTAssertEqual(stats[0].count, 1, "delta path does not bump count")
        XCTAssertEqual(stats[0].words, 8, "delta lifted 5 → 8 (not 13)")
        XCTAssertEqual(stats[0].durationMs, 3000)
    }

    // MARK: - dailyStats window

    func testDailyStatsReturnsDenseZeroFilledWindow() throws {
        // No dictations at all.
        let stats = try repo.dailyStats(daysBack: 7)
        XCTAssertEqual(stats.count, 7)
        XCTAssertTrue(stats.allSatisfy { $0.count == 0 })
    }

    func testDailyStatsWindowEndsToday() throws {
        try repo.save(Dictation(durationMs: 1000, rawTranscript: "today", wordCount: 1))
        let stats = try repo.dailyStats(daysBack: 7)
        XCTAssertEqual(stats.last?.count, 1, "today is the last (most recent) entry")
        XCTAssertTrue(Calendar.current.isDateInToday(stats.last!.day))
    }

    func testDailyStatsRejectsNonPositiveWindow() throws {
        try repo.save(Dictation(durationMs: 1000, rawTranscript: "today", wordCount: 1))

        XCTAssertEqual(try repo.dailyStats(daysBack: 0), [])
        XCTAssertEqual(try repo.dailyStats(daysBack: -7), [])
    }

    // MARK: - Streak helpers (pure)

    func testCurrentStreakWithTodayActive() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!

        let active: Set<String> = [
            DictationRepository.dayKey(for: today, calendar: cal),
            DictationRepository.dayKey(for: yesterday, calendar: cal),
            DictationRepository.dayKey(for: twoDaysAgo, calendar: cal)
        ]
        XCTAssertEqual(DictationRepository.computeCurrentDailyStreak(activeDays: active, calendar: cal), 3)
    }

    func testCurrentStreakWithTodayMissingButYesterdayActive() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!

        let active: Set<String> = [
            DictationRepository.dayKey(for: yesterday, calendar: cal),
            DictationRepository.dayKey(for: twoDaysAgo, calendar: cal)
        ]
        // Today missing → grace window starts at yesterday; streak counts back from there.
        XCTAssertEqual(DictationRepository.computeCurrentDailyStreak(activeDays: active, calendar: cal), 2)
    }

    func testCurrentStreakBrokenAfterTwoDayGap() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: today)!

        // Only a 3-days-ago entry — neither today nor yesterday active.
        let active: Set<String> = [DictationRepository.dayKey(for: threeDaysAgo, calendar: cal)]
        XCTAssertEqual(DictationRepository.computeCurrentDailyStreak(activeDays: active, calendar: cal), 0)
    }

    func testCurrentStreakOnEmptyHistory() {
        XCTAssertEqual(DictationRepository.computeCurrentDailyStreak(activeDays: []), 0)
    }

    func testLongestStreakAcrossMultipleRuns() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let base = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!

        // Run A: 3 consecutive days (Jan 1, 2, 3).
        // Gap: Jan 4.
        // Run B: 5 consecutive days (Jan 5, 6, 7, 8, 9).
        // Gap: Jan 10, 11.
        // Run C: 1 day (Jan 12).
        let activeOffsets = [0, 1, 2, 4, 5, 6, 7, 8, 11]
        let active = Set(activeOffsets.map { offset in
            DictationRepository.dayKey(for: cal.date(byAdding: .day, value: offset, to: base)!, calendar: cal)
        })
        XCTAssertEqual(DictationRepository.computeLongestDailyStreak(activeDays: active, calendar: cal), 5)
    }

    func testLongestStreakOfOne() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let active: Set<String> = [DictationRepository.dayKey(for: today, calendar: cal)]
        XCTAssertEqual(DictationRepository.computeLongestDailyStreak(activeDays: active, calendar: cal), 1)
    }

    func testLongestStreakOnEmptyHistory() {
        XCTAssertEqual(DictationRepository.computeLongestDailyStreak(activeDays: []), 0)
    }

    // MARK: - Backfill

    func testBackfillAggregatesByLocalDay() throws {
        // Insert raw rows (bypassing the save path) at known dates so we can
        // assert the backfill helper groups them correctly. Then wipe the
        // rollup table and re-run backfill to validate the migration logic.
        let cal = Calendar.current
        let dayOne = cal.startOfDay(for: Date())
        let dayTwo = cal.date(byAdding: .day, value: -1, to: dayOne)!

        try manager.dbQueue.write { db in
            for (date, words, durationMs) in [(dayOne, 3, 1000), (dayOne, 2, 500), (dayTwo, 5, 2000)] {
                try db.execute(
                    sql: """
                        INSERT INTO dictations
                          (id, createdAt, durationMs, rawTranscript, processingMode, status, updatedAt, hidden, wordCount)
                        VALUES (?, ?, ?, '', 'raw', 'completed', ?, 0, ?)
                        """,
                    arguments: [UUID(), date, durationMs, date, words]
                )
            }
            // Wipe the rollup the save path would have written via a different
            // code path (these inserts bypass save), then re-run backfill.
            try db.execute(sql: "DELETE FROM daily_dictation_stats")
            try DictationRepository.backfillDailyStats(db: db)
        }

        let stats = try repo.dailyStats(daysBack: 2)
        XCTAssertEqual(stats[0].count, 1, "yesterday: one row, 5 words")
        XCTAssertEqual(stats[0].words, 5)
        XCTAssertEqual(stats[1].count, 2, "today: two rows aggregated")
        XCTAssertEqual(stats[1].words, 5)
        XCTAssertEqual(stats[1].durationMs, 1500)
    }

    // MARK: - Top apps

    func testTopAppsSortsByCount() throws {
        for _ in 0..<5 {
            var d = Dictation(durationMs: 1000, rawTranscript: "safari", wordCount: 1)
            d.pastedToApp = "com.apple.Safari"
            try repo.save(d)
        }
        for _ in 0..<2 {
            var d = Dictation(durationMs: 1000, rawTranscript: "notes", wordCount: 1)
            d.pastedToApp = "com.apple.Notes"
            try repo.save(d)
        }
        // Nil app — should not appear.
        try repo.save(Dictation(durationMs: 1000, rawTranscript: "no app", wordCount: 1))

        let top = try repo.topApps(limit: 5)
        XCTAssertEqual(top.count, 2)
        XCTAssertEqual(top[0].app, "com.apple.Safari")
        XCTAssertEqual(top[0].count, 5)
        XCTAssertEqual(top[1].app, "com.apple.Notes")
        XCTAssertEqual(top[1].count, 2)
    }

    func testTopAppsIgnoresEmptyAndWhitespaceAppNames() throws {
        var d = Dictation(durationMs: 1000, rawTranscript: "blank", wordCount: 1)
        d.pastedToApp = "   "
        try repo.save(d)
        XCTAssertEqual(try repo.topApps(limit: 5).count, 0)
    }

    func testTopAppsRejectsNonPositiveLimit() throws {
        var d = Dictation(durationMs: 1000, rawTranscript: "safari", wordCount: 1)
        d.pastedToApp = "com.apple.Safari"
        try repo.save(d)

        XCTAssertEqual(try repo.topApps(limit: 0).count, 0)
        XCTAssertEqual(try repo.topApps(limit: -5).count, 0)
    }
}
