import Foundation
import SwiftData

@MainActor
final class ScheduleCoordinator: ObservableObject {
    private let modelContainer: ModelContainer
    private let reminderService: ReminderService
    private var midnightTimer: Timer?

    init(modelContainer: ModelContainer, reminderService: ReminderService) {
        self.modelContainer = modelContainer
        self.reminderService = reminderService
    }

    deinit {
        midnightTimer?.invalidate()
    }

    func start() {
        generateToday()
        scheduleNextMidnightRefresh()
    }

    func generateToday() {
        let context = ModelContext(modelContainer)
        let today = Calendar.current.startOfDay(for: Date())
        generateItems(for: today, context: context)
        reminderService.scheduleTodayReminders(modelContainer: modelContainer)
    }

    func scheduleChanged() {
        generateToday()
    }

    func generateItems(for day: Date, context: ModelContext) {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .day, for: day) ?? DateInterval(start: day, duration: 86_400)

        let scheduleDescriptor = FetchDescriptor<ScheduleItem>(
            predicate: #Predicate { $0.isActive == true }
        )
        let schedules = (try? context.fetch(scheduleDescriptor)) ?? []

        let taskDescriptor = FetchDescriptor<DailyTask>(
            predicate: #Predicate<DailyTask> { task in
                task.date >= interval.start && task.date < interval.end
            }
        )
        let todayItems = (try? context.fetch(taskDescriptor)) ?? []
        let generatedScheduleIDs = Set(todayItems.compactMap(\.scheduleItemId))

        for schedule in schedules where schedule.matches(date: day, calendar: calendar) {
            guard !generatedScheduleIDs.contains(schedule.id) else { continue }
            context.insert(DailyTask(
                date: interval.start,
                title: schedule.title,
                note: schedule.note,
                scheduleItemId: schedule.id,
                source: .schedule,
                itemKind: schedule.kind
            ))
        }

        do {
            try context.save()
        } catch {
            assertionFailure("Failed to generate schedule items: \(error)")
        }
    }

    private func scheduleNextMidnightRefresh() {
        midnightTimer?.invalidate()
        guard let nextMidnight = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 3),
            matchingPolicy: .nextTime
        ) else { return }

        let timer = Timer(fireAt: nextMidnight, interval: 0, target: self, selector: #selector(handleMidnightTimer), userInfo: nil, repeats: false)
        midnightTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func handleMidnightTimer() {
        generateToday()
        scheduleNextMidnightRefresh()
    }
}

