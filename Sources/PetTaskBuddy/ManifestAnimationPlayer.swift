import AppKit
import SpriteKit

// Per-frame alpha bitmask used for pixel-accurate hit testing.
// Stored in CPU memory at load time so runtime lookup is a plain array access.
struct AlphaMask {
    let width: Int
    let height: Int
    // Flattened row-major alpha values. Row 0 matches SpriteKit's visual bottom
    // for these generated sprite strips.
    private let alphas: [UInt8]
    private let opaqueBounds: CGRect?

    init(width: Int, height: Int, alphas: [UInt8]) {
        self.width = width
        self.height = height
        self.alphas = alphas
        self.opaqueBounds = Self.makeOpaqueBounds(width: width, height: height, alphas: alphas)
    }

    // normalizedX/Y in [0,1], origin bottom-left (matches SpriteKit scene coords).
    func isOpaque(normalizedX: CGFloat, normalizedY: CGFloat, threshold: UInt8 = 10) -> Bool {
        let px = min(max(Int(normalizedX * CGFloat(width)),  0), width  - 1)
        let py = min(max(Int(normalizedY * CGFloat(height)), 0), height - 1)
        return alphas[py * width + px] > threshold
    }

    func isInsideOpaqueBody(normalizedX: CGFloat, normalizedY: CGFloat) -> Bool {
        guard let opaqueBounds else { return false }
        return opaqueBounds.contains(CGPoint(x: normalizedX, y: normalizedY))
    }

    private static func makeOpaqueBounds(width: Int, height: Int, alphas: [UInt8]) -> CGRect? {
        var minX = width
        var maxX = -1
        var minY = height
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width where alphas[y * width + x] > 10 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }

        let padding: CGFloat = 2
        let left = max(CGFloat(minX) - padding, 0) / CGFloat(width)
        let bottom = max(CGFloat(minY) - padding, 0) / CGFloat(height)
        let right = min(CGFloat(maxX + 1) + padding, CGFloat(width)) / CGFloat(width)
        let top = min(CGFloat(maxY + 1) + padding, CGFloat(height)) / CGFloat(height)
        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
    }
}

final class ManifestAnimationPlayer {
    private enum PlaybackMode {
        case normal
        case oneCycle
    }

    private enum ActionKey {
        static let animation = "pet.animation"
    }

    private let manifest: AnimationManifest
    private let texturesByState: [String: [SKTexture]]
    private let sourcePathByState: [String: String]
    // Keyed by the SKTexture's object identity so lookup is O(1) per hit-test.
    private let alphaMasksByTexture: [ObjectIdentifier: AlphaMask]
    private weak var sprite: SKSpriteNode?
    private var currentState: String?
    private var queuedState: (name: String, completion: (() -> Void)?)?
    private var isOneShotRunning = false

    init(sprite: SKSpriteNode, manifest: AnimationManifest, resourceDirectory: URL) {
        self.sprite = sprite
        self.manifest = manifest
        let loadedResources = Self.loadTextures(manifest: manifest, resourceDirectory: resourceDirectory)
        self.texturesByState = loadedResources.textures
        self.sourcePathByState = loadedResources.sourcePaths
        self.alphaMasksByTexture = loadedResources.alphaMasks
        Self.logManifestCoverage(
            manifest: manifest,
            texturesByState: texturesByState,
            sourcePathByState: sourcePathByState,
            resourceDirectory: resourceDirectory
        )
        installInitialTexture()
    }

    // Returns true if the current animation frame has an opaque pixel at the given
    // normalised sprite coordinates (origin bottom-left, matching SpriteKit space).
    // Fails open (returns true) when no mask is available so clicks still work.
    func isOpaqueAt(normalizedX: CGFloat, normalizedY: CGFloat) -> Bool {
        guard let sprite, let texture = sprite.texture else { return false }
        guard let mask = alphaMasksByTexture[ObjectIdentifier(texture)] else { return true }
        return mask.isInsideOpaqueBody(normalizedX: normalizedX, normalizedY: normalizedY)
    }

