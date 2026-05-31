import Foundation
import SwiftData

enum PetStateSmokeTest {
    @MainActor
    static func run() {
        do {
            let container = try PersistenceController.makeModelContainer(storeFileName: "PetTaskBuddyPetStateSmoke-\(UUID().uuidString).store")
            let context = ModelContext(container)
            let testTask = DailyTask(
                date: Calendar.current.startOfDay(for: Date()),
                title: "Pet state smoke test",
                source: .manual
            )
            context.insert(testTask)
            try context.save()

            let engine = try PetStateEngine(modelContainer: container)
            let initialFullness = engine.fullness
            let initialMood = engine.mood

            testTask.isCompleted = true
            testTask.completedAt = Date()
            try context.save()
            engine.completeTaskReward()

            guard engine.fullness >= initialFullness, engine.mood >= initialMood else {
                throw PetStateSmokeTestError.rewardDidNotIncreaseState
            }

            let verificationContext = ModelContext(container)
            var descriptor = FetchDescriptor<PetStateRecord>(
                predicate: #Predicate { $0.id == "default" }
            )
            descriptor.fetchLimit = 1

            guard let record = try verificationContext.fetch(descriptor).first else {
                throw PetStateSmokeTestError.stateNotPersisted
            }

            let fullnessAfterReward = record.fullness
            record.lastUpdated = Date().addingTimeInterval(-7200)
            try verificationContext.save()
            let decayedEngine = try PetStateEngine(modelContainer: container)

            guard decayedEngine.fullness <= fullnessAfterReward - 6 else {
                throw PetStateSmokeTestError.decayDidNotApply
            }

            context.delete(testTask)
            try context.save()

            print("Pet state smoke test passed.")
        } catch {
            fputs("Pet state smoke test failed: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}

enum PetStateSmokeTestError: Error {
    case rewardDidNotIncreaseState
    case stateNotPersisted
    case decayDidNotApply
}
