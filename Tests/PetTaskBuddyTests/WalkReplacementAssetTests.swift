import AppKit
import XCTest
@testable import PetTaskBuddy

final class WalkReplacementAssetTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testWalkManifestStillUsesFourFrames() throws {
        let manifestURL = projectRoot.appendingPathComponent("Assets/pet/manifest.json")
        let manifest = try JSONDecoder().decode(
            AnimationManifest.self,
            from: Data(contentsOf: manifestURL)
        )

        XCTAssertEqual(manifest.states[PetAnimationState.walk.rawValue]?.frames, 2)
    }

    func testWalkUsesTwoIndependentTransparentFrameFiles() throws {
        let frameURLs = [
            projectRoot.appendingPathComponent("Assets/pet/walk/frame1.png"),
            projectRoot.appendingPathComponent("Assets/pet/walk/frame2.png")
        ]

        for imageURL in frameURLs {
            let image = try XCTUnwrap(NSImage(contentsOf: imageURL))
            let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))

            XCTAssertGreaterThan(cgImage.width, 64)
            XCTAssertGreaterThan(cgImage.height, 64)
            XCTAssertEqual(alpha(atX: 0, y: 0, in: cgImage), 0)
            XCTAssertEqual(alpha(atX: cgImage.width - 1, y: 0, in: cgImage), 0)
            XCTAssertEqual(alpha(atX: 0, y: cgImage.height - 1, in: cgImage), 0)
            XCTAssertEqual(alpha(atX: cgImage.width - 1, y: cgImage.height - 1, in: cgImage), 0)
        }
    }

    private func alpha(atX x: Int, y: Int, in image: CGImage) -> UInt8 {
        var raw = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &raw,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(
            image,
            in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height)
        )
        return raw[3]
    }
}
