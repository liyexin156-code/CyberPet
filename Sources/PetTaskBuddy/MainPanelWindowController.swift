import AppKit
import SwiftData
import SwiftUI

@MainActor
final class MainPanelWindowController: NSWindowController {
    private let modelContainer: ModelContainer
    private let petStateEngine: PetStateEngine
    private let scheduleCoordinator: ScheduleCoordinator

    init(
        modelContainer: ModelContainer,
        petStateEngine: PetStateEngine,
        scheduleCoordinator: ScheduleCoordinator
    ) {
        self.modelContainer = modelContainer
        self.petStateEngine = petStateEngine
        self.scheduleCoordinator = scheduleCoordinator

        let rootView = MainPanelView()
            .modelContainer(modelContainer)
            .environmentObject(petStateEngine)
            .environmentObject(scheduleCoordinator)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "桌宠任务伙伴"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(relativeTo petWindow: NSWindow) {
        if let screen = petWindow.screen ?? NSScreen.main, let window {
            let visible = screen.visibleFrame
            let proposed = CGPoint(
                x: min(max(petWindow.frame.maxX + 12, visible.minX + 12), visible.maxX - window.frame.width - 12),
                y: min(max(petWindow.frame.midY - window.frame.height / 2, visible.minY + 12), visible.maxY - window.frame.height - 12)
            )
            window.setFrameOrigin(proposed)
        }

        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct MainPanelView: View {
    @State private var selectedTab: MainPanelTab = .today

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                ForEach(MainPanelTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 6) {
                            Text(tab.title)
                                .foregroundStyle(selectedTab == tab ? PixelTheme.cyan : PixelTheme.secondaryText)
                            Rectangle()
                                .fill(selectedTab == tab ? PixelTheme.cyan : Color.clear)
                                .frame(height: 2)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, PixelTheme.pagePadding)
            .padding(.top, 16)
            .padding(.bottom, 10)
            .background(PixelTheme.panel)

            Divider()
                .overlay(PixelTheme.borderMuted)

            Group {
                switch selectedTab {
                case .today:
                    TodayTaskView()
                case .schedule:
                    ScheduleListView()
                }
            }
        }
        .pixelPanel()
        .frame(minWidth: 380, minHeight: 580)
    }
}

enum MainPanelTab: String, CaseIterable, Identifiable {
    case today
    case schedule

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "今日"
        case .schedule: "日程"
        }
    }
}

struct TodayTaskView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var petStateEngine: PetStateEngine
    @AppStorage("thoughtBubbleAlwaysVisible") private var thoughtBubbleAlwaysVisible = true
    @Query private var tasks: [DailyTask]

    @State private var newTaskTitle = ""
    @State private var newTaskNote = ""

    init(today: Date = Date()) {
        let interval = Calendar.current.dateInterval(of: .day, for: today) ?? DateInterval(start: today, duration: 86_400)
        _tasks = Query(
            filter: #Predicate<DailyTask> { task in
                task.date >= interval.start && task.date < interval.end
            },
            sort: \DailyTask.date,
            order: .forward
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            thoughtBubbleSetting
            petStateSummary
            addTaskForm
            taskList
        }
        .padding(PixelTheme.pagePadding)
    }

    private var thoughtBubbleSetting: some View {
        Toggle("思考泡泡常驻显示", isOn: $thoughtBubbleAlwaysVisible)
            .toggleStyle(PixelToggleButtonStyle())
            .help("关闭后，悬停到狗狗时再显示思考泡泡")
    }

    private var petStateSummary: some View {
        VStack(spacing: 8) {
            MeterRow(title: "饱食度", value: petStateEngine.fullness)
            MeterRow(title: "心情", value: petStateEngine.mood)
        }
        .padding(12)
        .pixelCard()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("今天的小任务")
                .font(PixelTheme.monoTitle)
            Text("写下一个今天愿意照顾的小目标。")
                .font(PixelTheme.monoCaption)
                .foregroundStyle(PixelTheme.secondaryText)
        }
    }

    private var addTaskForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("添加一个小任务", text: $newTaskTitle)
                .textFieldStyle(PixelTextFieldStyle())
                .onSubmit(addTask)

            TextField("备注，可不填", text: $newTaskNote)
                .textFieldStyle(PixelTextFieldStyle())
                .onSubmit(addTask)

            HStack {
                Spacer()
                Button(action: addTask) {
                    Label("添加", systemImage: "plus")
                }
                .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(PixelPrimaryButtonStyle())
            }
        }
        .pixelCard()
    }

    private var taskList: some View {
        Group {
            if tasks.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "今天还很清爽",
                    systemImage: "checklist",
                    description: Text("先加一件很小、能开始的事就好。")
                )
                Spacer()
            } else {
                List {
                    ForEach(tasks) { task in
                        TaskRow(task: task, onDelete: { delete(task) })
                            .listRowBackground(PixelTheme.panel)
                            .listRowSeparatorTint(PixelTheme.borderMuted)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(PixelTheme.screen)
            }
        }
    }

    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let note = newTaskNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let today = Calendar.current.startOfDay(for: Date())
        modelContext.insert(DailyTask(
            date: today,
            title: title,
            note: note.isEmpty ? nil : note,
            source: .manual
        ))
        save()
        petStateEngine.refreshMoodFromCurrentTasks(allowLowering: true)

        newTaskTitle = ""
        newTaskNote = ""
    }

    private func delete(_ task: DailyTask) {
        modelContext.delete(task)
        save()
        petStateEngine.refreshMoodFromCurrentTasks(allowLowering: true)
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save tasks: \(error)")
        }
    }
}

