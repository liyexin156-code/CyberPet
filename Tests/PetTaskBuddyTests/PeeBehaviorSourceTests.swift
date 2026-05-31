import XCTest
@testable import PetTaskBuddy

final class PeeBehaviorSourceTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testPeeResourceAndManifestArePresent() throws {
        let peeURL = projectRoot.appendingPathComponent("Assets/pet/pee.png")
        let manifestSource = try source("Assets/pet/manifest.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: peeURL.path))
        XCTAssertTrue(manifestSource.contains("\"pee\""))
    }

    func testContextMenuRequestsManualPee() throws {
        let sceneSource = try source("Sources/PetTaskBuddy/PetScene.swift")

        XCTAssertTrue(sceneSource.contains("LocalizationManager.shared.string(.menuPee)"))
        XCTAssertTrue(sceneSource.contains("#selector(ContextMenuTarget.performPee)"))
        XCTAssertTrue(sceneSource.contains("func performPee()"))
        XCTAssertTrue(sceneSource.contains("request(.pee)"))
    }

    func testPeeStateLastsThreeSecondsAndRestoresIdle() throws {
        let behaviorSource = try source("Sources/PetTaskBuddy/PetAutonomousBehavior.swift")
        let controllerSource = try source("Sources/PetTaskBuddy/PetWindowController.swift")

        XCTAssertTrue(behaviorSource.contains("case pee"))
        XCTAssertTrue(behaviorSource.contains("static let sniffPeeChance: Double = 0.25"))
        XCTAssertTrue(behaviorSource.contains("static let peeHoldDuration: TimeInterval = 3.0"))
        XCTAssertTrue(controllerSource.contains("case .pee:"))
        XCTAssertTrue(controllerSource.contains("performManualPee()"))

        let dailySniffBody = try XCTUnwrap(extractFunction("finishDailySniff", from: controllerSource))
        XCTAssertTrue(dailySniffBody.contains("Double.random(in: 0..<1) < PetAutonomousBehaviorConfig.sniffPeeChance"))
        XCTAssertTrue(dailySniffBody.contains("performAutonomousPee()"))

        let autonomousPeeBody = try XCTUnwrap(extractFunction("performAutonomousPee", from: controllerSource))
        XCTAssertTrue(autonomousPeeBody.contains("movementTimer?.invalidate()"))
        XCTAssertTrue(autonomousPeeBody.contains("playPeeAnimation(isManual: false)"))

        let playPeeBody = try XCTUnwrap(extractFunction("playPeeAnimation", from: controllerSource))
        XCTAssertTrue(playPeeBody.contains("scene.playOneCycle("))
        XCTAssertTrue(playPeeBody.contains(".pee,"))
        XCTAssertTrue(playPeeBody.contains("PetAutonomousBehaviorConfig.peeHoldDuration"))

        let finishPeeBody = try XCTUnwrap(extractFunction("finishPee", from: controllerSource))
        XCTAssertTrue(finishPeeBody.contains("scene.forcePlay(.idle)"))
        XCTAssertTrue(finishPeeBody.contains("scheduleNextBehavior()"))
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
