import XCTest

final class PoopManualActionTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testPoopResourceAndManifestArePresent() throws {
        let poopURL = projectRoot.appendingPathComponent("Assets/pet/poop.png")
        let manifest = try source("Assets/pet/manifest.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: poopURL.path))
        XCTAssertTrue(manifest.contains("\"poop\""))
        XCTAssertTrue(manifest.contains("\"type\": \"once\""))
        XCTAssertTrue(manifest.contains("\"returnTo\": \"idle\""))
    }

    func testContextMenuRequestsManualPoop() throws {
        let sceneSource = try source("Sources/PetTaskBuddy/PetScene.swift")
        let localizationSource = try source("Sources/PetTaskBuddy/LocalizationManager.swift")

        XCTAssertTrue(sceneSource.contains("LocalizationManager.shared.string(.menuPoop)"))
        XCTAssertTrue(sceneSource.contains("#selector(ContextMenuTarget.performPoop)"))
        XCTAssertTrue(sceneSource.contains("func performPoop()"))
        XCTAssertTrue(sceneSource.contains("request(.poop)"))
        XCTAssertTrue(localizationSource.contains(".menuPoop: \"拉屎\""))
        XCTAssertTrue(localizationSource.contains(".menuPoop: \"Poop\""))
    }

    func testManualPoopPlaysOnceWithoutMovementAndRestoresIdle() throws {
        let animationSource = try source("Sources/PetTaskBuddy/AnimationManifest.swift")
        let behaviorSource = try source("Sources/PetTaskBuddy/PetAutonomousBehavior.swift")
        let controllerSource = try source("Sources/PetTaskBuddy/PetWindowController.swift")
        let playerSource = try source("Sources/PetTaskBuddy/ManifestAnimationPlayer.swift")

        XCTAssertTrue(animationSource.contains("case poop"))
        XCTAssertTrue(animationSource.contains("case once"))
        XCTAssertTrue(behaviorSource.contains("case poop"))
        XCTAssertTrue(controllerSource.contains("case .poop:"))
        XCTAssertTrue(controllerSource.contains("performManualPoop()"))
        XCTAssertTrue(controllerSource.contains("performPoop(isManual: true)"))
        XCTAssertTrue(playerSource.contains("stateName == PetAnimationState.poop.rawValue"))

        let poopBody = try XCTUnwrap(extractFunction("performManualPoop", from: controllerSource))
        XCTAssertTrue(poopBody.contains("performPoop(isManual: true)"))

        let sharedPoopBody = try XCTUnwrap(extractFunction("performPoop", from: controllerSource))
        XCTAssertTrue(sharedPoopBody.contains("movementTimer?.invalidate()"))
        XCTAssertTrue(sharedPoopBody.contains("scene.playOneCycle(.poop)"))
        XCTAssertTrue(sharedPoopBody.contains("scene.forcePlay(.idle)"))
        XCTAssertFalse(sharedPoopBody.contains("animateWindow("))
    }

    func testEatingTwiceTriggersSharedPoopActionAndResetsCounter() throws {
        let controllerSource = try source("Sources/PetTaskBuddy/PetWindowController.swift")

        XCTAssertTrue(controllerSource.contains("private var completedEatCount = 0"))
        XCTAssertTrue(controllerSource.contains("private let poopTriggerEatCount = 2"))
        XCTAssertTrue(controllerSource.contains("recordCompletedEatingAndShouldPoop()"))

        let rewardBody = try XCTUnwrap(extractFunction("performReward", from: controllerSource))
        XCTAssertTrue(rewardBody.contains("if kind == .eat, self.recordCompletedEatingAndShouldPoop()"))
        XCTAssertTrue(rewardBody.contains("self.performPoop(isManual: false)"))

        let counterBody = try XCTUnwrap(extractFunction("recordCompletedEatingAndShouldPoop", from: controllerSource))
        XCTAssertTrue(counterBody.contains("completedEatCount += 1"))
        XCTAssertTrue(counterBody.contains("completedEatCount >= poopTriggerEatCount"))
        XCTAssertTrue(counterBody.contains("completedEatCount = 0"))

        let sharedPoopBody = try XCTUnwrap(extractFunction("performPoop", from: controllerSource))
        XCTAssertTrue(sharedPoopBody.contains("movementTimer?.invalidate()"))
        XCTAssertTrue(sharedPoopBody.contains("scene.playOneCycle(.poop)"))
        XCTAssertTrue(sharedPoopBody.contains("scene.forcePlay(.idle)"))
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
