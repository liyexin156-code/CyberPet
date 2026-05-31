import AppKit
import SpriteKit

@MainActor
protocol PetSceneDelegate: AnyObject {
    func petSceneDidRequestExit(_ scene: PetScene)
    func petScene(_ scene: PetScene, didRequestManualPerformance kind: PetManualPerformanceKind)
    func petSceneDidDoubleClick(_ scene: PetScene)
    func petSceneDidBeginDrag(_ scene: PetScene)
    func petSceneDidDrag(_ scene: PetScene)
    func petSceneDidEndDrag(_ scene: PetScene)
}

final class PetScene: SKScene {
    weak var petDelegate: PetSceneDelegate?

    private let petNode = SKSpriteNode()
    private var animationPlayer: ManifestAnimationPlayer?
    private var didDragAfterMouseDown = false
    private var rewardDropGoesRight = true

    // Reward bowl placement, all derived from the dog's mouth so the bowl lands
    // directly under the muzzle for either facing — never floating, buried, or
    // offset. Tuned to the eat/drink sprite art, where the muzzle sits ~0.32 of
    // the (square) frame width ahead of the sprite centre and the drawn bowl a
    // little further forward still.
    private static let rewardGroundY: CGFloat = 16              // ground line = petNode feet (anchor y=0)
    private static let rewardMouthForwardFraction: CGFloat = 0.32
    private static let rewardBowlGap: CGFloat = 8               // bowl sits a touch in front of the mouth
    private static let rewardStepForward: CGFloat = 10          // small forward step toward the bowl (no turn-around)
    private static let rewardBowlHalfHeight: CGFloat = 5        // half of rewardNode bowl height (10)

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        scaleMode = .resizeFill

        petNode.name = "pet"
        petNode.anchorPoint = CGPoint(x: 0.5, y: 0)
        petNode.position = CGPoint(x: size.width / 2, y: 16)
        addChild(petNode)

