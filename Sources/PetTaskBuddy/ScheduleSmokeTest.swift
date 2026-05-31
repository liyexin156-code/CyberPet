import Foundation
import SwiftData

enum ScheduleSmokeTest {
    @MainActor
    static func run() {
        do {
            let storeName = "PetTaskBuddyScheduleSmoke-\(UUID().uuidString).store"
            let container = try PersistenceController.makeModelContainer(storeFileName: storeName)
            let context = ModelContext(container)
            let reminderService = ReminderService()
            let coordinator = ScheduleCoordinator(modelContainer: container, reminderService: reminderService)
            let calendar = Calendar(identifier: .gregorian)
            let monday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
            let tuesday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 2))!
            let birthday = calendar.date(from: DateComponents(year: 2020, month: 6, day: 1))!

            let daily = ScheduleItem(
                title: "Daily schedule smoke",
                kind: .task,
                recurrence: Recurrence(type: .daily, yearlyRepeat: false)
            )
            let weekly = ScheduleItem(
                title: "MWF schedule smoke",
                kind: .task,
                recurrence: Recurrence(type: .weekly, weekdays: [2, 4, 6], yearlyRepeat: false)
            )
            let yearlyReminder = ScheduleItem(
                title: "Yearly reminder smoke",
                kind: .reminder,
                recurrence: Recurrence(type: .date, date: birthday, yearlyRepeat: true),
                reminderTime: DateComponents(hour: 9, minute: 30)
            )

            context.insert(daily)
            context.insert(weekly)
            context.insert(yearlyReminder)
            try context.save()

            coordinator.generateItems(for: monday, context: context)
            coordinator.generateItems(for: monday, context: context)
            let mondayItems = try tasks(on: monday, context: context)

            guard mondayItems.filter({ $0.scheduleItemId == daily.id }).count == 1 else {
                throw ScheduleSmokeTestError.dailyDedupFailed
            }
            guard mondayItems.contains(where: { $0.scheduleItemId == weekly.id && $0.itemKind == .task }) else {
                throw ScheduleSmokeTestError.weeklyMatchFailed
            }
            guard mondayItems.contains(where: { $0.scheduleItemId == yearlyReminder.id && $0.itemKind == .reminder }) else {
                throw ScheduleSmokeTestError.yearlyReminderMatchFailed
            }

            coordinator.generateItems(for: tuesday, context: context)
            let tuesdayItems = try tasks(on: tuesday, context: context)
            guard tuesdayItems.contains(where: { $0.scheduleItemId == daily.id }) else {
                throw ScheduleSmokeTestError.dailyMissingOnNextDay
            }
            guard !tuesdayItems.contains(where: { $0.scheduleItemId == weekly.id }) else {
                throw ScheduleSmokeTestError.weeklyGeneratedOnWrongDay
            }

            print("Schedule smoke test passed.")
        } catch {
            fputs("Schedule smoke test failed: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func tasks(on day: Date, context: ModelContext) throws -> [DailyTask] {
        let interval = Calendar.current.dateInterval(of: .day, for: day) ?? DateInterval(start: day, duration: 86_400)
        let descriptor = FetchDescriptor<DailyTask>(
            predicate: #Predicate<DailyTask> { task in
                task.date >= interval.start && task.date < interval.end
            }
        )
        return try context.fetch(descriptor)
    }
}

enum ScheduleSmokeTestError: Error {
    case dailyDedupFailed
    case weeklyMatchFailed
    case yearlyReminderMatchFailed
    case dailyMissingOnNextDay
    case weeklyGeneratedOnWrongDay
}
