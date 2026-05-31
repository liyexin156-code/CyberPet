import AppKit
import Combine
import SwiftData
import SwiftUI

@MainActor
final class ThoughtBubbleWindowController: NSWindowController {
    private let visibilityState = ThoughtBubbleVisibilityState()
    private let hitRegion = ThoughtBubbleHitRegion(windowSize: ThoughtBubbleLayout.windowSize)
    private var cancellables: Set<AnyCancellable> = []
    private var mousePassthroughTimer: Timer?

    init(modelContainer: ModelContainer, petStateEngine: PetStateEngine) {
        let rootView = ThoughtBubbleRootView(visibilityState: visibilityState)
            .modelContainer(modelContainer)
            .environmentObject(petStateEngine)
        let hostingController = NSHostingController(rootView: rootView)
        let panel = ThoughtBubblePanel(
            contentRect: NSRect(origin: .zero, size: ThoughtBubbleLayout.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentViewController = hostingController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true

        super.init(window: panel)

        visibilityState.$isContentVisible
            .sink { [weak self] _ in
                self?.updateMousePassthrough()
            }
            .store(in: &cancellables)

        startMousePassthroughUpdates()
    }

    deinit {
        mousePassthroughTimer?.invalidate()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(relativeTo petWindow: NSWindow) {
        updatePosition(relativeTo: petWindow)
        window?.orderFrontRegardless()
    }

    func updatePosition(relativeTo petWindow: NSWindow) {
        guard let window, let screen = petWindow.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let size = ThoughtBubbleLayout.windowSize
        let proposedX = petWindow.frame.midX - size.width / 2
        let proposedY = petWindow.frame.maxY - ThoughtBubbleLayout.petTopOverlap
        let origin = CGPoint(
            x: min(max(proposedX, visible.minX), visible.maxX - size.width),
            y: min(max(proposedY, visible.minY), visible.maxY - size.height)
        )
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    func setPetHovered(_ isHovered: Bool) {
        visibilityState.isPetHovered = isHovered
    }

    private func startMousePassthroughUpdates() {
        mousePassthroughTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMousePassthrough()
            }
        }
        mousePassthroughTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        updateMousePassthrough()
    }

    private func updateMousePassthrough() {
        guard let window, window.isVisible, visibilityState.isContentVisible else {
            window?.ignoresMouseEvents = true
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        guard window.frame.contains(mouseLocation) else {
            window.ignoresMouseEvents = true
            return
        }

        let windowPoint = CGPoint(
            x: mouseLocation.x - window.frame.minX,
            y: mouseLocation.y - window.frame.minY
        )
        window.ignoresMouseEvents = !hitRegion.contains(windowPoint)
    }
}

struct ThoughtBubbleHitRegion {
    let windowSize: CGSize

    func contains(_ point: CGPoint) -> Bool {
        interactiveRect.contains(point)
    }

    private var interactiveRect: CGRect {
        CGRect(
            x: 24,
            y: 0,
            width: max(windowSize.width - 48, 1),
            height: min(windowSize.height, 132)
        )
    }
}

final class ThoughtBubblePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ThoughtBubbleVisibilityState: ObservableObject {
    @Published var isPetHovered = false
    @Published var isBubbleHovered = false
    @Published var isContentVisible = false
}

private struct ThoughtBubbleRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var petStateEngine: PetStateEngine
    @ObservedObject var visibilityState: ThoughtBubbleVisibilityState
    @AppStorage("thoughtBubbleAlwaysVisible") private var alwaysVisible = true

    @Query private var todayItems: [DailyTask]
    @Query(sort: \ScheduleItem.createdAt, order: .forward) private var schedules: [ScheduleItem]
    @State private var dismissedReminderIDs: Set<UUID> = []

    init(visibilityState: ThoughtBubbleVisibilityState, today: Date = Date()) {
        self.visibilityState = visibilityState
        let interval = Calendar.current.dateInterval(of: .day, for: today) ?? DateInterval(start: today, duration: 86_400)
        _todayItems = Query(
            filter: #Predicate<DailyTask> { task in
                task.date >= interval.start && task.date < interval.end
            },
            sort: \DailyTask.date,
            order: .forward
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if shouldShow {
                ThoughtBubbleClusterView(
                    visibleItems: visibleItems,
                    overflowCount: overflowCount,
                    showDoneBubble: showDoneBubble,
                    schedules: schedules,
                    onComplete: complete,
                    onDismissReminder: dismissReminder
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }
        }
        .frame(
            width: ThoughtBubbleLayout.windowSize.width,
            height: ThoughtBubbleLayout.windowSize.height,
            alignment: .bottom
        )
        .contentShape(Rectangle())
        .onHover { visibilityState.isBubbleHovered = $0 }
        .onAppear { visibilityState.isContentVisible = shouldShow }
        .onChange(of: shouldShow) { _, newValue in
            visibilityState.isContentVisible = newValue
        }
        .animation(.easeOut(duration: 0.18), value: shouldShow)
    }

    private var shouldShow: Bool {
        (alwaysVisible || visibilityState.isPetHovered || visibilityState.isBubbleHovered)
            && (!visibleItems.isEmpty || showDoneBubble)
    }

    private var unfinishedItems: [DailyTask] {
        todayItems.filter { item in
            if item.itemKind == .task {
                return !item.isCompleted
            }
            return !dismissedReminderIDs.contains(item.id)
        }
    }

    private var visibleItems: [DailyTask] {
        Array(unfinishedItems.prefix(4))
    }

    private var overflowCount: Int {
        max(unfinishedItems.count - visibleItems.count, 0)
    }

    private var showDoneBubble: Bool {
        let taskItems = todayItems.filter { $0.itemKind == .task }
        return !taskItems.isEmpty && unfinishedItems.isEmpty
    }

    private func complete(_ task: DailyTask) {
        guard task.itemKind == .task, !task.isCompleted else { return }
        task.isCompleted = true
        task.completedAt = Date()
        do {
            try modelContext.save()
            petStateEngine.completeTaskReward()
        } catch {
            assertionFailure("Failed to complete thought bubble task: \(error)")
        }
    }

    private func dismissReminder(_ item: DailyTask) {
        dismissedReminderIDs.insert(item.id)
    }
}

private struct ThoughtBubbleClusterView: View {
    let visibleItems: [DailyTask]
    let overflowCount: Int
    let showDoneBubble: Bool
    let schedules: [ScheduleItem]
    let onComplete: (DailyTask) -> Void
    let onDismissReminder: (DailyTask) -> Void

    var body: some View {
        VStack(spacing: ThoughtBubbleLayout.verticalSpacing) {
            if overflowCount > 0 {
                Text("+\(overflowCount)")
                    .font(PixelTheme.monoCaption.weight(.semibold))
                    .foregroundStyle(PixelTheme.cyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PixelTheme.panel.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: PixelTheme.radius)
                            .stroke(PixelTheme.cyan, lineWidth: 1)
                    )
                    .scaleEffect(ThoughtBubbleLayout.scale)
                    .offset(x: ThoughtBubbleLayout.overflowOffsetX)
                    .transition(.scale.combined(with: .opacity))
            }

            if showDoneBubble {
                ThoughtBubblePill(delay: 0, horizontalOffset: 0) {
                    Text("今天都照顾好啦～")
                        .font(PixelTheme.monoCaption.weight(.medium))
                        .foregroundStyle(PixelTheme.text)
                }
            } else {
                ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                    ThoughtBubblePill(delay: Double(index) * 0.24, horizontalOffset: horizontalOffset(for: index)) {
                        ThoughtBubbleItemView(
                            item: item,
                            reminderTimeText: reminderTimeText(for: item),
                            onComplete: { onComplete(item) },
                            onDismissReminder: { onDismissReminder(item) }
                        )
                    }
                }
            }

            ThoughtDotsView()
                .padding(.top, -6)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, ThoughtBubbleLayout.bottomPadding)
    }

