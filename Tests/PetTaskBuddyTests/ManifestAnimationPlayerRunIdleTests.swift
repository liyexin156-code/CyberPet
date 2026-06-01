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
        XCTAssertEqual(sprite.texture?.size().width, 1024)
        XCTAssertEqual(sprite.texture?.size().height, 1536)
        let expectedDisplaySize = CGFloat(Double(manifest.frameSize) * manifest.scale * PetLayout.spriteDisplayScale)
        XCTAssertEqual(sprite.size.width, expectedDisplaySize, accuracy: 0.001)
        XCTAssertEqual(sprite.size.height, expectedDisplaySize, accuracy: 0.001)
        XCTAssertEqual(sprite.alpha, 1)
        XCTAssertFalse(sprite.isHidden)
        XCTAssertEqual(sprite.colorBlendFactor, 0)
    }
}