    var currentAnimationName: String? {
        currentState
    }

    func play(_ state: PetAnimationState) {
        play(state.rawValue, completion: nil)
    }

    func forcePlay(_ state: PetAnimationState) {
        queuedState = nil
        isOneShotRunning = false
        currentState = nil
        transition(to: state.rawValue, mode: .normal, completion: nil)
    }

    func play(_ state: PetAnimationState, completion: (() -> Void)?) {
        play(state.rawValue, completion: completion)
    }

    func duration(for state: PetAnimationState) -> TimeInterval {
        guard let stateManifest = manifest.states[state.rawValue] else {
            NSLog("[PetAnimation] Missing manifest state '\(state.rawValue)' while calculating duration.")
            return 0
        }
        let frameCount = texturesByState[state.rawValue]?.count ?? stateManifest.frames
        return Double(frameCount) * frameDuration(for: state, manifestState: stateManifest)
    }

    func play(_ stateName: String, completion: (() -> Void)? = nil) {
        play(stateName, mode: .normal, completion: completion)
    }

    func playOneCycle(_ state: PetAnimationState, completion: (() -> Void)?) {
        play(state.rawValue, mode: .oneCycle, completion: completion)
    }

    func playOneCycle(
        _ state: PetAnimationState,
        timePerFrame: TimeInterval,
        holdDuration: TimeInterval,
        completion: (() -> Void)?
    ) {
        play(
            state.rawValue,
            mode: .oneCycle,
            timePerFrameOverride: timePerFrame,
            holdDuration: holdDuration,
            completion: completion
        )
    }

    private func play(
        _ stateName: String,
        mode: PlaybackMode,
        timePerFrameOverride: TimeInterval? = nil,
        holdDuration: TimeInterval = 0,
        completion: (() -> Void)? = nil
    ) {
        if mode == .normal, currentState == stateName { return }
        guard manifest.states[stateName] != nil, let textures = texturesByState[stateName], !textures.isEmpty else {
            let imagePath = "\(stateName).png"
            NSLog("[PetAnimation] Cannot play state '\(stateName)': manifest entry or texture frames missing. Expected image: \(imagePath)")
            return
        }

        if isOneShotRunning {
            queuedState = (stateName, completion)
            return
        }

        if mode == .normal, shouldRouteThroughIdle(target: stateName) {
            transition(to: PetAnimationState.idle.rawValue, mode: .normal) { [weak self] in
                let delay = self?.crossfadeDuration ?? 0.1
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self?.play(stateName, completion: completion)
                }
            }
            return
        }

