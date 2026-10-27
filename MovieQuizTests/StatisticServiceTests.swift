import XCTest
import Foundation
@testable import MovieQuiz

final class StatisticServiceTests: XCTestCase {
    func testEmptyStorageHasZeroStatistics() throws {
        try withStorage { storage in
            let service = StatisticService(storage: storage)
            XCTAssertEqual(service.gamesCount, 0)
            XCTAssertEqual(service.totalAccuracy, 0)
            XCTAssertEqual(service.bestGame.correct, 0)
            XCTAssertEqual(service.bestGame.total, 0)
        }
    }

    func testFirstZeroScoreIsRecordedAsACompletedGame() throws {
        try withStorage { storage in
            let service = StatisticService(storage: storage)
            let before = Date()
            service.store(correct: 0, total: 10)
            XCTAssertEqual(service.gamesCount, 1)
            XCTAssertEqual(service.bestGame.correct, 0)
            XCTAssertEqual(service.bestGame.total, 10)
            XCTAssertGreaterThanOrEqual(service.bestGame.date, before)
            XCTAssertLessThanOrEqual(service.bestGame.date, Date())
            XCTAssertEqual(service.totalAccuracy, 0)
        }
    }

    func testOnlyBetterScoreReplacesRecordAndEveryGameCounts() throws {
        try withStorage { storage in
            let service = StatisticService(storage: storage)
            service.store(correct: 6, total: 10)
            service.store(correct: 10, total: 10)
            let recordDate = service.bestGame.date
            service.store(correct: 10, total: 10)
            service.store(correct: 2, total: 10)
            XCTAssertEqual(service.gamesCount, 4)
            XCTAssertEqual(service.bestGame.correct, 10)
            XCTAssertEqual(service.bestGame.total, 10)
            XCTAssertEqual(service.bestGame.date, recordDate)
            XCTAssertEqual(service.totalAccuracy, 70, accuracy: 0.0001)
        }
    }

    func testWeightedAccuracyAndPersistenceAcrossServiceInstances() throws {
        try withStorage { storage in
            let service = StatisticService(storage: storage)
            service.store(correct: 3, total: 4)
            service.store(correct: 1, total: 2)
            let restored = StatisticService(storage: storage)
            XCTAssertEqual(restored.gamesCount, 2)
            XCTAssertEqual(restored.totalAccuracy, 100 * 4.0 / 6.0, accuracy: 0.0001)
            XCTAssertEqual(restored.bestGame.correct, 3)
            XCTAssertEqual(restored.bestGame.total, 4)
            XCTAssertEqual(restored.bestGame.date, service.bestGame.date)
        }
    }

    func testInvalidResultsDoNotChangeStatistics() throws {
        try withStorage { storage in
            let service = StatisticService(storage: storage)
            service.store(correct: 5, total: 10)
            let recordDate = service.bestGame.date
            for input in [(-1, 10), (11, 10), (0, 0), (0, -1)] {
                service.store(correct: input.0, total: input.1)
            }
            XCTAssertEqual(service.gamesCount, 1)
            XCTAssertEqual(service.totalAccuracy, 50)
            XCTAssertEqual(service.bestGame.correct, 5)
            XCTAssertEqual(service.bestGame.total, 10)
            XCTAssertEqual(service.bestGame.date, recordDate)
        }
    }

    func testDateFormattingUsesCalendarYearAndTwentyFourHourTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2020, month: 12, day: 31, hour: 23, minute: 45)))
        XCTAssertEqual(date.dateTimeString, "31.12.20 23:45")
    }

    private func withStorage(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "MovieQuiz.StatisticServiceTests.\(UUID().uuidString)"
        let storage = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        storage.removePersistentDomain(forName: suiteName)
        defer { storage.removePersistentDomain(forName: suiteName) }
        try body(storage)
    }
}
