import AppKit
import Foundation
import SwiftData
import UserNotifications

@MainActor
final class ReminderService: NSObject, ObservableObject {
    var onPetBubble: ((String) -> Void)?
    var onPetReminder: ((ScheduleItem) -> Void)?
    private var timers: [UUID: Timer] = [:]
    private var scheduledFireDates: [UUID: Date] = [:]
    private weak var modelContainer: ModelContainer?

    override init() {
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        timers.values.forEach { $0.invalidate() }
    }

    func requestAuthorization() {
        guard canUseSystemNotifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func scheduleTodayReminders(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
        scheduledFireDates.removeAll()

        let context = ModelContext(modelContainer)
        let today = Calendar.current.startOfDay(for: Date())
        let scheduleDescriptor = FetchDescriptor<ScheduleItem>(
            predicate: #Predicate { $0.isActive == true }
        )
        let schedules = (try? context.fetch(scheduleDescriptor)) ?? []
        let matchingSchedules = schedules.filter { $0.matches(date: today) }

        if canUseSystemNotifications {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: matchingSchedules.map { notificationIdentifier(for: $0.id, day: today) }
            )
        }

        for schedule in matchingSchedules {
            if schedule.recurrence.type == .interval {
                scheduleIntervalReminder(for: schedule)
                continue
            }
            guard let reminderDate = schedule.reminderDate(on: today), reminderDate > Date() else { continue }
            if canUseSystemNotifications {
                scheduleSystemNotification(for: schedule, at: reminderDate, day: today)
            }
            schedulePetReminder(for: schedule, at: reminderDate)
        }
    }

    private var canUseSystemNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private func scheduleSystemNotification(for schedule: ScheduleItem, at date: Date, day: Date) {
        guard date > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = schedule.kind == .task ? "今天的小任务" : "温柔提醒"
        content.body = schedule.title
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationIdentifier(for: schedule.id, day: day),
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func schedulePetReminder(for schedule: ScheduleItem, at date: Date) {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return }

        let scheduleID = schedule.id
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.fire(scheduleID: scheduleID)
            }
        }
        timers[scheduleID] = timer
        scheduledFireDates[scheduleID] = date
        RunLoop.main.add(timer, forMode: .common)
    }

    private func scheduleIntervalReminder(for schedule: ScheduleItem) {
        let seconds = max(schedule.intervalSeconds ?? ReminderTriggerConfig.defaultIntervalSeconds, 1)
        let fireDate = Date().addingTimeInterval(TimeInterval(seconds))
        schedulePetReminder(for: schedule, at: fireDate)
    }

    private func fire(scheduleID: UUID) {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ScheduleItem>(
            predicate: #Predicate { $0.id == scheduleID }
        )
        guard let schedule = try? context.fetch(descriptor).first, schedule.isActive else {
            timers[scheduleID]?.invalidate()
            timers[scheduleID] = nil
            scheduledFireDates[scheduleID] = nil
            return
        }
        fire(schedule)
    }

    private func fire(_ schedule: ScheduleItem) {
        timers[schedule.id]?.invalidate()
        timers[schedule.id] = nil
        scheduledFireDates[schedule.id] = nil
        PetDebugLog.write("Reminder fired: \(schedule.title)")
        if let onPetReminder {
            onPetReminder(schedule)
        } else {
            onPetBubble?(schedule.title)
        }

        if schedule.recurrence.type == .interval, schedule.isActive {
            scheduleIntervalReminder(for: schedule)
        }
    }

    @objc private func handleSystemWake() {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ScheduleItem>(
            predicate: #Predicate { $0.isActive == true }
        )
        let schedules = (try? context.fetch(descriptor)) ?? []
        let schedulesByID = Dictionary(uniqueKeysWithValues: schedules.map { ($0.id, $0) })
        let now = Date()

        let overdueIDs = scheduledFireDates.compactMap { id, fireDate in
            fireDate <= now ? id : nil
        }

        for id in overdueIDs {
            if let schedule = schedulesByID[id] {
                fire(schedule)
            }
        }

        scheduleTodayReminders(modelContainer: modelContainer)
    }

    private func notificationIdentifier(for scheduleID: UUID, day: Date) -> String {
        let formatted = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: day))
        return "schedule.\(scheduleID.uuidString).\(formatted)"
    }
}

enum ReminderTriggerConfig {
    static let defaultIntervalSeconds = 90
    static let minimumIntervalSeconds = 1
    static let reminderRewardKind: PetRewardKind = .drink
}