        transition(
            to: stateName,
            mode: mode,
            timePerFrameOverride: timePerFrameOverride,
            holdDuration: holdDuration,
            completion: completion
        )
    }

    private func transition(
        to stateName: String,
        mode: PlaybackMode,
        timePerFrameOverride: TimeInterval? = nil,
        holdDuration: TimeInterval = 0,
        completion: (() -> Void)?
    ) {
        guard let state = manifest.states[stateName], let textures = texturesByState[stateName], !textures.isEmpty else {
            NSLog("[PetAnimation] Transition skipped. State '\(stateName)' is missing manifest data or textures.")
            completion?()
            return
        }

        currentState = stateName
        sprite?.removeAction(forKey: ActionKey.animation)
        sprite?.isHidden = false
        sprite?.alpha = 1
        let firstTextureSize = textures.first?.size() ?? CGSize(width: manifest.frameSize, height: manifest.frameSize)
        let textureAspectRatio = firstTextureSize.height > 0 ? firstTextureSize.width / firstTextureSize.height : 1
        let displayHeight = Double(manifest.frameSize) * manifest.scale * PetLayout.spriteDisplayScale
        sprite?.size = CGSize(
            width: displayHeight * textureAspectRatio,
            height: displayHeight
        )
        sprite?.texture = textures.first
        sprite?.color = .white
        sprite?.colorBlendFactor = 0
        logRenderedTexture(stateName: stateName, textures: textures)

        let animationState = PetAnimationState(rawValue: stateName) ?? .idle
        let frameDuration = timePerFrameOverride ?? frameDuration(for: animationState, manifestState: state)
        let animate = SKAction.animate(with: textures, timePerFrame: frameDuration, resize: false, restore: false)
        let fadeOut = SKAction.fadeAlpha(to: 0.72, duration: crossfadeDuration / 2)
        let fadeIn = SKAction.fadeAlpha(to: 1, duration: crossfadeDuration / 2)
        let crossfade = SKAction.sequence([fadeOut, fadeIn])

        if mode == .oneCycle {
            sprite?.run(.sequence([
                crossfade,
                animate,
                .wait(forDuration: holdDuration),
                .run { completion?() }
            ]), withKey: ActionKey.animation)
            return
        }

        switch state.type {
        case .oneshot:
            isOneShotRunning = true
            let nextState = state.returnTo ?? PetAnimationState.idle.rawValue
            sprite?.run(.sequence([
                crossfade,
                animate,
                .run { [weak self] in
                    self?.isOneShotRunning = false
                    let queued = self?.queuedState
                    self?.queuedState = nil
                    completion?()
                    if let queued {
                        self?.play(queued.name, completion: queued.completion)
                    } else {
                        self?.play(nextState)
                    }
                }
            ]), withKey: ActionKey.animation)
        case .loop:
            if textures.count == 1 {
                sprite?.run(.sequence([
                    crossfade,
                    .run { completion?() }
                ]), withKey: ActionKey.animation)
                return
            }
            sprite?.run(.sequence([
                crossfade,
                .run { completion?() },
                .repeatForever(animate)
            ]), withKey: ActionKey.animation)
        }
    }

    private var crossfadeDuration: TimeInterval {
        TimeInterval(manifest.transition?.crossfadeMs ?? 100) / 1000
    }

    private func frameDuration(for state: PetAnimationState, manifestState: AnimationManifest.State) -> TimeInterval {
        if state == .run, manifestState.fps > 0 {
            return 1.0 / manifestState.fps
        }
        return PetAutonomousBehaviorConfig.timePerFrame(for: state)
    }

    private func shouldRouteThroughIdle(target: String) -> Bool {
        guard let currentState, currentState != PetAnimationState.idle.rawValue else { return false }
        guard target != PetAnimationState.idle.rawValue else { return false }

        let directPair = Set([currentState, target])
        if directPair == Set([PetAnimationState.idle.rawValue, PetAnimationState.walk.rawValue]) {
            return false
        }

        if currentState == PetAnimationState.walk.rawValue, target == PetAnimationState.idle.rawValue {
            return false
        }

        return currentState != PetAnimationState.walk.rawValue || target != PetAnimationState.idle.rawValue
    }

    private func installInitialTexture() {
        guard let idleTextures = texturesByState[PetAnimationState.idle.rawValue], let firstTexture = idleTextures.first else {
            NSLog("[PetAnimation] Initial idle texture is missing; sprite will stay untextured.")
            return
        }

        sprite?.texture = firstTexture
        sprite?.color = .white
        sprite?.colorBlendFactor = 0
        sprite?.isHidden = false
        sprite?.alpha = 1
        NSLog("[PetAnimation] Initial render texture installed: state=idle source=\(sourcePathByState[PetAnimationState.idle.rawValue] ?? "unknown") textureSize=\(firstTexture.size()) colorBlendFactor=\(sprite?.colorBlendFactor ?? -1)")
    }

    private func logRenderedTexture(stateName: String, textures: [SKTexture]) {
        let textureSize = textures.first?.size() ?? .zero
        NSLog("[PetAnimation] Rendering state '\(stateName)' from \(sourcePathByState[stateName] ?? "unknown") firstFrameSize=\(textureSize) spriteTextureSize=\(sprite?.texture?.size() ?? .zero) colorBlendFactor=\(sprite?.colorBlendFactor ?? -1)")
    }

    private static func loadTextures(
        manifest: AnimationManifest,
        resourceDirectory: URL
    ) -> (textures: [String: [SKTexture]], sourcePaths: [String: String], alphaMasks: [ObjectIdentifier: AlphaMask]) {
        var textures: [String: [SKTexture]] = [:]
        var sourcePaths: [String: String] = [:]
        var alphaMasks: [ObjectIdentifier: AlphaMask] = [:]

        for (stateName, state) in manifest.states {
            if stateName == PetAnimationState.walk.rawValue,
               let frameImages = loadIndividualFrameImages(
                   for: stateName,
                   expectedCount: state.frames,
                   resourceDirectory: resourceDirectory
               ) {
                let normalizedFrames = normalizeFrameImages(frameImages.images)
                sourcePaths[stateName] = frameImages.paths.joined(separator: ", ")
                textures[stateName] = makeTextures(from: normalizedFrames, alphaMasks: &alphaMasks)
                NSLog("[PetAnimation] State '\(stateName)' loaded \(normalizedFrames.count) individual frame(s) from \(sourcePaths[stateName] ?? "unknown").")
                continue
            }

            let imageURL = resourceDirectory.appendingPathComponent("\(stateName).png")

            guard let image = NSImage(contentsOf: imageURL),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else {
                NSLog("[PetAnimation] Missing or unreadable sprite strip for state '\(stateName)': \(imageURL.path)")
                continue
            }

            let defaultFrameSize = manifest.frameSize
            let actualWidth = cgImage.width
            let actualHeight = cgImage.height
            let usesManifestFrameCount = stateName == PetAnimationState.run.rawValue
                && state.frames > 0
                && actualWidth % state.frames == 0
            let frameWidth = usesManifestFrameCount ? actualWidth / state.frames : defaultFrameSize
            let frameHeight = usesManifestFrameCount ? actualHeight : defaultFrameSize
            let inferredFrames = usesManifestFrameCount ? state.frames : max(actualWidth / max(frameWidth, 1), 1)
            let hasWidthRemainder = actualWidth % max(frameWidth, 1) != 0
            let hasHeightMismatch = !usesManifestFrameCount && actualHeight != frameHeight

            NSLog("[PetAnimation] Strip '\(stateName)': imageWidth=\(actualWidth), imageHeight=\(actualHeight), frameSize=\(frameWidth)x\(frameHeight), inferredFrames=\(inferredFrames), manifestFrames=\(state.frames).")

            if inferredFrames != state.frames {
                NSLog("[PetAnimation] Frame count mismatch for '\(stateName)': manifest=\(state.frames), inferred=\(inferredFrames). Using inferred frame count.")
            }
            if hasWidthRemainder {
                NSLog("[PetAnimation] Strip width for '\(stateName)' is not divisible by frameSize. Trailing pixels will be ignored.")
            }
            if hasHeightMismatch {
                NSLog("[PetAnimation] Strip height mismatch for '\(stateName)': expected \(frameHeight), got \(actualHeight). Cropping top-left \(frameWidth)x\(frameHeight) cells.")
            }

            sourcePaths[stateName] = imageURL.path

            var stateTextures: [SKTexture] = []
            for frameIndex in 0..<inferredFrames {
                let cropRect = CGRect(
                    x: frameIndex * frameWidth,
                    y: 0,
                    width: min(frameWidth, actualWidth - frameIndex * frameWidth),
                    height: min(frameHeight, actualHeight)
                )
                guard let frameImage = cgImage.cropping(to: cropRect) else {
                    NSLog("[PetAnimation] Failed to crop frame \(frameIndex) for state '\(stateName)' at rect \(cropRect).")
                    continue
                }

                let texture = SKTexture(cgImage: frameImage)
                texture.filteringMode = .nearest
                // Extract alpha mask at load time (CPU only, no GPU readback).
                if let mask = extractAlphaMask(from: frameImage) {
                    alphaMasks[ObjectIdentifier(texture)] = mask
                }
                stateTextures.append(texture)
            }
            textures[stateName] = stateTextures
        }

        return (textures: textures, sourcePaths: sourcePaths, alphaMasks: alphaMasks)
    }

    private static func loadIndividualFrameImages(
        for stateName: String,
        expectedCount: Int,
        resourceDirectory: URL
    ) -> (images: [CGImage], paths: [String])? {
        let frameDirectory = resourceDirectory.appendingPathComponent(stateName, isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: frameDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        let imageURLs = urls
            .filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard imageURLs.count == expectedCount else {
            NSLog("[PetAnimation] Individual frame count mismatch for '\(stateName)': expected \(expectedCount), found \(imageURLs.count) in \(frameDirectory.path). Falling back to sprite strip.")
            return nil
        }

        var images: [CGImage] = []
        var paths: [String] = []
        for url in imageURLs {
            guard let image = NSImage(contentsOf: url),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else {
                NSLog("[PetAnimation] Failed to load individual frame for '\(stateName)': \(url.path)")
                return nil
            }
            images.append(cgImage)
            paths.append(url.path)
        }
        return (images, paths)
    }

    private static func normalizeFrameImages(_ images: [CGImage]) -> [CGImage] {
        guard let maxWidth = images.map(\.width).max(),
              let maxHeight = images.map(\.height).max(),
              maxWidth > 0,
              maxHeight > 0
        else {
            return images
        }

        return images.map { image in
            guard image.width != maxWidth || image.height != maxHeight else { return image }
            let space = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(
                data: nil,
                width: maxWidth,
                height: maxHeight,
                bitsPerComponent: 8,
                bytesPerRow: maxWidth * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return image
            }
            ctx.clear(CGRect(x: 0, y: 0, width: maxWidth, height: maxHeight))
            ctx.interpolationQuality = .none
            let x = (maxWidth - image.width) / 2
            ctx.draw(
                image,
                in: CGRect(x: x, y: 0, width: image.width, height: image.height)
            )
            return ctx.makeImage() ?? image
        }
    }

    private static func makeTextures(
        from frameImages: [CGImage],
        alphaMasks: inout [ObjectIdentifier: AlphaMask]
    ) -> [SKTexture] {
        frameImages.map { frameImage in
            let texture = SKTexture(cgImage: frameImage)
            texture.filteringMode = .nearest
            if let mask = extractAlphaMask(from: frameImage) {
                alphaMasks[ObjectIdentifier(texture)] = mask
            }
            return texture
        }
    }

    // Draws the frame into a known RGBA-8888 CGContext so we get reliable alpha
    // data regardless of the source image's original pixel format.
    // The generated sprite strips used by this app render into the bitmap with
    // row 0 matching SpriteKit's visual bottom, so SpriteKit normalized Y maps
    // directly to AlphaMask rows.
    private static func extractAlphaMask(from cgImage: CGImage) -> AlphaMask? {
        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else { return nil }
        var raw = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &raw,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        // RGBA: alpha is at every 4th byte starting at index 3.
        let alphas = stride(from: 3, to: raw.count, by: 4).map { raw[$0] }
        return AlphaMask(width: w, height: h, alphas: alphas)
    }

    private static func logManifestCoverage(
        manifest: AnimationManifest,
        texturesByState: [String: [SKTexture]],
        sourcePathByState: [String: String],
        resourceDirectory: URL
    ) {
        NSLog("[PetAnimation] Loaded pet manifest from: \(resourceDirectory.path)")
        for state in PetAnimationState.allCases {
            let stateName = state.rawValue
            if manifest.states[stateName] == nil {
                NSLog("[PetAnimation] Manifest is missing expected state '\(stateName)'.")
                continue
            }
            let frameCount = texturesByState[stateName]?.count ?? 0
            if frameCount == 0 {
                NSLog("[PetAnimation] State '\(stateName)' has no loaded texture frames. Expected: \(resourceDirectory.appendingPathComponent("\(stateName).png").path)")
            } else {
                NSLog("[PetAnimation] State '\(stateName)' loaded \(frameCount) frame(s) from \(sourcePathByState[stateName] ?? "unknown").")
            }
        }
    }
}
