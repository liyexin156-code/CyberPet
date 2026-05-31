import Foundation
import SwiftData

@MainActor
final class PetStateEngine: ObservableObject {
    @Published private(set) var fullness: Int
    @Published private(set) var mood: Int

    var onMoodStateChange: ((PetAnimationState) -> Void)?

    private let context: ModelContext
    private let record: PetStateRecord
    private var decayTimer: Timer?

    init(modelContainer: ModelContainer) throws {
        context = ModelContext(modelContainer)

        var descriptor = FetchDescriptor<PetStateRecord>(
            predicate: #Predicate { $0.id == "default" }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            record = existing
        } else {
            let created = PetStateRecord()
            context.insert(created)
            try context.save()
            record = created
        }

        fullness = record.fullness
        mood = record.mood
        applyElapsedDecay()
        refreshMoodFromCurrentTasks(allowLowering: true)
        startDecayTimer()
    }

    deinit {
        decayTimer?.invalidate()
    }

    var visualState: PetAnimationState {
        if mood >= 70 {
            return .happy
        }
        if mood < 40 {
            return .listless
        }
        return .idle
    }

    func completeTaskReward() {
        applyElapsedDecay()
        let beforeMood = record.mood
        record.fullness = clamp(record.fullness + 15)
        record.mood = clamp(record.mood + 10)
        record.xp += 10
        record.lastUpdated = Date()

        refreshPublishedValues()
        refreshMoodFromCurrentTasks(allowLowering: false)
        save()

        if beforeMood != record.mood {
            onMoodStateChange?(visualState)
        }
    }

    func refreshMoodFromCurrentTasks(allowLowering: Bool) {
        let computed = computedMoodFromTasksAndFullness()
        if allowLowering {
            record.mood = computed
        } else {
            record.mood = max(record.mood, computed)
        }
        record.lastUpdated = Date()
        refreshPublishedValues()
        save()
        onMoodStateChange?(visualState)
    }

    func applyElapsedDecay(now: Date = Date()) {
        let elapsedHours = max(0, now.timeIntervalSince(record.lastUpdated) / 3600)
        let decay = Int(floor(elapsedHours * 3))
        guard decay > 0 else { return }

        record.fullness = clamp(record.fullness - decay)
        record.lastUpdated = now
        refreshPublishedValues()
        refreshMoodFromCurrentTasks(allowLowering: true)
        save()
    }

    private func startDecayTimer() {
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.applyElapsedDecay()
            }
        }
        decayTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func computedMoodFromTasksAndFullness() -> Int {
        let interval = Calendar.current.dateInterval(of: .day, for: Date()) ?? DateInterval(start: Date(), duration: 86_400)
        let descriptor = FetchDescriptor<DailyTask>(
            predicate: #Predicate<DailyTask> { task in
                task.date >= interval.start && task.date < interval.end
            }
        )

        let tasks = (try? context.fetch(descriptor)) ?? []
            .filter { $0.itemKind == .task }
        let completionRate: Double
        if tasks.isEmpty {
            completionRate = 0.5
        } else {
            completionRate = Double(tasks.filter(\.isCompleted).count) / Double(tasks.count)
        }

        return clamp(Int((completionRate * 60).rounded()) + Int((Double(record.fullness) * 0.4).rounded()))
    }

    private func refreshPublishedValues() {
        fullness = record.fullness
        mood = record.mood
    }

    private func save() {
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save pet state: \(error)")
        }
    }

    private func clamp(_ value: Int) -> Int {
        min(max(value, 0), 100)
    }
}
