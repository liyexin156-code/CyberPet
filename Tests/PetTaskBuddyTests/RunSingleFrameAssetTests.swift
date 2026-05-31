import XCTest
@testable import PetTaskBuddy

final class RunSingleFrameAssetTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testRunManifestUsesSingleFramePose() throws {
        let manifestURL = projectRoot
            .appendingPathComponent("Assets/pet/manifest.json")
        let manifest = try JSONDecoder().decode(
            AnimationManifest.self,
            from: Data(contentsOf: manifestURL)
        )

        XCTAssertEqual(manifest.states[PetAnimationState.run.rawValue]?.frames, 1)
        XCTAssertEqual(manifest.states[PetAnimationState.run.rawValue]?.type, .loop)
    }

    func testContextMenuDoesNotExposeManualRunIn() throws {
        let sourceURL = projectRoot
            .appendingPathComponent("Sources/PetTaskBuddy/PetScene.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("title: \"跑进来\""))
        XCTAssertFalse(source.contains("func performRun()"))
    }
}
