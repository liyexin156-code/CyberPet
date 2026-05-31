import XCTest
@testable import PetTaskBuddy

final class WalkSessionSourceTests: XCTestCase {
    private var controllerSource: String {
        get throws {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let sourceURL = root.appendingPathComponent("Sources/PetTaskBuddy/PetWindowController.swift")
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
    }

    func testManualRoamStepDoesNotPlayRestingAnimationBetweenSegments() throws {
        let source = try controllerSource
        let functionBody = try XCTUnwrap(extractFunction("scheduleManualRoamStep", from: source))

        XCTAssertFalse(functionBody.contains("scene.play(restingStateForCurrentMood())"))
        XCTAssertFalse(functionBody.contains("scene.play(.idle)"))
    }

    func testManualWalkSessionStartsWithWalkAndFinishesWithIdle() throws {
        let source = try controllerSource

        XCTAssertTrue(source.contains("beginManualWalkingSession(until:"))
        XCTAssertTrue(source.contains("finishManualWalkingSession()"))
        XCTAssertTrue(source.contains("scene.forcePlay(.idle)"))
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
