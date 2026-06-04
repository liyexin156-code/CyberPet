import XCTest
@testable import PetTaskBuddy

final class SleepDurationSourceTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testSleepDurationsAreCentralizedForManualAndRandomSources() throws {
        let behaviorSource = try source("Sources/PetTaskBuddy/PetAutonomousBehavior.swift")

        XCTAssertTrue(behaviorSource.contains("static let manualSleepHoldDuration: TimeInterval = 180"))
        XCTAssertTrue(behaviorSource.contains("static let randomSleepHoldRange: ClosedRange<TimeInterval> = 120...300"))
        XCTAssertTrue(behaviorSource.contains("static let manualSideLieHoldDuration: TimeInterval = manualSleepHoldDuration"))
        XCTAssertTrue(behaviorSource.contains("case .sleep, .lieDown:"))
        XCTAssertTrue(behaviorSource.contains("randomSleepHoldRange"))
    }

    func testManualSleepAndSideLieUseSharedSleepHoldWithDebugLogging() throws {
        let controllerSource = try source("Sources/PetTaskBuddy/PetWindowController.swift")

        let manualStationaryBody = try XCTUnwrap(extractFunction("performManualStationary", from: controllerSource))
        XCTAssertTrue(manualStationaryBody.contains("state == .sleep"))
        XCTAssertTrue(manualStationaryBody.contains("beginSleepHold"))
        XCTAssertTrue(manualStationaryBody.contains("trigger: .manual"))
        XCTAssertTrue(manualStationaryBody.contains("PetAutonomousBehaviorConfig.manualSleepHoldDuration"))

        let sideLieBody = try XCTUnwrap(extractFunction("performManualSideLie", from: controllerSource))
        XCTAssertTrue(sideLieBody.contains("beginSleepHold"))
        XCTAssertTrue(sideLieBody.contains("state: .lieDown"))
        XCTAssertTrue(sideLieBody.contains("trigger: .manual"))
        XCTAssertTrue(sideLieBody.contains("PetAutonomousBehaviorConfig.manualSideLieHoldDuration"))

        let sleepHoldBody = try XCTUnwrap(extractFunction("beginSleepHold", from: controllerSource))
        XCTAssertTrue(sleepHoldBody.contains("SLEEP LOCK START"))
        XCTAssertTrue(sleepHoldBody.contains("state"))
        XCTAssertTrue(sleepHoldBody.contains("duration"))
        XCTAssertTrue(sleepHoldBody.contains("trigger source"))
        XCTAssertTrue(sleepHoldBody.contains("lockUntil timestamp"))
        XCTAssertTrue(sleepHoldBody.contains("sleepLockTimer"))
        XCTAssertTrue(sleepHoldBody.contains("endActiveSleepIfNeeded()"))
        XCTAssertTrue(sleepHoldBody.contains("scene.play(state)"))
        XCTAssertTrue(controllerSource.contains("SLEEP LOCK END"))
    }

    func testRandomSleepAndSideLieLoopUntilHoldDurationEnds() throws {
        let controllerSource = try source("Sources/PetTaskBuddy/PetWindowController.swift")

        let dailyStationaryBody = try XCTUnwrap(extractFunction("performDailyStationaryBehavior", from: controllerSource))
        XCTAssertTrue(dailyStationaryBody.contains("case .sleep, .lieDown:"))
        XCTAssertTrue(dailyStationaryBody.contains("beginSleepHold"))
        XCTAssertTrue(dailyStationaryBody.contains("trigger: .random"))
        XCTAssertTrue(dailyStationaryBody.contains("TimeInterval.random(in: PetAutonomousBehaviorConfig.randomSleepHoldRange)"))

        let sleepHoldBody = try XCTUnwrap(extractFunction("beginSleepHold", from: controllerSource))
        XCTAssertTrue(sleepHoldBody.contains("behaviorTimer?.invalidate()"))
        XCTAssertTrue(sleepHoldBody.contains("sleepLockTimer?.invalidate()"))
        XCTAssertTrue(sleepHoldBody.contains("completion()"))
    }

    func testSleepLockBlocksOrdinaryInterruptionsButAllowsManualMenuActions() throws {
        let controllerSource = try source("Sources/PetTaskBuddy/PetWindowController.swift")

        let scheduleBody = try XCTUnwrap(extractFunction("scheduleNextBehavior", from: controllerSource))
        XCTAssertTrue(scheduleBody.contains("blockIfSleepLocked"))

        let moodCallbackBody = try XCTUnwrap(extractFunction("configurePetStateCallbacks", from: controllerSource))
        XCTAssertTrue(moodCallbackBody.contains("blockIfSleepLocked"))
        XCTAssertTrue(moodCallbackBody.contains("mood state"))

        let interruptBody = try XCTUnwrap(extractFunction("interruptAutonomousBehavior", from: controllerSource))
        XCTAssertTrue(interruptBody.contains("allowSleepLockInterruption"))
        XCTAssertTrue(interruptBody.contains("blocked: !allowSleepLockInterruption"))
        XCTAssertTrue(controllerSource.contains("blocked=\\(blocked)"))

        let manualStartBody = try XCTUnwrap(extractFunction("startManualPerformance", from: controllerSource))
        XCTAssertTrue(manualStartBody.contains("allowSleepLockInterruption: true"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func extractFunction(_ name: String, from source: String) -> String? {
        guard let range = source.range(of: "private func \(name)") else { return nil }
        var depth = 0
        var started = false
        var index = range.lowerBound
        while index < source.endIndex {
            let char = source[index]
            if char == "{" {
                depth += 1
                started = true
            } else if char == "}" {
                depth -= 1
                if started && depth == 0 {
                    let end = source.index(after: index)
                    return String(source[range.lowerBound..<end])
                }
            }
            index = source.index(after: index)
        }
        return nil
    }
}
