import XCTest
@testable import PetTaskBuddy

final class SideLieManualActionTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testContextMenuRequestsSideLieManualPerformance() throws {
        let sceneSource = try source("Sources/PetTaskBuddy/PetScene.swift")

        XCTAssertTrue(sceneSource.contains("LocalizationManager.shared.string(.menuSideLie)"))
        XCTAssertTrue(sceneSource.contains("#selector(ContextMenuTarget.performSideLie)"))
        XCTAssertTrue(sceneSource.contains("func performSideLie()"))
        XCTAssertTrue(sceneSource.contains("request(.sideLie)"))
    }

    func testSideLieUsesLieDownForThreeMinutesThenRestoresIdle() throws {
        let behaviorSource = try source("Sources/PetTaskBuddy/PetAutonomousBehavior.swift")
        let controllerSource = try source("Sources/PetTaskBuddy/PetWindowController.swift")

        XCTAssertTrue(behaviorSource.contains("static let manualSideLieHoldDuration: TimeInterval = 180"))
        XCTAssertTrue(behaviorSource.contains("case sideLie"))
        XCTAssertTrue(controllerSource.contains("case .sideLie:"))
        XCTAssertTrue(controllerSource.contains("performManualSideLie()"))

        let sideLieBody = try XCTUnwrap(extractFunction("performManualSideLie", from: controllerSource))
        XCTAssertTrue(sideLieBody.contains("scene.forcePlay(.lieDown)"))
        XCTAssertTrue(sideLieBody.contains("PetAutonomousBehaviorConfig.manualSideLieHoldDuration"))

        let finishBody = try XCTUnwrap(extractFunction("finishManualPerformance", from: controllerSource))
        XCTAssertTrue(finishBody.contains("finishingManualPerformance == .sideLie"))
        XCTAssertTrue(finishBody.contains("scene.forcePlay(.idle)"))
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
