import AppKit
import Foundation

struct SpriteState {
    let name: String
    let frames: Int
    let bodyColor: NSColor
    let accentColor: NSColor
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputDirectory = root.appendingPathComponent("Assets/pet", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let states = [
    SpriteState(name: "idle", frames: 4, bodyColor: .systemTeal, accentColor: .systemPink),
    SpriteState(name: "walk", frames: 4, bodyColor: .systemGreen, accentColor: .systemPink),
    SpriteState(name: "happy", frames: 4, bodyColor: .systemYellow, accentColor: .systemOrange),
    SpriteState(name: "eat", frames: 4, bodyColor: .systemMint, accentColor: .systemBrown),
    SpriteState(name: "drink", frames: 3, bodyColor: .systemCyan, accentColor: .systemBlue),
    SpriteState(name: "listless", frames: 2, bodyColor: .systemGray, accentColor: .systemIndigo),
    SpriteState(name: "sleep", frames: 2, bodyColor: .systemPurple, accentColor: .systemBlue)
]

for state in states {
    let image = NSImage(size: NSSize(width: 64 * state.frames, height: 64))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .none
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: 64 * state.frames, height: 64).fill()

    for frame in 0..<state.frames {
        let x = frame * 64
        let bob = state.name == "idle" ? frame % 2 : abs((frame % 4) - 1)
        let yOffset = state.name == "happy" ? [0, 5, 9, 4][frame % 4] : bob

        state.bodyColor.setFill()
        pixelRect(x + 18, 20 + yOffset, 30, 24).fill()
        pixelRect(x + 42, 28 + yOffset, 12, 12).fill()

        state.accentColor.setFill()
        pixelRect(x + 23, 40 + yOffset, 8, 8).fill()
        pixelRect(x + 48, 36 + yOffset, 4, 5).fill()

        NSColor.white.setFill()
        pixelRect(x + 48, 34 + yOffset, 3, 3).fill()

        NSColor.black.setFill()
        pixelRect(x + 49, 35 + yOffset, 1, 1).fill()
        pixelRect(x + 52, 31 + yOffset, 2, 2).fill()

        let legShift = state.name == "walk" ? (frame % 2 == 0 ? 3 : -1) : 0
        state.bodyColor.setFill()
        pixelRect(x + 23 + legShift, 14 + yOffset, 5, 8).fill()
        pixelRect(x + 39 - legShift, 14 + yOffset, 5, 8).fill()

        state.accentColor.setFill()
        let tailLift = state.name == "happy" ? 10 : 4 + (state.name == "listless" ? -6 : frame % 2)
        pixelRect(x + 13, 33 + yOffset + tailLift, 7, 4).fill()

        if state.name == "eat" {
            NSColor.systemBrown.setFill()
            pixelRect(x + 45, 12, 13, 5).fill()
        } else if state.name == "drink" {
            NSColor.systemBlue.setFill()
            pixelRect(x + 45, 12, 13, 5).fill()
        } else if state.name == "sleep" {
            NSColor.white.setFill()
            pixelRect(x + 48, 50, 4, 2).fill()
            pixelRect(x + 52, 54, 5, 2).fill()
        }
    }

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "PlaceholderSprite", code: 1)
    }

    try png.write(to: outputDirectory.appendingPathComponent("\(state.name).png"))
}

func pixelRect(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> NSRect {
    NSRect(x: x, y: y, width: width, height: height)
}