    private func horizontalOffset(for index: Int) -> CGFloat {
        ThoughtBubbleLayout.bubbleOffsets[index % ThoughtBubbleLayout.bubbleOffsets.count]
    }

    private func reminderTimeText(for item: DailyTask) -> String? {
        guard item.itemKind == .reminder,
              let scheduleID = item.scheduleItemId,
              let schedule = schedules.first(where: { $0.id == scheduleID }),
              let reminderTime = schedule.reminderTime
        else { return nil }

        let hour = String(format: "%02d", reminderTime.hour ?? 0)
        let minute = String(format: "%02d", reminderTime.minute ?? 0)
        let second = String(format: "%02d", reminderTime.second ?? 0)
        return "\(hour):\(minute):\(second)"
    }
}

private struct ThoughtBubblePill<Content: View>: View {
    let delay: Double
    let horizontalOffset: CGFloat
    @ViewBuilder let content: Content

    @State private var appeared = false
    @State private var floatUp = false

    var body: some View {
        content
            .padding(.horizontal, ThoughtBubbleLayout.pillHorizontalPadding)
            .padding(.vertical, ThoughtBubbleLayout.pillVerticalPadding)
            .background(PixelTheme.panel.opacity(0.94))
            .overlay(
                RoundedRectangle(cornerRadius: PixelTheme.radius)
                    .stroke(PixelTheme.cyan, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PixelTheme.radius))
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .scaleEffect((appeared ? 1 : 0.88) * ThoughtBubbleLayout.scale)
            .offset(
                x: horizontalOffset,
                y: appeared
                    ? (floatUp ? -ThoughtBubbleLayout.pillFloatOffset : ThoughtBubbleLayout.pillFloatOffset)
                    : ThoughtBubbleLayout.pillInitialRiseOffset
            )
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.8).delay(delay)) {
                    appeared = true
                }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true).delay(delay + 0.36)) {
                    floatUp = true
                }
            }
    }
}

private struct ThoughtBubbleItemView: View {
    let item: DailyTask
    let reminderTimeText: String?
    let onComplete: () -> Void
    let onDismissReminder: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if item.itemKind == .task {
                Button(action: onComplete) {
                    Rectangle()
                        .fill(PixelTheme.screen)
                        .overlay(Rectangle().stroke(PixelTheme.cyan, lineWidth: 1))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .help("完成")
            } else {
                Image(systemName: "bell.fill")
                    .foregroundStyle(PixelTheme.amber)
                    .font(PixelTheme.monoCaption)
            }

            Text(item.title)
                .font(PixelTheme.monoCaption)
                .foregroundStyle(PixelTheme.text)
                .lineLimit(1)

            if let reminderTimeText {
                Text(reminderTimeText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(PixelTheme.secondaryText)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if item.itemKind == .reminder {
                onDismissReminder()
            }
        }
    }
}

private struct ThoughtDotsView: View {
    var body: some View {
        VStack(spacing: ThoughtBubbleLayout.dotSpacing) {
            ForEach(ThoughtBubbleLayout.dotSizes, id: \.self) { size in
                Rectangle()
                    .frame(width: size, height: size)
            }
        }
        .foregroundStyle(PixelTheme.panel.opacity(0.94))
        .overlay(
            VStack(spacing: ThoughtBubbleLayout.dotSpacing) {
                ForEach(ThoughtBubbleLayout.dotSizes, id: \.self) { size in
                    Rectangle()
                        .stroke(PixelTheme.cyan, lineWidth: 1)
                        .frame(width: size, height: size)
                }
            }
        )
        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
    }
}
