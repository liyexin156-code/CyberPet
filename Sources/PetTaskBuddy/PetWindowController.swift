import AppKit
import SpriteKit

@MainActor
final class PetWindowController: NSObject {
    private static let lowerScreenRoamingRatio: CGFloat = 0.33
    private static let dockSafeBottomPadding: CGFloat = 18
    private static let roamingHorizontalPadding: CGFloat = 32

    private let window: NSWindow
    private let scene = PetScene(size: CGSize(width: 220, height: 220))
    private let skView = PassthroughSKView(frame: NSRect(x: 0, y: 0, width: 220, height: 220))
    private weak var mainPanelWindowController: MainPanelWindowController?
    private weak var thoughtBubbleWindowController: ThoughtBubbleWindowController?
    private let petStateEngine: PetStateEngine
    private let reminderService: ReminderService

    private var behaviorTimer: Timer?
    private var movementTimer: Timer?
    private var mousePassthroughTimer: Timer?
    private var lastHitLoggedAnimationName: String?
    private var manualPerformanceTimers: [Timer] = []
    private var visibilityUpdateWork: DispatchWorkItem?
    private var roamDirection: CGFloat = 1
    private var currentBehavior: PetAutonomousBehaviorKind?
    private var lastDailyBehavior: PetAutonomousBehaviorKind?
    private var currentManualPerformance: PetManualPerformanceKind?
    private var isManualPerformance = false
    private var dragStartWindowOrigin = CGPoint.zero
    private var dragStartMouseLocation = CGPoint.zero
    private var isDragging = false
    private var isRewarding = false
    private var hasPlayedStartupSequence = false
    private var isStartupSequenceRunning = false
    private var isRenderingPausedForVisibility = false

    // Mouse Attention state.
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var lastMouseScreenPoint: CGPoint?
    private var lastMouseSampleTime: TimeInterval = 0
    private var lastMouseVelocity: CGFloat = 0
    private var lastMouseDistanceToPet: CGFloat = .greatestFiniteMagnitude
    private var attentionStepsRemaining = 0
    private var isAttendingMouse = false
    private var mouseAttentionCooldownUntil = Date.distantPast
    private var attentionTimers: [Timer] = []
    // True once the entry animation has played for the current visibility session.
    // Reset to false each time the window becomes hidden so the next re-appear
    // triggers a fresh entry run-in.
    private var hasEnteredForCurrentVisibility = false

    private struct EntryAnimationPlan {
        let startOrigin: CGPoint
        let restOrigin: CGPoint
        let duration: TimeInterval
    }

