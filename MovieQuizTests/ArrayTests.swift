import XCTest
@testable import MovieQuiz

final class ArrayTests: XCTestCase {
    func testGetValueInRange() {
        let values = [1, 1, 2, 3, 5]

        let value = values[safe: 2]

        XCTAssertNotNil(value)
        XCTAssertEqual(value, 2)
    }

    func testGetValueOutOfRange() {
        let values = [1, 1, 2, 3, 5]

        let value = values[safe: 20]

        XCTAssertNil(value)
    }

    func testFirstAndLastIndicesAreIncluded() {
        let values = [1, 1, 2, 3, 5]

        let firstValue = values[safe: 0]
        let lastValue = values[safe: values.count - 1]

        XCTAssertEqual(firstValue, 1)
        XCTAssertEqual(lastValue, 5)
    }

    func testIndexEqualToCountIsOutOfRange() {
        let values = [1, 1, 2, 3, 5]

        let value = values[safe: values.count]

        XCTAssertNil(value)
    }

    func testNegativeIndexIsOutOfRange() {
        let values = [1, 1, 2, 3, 5]

        let value = values[safe: -1]

        XCTAssertNil(value)
    }

    func testEmptyArrayHasNoValueAtZero() {
        let values: [Int] = []

        let value = values[safe: 0]

        XCTAssertNil(value)
    }

    func testExtremeIndicesAreOutOfRange() {
        let values = [1, 1, 2, 3, 5]

        let minimum = values[safe: Int.min]
        let maximum = values[safe: Int.max]

        XCTAssertNil(minimum)
        XCTAssertNil(maximum)
    }
}