struct TaskRow: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var petStateEngine: PetStateEngine
    @Bindable var task: DailyTask
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if task.itemKind == .task {
                Toggle(isOn: completionBinding) {
                    taskText
                }
                .toggleStyle(PixelSquareCheckboxStyle())
            } else {
                Image(systemName: "bell")
                    .foregroundStyle(PixelTheme.secondaryText)
                    .frame(width: 16)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    taskText
                    Text("提醒")
                        .font(.caption2)
                        .foregroundStyle(PixelTheme.secondaryText)
                }
            }

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(PixelTheme.pink)
            .help("删除任务")
        }
        .padding(.vertical, 4)
    }

    private var taskText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(task.title)
                .strikethrough(task.itemKind == .task && task.isCompleted)
                .foregroundStyle(task.isCompleted ? PixelTheme.secondaryText : PixelTheme.text)
            if let note = task.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(PixelTheme.secondaryText)
            }
        }
    }

    private var completionBinding: Binding<Bool> {
        Binding(
            get: { task.isCompleted },
            set: { isCompleted in
                guard task.itemKind == .task else { return }
                let wasCompleted = task.isCompleted
                task.isCompleted = isCompleted
                task.completedAt = isCompleted ? Date() : nil
                do {
                    try modelContext.save()
                    if isCompleted && !wasCompleted {
                        petStateEngine.completeTaskReward()
                    } else {
                        petStateEngine.refreshMoodFromCurrentTasks(allowLowering: true)
                    }
                } catch {
                    assertionFailure("Failed to save task completion: \(error)")
                }
            }
        )
    }
}

