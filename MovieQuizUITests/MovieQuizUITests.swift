import XCTest

final class MovieQuizUITests: XCTestCase {
    private let app = XCUIApplication()
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        try super.tearDownWithError()
    }

    func testYesButton() {
        assertPosterChanges(afterTapping: "Yes")
    }

    func testNoButton() {
        assertPosterChanges(afterTapping: "No")
    }

    func testIndexLabel() {
        waitForQuestion(1)
        XCTAssertEqual(app.staticTexts["Index"].label, "1/10")

        app.buttons["Yes"].tap()
        waitForQuestion(2)

        XCTAssertEqual(app.staticTexts["Index"].label, "2/10")
    }

    func testEndRoundAlert() {
        let alert = finishRound()

        XCTAssertTrue(alert.staticTexts["Этот раунд окончен!"].exists)
        XCTAssertTrue(alert.buttons["Сыграть еще раз"].exists)
    }

    func testRestart() {
        let alert = finishRound()
        alert.buttons["Сыграть еще раз"].tap()

        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: alert
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: timeout), .completed)
        waitForQuestion(1)

        XCTAssertFalse(alert.exists)
        XCTAssertEqual(app.staticTexts["Index"].label, "1/10")
    }

    private func assertPosterChanges(
        afterTapping button: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        waitForQuestion(1, file: file, line: line)
        let firstPoster = app.images["Poster"]
        XCTAssertTrue(firstPoster.waitForExistence(timeout: timeout), file: file, line: line)
        let firstImage: Data = firstPoster.screenshot().pngRepresentation

        app.buttons[button].tap()
        waitForQuestion(2, file: file, line: line)

        let secondPoster = app.images["Poster"]
        XCTAssertTrue(secondPoster.waitForExistence(timeout: timeout), file: file, line: line)
        let secondImage: Data = secondPoster.screenshot().pngRepresentation
        XCTAssertNotEqual(firstImage, secondImage, file: file, line: line)
    }

    private func waitForQuestion(
        _ number: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let index = app.staticTexts["Index"]
        XCTAssertTrue(index.waitForExistence(timeout: timeout), file: file, line: line)
        let ready = NSPredicate { [app] _, _ in
            let yes = app.buttons["Yes"]
            let no = app.buttons["No"]
            return index.label == "\(number)/10"
                && yes.exists && yes.isEnabled && yes.isHittable
                && no.exists && no.isEnabled && no.isHittable
                && app.images["Poster"].exists
        }
        let expectation = XCTNSPredicateExpectation(predicate: ready, object: app)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "Expected question \(number)/10 with a poster and enabled answer buttons.",
            file: file,
            line: line
        )
    }

    private func finishRound() -> XCUIElement {
        for number in 1...10 {
            waitForQuestion(number)
            app.buttons["Yes"].tap()
        }

        let alert = app.alerts["Этот раунд окончен!"]
        XCTAssertTrue(alert.waitForExistence(timeout: timeout))
        XCTAssertTrue(alert.buttons["Сыграть еще раз"].waitForExistence(timeout: timeout))
        return alert
    }
}
