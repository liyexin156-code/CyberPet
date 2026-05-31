import Foundation
import SwiftData

enum ReminderSecondsSmokeTest {
    @MainActor
    static func run() {
        do {
            let storeName = "PetTaskBuddyReminderSecondsSmoke-\(UUID().uuidString).store"
            let container = try PersistenceController.makeModelContainer(storeFileName: storeName)
            let context = ModelContext(container)
            let reminderService = ReminderService()

            let timedReminder = ScheduleItem(
                title: "Timed seconds smoke",
                kind: .reminder,
                recurrence: Recurrence(type: .daily, yearlyRepeat: false),
                reminderTime: DateComponents(hour: 18, minute: 0, second: 30)
            )
            guard timedReminder.reminderTime?.second == 30 else {
                throw ReminderSecondsSmokeTestError.secondNotPersisted
            }

            let intervalReminder = ScheduleItem(
                title: "Interval seconds smoke",
                kind: .reminder,
                recurrence: Recurrence(type: .interval, yearlyRepeat: false),
                intervalSeconds: 2
            )
            context.insert(timedReminder)
            context.insert(intervalReminder)
            try context.save()

            var firedAt: Date?
            reminderService.onPetReminder = { schedule in
                if schedule.id == intervalReminder.id {
                    firedAt = Date()
                }
            }

            let startedAt = Date()
            reminderService.scheduleTodayReminders(modelContainer: container)
            while firedAt == nil && Date().timeIntervalSince(startedAt) < 4 {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }

            guard let firedAt else {
                throw ReminderSecondsSmokeTestError.intervalDidNotFire
            }

            let elapsed = firedAt.timeIntervalSince(startedAt)
            guard elapsed >= 1.5 && elapsed <= 3.2 else {
                throw ReminderSecondsSmokeTestError.intervalTimingOutOfRange(elapsed)
            }

            print("Reminder seconds smoke test passed.")
        } catch {
            fputs("Reminder seconds smoke test failed: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}

enum ReminderSecondsSmokeTestError: Error {
    case secondNotPersisted
    case intervalDidNotFire
    case intervalTimingOutOfRange(TimeInterval)
}
