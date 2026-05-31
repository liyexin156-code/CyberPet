import SpriteKit
import XCTest
@testable import PetTaskBuddy

final class ManifestAnimationPlayerRunIdleTests: XCTestCase {
    func testForceIdleAfterRunLeavesVisibleIdleTexture() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let petDirectory = root.appendingPathComponent("Assets/pet")
        let manifestURL = petDirectory.appendingPathComponent("manifest.json")
        let manifest = try JSONDecoder().decode(
            AnimationManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let sprite = SKSpriteNode()
        let player = ManifestAnimationPlayer(
            sprite: sprite,
            manifest: manifest,
            resourceDirectory: petDirectory
        )

        player.play(.run)
        player.forcePlay(.idle)

        XCTAssertEqual(player.currentAnimationName, PetAnimationState.idle.rawValue)
        XCTAssertNotNil(sprite.texture)
        XCTAssertEqual(sprite.alpha, 1)
        XCTAssertFalse(sprite.isHidden)
        XCTAssertEqual(sprite.colorBlendFactor, 0)
    }
}