struct ScheduleListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var scheduleCoordinator: ScheduleCoordinator
    @Query(sort: \ScheduleItem.createdAt, order: .forward) private var schedules: [ScheduleItem]

    @State private var editingItem: ScheduleItem?
    @State private var title = ""
    @State private var note = ""
    @State private var kind: ScheduleItemKind = .task
    @State private var recurrenceType: RecurrenceType = .daily
    @State private var selectedWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var recurrenceDate = Date()
    @State private var yearlyRepeat = false
    @State private var hasReminderTime = false
    @State private var reminderHour = Calendar.current.component(.hour, from: Date())
    @State private var reminderMinute = Calendar.current.component(.minute, from: Date())
    @State private var reminderSecond = Calendar.current.component(.second, from: Date())
    @State private var intervalHours = 0
    @State private var intervalMinutes = 1
    @State private var intervalSeconds = 30
    @State private var intervalTotalSecondsText = "90"
    @State private var isActive = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PixelTheme.gap) {
                scheduleList
                editor
            }
            .padding(PixelTheme.pagePadding)
        }
        .scrollContentBackground(.hidden)
        .background(PixelTheme.screen)
    }

    private var scheduleList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("日程")
                    .font(PixelTheme.monoTitle)
                Spacer()
                Button(action: resetForm) {
                    Label("新建", systemImage: "plus")
                }
                .buttonStyle(PixelSecondaryButtonStyle())
                .help("新建日程")
            }

            if schedules.isEmpty {
                ContentUnavailableView(
                    "还没有固定日程",
                    systemImage: "calendar.badge.plus",
                    description: Text("把每天或每周会重复的小事放在这里。")
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(schedules) { item in
                        Button {
                            load(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: item.kind == .task ? "checklist" : "bell")
                                        .foregroundStyle(item.isActive ? PixelTheme.cyan : PixelTheme.secondaryText)
                                    Text(item.title)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                Text(summary(for: item))
                                    .font(PixelTheme.monoCaption)
                                    .foregroundStyle(PixelTheme.secondaryText)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(editingItem?.id == item.id ? PixelTheme.borderMuted : PixelTheme.panel)
                            .overlay(
                                RoundedRectangle(cornerRadius: PixelTheme.radius)
                                    .stroke(editingItem?.id == item.id ? PixelTheme.cyan : PixelTheme.borderMuted, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .pixelCard()
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editingItem == nil ? "新建日程" : "编辑日程")
                .font(PixelTheme.monoTitle)

            TextField("标题", text: $title)
                .textFieldStyle(PixelTextFieldStyle())

            TextField("备注，可不填", text: $note)
                .textFieldStyle(PixelTextFieldStyle())

            Picker("类型", selection: $kind) {
                ForEach(ScheduleItemKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Picker("规则", selection: $recurrenceType) {
                ForEach(RecurrenceType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)

            recurrenceControls

            if recurrenceType == .interval {
                IntervalSecondsInput(
                    hours: $intervalHours,
                    minutes: $intervalMinutes,
                    seconds: $intervalSeconds,
                    totalSecondsText: $intervalTotalSecondsText
                )
            } else {
                Toggle("启用提醒时间", isOn: $hasReminderTime)
                    .toggleStyle(PixelToggleButtonStyle())
                if hasReminderTime {
                    TimeOfDaySecondsInput(
                        hour: $reminderHour,
                        minute: $reminderMinute,
                        second: $reminderSecond
                    )
                }
            }

            Toggle("启用这条日程", isOn: $isActive)
                .toggleStyle(PixelToggleButtonStyle())

            HStack {
                Button(role: .destructive, action: deleteEditingItem) {
                    Label("删除", systemImage: "trash")
                }
                .disabled(editingItem == nil)
                .buttonStyle(PixelSecondaryButtonStyle())
                .foregroundStyle(PixelTheme.pink)

                Spacer()

                Button(action: save) {
                    Label(editingItem == nil ? "添加" : "保存", systemImage: "checkmark")
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(PixelPrimaryButtonStyle())
            }
        }
        .pixelCard()
    }

    @ViewBuilder
    private var recurrenceControls: some View {
        switch recurrenceType {
        case .interval:
            EmptyView()
        case .daily:
            EmptyView()
        case .weekly:
            VStack(alignment: .leading, spacing: 8) {
                Text("选择星期")
                    .font(PixelTheme.monoCaption.weight(.medium))
                    .foregroundStyle(PixelTheme.secondaryText)
                HStack(spacing: 6) {
                    ForEach(weekdayOptions, id: \.value) { option in
                        Toggle(option.label, isOn: Binding(
                            get: { selectedWeekdays.contains(option.value) },
                            set: { selected in
                                if selected {
                                    selectedWeekdays.insert(option.value)
                                } else {
                                    selectedWeekdays.remove(option.value)
                                }
                            }
                        ))
                        .toggleStyle(PixelToggleButtonStyle())
                    }
                }
            }
        case .date:
            VStack(alignment: .leading, spacing: 8) {
                DatePicker("日期", selection: $recurrenceDate, displayedComponents: .date)
                Toggle("每年重复", isOn: $yearlyRepeat)
                    .toggleStyle(PixelToggleButtonStyle())
            }
        }
    }

    private var weekdayOptions: [(label: String, value: Int)] {
        [
            ("日", 1), ("一", 2), ("二", 3), ("三", 4),
            ("四", 5), ("五", 6), ("六", 7)
        ]
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let recurrence = Recurrence(
            type: recurrenceType,
            weekdays: recurrenceType == .weekly ? Array(selectedWeekdays).sorted() : nil,
            date: recurrenceType == .date ? recurrenceDate : nil,
            yearlyRepeat: recurrenceType == .date && yearlyRepeat
        )
        let reminderComponents = hasReminderTime && recurrenceType != .interval
            ? DateComponents(hour: reminderHour, minute: reminderMinute, second: reminderSecond)
            : nil
        let intervalTotalSeconds = recurrenceType == .interval ? currentIntervalTotalSeconds : nil

        if let editingItem {
            editingItem.title = cleanTitle
            editingItem.note = cleanNote.isEmpty ? nil : cleanNote
            editingItem.kind = kind
            editingItem.recurrence = recurrence
            editingItem.reminderTime = reminderComponents
            editingItem.intervalSeconds = intervalTotalSeconds
            editingItem.isActive = isActive
        } else {
            modelContext.insert(ScheduleItem(
                title: cleanTitle,
                note: cleanNote.isEmpty ? nil : cleanNote,
                kind: kind,
                recurrence: recurrence,
                reminderTime: reminderComponents,
                intervalSeconds: intervalTotalSeconds,
                isActive: isActive
            ))
        }

        persistScheduleChange()
        resetForm()
    }

    private func deleteEditingItem() {
        guard let editingItem else { return }
        modelContext.delete(editingItem)
        persistScheduleChange()
        resetForm()
    }

    private func persistScheduleChange() {
        do {
            try modelContext.save()
            scheduleCoordinator.scheduleChanged()
        } catch {
            assertionFailure("Failed to save schedule: \(error)")
        }
    }

    private func load(_ item: ScheduleItem) {
        editingItem = item
        title = item.title
        note = item.note ?? ""
        kind = item.kind
        recurrenceType = item.recurrence.type
        selectedWeekdays = Set(item.weekdays ?? [2, 3, 4, 5, 6])
        recurrenceDate = item.recurrence.date ?? Date()
        yearlyRepeat = item.yearlyRepeat
        hasReminderTime = item.reminderTime != nil
        if let reminderTime = item.reminderTime {
            reminderHour = reminderTime.hour ?? 9
            reminderMinute = reminderTime.minute ?? 0
            reminderSecond = reminderTime.second ?? 0
        }
        setIntervalFields(totalSeconds: item.intervalSeconds ?? ReminderTriggerConfig.defaultIntervalSeconds)
        isActive = item.isActive
    }

    private func resetForm() {
        editingItem = nil
        title = ""
        note = ""
        kind = .task
        recurrenceType = .daily
        selectedWeekdays = [2, 3, 4, 5, 6]
        recurrenceDate = Date()
        yearlyRepeat = false
        hasReminderTime = false
        let now = Date()
        reminderHour = Calendar.current.component(.hour, from: now)
        reminderMinute = Calendar.current.component(.minute, from: now)
        reminderSecond = Calendar.current.component(.second, from: now)
        setIntervalFields(totalSeconds: ReminderTriggerConfig.defaultIntervalSeconds)
        isActive = true
    }

    private func summary(for item: ScheduleItem) -> String {
        var parts: [String] = [item.kind.title, recurrenceSummary(for: item)]
        if let reminder = item.reminderTime {
            let hour = String(format: "%02d", reminder.hour ?? 0)
            let minute = String(format: "%02d", reminder.minute ?? 0)
            let second = String(format: "%02d", reminder.second ?? 0)
            parts.append("\(hour):\(minute):\(second)")
        }
        if !item.isActive {
            parts.append("已停用")
        }
        return parts.joined(separator: " · ")
    }

    private func recurrenceSummary(for item: ScheduleItem) -> String {
        switch item.recurrence.type {
        case .interval:
            return "每 \(formatInterval(item.intervalSeconds ?? ReminderTriggerConfig.defaultIntervalSeconds))"
        case .daily:
            return "每天"
        case .weekly:
            let labels = (item.weekdays ?? []).compactMap { weekday in
                weekdayOptions.first(where: { $0.value == weekday })?.label
            }
            return labels.isEmpty ? "未选星期" : "每周" + labels.joined(separator: "")
        case .date:
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            let dateText = item.recurrence.date.map { formatter.string(from: $0) } ?? "未选日期"
            return item.yearlyRepeat ? "\(dateText) 每年" : dateText
        }
    }

    private var currentIntervalTotalSeconds: Int {
        if let typed = Int(intervalTotalSecondsText.trimmingCharacters(in: .whitespacesAndNewlines)), typed > 0 {
            return max(typed, ReminderTriggerConfig.minimumIntervalSeconds)
        }
        return max(
            intervalHours * 3600 + intervalMinutes * 60 + intervalSeconds,
            ReminderTriggerConfig.minimumIntervalSeconds
        )
    }

    private func setIntervalFields(totalSeconds: Int) {
        let clamped = max(totalSeconds, ReminderTriggerConfig.minimumIntervalSeconds)
        intervalHours = clamped / 3600
        intervalMinutes = (clamped % 3600) / 60
        intervalSeconds = clamped % 60
        intervalTotalSecondsText = String(clamped)
    }

    private func formatInterval(_ totalSeconds: Int) -> String {
        let clamped = max(totalSeconds, 0)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let seconds = clamped % 60
        if hours > 0 {
            return "\(hours)时\(minutes)分\(seconds)秒"
        }
        if minutes > 0 {
            return "\(minutes)分\(seconds)秒"
        }
        return "\(seconds)秒"
    }
}

private struct TimeOfDaySecondsInput: View {
    @Binding var hour: Int
    @Binding var minute: Int
    @Binding var second: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("提醒时刻")
                .font(PixelTheme.monoCaption.weight(.medium))
                .foregroundStyle(PixelTheme.secondaryText)
            HStack(spacing: 8) {
                Stepper(value: $hour, in: 0...23) {
                    Text("\(hour) 时")
                }
                Stepper(value: $minute, in: 0...59) {
                    Text("\(minute) 分")
                }
                Stepper(value: $second, in: 0...59) {
                    Text("\(second) 秒")
                }
            }
        }
    }
}

private struct IntervalSecondsInput: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var seconds: Int
    @Binding var totalSecondsText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("间隔时长")
                .font(PixelTheme.monoCaption.weight(.medium))
                .foregroundStyle(PixelTheme.secondaryText)
            HStack(spacing: 8) {
                Stepper(value: hoursBinding, in: 0...23) {
                    Text("\(hours) 时")
                }
                Stepper(value: minutesBinding, in: 0...59) {
                    Text("\(minutes) 分")
                }
                Stepper(value: secondsBinding, in: 0...59) {
                    Text("\(seconds) 秒")
                }
            }
            TextField("总秒数，比如 90", text: Binding(
                get: { totalSecondsText },
                set: { newValue in
                    totalSecondsText = newValue.filter(\.isNumber)
                    if let total = Int(totalSecondsText), total > 0 {
                        hours = total / 3600
                        minutes = (total % 3600) / 60
                        seconds = total % 60
                    }
                }
            ))
            .textFieldStyle(PixelTextFieldStyle())
        }
    }

    private var hoursBinding: Binding<Int> {
        Binding(
            get: { hours },
            set: { newValue in
                hours = min(max(newValue, 0), 23)
                updateTotalSecondsText()
            }
        )
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { minutes },
            set: { newValue in
                minutes = min(max(newValue, 0), 59)
                updateTotalSecondsText()
            }
        )
    }

    private var secondsBinding: Binding<Int> {
        Binding(
            get: { seconds },
            set: { newValue in
                seconds = min(max(newValue, 0), 59)
                updateTotalSecondsText()
            }
        )
    }

    private func updateTotalSecondsText() {
        totalSecondsText = String(hours * 3600 + minutes * 60 + seconds)
    }
}

struct MeterRow: View {
    let title: String
    let value: Int

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption.weight(.medium))
                .frame(width: 48, alignment: .leading)
            SegmentedPixelMeter(value: value)
            Text("\(value)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(PixelTheme.secondaryText)
                .frame(width: 28, alignment: .trailing)
        }
    }
}