    // Read from UserDefaults so the user can toggle the animation via settings.
    // Defaults to true (nil in UserDefaults == not yet explicitly set).
    private var entryAnimationEnabled: Bool {
        guard UserDefaults.standard.object(forKey: PetAutonomousBehaviorConfig.entryAnimationEnabledKey) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: PetAutonomousBehaviorConfig.entryAnimationEnabledKey)
    }

    init(
        mainPanelWindowController: MainPanelWindowController?,
        petStateEngine: PetStateEngine,
        reminderService: ReminderService,
        thoughtBubbleWindowController: ThoughtBubbleWindowController?
    ) {
        self.mainPanelWindowController = mainPanelWindowController
        self.thoughtBubbleWindowController = thoughtBubbleWindowController
        self.petStateEngine = petStateEngine
        self.reminderService = reminderService
        window = PetWindow(
            contentRect: NSRect(x: 160, y: 160, width: 220, height: 220),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()

        configureWindow()
        configureSpriteKit()
        configurePetStateCallbacks()
        configureVisibilityObservers()
    }

    deinit {
        visibilityUpdateWork?.cancel()
        NotificationCenter.default.removeObserver(self)
        behaviorTimer?.invalidate()
        movementTimer?.invalidate()
        mousePassthroughTimer?.invalidate()
        manualPerformanceTimers.forEach { $0.invalidate() }
        attentionTimers.forEach { $0.invalidate() }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
    }

    func show() {
        let isAnimationSmokeTest = CommandLine.arguments.contains("--smoke-test-rewards")
            || CommandLine.arguments.contains("--smoke-test-reminder-pet-action")
        positionNearLowerRight()
        let entryPlan = !isAnimationSmokeTest && entryAnimationEnabled ? makeEntryAnimationPlan() : nil
        if let entryPlan {
            prepareEntryAnimation(entryPlan)
        }
        window.orderFrontRegardless()
        validateDrawableSize()
        updateRenderingActivity()
        startMousePassthroughUpdates()
        setupMouseAttentionMonitors()
        thoughtBubbleWindowController?.show(relativeTo: window)
        if isAnimationSmokeTest {
            scene.play(.idle)
        } else {
            startStartupSequence(entryPlan: entryPlan)
        }
    }

    func runRewardSmokeTest(completion: @escaping () -> Void) {
        PetDebugLog.write("Reward smoke test started")
        runRewardSmokeTest(kind: .eat) { [weak self] in
            self?.runRewardSmokeTest(kind: .drink) {
                PetDebugLog.write("Reward smoke test complete")
                completion()
            }
        }
    }

    func runReminderPetActionSmokeTest(completion: @escaping () -> Void) {
        let schedule = ScheduleItem(
            title: "Reminder pet action smoke",
            kind: .reminder,
            recurrence: Recurrence(type: .interval, yearlyRepeat: false),
            intervalSeconds: 2
        )
        performReminder(schedule, completion: completion)
    }

    private func configureWindow() {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        skView.autoresizingMask = [.width, .height]
        window.contentView = skView
    }

    private func configureSpriteKit() {
        skView.frame = NSRect(origin: .zero, size: CGSize(width: 220, height: 220))
        skView.wantsLayer = true
        skView.layer?.backgroundColor = NSColor.clear.cgColor
        skView.layer?.isOpaque = false
        skView.alphaValue = 1
        skView.allowsTransparency = true
        skView.ignoresSiblingOrder = true
        skView.preferredFramesPerSecond = 12
        skView.shouldCullNonVisibleNodes = true
        skView.petHitRect = NSRect(x: 14, y: 16, width: 192, height: 192)
        skView.onHoverChanged = { [weak self] isHovered in
            self?.thoughtBubbleWindowController?.setPetHovered(isHovered)
        }
        // Per-pixel alpha hit-test: transparent regions of the sprite fall through
        // to whatever is beneath the window (desktop, other apps).
        skView.isOpaqueAtPoint = { [weak self] point in
            self?.scene.isOpaqueAt(viewPoint: point) ?? false
        }

        scene.petDelegate = self
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)
    }

    private func positionNearLowerRight() {
        guard let screen = NSScreen.main else { return }
        let band = roamingBand(on: screen)
        let origin = CGPoint(
            x: band.maxX - 80,
            y: band.minY + 52
        )
        window.setFrameOrigin(clamp(origin, in: band))
        updateThoughtBubblePosition()
    }

    // Slides the pet window in from just off the right edge of the screen.
    // Duration = distance / speed (see PetAutonomousBehaviorConfig.entryRunSpeedPointsPerSecond),
    // so it adapts to any monitor size automatically.
    // On arrival the dog turns right, plays idle, then hands off to scheduleNextBehavior()
    // (NOT startAutonomousBehavior, which uses a longer first-launch delay).
    private func makeEntryAnimationPlan() -> EntryAnimationPlan? {
        guard let screen = window.screen ?? NSScreen.main else { return nil }
        // Compute the same resting spot that positionNearLowerRight() would land on.
        let band = roamingBand(on: screen)
        let restOrigin = clamp(
            CGPoint(x: band.maxX - 80, y: band.minY + 52),
            in: band
        )

        // Start position: window just off the right edge of the physical screen.
        let startOrigin = CGPoint(x: screen.frame.maxX, y: restOrigin.y)

        let distance = startOrigin.x - restOrigin.x
        let speed = Double(PetAutonomousBehaviorConfig.entryRunSpeedPointsPerSecond)
        // Clamp to a sensible range so unusually small/large screens don't feel wrong.
        let duration = min(max(distance / speed, 0.8), 4.0)

        return EntryAnimationPlan(startOrigin: startOrigin, restOrigin: restOrigin, duration: duration)
    }

    private func prepareEntryAnimation(_ plan: EntryAnimationPlan) {
        // Place window off-screen before SpriteKit is unpaused or shown again.
        window.setFrameOrigin(plan.startOrigin)
        updateThoughtBubblePosition()
        // Dog runs leftward (from right to left), so mirror the sprite.
        scene.faceRight(false)
        scene.play(.run)
    }

    private func startEntryAnimation(_ plan: EntryAnimationPlan) {
        PetDebugLog.write("Startup sequence step: run-in")
        animateWindow(from: plan.startOrigin, to: plan.restOrigin, duration: plan.duration) { [weak self] in
            guard let self else { return }
            self.scene.faceRight(true)
            self.playStartupStretch()
        }
    }

    private func startAutonomousBehavior() {
        let delay = TimeInterval.random(in: PetAutonomousBehaviorConfig.firstBehaviorDelayRange)
        scheduleNextBehavior(after: delay)
    }

    private func scheduleNextBehavior(after delay: TimeInterval? = nil) {
        guard !isStartupSequenceRunning, !isRenderingPausedForVisibility, !isDragging, !isRewarding, !isManualPerformance else { return }
        behaviorTimer?.invalidate()
        currentBehavior = nil

        let nextDelay = delay ?? TimeInterval.random(in: PetAutonomousBehaviorConfig.idleGapRange)
        PetDebugLog.write("Scheduling next daily behavior after \(String(format: "%.2f", nextDelay))s")
        let timer = Timer(timeInterval: nextDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performNextAutonomousBehavior()
            }
        }
        behaviorTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func performNextAutonomousBehavior() {
        guard !isRenderingPausedForVisibility, !isDragging, !isRewarding, !isManualPerformance else { return }
        let behavior = chooseNextBehavior()
        lastDailyBehavior = behavior
        currentBehavior = behavior
        PetDebugLog.write("Starting daily behavior \(behavior.rawValue)")

        switch behavior {
        case .walk:
            performDailyWalk()
        case .sniff:
            performDailySniff()
        default:
            performDailyStationaryBehavior(behavior)
        }
    }

    private func performDailySniff() {
        performSniffWalk { [weak self] in
            self?.finishDailySniff()
        }
    }

    private func finishDailySniff() {
        guard !isRenderingPausedForVisibility, !isDragging, !isRewarding, !isManualPerformance else { return }
        if Double.random(in: 0..<1) < PetAutonomousBehaviorConfig.sniffPeeChance {
            performAutonomousPee()
            return
        }
        finishAutonomousBehavior()
    }

    // Plays the looping sniff animation while the window drifts slowly forward.
    // Shared by the autonomous and manual sniff paths; the long sniff hold spread
    // over a short distance produces the deliberately slow forward creep.
    private func performSniffWalk(completion: @escaping () -> Void) {
        guard !isRenderingPausedForVisibility, !isDragging, !isRewarding,
              let screen = window.screen ?? NSScreen.main else {
            completion()
            return
        }
        movementTimer?.invalidate()

        let band = roamingBand(on: screen)
        let start = window.frame.origin
        let horizontalStride = CGFloat(Double.random(in: PetAutonomousBehaviorConfig.sniffWalkDistanceRange)) * roamDirection
        roamDirection *= -1
        let destination = clamp(
            CGPoint(x: start.x + horizontalStride, y: start.y),
            in: band
        )
        let duration = TimeInterval.random(in: PetAutonomousBehaviorConfig.sniffHoldRange)

        if abs(destination.x - start.x) >= 1 {
            scene.faceRight(destination.x >= start.x)
        }
        scene.play(.sniff)
        animateWindow(from: start, to: destination, duration: duration, completion: completion)
    }

    private func performDailyWalk() {
        guard !isRenderingPausedForVisibility, !isDragging, !isRewarding, !isManualPerformance, let screen = window.screen ?? NSScreen.main else { return }
        movementTimer?.invalidate()

        let band = roamingBand(on: screen)
        let start = window.frame.origin
        let horizontalStride = CGFloat(Double.random(in: PetAutonomousBehaviorConfig.walkDistanceRange)) * roamDirection
        roamDirection *= -1
        let destination = clamp(
            CGPoint(
                x: start.x + horizontalStride,
                y: start.y + CGFloat(Double.random(in: PetAutonomousBehaviorConfig.walkVerticalDriftRange))
            ),
            in: band
        )

        guard hypot(destination.x - start.x, destination.y - start.y) > CGFloat(PetAutonomousBehaviorConfig.minimumWalkDistance) else {
            finishAutonomousBehavior()
            return
        }

        scene.faceRight(destination.x >= start.x)
        let animationDuration = scene.animationDuration(for: .walk)
        let moveDuration = max(animationDuration, 0.1)
        scene.playOneCycle(.walk) { [weak self] in
            self?.finishAutonomousBehavior()
        }
        animateWindow(
            from: start,
            to: destination,
            duration: moveDuration
        ) { }
    }

    private func performDailyStationaryBehavior(_ behavior: PetAutonomousBehaviorKind) {
        guard !isRenderingPausedForVisibility, !isDragging, !isRewarding, !isManualPerformance else { return }

        let animationState = animationState(for: behavior)
        scene.playOneCycle(animationState) { [weak self] in
            self?.finishAutonomousBehavior()
        }
    }

    private func finishAutonomousBehavior() {
        guard !isRenderingPausedForVisibility, !isDragging, !isRewarding, !isManualPerformance else { return }
        currentBehavior = nil
        movementTimer?.invalidate()
        movementTimer = nil
        if lastDailyBehavior == .walk {
            scene.forcePlay(.idle)
        }
        let stayDuration = TimeInterval.random(in: PetAutonomousBehaviorConfig.holdRange(for: lastDailyBehavior ?? .idle))
        PetDebugLog.write("Daily behavior complete; staying \(String(format: "%.2f", stayDuration))s")
        scheduleNextBehavior(after: stayDuration)
    }

    private func performAutonomousPee() {
        guard !isRenderingPausedForVisibility, !isDragging, !isRewarding, !isManualPerformance else { return }
        currentBehavior = .pee
        lastDailyBehavior = .pee
        movementTimer?.invalidate()
        movementTimer = nil
        PetDebugLog.write("Starting daily behavior pee")
        playPeeAnimation(isManual: false)
    }

    private func interruptAutonomousBehavior(playIdle: Bool) {
        abortMouseAttention()
        behaviorTimer?.invalidate()
        behaviorTimer = nil
        manualPerformanceTimers.forEach { $0.invalidate() }
        manualPerformanceTimers.removeAll()
        movementTimer?.invalidate()
        movementTimer = nil
        currentBehavior = nil
        isManualPerformance = false
        currentManualPerformance = nil
        if playIdle {
            scene.play(restingStateForCurrentMood())
        }
    }

    // MARK: - Mouse Attention ("鼠标吸引")

    // Global + local mouse-move monitors. .mouseMoved needs no Accessibility
    // permission (unlike keyboard taps); handlers are delivered on the main thread.
    private func setupMouseAttentionMonitors() {
        guard globalMouseMonitor == nil, localMouseMonitor == nil else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMousePoint(NSEvent.mouseLocation, at: ProcessInfo.processInfo.systemUptime)
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleMousePoint(NSEvent.mouseLocation, at: ProcessInfo.processInfo.systemUptime)
            }
            return event
        }
    }

    // Approximate the dog's on-screen centre (lower-middle of the window).
    private func petScreenPoint() -> CGPoint {
        let frame = window.frame
        return CGPoint(x: frame.midX, y: frame.minY + 80)
    }

    private var canStartMouseAttention: Bool {
        guard !isAttendingMouse, !isDragging, !isRewarding, !isManualPerformance,
              !isRenderingPausedForVisibility, !isStartupSequenceRunning,
              movementTimer == nil,
              Date() >= mouseAttentionCooldownUntil
        else { return false }
        // Never disturb sleeping / lying / listless rest.
        switch currentBehavior {
        case .sleep, .lieDown, .listless:
            return false
        default:
            return true
        }
    }

    // While an attention sequence is mid-flight, a drag/reward/manual action takes over.
    private var canContinueAttention: Bool {
        !isDragging && !isRewarding && !isManualPerformance && !isRenderingPausedForVisibility
    }

    private func handleMousePoint(_ point: CGPoint, at time: TimeInterval) {
        defer {
            lastMouseScreenPoint = point
            lastMouseSampleTime = time
        }
        guard let last = lastMouseScreenPoint else { return }
        let dt = time - lastMouseSampleTime
        guard dt > MouseAttentionConfig.sampleMinInterval, dt < MouseAttentionConfig.sampleMaxGap else { return }

        let velocity = CGFloat(hypot(point.x - last.x, point.y - last.y)) / CGFloat(dt)
        let petPoint = petScreenPoint()
        let distance = CGFloat(hypot(point.x - petPoint.x, point.y - petPoint.y))
        lastMouseVelocity = velocity
        lastMouseDistanceToPet = distance

        guard canStartMouseAttention else { return }
        if distance < MouseAttentionConfig.triggerRadius, velocity > MouseAttentionConfig.triggerVelocity {
            beginMouseAttention(towardRight: point.x >= petPoint.x)
        }
    }

    // Phase 1 — notice & glance toward the cursor; the current animation keeps
    // playing (we only turn to face it, no interrupting gesture yet).
    private func beginMouseAttention(towardRight: Bool) {
        isAttendingMouse = true
        behaviorTimer?.invalidate()
        behaviorTimer = nil
        currentBehavior = nil
        PetDebugLog.write("MouseAttention phase1 look dist=\(Int(lastMouseDistanceToPet)) vel=\(Int(lastMouseVelocity))")

        scene.faceRight(towardRight)
        attentionStepsRemaining = Int.random(in: MouseAttentionConfig.followStepsRange)
        scheduleAttention(after: PetAutonomousBehaviorConfig.manualPerformanceStepGap) { [weak self] in
            self?.mouseAttentionPhase3()
        }
    }

    // Phase 2 — if the cursor lingered nearby, cock the head toward it (body stays put).
    private func mouseAttentionPhase2() {
        guard isAttendingMouse, canContinueAttention else { abortMouseAttention(); return }

        let petPoint = petScreenPoint()
        let near = lastMouseDistanceToPet < MouseAttentionConfig.triggerRadius
        guard near else {
            mouseAttentionLoseInterest() // cursor already gone — just settle back
            return
        }

        let towardRight = (lastMouseScreenPoint?.x ?? petPoint.x) >= petPoint.x
        scene.faceRight(towardRight)
        PetDebugLog.write("MouseAttention phase2 head-turn")
        scheduleAttention(after: PetAutonomousBehaviorConfig.manualPerformanceStepGap) { [weak self] in
            self?.mouseAttentionPhase3()
        }
    }

    // Phase 3 — rarely, a quick curious chase. "咦? → 跑两步 → 算了".
    private func mouseAttentionPhase3() {
        guard isAttendingMouse, canContinueAttention else { abortMouseAttention(); return }

        let wantsChase = attentionStepsRemaining > 0
            && lastMouseDistanceToPet < MouseAttentionConfig.followGiveUpRadius
        guard wantsChase, let screen = window.screen ?? NSScreen.main else {
            mouseAttentionLoseInterest()
            return
        }

        let petPoint = petScreenPoint()
        let dirRight = (lastMouseScreenPoint?.x ?? petPoint.x) >= petPoint.x
        let direction: CGFloat = dirRight ? 1 : -1
        let cursorGap = max(lastMouseDistanceToPet - MouseAttentionConfig.followStopGap, 0)
        let stride = min(MouseAttentionConfig.followMaxStepDistance, cursorGap)
        let band = roamingBand(on: screen)
        let start = window.frame.origin
        let destination = clamp(CGPoint(x: start.x + direction * stride, y: start.y), in: band)
        guard abs(destination.x - start.x) >= MouseAttentionConfig.followMinStep else {
            mouseAttentionLoseInterest()
            return
        }

        scene.faceRight(dirRight)
        scene.play(.run)
        PetDebugLog.write("MouseAttention phase3 curious-chase \(Int(destination.x - start.x))px")
        attentionStepsRemaining -= 1
        let distance = Double(abs(destination.x - start.x))
        let speed = Double(MouseAttentionConfig.followSpeedPointsPerSecond)
        animateWindow(
            from: start,
            to: destination,
            duration: max(distance / speed, 0.2)
        ) { [weak self] in
            guard let self else { return }
            if self.attentionStepsRemaining > 0 {
                self.scheduleAttention(after: PetAutonomousBehaviorConfig.manualPerformanceStepGap) { [weak self] in
                    self?.mouseAttentionPhase3()
                }
            } else {
                self.mouseAttentionLoseInterest()
            }
        }
    }

    // Phase 4 — lose interest with a small casual beat, then hand back to autonomous.
    private func mouseAttentionLoseInterest() {
        guard isAttendingMouse else { return }
        guard canContinueAttention else { abortMouseAttention(); return }

        let pick = [PetAnimationState.sitFront, .stretch, .sniff, .lookFront].randomElement() ?? .idle
        PetDebugLog.write("MouseAttention phase4 lose-interest -> \(pick.rawValue)")
        scene.play(pick)
        let hold = max(scene.animationDuration(for: pick), 0.6)
        scheduleAttention(after: hold) { [weak self] in
            self?.endMouseAttention()
        }
    }

    private func endMouseAttention() {
        clearAttentionState()
        guard canContinueAttention else { return }
        scene.play(restingStateForCurrentMood())
        scheduleNextBehavior(after: TimeInterval.random(in: PetAutonomousBehaviorConfig.idleGapRange))
    }

    // Hard stop used when a higher-priority action (drag/reward/reminder/manual)
    // takes over. That action owns resuming autonomous behavior, so we don't.
    private func abortMouseAttention() {
        guard isAttendingMouse else { return }
        clearAttentionState()
        PetDebugLog.write("MouseAttention aborted")
    }

    private func clearAttentionState() {
        isAttendingMouse = false
        attentionTimers.forEach { $0.invalidate() }
        attentionTimers.removeAll()
        attentionStepsRemaining = 0
        mouseAttentionCooldownUntil = Date().addingTimeInterval(
            TimeInterval.random(in: MouseAttentionConfig.cooldownRange)
        )
    }

    private func scheduleAttention(after delay: TimeInterval, _ block: @escaping () -> Void) {
        let timer = Timer(timeInterval: max(delay, 0.01), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isAttendingMouse else { return }
                block()
            }
        }
        attentionTimers.append(timer)
        RunLoop.main.add(timer, forMode: .common)
    }

    private func chooseNextBehavior() -> PetAutonomousBehaviorKind {
        let table = PetAutonomousBehaviorConfig.dailyWeights.filter { $0.kind != lastDailyBehavior }
        let totalWeight = table.reduce(0) { $0 + max($1.weight, 0) }
        guard totalWeight > 0 else { return .idle }

        var roll = Double.random(in: 0..<totalWeight)
        for choice in table {
            roll -= max(choice.weight, 0)
            if roll <= 0 {
                return choice.kind
            }
        }
        return table.last?.kind ?? .idle
    }

    private func startStartupSequence(entryPlan: EntryAnimationPlan?) {
        guard !hasPlayedStartupSequence else { return }
        hasPlayedStartupSequence = true
        isStartupSequenceRunning = true
        PetDebugLog.write("Startup sequence started")

        if let entryPlan {
            startEntryAnimation(entryPlan)
        } else {
            playStartupStretch()
        }
    }

    private func playStartupStretch() {
        guard !isDragging, !isRewarding else { return }
        PetDebugLog.write("Startup sequence step: stretch")
        scene.playOneCycle(.stretch) { [weak self] in
            self?.playStartupWalk()
        }
    }

    private func playStartupWalk() {
        guard !isDragging, !isRewarding, let screen = window.screen ?? NSScreen.main else { return }
        PetDebugLog.write("Startup sequence step: walk")
        let band = roamingBand(on: screen)
        let start = window.frame.origin
        let destination = clamp(
            CGPoint(x: start.x - 72, y: start.y),
            in: band
        )
        scene.faceRight(destination.x >= start.x)
        scene.playOneCycle(.walk) { [weak self] in
            PetDebugLog.write("Startup sequence complete")
            self?.isStartupSequenceRunning = false
            self?.scheduleNextBehavior()
        }
        animateWindow(
            from: start,
            to: destination,
            duration: max(scene.animationDuration(for: .walk), 0.1)
        ) { }
    }

    private func behaviorWeights() -> [PetAutonomousBehaviorConfig.WeightedChoice] {
        if isNightTime() {
            return PetAutonomousBehaviorConfig.nightWeights
        }
        if petStateEngine.mood >= 70 {
            return PetAutonomousBehaviorConfig.happyWeights
        }
        if petStateEngine.mood < 40 {
            return PetAutonomousBehaviorConfig.lowMoodWeights
        }
        return PetAutonomousBehaviorConfig.calmWeights
    }

    private func isNightTime(date: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= PetAutonomousBehaviorConfig.nightStartHour || hour < PetAutonomousBehaviorConfig.nightEndHour
    }

    private func restingStateForCurrentMood() -> PetAnimationState {
        if isNightTime() {
            return .sleep
        }
        if petStateEngine.mood < 40 {
            return .sleep
        }
        return .lieDown
    }

    private func animationState(for behavior: PetAutonomousBehaviorKind) -> PetAnimationState {
        switch behavior {
        case .idle:
            .idle
        case .walk:
            .walk
        case .sit:
            .sitFront
        case .sniff:
            .sniff
        case .yawn:
            .lookFront
        case .stretch:
            .stretch
        case .shake:
            .shake
        case .scratch:
            .scratch
        case .lieDown:
            .lieDown
        case .sleep:
            .sleep
        case .listless:
            .listless
        case .pee:
            .pee
        }
    }

    private func animateWindow(from start: CGPoint, to destination: CGPoint, duration: TimeInterval) {
        animateWindow(from: start, to: destination, duration: duration) { [weak self] in
            self?.finishAutonomousBehavior()
        }
    }

    private func animateWindow(
        from start: CGPoint,
        to destination: CGPoint,
        duration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        let startedAt = Date()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else {
                    timer.invalidate()
                    return
                }

                if self.isDragging || self.isRewarding {
                    timer.invalidate()
                    return
                }

                let elapsed = Date().timeIntervalSince(startedAt)
                let progress = min(max(elapsed / duration, 0), 1)
                let eased = 0.5 - cos(progress * .pi) / 2
                self.window.setFrameOrigin(CGPoint(
                    x: start.x + (destination.x - start.x) * eased,
                    y: start.y + (destination.y - start.y) * eased
                ))
                self.updateThoughtBubblePosition()

                if progress >= 1 {
                    timer.invalidate()
                    self.movementTimer = nil
                    completion()
                }
            }
        }

        movementTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startManualPerformance(_ kind: PetManualPerformanceKind) {
        guard !isRenderingPausedForVisibility, !isDragging, !isRewarding else { return }
        interruptAutonomousBehavior(playIdle: false)
        isManualPerformance = true
        currentManualPerformance = kind
        PetDebugLog.write("Manual performance \(kind)")

        switch kind {
        case .stretch:
            performManualOneShot(.stretch)
        case .walk:
            beginManualWalkingSession(until: Date().addingTimeInterval(manualPerformanceDuration()))
        case .idle:
            performManualStationary(.idle)
        case .sleep:
            performManualStationary(.sleep)
        case .sideLie:
            performManualSideLie()
        case .pee:
            performManualPee()
        case .sit:
            performManualStationary(.sitFront)
        case .happy:
            performManualOneShot(.happy)
        case .roam:
            beginManualWalkingSession(until: Date().addingTimeInterval(manualPerformanceDuration()))
        case .sleepy:
            performManualSleepy()
        case .sniff:
            performManualSniff(until: Date().addingTimeInterval(manualPerformanceDuration()))
        case .shake:
            performManualStationary(.shake)
        case .scratch:
            performManualStationary(.scratch)
        }
    }

    private func performManualOneShot(_ state: PetAnimationState) {
        let duration = max(scene.animationDuration(for: state), 0.8)
        scene.play(state)
        scheduleManualFinish(after: duration + TimeInterval.random(in: PetAutonomousBehaviorConfig.idleGapRange))
    }

    // Menu "跑进来": dash the real window across most of the visible screen.
    // The startup entry animation (makeEntryAnimationPlan/startEntryAnimation)
    // is intentionally separate and untouched.
    private func performManualRun() {
        guard isManualPerformance, !isRewarding, !isDragging, let screen = window.screen ?? NSScreen.main else {
            performManualOneShot(.run)
            return
        }

        let visible = screen.visibleFrame
        let frame = window.frame
        let safeInset: CGFloat = 32
        let safeLeftX = visible.minX + safeInset
        let safeRightX = max(safeLeftX, visible.maxX - frame.width - safeInset)
        guard abs(safeRightX - safeLeftX) >= 1 else {
            performManualOneShot(.run)
            return
        }

        let startFromLeft = frame.midX > visible.midX
        let startOrigin = CGPoint(
            x: startFromLeft ? visible.minX - frame.width - safeInset : visible.maxX + safeInset,
            y: frame.origin.y
        )
        let targetOrigin = CGPoint(
            x: startFromLeft ? safeRightX : safeLeftX,
            y: frame.origin.y
        )

        PetDebugLog.write("RUN IN START")
        PetDebugLog.write("RUN IN start origin \(startOrigin)")
        PetDebugLog.write("RUN IN target origin \(targetOrigin)")
        window.setFrameOrigin(startOrigin)
        updateThoughtBubblePosition()
        scene.faceRight(targetOrigin.x >= startOrigin.x)
        scene.play(.run)
        PetDebugLog.write("RUN IN animation state used \(scene.currentAnimationName ?? "unknown")")

        let distance = Double(abs(targetOrigin.x - startOrigin.x))
        let speed = Double(PetAutonomousBehaviorConfig.manualRunSpeedPointsPerSecond)
        let duration = max(distance / speed, 0.8)
        animateWindow(from: startOrigin, to: targetOrigin, duration: duration) { [weak self] in
            guard let self else { return }
            PetDebugLog.write("RUN IN final origin \(self.window.frame.origin)")
            self.finishManualRunIn()
        }
    }

    private func finishManualRunIn() {
        guard isManualPerformance, !isRewarding, !isDragging else { return }
        manualPerformanceTimers.forEach { $0.invalidate() }
        manualPerformanceTimers.removeAll()
        isManualPerformance = false
        currentBehavior = nil
        movementTimer?.invalidate()
        movementTimer = nil
        skView.isHidden = false
        skView.alphaValue = 1
        skView.layer?.backgroundColor = NSColor.clear.cgColor
        skView.layer?.isOpaque = false
        window.alphaValue = 1
        scene.forcePlay(.idle)
        PetDebugLog.write("RUN IN restored idle state \(scene.currentAnimationName ?? "unknown")")
        scheduleNextBehavior()
    }

    private func performManualStationary(_ state: PetAnimationState) {
        scene.play(state)
        scheduleManualFinish(after: manualPerformanceDuration())
    }

    private func performManualSideLie() {
        scene.forcePlay(.lieDown)
        scheduleManualFinish(after: PetAutonomousBehaviorConfig.manualSideLieHoldDuration)
    }

    private func performManualPee() {
        movementTimer?.invalidate()
        movementTimer = nil
        playPeeAnimation(isManual: true)
    }

    private func performManualSleepy() {
        scene.play(.stretch)
        let stretchDuration = max(scene.animationDuration(for: .stretch), 0.8)
        let lieDownAt = stretchDuration + PetAutonomousBehaviorConfig.manualPerformanceStepGap
        let sleepAt = lieDownAt + PetAutonomousBehaviorConfig.manualSleepLieDownHold
        let totalDuration = max(manualPerformanceDuration(), sleepAt + 4)

        let lieDownTimer = Timer(timeInterval: lieDownAt, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isManualPerformance, !self.isRewarding, !self.isDragging else { return }
                self.scene.play(.lieDown)
            }
        }
        registerManualTimer(lieDownTimer)

        let sleepTimer = Timer(timeInterval: sleepAt, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isManualPerformance, !self.isRewarding, !self.isDragging else { return }
                self.scene.play(.sleep)
            }
        }
        registerManualTimer(sleepTimer)

        let finishTimer = Timer(timeInterval: totalDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.finishManualPerformance(didSleep: true)
            }
        }
        registerManualTimer(finishTimer)
    }

    private func beginManualWalkingSession(until deadline: Date) {
        guard isManualPerformance, !isRewarding, !isDragging else { return }
        scene.play(.walk)
        performManualRoam(until: deadline)
    }

    private func performManualRoam(until deadline: Date) {
        guard isManualPerformance, !isRewarding, !isDragging, let screen = window.screen ?? NSScreen.main else { return }
        if Date() >= deadline {
            finishManualWalkingSession()
            return
        }

        let band = roamingBand(on: screen)
        let start = window.frame.origin
        let horizontalStride = CGFloat(Double.random(in: PetAutonomousBehaviorConfig.walkDistanceRange)) * roamDirection
        roamDirection *= -1
        let destination = clamp(
            CGPoint(
                x: start.x + horizontalStride,
                y: start.y + CGFloat(Double.random(in: PetAutonomousBehaviorConfig.walkVerticalDriftRange))
            ),
            in: band
        )

        guard hypot(destination.x - start.x, destination.y - start.y) > CGFloat(PetAutonomousBehaviorConfig.minimumWalkDistance) else {
            scheduleManualRoamStep(until: deadline)
            return
        }

        scene.faceRight(destination.x >= start.x)
        animateWindow(
            from: start,
            to: destination,
            duration: TimeInterval.random(in: PetAutonomousBehaviorConfig.walkDurationRange)
        ) { [weak self] in
            self?.scheduleManualRoamStep(until: deadline)
        }
    }

    private func performManualSniff(until deadline: Date) {
        guard isManualPerformance, !isRewarding, !isDragging else { return }
        if Date() >= deadline {
            finishManualPerformance()
            return
        }

        performSniffWalk { [weak self] in
            self?.scheduleManualSniffStep(until: deadline)
        }
    }

    private func scheduleManualSniffStep(until deadline: Date) {
        guard isManualPerformance, !isRewarding, !isDragging else { return }
        let timer = Timer(timeInterval: PetAutonomousBehaviorConfig.manualPerformanceStepGap, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performManualSniff(until: deadline)
            }
        }
        behaviorTimer?.invalidate()
        behaviorTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func scheduleManualRoamStep(until deadline: Date) {
        guard isManualPerformance, !isRewarding, !isDragging else { return }
        let timer = Timer(timeInterval: PetAutonomousBehaviorConfig.manualPerformanceStepGap, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performManualRoam(until: deadline)
            }
        }
        behaviorTimer?.invalidate()
        behaviorTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func finishManualWalkingSession() {
        guard isManualPerformance, !isRewarding, !isDragging else { return }
        manualPerformanceTimers.forEach { $0.invalidate() }
        manualPerformanceTimers.removeAll()
        isManualPerformance = false
        currentManualPerformance = nil
        currentBehavior = nil
        movementTimer?.invalidate()
        movementTimer = nil
        scene.forcePlay(.idle)
        scheduleNextBehavior()
    }

    private func scheduleManualFinish(after delay: TimeInterval) {
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.finishManualPerformance()
            }
        }
        behaviorTimer?.invalidate()
        behaviorTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func playPeeAnimation(isManual: Bool) {
        let animationDuration = scene.animationDuration(for: .pee)
        let holdDuration = max(PetAutonomousBehaviorConfig.peeHoldDuration - animationDuration, 0)
        scene.playOneCycle(
            .pee,
            timePerFrame: PetAutonomousBehaviorConfig.timePerFrame(for: .pee),
            holdDuration: holdDuration
        ) { [weak self] in
            self?.finishPee(isManual: isManual)
        }
    }

    private func finishPee(isManual: Bool) {
        guard !isRewarding, !isDragging else { return }
        behaviorTimer?.invalidate()
        behaviorTimer = nil
        movementTimer?.invalidate()
        movementTimer = nil
        scene.forcePlay(.idle)

        if isManual {
            isManualPerformance = false
            currentManualPerformance = nil
        }
        currentBehavior = nil
        scheduleNextBehavior()
    }

    private func finishManualPerformance(didSleep: Bool = false) {
        guard isManualPerformance, !isRewarding, !isDragging else { return }
        manualPerformanceTimers.forEach { $0.invalidate() }
        manualPerformanceTimers.removeAll()
        isManualPerformance = false
        let finishingManualPerformance = currentManualPerformance
        currentManualPerformance = nil
        currentBehavior = nil
        movementTimer?.invalidate()
        movementTimer = nil

        if didSleep {
            let duration = max(
                TimeInterval.random(in: PetAutonomousBehaviorConfig.stretchHoldRange),
                scene.animationDuration(for: .stretch)
            )
            scene.play(.stretch)
            scheduleNextBehavior(after: duration + TimeInterval.random(in: PetAutonomousBehaviorConfig.idleGapRange))
            return
        }

        if finishingManualPerformance == .walk || finishingManualPerformance == .roam || finishingManualPerformance == .sideLie {
            scene.forcePlay(.idle)
            scheduleNextBehavior()
            return
        }

        scene.play(restingStateForCurrentMood())
        scheduleNextBehavior()
    }

    private func manualPerformanceDuration() -> TimeInterval {
        TimeInterval.random(in: PetAutonomousBehaviorConfig.manualPerformanceDurationRange)
    }

    private func registerManualTimer(_ timer: Timer) {
        manualPerformanceTimers.append(timer)
        RunLoop.main.add(timer, forMode: .common)
    }

    private func roamingBand(on screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame.insetBy(
            dx: Self.roamingHorizontalPadding,
            dy: 0
        )
        let lowerBandHeight = max(visible.height * Self.lowerScreenRoamingRatio, window.frame.height + 24)
        let minY = visible.minY + Self.dockSafeBottomPadding
        let maxWindowOriginY = max(minY, visible.minY + lowerBandHeight - window.frame.height)
        let maxWindowOriginX = max(visible.minX, visible.maxX - window.frame.width)

        return CGRect(
            x: visible.minX,
            y: minY,
            width: max(maxWindowOriginX - visible.minX, 0),
            height: max(maxWindowOriginY - minY, 0)
        )
    }

    private func clamp(_ point: CGPoint, in band: CGRect) -> CGPoint {
        clamp(
            point,
            minX: band.minX,
            maxX: band.maxX,
            minY: band.minY,
            maxY: band.maxY
        )
    }

    private func clamp(_ point: CGPoint, minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) -> CGPoint {
        CGPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, minY), maxY)
        )
    }

    private func configurePetStateCallbacks() {
        petStateEngine.onMoodStateChange = { [weak self] state in
            guard let self,
                  !self.isStartupSequenceRunning,
                  !self.isRewarding,
                  !self.isDragging,
                  !self.isManualPerformance,
                  self.currentBehavior == nil,
                  self.behaviorTimer == nil
            else { return }
            if state == .happy, self.behaviorTimer != nil {
                return
            }
            self.scene.applyMoodState(state)
        }

        reminderService.onPetBubble = { [weak self] message in
            self?.showReminderBubble(message)
        }
        reminderService.onPetReminder = { [weak self] schedule in
            self?.performReminder(schedule)
        }
    }

    private func performReward(kind: PetRewardKind) {
        isRewarding = true
        interruptAutonomousBehavior(playIdle: false)
        let startedAt = Date()
        PetDebugLog.write("Reward feedback \(kind) started")
        scene.performReward(kind) { [weak self] in
            guard let self else { return }
            let elapsed = Date().timeIntervalSince(startedAt)
            PetDebugLog.write("Reward feedback \(kind) finished after \(String(format: "%.2f", elapsed))s")
            self.isRewarding = false
            self.scene.applyMoodState(self.petStateEngine.visualState)
            self.startAutonomousBehavior()
        }
    }

    private func runRewardSmokeTest(kind: PetRewardKind, completion: @escaping () -> Void) {
        isRewarding = true
        interruptAutonomousBehavior(playIdle: false)
        let startedAt = Date()
        PetDebugLog.write("Reward smoke \(kind) started")
        scene.performReward(kind) { [weak self] in
            guard let self else { return }
            let elapsed = Date().timeIntervalSince(startedAt)
            PetDebugLog.write("Reward smoke \(kind) finished after \(String(format: "%.2f", elapsed))s")
            self.isRewarding = false
            completion()
        }
    }

    private func showReminderBubble(_ message: String) {
        interruptAutonomousBehavior(playIdle: true)
        scene.showBubble(message)
        scheduleNextBehavior(after: PetAutonomousBehaviorConfig.reminderPauseBeforeNextBehavior)
    }

    private func performReminder(_ schedule: ScheduleItem) {
        performReminder(schedule, completion: nil)
    }

    private func performReminder(_ schedule: ScheduleItem, completion: (() -> Void)?) {
        isRewarding = true
        interruptAutonomousBehavior(playIdle: false)
        scene.showBubble(schedule.title)
        PetDebugLog.write("Pet reminder action started: \(schedule.title)")
        scene.performReward(ReminderTriggerConfig.reminderRewardKind) { [weak self] in
            guard let self else { return }
            PetDebugLog.write("Pet reminder action finished: \(schedule.title)")
            self.isRewarding = false
            self.startAutonomousBehavior()
            completion?()
        }
    }

    private func updateThoughtBubblePosition() {
        thoughtBubbleWindowController?.updatePosition(relativeTo: window)
    }

    private func startMousePassthroughUpdates() {
        mousePassthroughTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMousePassthrough()
            }
        }
        mousePassthroughTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        updateMousePassthrough()
    }

    private func updateMousePassthrough() {
        if isDragging {
            window.ignoresMouseEvents = false
            return
        }

        guard window.isVisible, !window.isMiniaturized, !skView.isHidden else {
            window.ignoresMouseEvents = true
            skView.setPetHovered(false)
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let windowFrame = window.frame
        guard windowFrame.contains(mouseLocation) else {
            window.ignoresMouseEvents = true
            skView.setPetHovered(false)
            return
        }

        let viewPoint = CGPoint(
            x: mouseLocation.x - windowFrame.minX,
            y: mouseLocation.y - windowFrame.minY
        )
        let hitsPet = skView.acceptsPetHit(at: viewPoint)
        if hitsPet, lastHitLoggedAnimationName != scene.currentAnimationName {
            lastHitLoggedAnimationName = scene.currentAnimationName
            PetDebugLog.write("Mouse hit pet body during \(scene.currentAnimationName ?? "unknown")")
        }
        window.ignoresMouseEvents = !hitsPet
        skView.setPetHovered(hitsPet)
    }

    private func configureVisibilityObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(windowVisibilityDidChange),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window
        )
        center.addObserver(
            self,
            selector: #selector(windowVisibilityDidChange),
            name: NSWindow.didMiniaturizeNotification,
            object: window
        )
        center.addObserver(
            self,
            selector: #selector(windowVisibilityDidChange),
            name: NSWindow.didDeminiaturizeNotification,
            object: window
        )
        center.addObserver(
            self,
            selector: #selector(windowVisibilityDidChange),
            name: NSWindow.didResizeNotification,
            object: window
        )
        center.addObserver(
            self,
            selector: #selector(windowVisibilityDidChange),
            name: NSApplication.didHideNotification,
            object: NSApp
        )
        center.addObserver(
            self,
            selector: #selector(windowVisibilityDidChange),
            name: NSApplication.didUnhideNotification,
            object: NSApp
        )
    }

    @objc private func windowVisibilityDidChange() {
        // Coalesce rapid occlusion-state changes that occur during the Space-switch
        // slide animation; without debouncing these fire multiple times in ~100 ms,
        // causing pause→resume cycles that reset the animation mid-play.
        visibilityUpdateWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.updateRenderingActivity()
        }
        visibilityUpdateWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func updateRenderingActivity() {
        validateDrawableSize()

        let hasDrawableSize = skView.bounds.width >= 1 && skView.bounds.height >= 1
        let isWindowDrawable = window.isVisible
            && !window.isMiniaturized
            && window.occlusionState.contains(.visible)
            && hasDrawableSize

        if isWindowDrawable {
            resumeRenderingIfNeeded()
            thoughtBubbleWindowController?.show(relativeTo: window)
        } else {
            pauseRenderingIfNeeded()
        }
    }

    private func pauseRenderingIfNeeded() {
        guard !isRenderingPausedForVisibility else { return }
        isRenderingPausedForVisibility = true
        // Reset entry flag so the next re-appear triggers a fresh entry animation.
        hasEnteredForCurrentVisibility = false
        behaviorTimer?.invalidate()
        behaviorTimer = nil
        manualPerformanceTimers.forEach { $0.invalidate() }
        manualPerformanceTimers.removeAll()
        currentBehavior = nil
        isManualPerformance = false
        movementTimer?.invalidate()
        movementTimer = nil
        skView.isHidden = true
        scene.isPaused = true
        skView.isPaused = true
    }

    private func resumeRenderingIfNeeded() {
        guard isRenderingPausedForVisibility else {
            skView.isPaused = false
            scene.isPaused = false
            skView.isHidden = false
            return
        }

        let shouldPlayEntry = !hasEnteredForCurrentVisibility
            && entryAnimationEnabled
            && !hasPlayedStartupSequence
            && !isDragging
            && !isRewarding
        let entryPlan = shouldPlayEntry ? makeEntryAnimationPlan() : nil

        isRenderingPausedForVisibility = false

        if shouldPlayEntry {
            hasEnteredForCurrentVisibility = true
            if let entryPlan {
                prepareEntryAnimation(entryPlan)
            }
        }

        // Unpausing scene/skView after entry preparation prevents the old resting
        // position from rendering for a frame before the off-screen start is applied.
        skView.isPaused = false
        scene.isPaused = false
        skView.isHidden = false

        guard !isDragging, !isRewarding else { return }

        // Entry path (first re-appear with animation enabled) vs. seamless resume path.
        // These are mutually exclusive: entry deliberately repositions the window and
        // replays run-in, while resume must NOT reset state (would cause the jitter bug).
        if shouldPlayEntry {
            if let entryPlan {
                startEntryAnimation(entryPlan)
            } else {
                // No screen available — fall back to normal schedule so nothing stalls.
                scheduleNextBehavior()
            }
        } else {
            // Seamless resume: SpriteKit already continues the frozen animation above.
            // Just re-attach behavior scheduling with the standard idle-gap interval.
            if behaviorTimer == nil, currentBehavior == nil {
                scheduleNextBehavior()
            }
        }
    }

    private func validateDrawableSize() {
        let minimumSize = CGSize(width: 1, height: 1)

        if window.frame.width < minimumSize.width || window.frame.height < minimumSize.height {
            window.setContentSize(CGSize(width: max(window.frame.width, 220), height: max(window.frame.height, 220)))
        }

        if skView.bounds.width < minimumSize.width || skView.bounds.height < minimumSize.height {
            skView.frame = NSRect(origin: .zero, size: CGSize(width: 220, height: 220))
        }

        if scene.size.width < minimumSize.width || scene.size.height < minimumSize.height {
            scene.size = CGSize(width: 220, height: 220)
        }
    }
}

