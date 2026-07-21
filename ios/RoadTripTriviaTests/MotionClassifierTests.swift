import XCTest
@testable import RoadTripTrivia

final class MotionClassifierTests: XCTestCase {
    private var classifier: MotionClassifier!
    private var now: Date!

    override func setUp() {
        super.setUp()
        classifier = MotionClassifier()
        now = Date()
    }

    func testStaysNilBelowStoppedDebounce() {
        classifier.recordSample(speed: 0, at: now)
        let result = classifier.recordSample(speed: 0, at: now.addingTimeInterval(89))
        XCTAssertNil(result)
    }

    func testFiresStoppedOnceDebounceElapses() {
        classifier.recordSample(speed: 0, at: now)
        let result = classifier.recordSample(speed: 0, at: now.addingTimeInterval(90))
        XCTAssertEqual(result, .stopped)
    }

    func testDoesNotRefireStoppedOnSubsequentSamples() {
        classifier.recordSample(speed: 0, at: now)
        XCTAssertEqual(classifier.recordSample(speed: 0, at: now.addingTimeInterval(90)), .stopped)
        XCTAssertNil(classifier.recordSample(speed: 0, at: now.addingTimeInterval(95)))
    }

    func testStaysNilBelowMovingDebounce() {
        classifier.recordSample(speed: 5, at: now)
        let result = classifier.recordSample(speed: 5, at: now.addingTimeInterval(19))
        XCTAssertNil(result)
    }

    func testFiresMovingOnceDebounceElapses() {
        classifier.recordSample(speed: 5, at: now)
        let result = classifier.recordSample(speed: 5, at: now.addingTimeInterval(20))
        XCTAssertEqual(result, .moving)
    }

    func testAmbiguousSpeedDoesNotAccumulateTowardEitherState() {
        classifier.recordSample(speed: 2, at: now) // between the stopped and moving thresholds
        let result = classifier.recordSample(speed: 2, at: now.addingTimeInterval(200))
        XCTAssertNil(result)
    }

    func testInterruptingAStoppedRunResetsTheDebounceClock() {
        classifier.recordSample(speed: 0, at: now)
        classifier.recordSample(speed: 5, at: now.addingTimeInterval(50)) // interrupts before 90s
        classifier.recordSample(speed: 0, at: now.addingTimeInterval(51)) // stopped again, clock restarts
        XCTAssertNil(classifier.recordSample(speed: 0, at: now.addingTimeInterval(51 + 89)))
        XCTAssertEqual(classifier.recordSample(speed: 0, at: now.addingTimeInterval(51 + 90)), .stopped)
    }

    func testTransitionsFromStoppedToMovingAfterConfirmed() {
        classifier.recordSample(speed: 0, at: now)
        XCTAssertEqual(classifier.recordSample(speed: 0, at: now.addingTimeInterval(90)), .stopped)

        classifier.recordSample(speed: 5, at: now.addingTimeInterval(91))
        let result = classifier.recordSample(speed: 5, at: now.addingTimeInterval(111))
        XCTAssertEqual(result, .moving)
    }

    func testReevaluateUsesLastKnownSpeedWithoutANewSample() {
        classifier.recordSample(speed: 0, at: now)
        let result = classifier.reevaluate(at: now.addingTimeInterval(90))
        XCTAssertEqual(result, .stopped)
    }

    func testResetRestartsTheDebounceClock() {
        classifier.recordSample(speed: 0, at: now)
        classifier.recordSample(speed: 0, at: now.addingTimeInterval(50))
        classifier.reset()
        classifier.recordSample(speed: 0, at: now.addingTimeInterval(51))
        XCTAssertNil(classifier.recordSample(speed: 0, at: now.addingTimeInterval(51 + 89)))
        XCTAssertEqual(classifier.recordSample(speed: 0, at: now.addingTimeInterval(51 + 90)), .stopped)
    }
}