        loadManifestDrivenAnimations()
        animationPlayer?.play(.idle)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        petNode.position = CGPoint(x: size.width / 2, y: 16)
    }

    func play(_ state: PetAnimationState) {
        animationPlayer?.play(state)
    }

    func forcePlay(_ state: PetAnimationState) {
        animationPlayer?.forcePlay(state)
    }

    func play(_ state: PetAnimationState, completion: (() -> Void)?) {
        animationPlayer?.play(state, completion: completion)
    }

    func playOneCycle(_ state: PetAnimationState, completion: @escaping () -> Void) {
        animationPlayer?.playOneCycle(state, completion: completion)
    }

    func playOneCycle(
        _ state: PetAnimationState,
        timePerFrame: TimeInterval,
        holdDuration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        animationPlayer?.playOneCycle(
            state,
            timePerFrame: timePerFrame,
            holdDuration: holdDuration,
            completion: completion
        )
    }

    func animationDuration(for state: PetAnimationState) -> TimeInterval {
        animationPlayer?.duration(for: state) ?? 0
    }

    func faceRight(_ isFacingRight: Bool) {
        petNode.xScale = isFacingRight ? abs(petNode.xScale) : -abs(petNode.xScale)
    }

    func applyMoodState(_ state: PetAnimationState) {
        animationPlayer?.play(state)
    }

    var currentAnimationName: String? {
        animationPlayer?.currentAnimationName
    }

    // Returns true only when viewPoint (NSView coordinates, origin bottom-left)
    // lands on an opaque pixel of the current animation frame.
    // Used by PassthroughSKView.hitTest for pixel-accurate click-through.
    func isOpaqueAt(viewPoint: CGPoint) -> Bool {
        let nodeSize = petNode.size
        guard nodeSize.width > 0, nodeSize.height > 0 else { return false }

        // petNode.anchorPoint = (0.5, 0)  →  bottom-center at petNode.position
        let spriteLeft   = petNode.position.x - nodeSize.width  / 2
        let spriteBottom = petNode.position.y                      // anchorPoint.y == 0

        // Fast bounds check before touching the alpha mask.
        guard viewPoint.x >= spriteLeft,
              viewPoint.x <= spriteLeft + nodeSize.width,
              viewPoint.y >= spriteBottom,
              viewPoint.y <= spriteBottom + nodeSize.height
        else { return false }

        // No manifest (coloured placeholder box) → treat whole sprite as opaque.
        guard let animationPlayer else { return true }

        // Normalised sprite coordinates, origin bottom-left, range [0, 1].
        let normX = (viewPoint.x - spriteLeft)   / nodeSize.width
        let normY = (viewPoint.y - spriteBottom) / nodeSize.height

        // Mirror X when sprite is facing left (xScale < 0).
        let facingNormX = petNode.xScale < 0 ? 1 - normX : normX

        // AlphaMask row 0 == bottom of sprite (see extractAlphaMask comment),
        // so normalizedY maps directly without a flip.
        return animationPlayer.isOpaqueAt(normalizedX: facingNormX, normalizedY: normY)
    }

    func showBubble(_ message: String) {
        childNode(withName: "pet.bubble")?.removeFromParent()

        let maxTextWidth: CGFloat = 170
        let label = SKLabelNode(text: message)
        label.fontName = "PingFangSC-Regular"
        label.fontSize = 13
        label.fontColor = .labelColor
        label.numberOfLines = 0
        label.preferredMaxLayoutWidth = maxTextWidth
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: 2)

        let width = min(max(label.frame.width + 24, 72), maxTextWidth + 24)
        let height = max(label.frame.height + 16, 34)
        let background = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 8)
        background.fillColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94)
        background.strokeColor = NSColor.separatorColor

        let bubble = SKNode()
        bubble.name = "pet.bubble"
        bubble.position = CGPoint(x: size.width / 2, y: min(size.height - height / 2 - 8, 190))
        bubble.alpha = 0
        bubble.addChild(background)
        bubble.addChild(label)
        addChild(bubble)

        bubble.run(.sequence([
            .fadeIn(withDuration: 0.14),
            .wait(forDuration: 4),
            .fadeOut(withDuration: 0.22),
            .removeFromParent()
        ]))
    }

    func performReward(_ kind: PetRewardKind, completion: @escaping () -> Void) {
        petNode.removeAction(forKey: "pet.reward")
        childNode(withName: "reward.item")?.removeFromParent()

        let timing = PetAutonomousBehaviorConfig.rewardTiming(for: kind)
        let groundY = Self.rewardGroundY

        // Alternate facing so both directions get exercised; everything else is
        // derived from where the dog's mouth will be for that facing.
        let facingRight = rewardDropGoesRight
        rewardDropGoesRight.toggle()
        let facing: CGFloat = facingRight ? 1 : -1

        // The dog drinks from a spot just ahead of centre on the facing side, so
        // it steps forward (no turn-around) to reach the bowl.
        let petStand = CGPoint(x: size.width / 2 + facing * Self.rewardStepForward, y: groundY)

        // Mouth anchor in scene space, then the bowl a touch in front of it with
        // its bottom resting on the ground line (= the dog's feet).
        let mouthX = petStand.x + facing * (petNode.size.width * Self.rewardMouthForwardFraction)
        let bowlX = mouthX + facing * Self.rewardBowlGap
        let bowlGround = CGPoint(x: bowlX, y: groundY + Self.rewardBowlHalfHeight)

        let item = rewardNode(kind: kind)
        item.name = "reward.item"
        item.position = CGPoint(x: bowlX, y: size.height - 24) // drop straight down onto the muzzle spot
        item.alpha = 0
        addChild(item)

        faceRight(facingRight)
        animationPlayer?.play(.walk)

        item.run(.group([
            .fadeIn(withDuration: 0.12),
            .move(to: bowlGround, duration: timing.itemDropDuration)
        ]))

        let goEat = SKAction.sequence([
            .move(to: petStand, duration: timing.approachDuration),
            .run { [weak self] in
                guard let self else { return }
                self.faceRight(facingRight)
                self.playOneCycle(
                    kind.animationState,
                    timePerFrame: timing.animationTimePerFrame,
                    holdDuration: timing.holdDuration,
                    completion: {
                        DispatchQueue.main.async {
                            item.run(.sequence([
                                .fadeOut(withDuration: timing.itemFadeOutDuration),
                                .removeFromParent()
                            ]))
                            let center = CGPoint(x: self.size.width / 2, y: groundY)
                            self.faceRight(center.x >= petStand.x)
                            self.animationPlayer?.play(.walk)
                            self.petNode.run(.sequence([
                                .move(to: center, duration: timing.returnDuration),
                                .run {
                                    self.animationPlayer?.play(.idle)
                                    completion()
                                }
                            ]))
                        }
                    })
            }
        ])

        petNode.run(goEat, withKey: "pet.reward")
    }

    override func mouseDown(with event: NSEvent) {
        if event.type == .rightMouseDown {
            openContextMenu(with: event)
            return
        }

        didDragAfterMouseDown = false
    }

    override func mouseDragged(with event: NSEvent) {
        if !didDragAfterMouseDown {
            petDelegate?.petSceneDidBeginDrag(self)
        }
        didDragAfterMouseDown = true
        petDelegate?.petSceneDidDrag(self)
    }

    override func mouseUp(with event: NSEvent) {
        if didDragAfterMouseDown {
            petDelegate?.petSceneDidEndDrag(self)
        } else if event.clickCount >= 2 {
            petDelegate?.petSceneDidDoubleClick(self)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        openContextMenu(with: event)
    }

    private func loadManifestDrivenAnimations() {
        guard let resourceDirectory = PetResourceLocator.petDirectory() else {
            NSLog("[PetAnimation] Could not find Assets/pet/manifest.json in bundle resources or development directory.")
            petNode.color = .systemTeal
            petNode.colorBlendFactor = 1
            petNode.size = CGSize(width: 160 * PetLayout.spriteDisplayScale, height: 160 * PetLayout.spriteDisplayScale)
            return
        }

        guard let manifestURL = PetResourceLocator.manifestURL(in: resourceDirectory) else {
            NSLog("[PetAnimation] Pet resource directory found, but manifest.json is missing: \(resourceDirectory.path)")
            petNode.color = .systemTeal
            petNode.colorBlendFactor = 1
            petNode.size = CGSize(width: 160 * PetLayout.spriteDisplayScale, height: 160 * PetLayout.spriteDisplayScale)
            return
        }

        let manifest: AnimationManifest
        do {
            let data = try Data(contentsOf: manifestURL)
            manifest = try JSONDecoder().decode(AnimationManifest.self, from: data)
        } catch {
            NSLog("[PetAnimation] Failed to decode pet manifest at \(manifestURL.path): \(error)")
            petNode.color = .systemTeal
            petNode.colorBlendFactor = 1
            petNode.size = CGSize(width: 160 * PetLayout.spriteDisplayScale, height: 160 * PetLayout.spriteDisplayScale)
            return
        }

        petNode.colorBlendFactor = 0
        petNode.size = CGSize(
            width: Double(manifest.frameSize) * manifest.scale * PetLayout.spriteDisplayScale,
            height: Double(manifest.frameSize) * manifest.scale * PetLayout.spriteDisplayScale
        )
        animationPlayer = ManifestAnimationPlayer(sprite: petNode, manifest: manifest, resourceDirectory: resourceDirectory)
    }

    private func rewardNode(kind: PetRewardKind) -> SKNode {
        let container = SKNode()
        let bowlColor: NSColor = kind == .eat ? .systemOrange : .systemBlue
        let bowl = SKShapeNode(rectOf: CGSize(width: 22, height: 10), cornerRadius: 2)
        bowl.fillColor = bowlColor
        bowl.strokeColor = .clear
        bowl.position = CGPoint(x: 0, y: 0)

        let shine = SKShapeNode(rectOf: CGSize(width: 8, height: 3), cornerRadius: 1)
        shine.fillColor = .white.withAlphaComponent(0.75)
        shine.strokeColor = .clear
        shine.position = CGPoint(x: -3, y: 2)

        container.addChild(bowl)
        container.addChild(shine)
        return container
    }

    private func openContextMenu(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "伸懒腰", action: #selector(ContextMenuTarget.performStretch), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "走一小段", action: #selector(ContextMenuTarget.performWalk), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "待机", action: #selector(ContextMenuTarget.performIdle), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "睡觉", action: #selector(ContextMenuTarget.performSleep), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "侧躺", action: #selector(ContextMenuTarget.performSideLie), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "坐一会儿", action: #selector(ContextMenuTarget.performSit), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "兴奋一下", action: #selector(ContextMenuTarget.performHappy), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "无聊乱逛", action: #selector(ContextMenuTarget.performRoam), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "疲惫想睡", action: #selector(ContextMenuTarget.performSleepy), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "嗅闻一下", action: #selector(ContextMenuTarget.performSniff), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "抖抖毛", action: #selector(ContextMenuTarget.performShake), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "挠挠痒", action: #selector(ContextMenuTarget.performScratch), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(ContextMenuTarget.exit), keyEquivalent: "q"))
        ContextMenuTarget.shared.scene = self
        menu.items.forEach { $0.target = ContextMenuTarget.shared }
        NSMenu.popUpContextMenu(menu, with: event, for: view ?? NSView())
    }
}