extension PetWindowController: PetSceneDelegate {
    func petSceneDidRequestExit(_ scene: PetScene) {
        NSApp.terminate(nil)
    }

    func petScene(_ scene: PetScene, didRequestManualPerformance kind: PetManualPerformanceKind) {
        startManualPerformance(kind)
    }

    func petSceneDidDoubleClick(_ scene: PetScene) {
        PetDebugLog.write("Pet double-clicked; opening daily checklist")
        mainPanelWindowController?.show(relativeTo: window)
    }

    func petSceneDidBeginDrag(_ scene: PetScene) {
        isDragging = true
        isRewarding = false
        interruptAutonomousBehavior(playIdle: true)
        dragStartWindowOrigin = window.frame.origin
        dragStartMouseLocation = NSEvent.mouseLocation
    }

    func petSceneDidDrag(_ scene: PetScene) {
        let mouseLocation = NSEvent.mouseLocation
        let delta = CGPoint(
            x: mouseLocation.x - dragStartMouseLocation.x,
            y: mouseLocation.y - dragStartMouseLocation.y
        )
        window.setFrameOrigin(CGPoint(
            x: dragStartWindowOrigin.x + delta.x,
            y: dragStartWindowOrigin.y + delta.y
        ))
        updateThoughtBubblePosition()
    }

