import XCTest
@testable import PetTaskBuddy

final class TaskRewardDropDisabledTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testTaskCompletionDoesNotEmitVisualRewardDropCallback() throws {
        let engineSource = try source("Sources/PetTaskBuddy/PetStateEngine.swift")
        let controllerSource = try source("Sources/PetTaskBuddy/PetWindowController.swift")
        let mainPanelSource = try source("Sources/PetTaskBuddy/MainPanelWindowController.swift")
        let thoughtBubbleSource = try source("Sources/PetTaskBuddy/ThoughtBubbleWindowController.swift")

        XCTAssertTrue(mainPanelSource.contains("petStateEngine.completeTaskReward()"))
        XCTAssertTrue(thoughtBubbleSource.contains("petStateEngine.completeTaskReward()"))
        XCTAssertFalse(engineSource.contains("onReward"))

        let callbacksBody = try XCTUnwrap(extractFunction("configurePetStateCallbacks", from: controllerSource))
        XCTAssertFalse(callbacksBody.contains("performReward(kind:"))
        XCTAssertFalse(callbacksBody.contains("petStateEngine.onReward"))
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
