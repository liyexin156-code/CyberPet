import Foundation
import SwiftData

enum TaskPersistenceSmokeTest {
    static func run() {
        do {
            let container = try PersistenceController.makeModelContainer(storeFileName: "PetTaskBuddyTaskSmoke-\(UUID().uuidString).store")
            let context = ModelContext(container)
            let taskID = UUID()
            let today = Calendar.current.startOfDay(for: Date())

            let task = DailyTask(
                id: taskID,
                date: today,
                title: "Smoke test task",
                note: "Verifies SwiftData CRUD",
                source: .manual
            )
            context.insert(task)
            try context.save()

            var descriptor = FetchDescriptor<DailyTask>(
                predicate: #Predicate { $0.id == taskID }
            )
            descriptor.fetchLimit = 1

            guard let inserted = try context.fetch(descriptor).first else {
                throw SmokeTestError.insertFetchFailed
            }

            inserted.isCompleted = true
            inserted.completedAt = Date()
            try context.save()

            guard let updated = try context.fetch(descriptor).first, updated.isCompleted, updated.completedAt != nil else {
                throw SmokeTestError.updateFetchFailed
            }

            context.delete(updated)
            try context.save()

            guard try context.fetch(descriptor).isEmpty else {
                throw SmokeTestError.deleteFailed
            }

            print("Task persistence smoke test passed.")
        } catch {
            fputs("Task persistence smoke test failed: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}

enum SmokeTestError: Error {
    case insertFetchFailed
    case updateFetchFailed
    case deleteFailed
}