    func petSceneDidEndDrag(_ scene: PetScene) {
        isDragging = false
        startAutonomousBehavior()
    }
}

final class PassthroughSKView: SKView {
    override var isOpaque: Bool { false }

    var petHitRect = NSRect.zero
    var onHoverChanged: ((Bool) -> Void)?
    // Set by PetWindowController to perform per-pixel alpha testing.
    // Returns true iff the point lies on an opaque pixel of the current frame.
    var isOpaqueAtPoint: ((CGPoint) -> Bool)?
    private var trackingArea: NSTrackingArea?
    private var isPetHovered = false

    func acceptsPetHit(at point: NSPoint) -> Bool {
        guard petHitRect.contains(point) else { return false }
        return isOpaqueAtPoint?(point) != false
    }

    func acceptsPetBounds(at point: NSPoint) -> Bool {
        petHitRect.contains(point)
    }

    func setPetHovered(_ isHovered: Bool) {
        guard isPetHovered != isHovered else { return }
        isPetHovered = isHovered
        onHoverChanged?(isHovered)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard acceptsPetHit(at: point) else { return nil }
        return super.hitTest(point)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(NSSize(width: max(newSize.width, 1), height: max(newSize.height, 1)))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: petHitRect,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        self.trackingArea = trackingArea
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }
}

final class PetWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
