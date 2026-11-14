import LorreCore
import XCTest
@testable import Lorre

@MainActor
final class OnboardingModelTests: XCTestCase {
    private var settings: SettingsStore!

    override func setUp() async throws {
        settings = SettingsStore(database: try LorreDatabase.inMemory())
    }

    func testIsNeededUntilDone() throws {
        XCTAssertTrue(OnboardingModel.isNeeded(settings: settings))
        try settings.set("1", for: .onboardingDone)
        XCTAssertFalse(OnboardingModel.isNeeded(settings: settings))
    }

    func testStartsOnWelcomeWithThreeSteps() {
        let model = OnboardingModel(settings: settings)
        XCTAssertEqual(model.step, .welcome)
        XCTAssertEqual(model.stepNumber, 1)
        XCTAssertEqual(OnboardingModel.stepCount, 3)
        XCTAssertTrue(model.isFirstStep)
        XCTAssertFalse(model.isLastStep)
        XCTAssertTrue(model.canContinue)
    }

    func testNamePrefilledFromSettings() throws {
        try settings.set("Anna", for: .userName)
        XCTAssertEqual(OnboardingModel(settings: settings).name, "Anna")
    }

    func testNextAndBackWalkTheSteps() {
        let model = OnboardingModel(settings: settings)
        model.back()
        XCTAssertEqual(model.step, .welcome, "cannot go before the first step")
        model.next()
        XCTAssertEqual(model.step, .name)
        model.next()
        XCTAssertEqual(model.step, .permissions)
        XCTAssertTrue(model.isLastStep)
        model.next()
        XCTAssertEqual(model.step, .permissions, "cannot go past the last step")
        model.back()
        XCTAssertEqual(model.step, .name)
    }

    func testNameStepNeedsAName() {
        let model = OnboardingModel(settings: settings)
        model.next()
        model.name = "   "
        XCTAssertFalse(model.canContinue)
        model.next()
        XCTAssertEqual(model.step, .name)
        model.name = " Thijs "
        XCTAssertTrue(model.canContinue)
        model.next()
        XCTAssertEqual(model.step, .permissions)
    }

    func testCompleteSavesTrimmedNameAndDoneFlag() throws {
        let model = OnboardingModel(settings: settings)
        model.next()
        model.name = "  Anna "
        model.next()
        model.complete()
        XCTAssertTrue(model.isCompleted)
        XCTAssertFalse(model.saveFailed)
        XCTAssertEqual(try settings.string(.userName), "Anna")
        XCTAssertEqual(try settings.string(.onboardingDone), "1")
        XCTAssertFalse(OnboardingModel.isNeeded(settings: settings))
    }

    func testCompleteWithEmptyNameKeepsTheExistingName() throws {
        try settings.set("Thijs", for: .userName)
        let model = OnboardingModel(settings: settings)
        model.name = ""
        model.complete()
        XCTAssertEqual(try settings.string(.userName), "Thijs")
        XCTAssertEqual(try settings.string(.onboardingDone), "1")
    }

    func testStepCounterTexts() {
        XCTAssertEqual(Strings.dutch.onboardingStepCounter(2, of: 3), "Stap 2 van 3")
        XCTAssertEqual(Strings.english.onboardingStepCounter(2, of: 3), "Step 2 of 3")
    }
}
