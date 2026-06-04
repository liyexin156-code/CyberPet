import SpriteKit
import XCTest
@testable import PetTaskBuddy

@MainActor
final class DogSizeSettingsTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testDogSizeSettingDefaultsClampsAndPersistsPercent() {
        let defaults = UserDefaults(suiteName: "DogSizeSettingsTests-\(UUID().uuidString)")!
        let settings = DogSizeSettings(userDefaults: defaults)

        XCTAssertEqual(settings.percent, 100)
        XCTAssertEqual(settings.scale, 1)

        settings.setPercent(42)
        XCTAssertEqual(settings.percent, 50)
        XCTAssertEqual(defaults.double(forKey: DogSizeSettings.userDefaultsKey), 50)

        settings.setPercent(215)
        XCTAssertEqual(settings.percent, 200)
        XCTAssertEqual(defaults.double(forKey: DogSizeSettings.userDefaultsKey), 200)

        settings.reset()
        XCTAssertEqual(settings.percent, 100)
        XCTAssertEqual(defaults.double(forKey: DogSizeSettings.userDefaultsKey), 100)
    }

    func testAnimationPlayerAppliesDogScaleWithoutChangingAnimationStateOrIdleTexture() throws {
        let petDirectory = projectRoot.appendingPathComponent("Assets/pet")
        let manifest = try JSONDecoder().decode(
            AnimationManifest.self,
            from: Data(contentsOf: petDirectory.appendingPathComponent("manifest.json"))
        )
        let sprite = SKSpriteNode()
        let player = ManifestAnimationPlayer(
            sprite: sprite,
            manifest: manifest,
            resourceDirectory: petDirectory
        )
        let baseDisplaySize = CGFloat(Double(manifest.frameSize) * manifest.scale * PetLayout.spriteDisplayScale)

        player.forcePlay(.idle)
        player.dogScale = 1.5

        XCTAssertEqual(player.currentAnimationName, PetAnimationState.idle.rawValue)
        XCTAssertEqual(sprite.texture?.size().width, 1024)
        XCTAssertEqual(sprite.texture?.size().height, 1536)
        XCTAssertEqual(sprite.size.width, baseDisplaySize * 1.5, accuracy: 0.001)
        XCTAssertEqual(sprite.size.height, baseDisplaySize * 1.5, accuracy: 0.001)

        player.forcePlay(.run)

        XCTAssertEqual(player.currentAnimationName, PetAnimationState.run.rawValue)
        XCTAssertEqual(sprite.size.height, baseDisplaySize * 1.5, accuracy: 0.001)
    }

    func testContextMenuDefinesDogSizeSliderAndLocalizedLabels() throws {
        let sceneSource = try source("Sources/PetTaskBuddy/PetScene.swift")
        let localizationSource = try source("Sources/PetTaskBuddy/LocalizationManager.swift")

        XCTAssertTrue(sceneSource.contains("NSSlider"))
        XCTAssertTrue(sceneSource.contains("DogSizeSettings.shared"))
        XCTAssertTrue(sceneSource.contains("cyberpet-dog-size-slider"))
        XCTAssertTrue(sceneSource.contains("resetDogSize"))
        XCTAssertTrue(localizationSource.contains("menuDogSize"))
        XCTAssertTrue(localizationSource.contains("狗狗大小"))
        XCTAssertTrue(localizationSource.contains("Dog Size"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