enum PetResourceLocator {
    static func petDirectory() -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("pet", isDirectory: true),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/pet", isDirectory: true),
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("Assets/pet", isDirectory: true)
        ].compactMap { $0 }

        return candidates.first { fileManager.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }
    }

    static func manifestURL(in petDirectory: URL) -> URL? {
        let url = petDirectory.appendingPathComponent("manifest.json")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

private final class ContextMenuTarget: NSObject {
    static let shared = ContextMenuTarget()
    weak var scene: PetScene?

    @MainActor
    @objc func performStretch() {
        request(.stretch)
    }

    @MainActor
    @objc func performWalk() {
        request(.walk)
    }

    @MainActor
    @objc func performIdle() {
        request(.idle)
    }

    @MainActor
    @objc func performSleep() {
        request(.sleep)
    }

    @MainActor
    @objc func performSideLie() {
        request(.sideLie)
    }

    @MainActor
    @objc func performHappy() {
        request(.happy)
    }

    @MainActor
    @objc func performRoam() {
        request(.roam)
    }

    @MainActor
    @objc func performSleepy() {
        request(.sleepy)
    }

    @MainActor
    @objc func performSniff() {
        request(.sniff)
    }

    @MainActor
    @objc func performSit() {
        request(.sit)
    }

    @MainActor
    @objc func performShake() {
        request(.shake)
    }

    @MainActor
    @objc func performScratch() {
        request(.scratch)
    }

    @MainActor
    @objc func exit() {
        guard let scene else { return }
        scene.petDelegate?.petSceneDidRequestExit(scene)
    }

    @MainActor
    private func request(_ kind: PetManualPerformanceKind) {
        guard let scene else { return }
        scene.petDelegate?.petScene(scene, didRequestManualPerformance: kind)
    }
}
