import Foundation
import SwiftData

enum AITaskSmokeTest {
    @MainActor
    static func run() async {
        do {
            let container = try PersistenceController.makeModelContainer(storeFileName: "PetTaskBuddyAISmoke-\(UUID().uuidString).store")
            let context = ModelContext(container)
            let goal = Goal(title: "学会弹吉他", detail: "每天轻轻练一点")
            context.insert(goal)
            context.insert(DailyTask(
                date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(),
                title: "练习 C-G 和弦切换 10 分钟",
                source: .manual,
                isCompleted: true,
                completedAt: Date()
            ))
            try context.save()

            let draftStore = AITaskDraftStore()
            let service = AITaskService(
                modelContainer: container,
                provider: MockLLMProvider(goalID: goal.id),
                draftStore: draftStore,
                apiKeyProvider: { "test-key" }
            )

            await service.generateDrafts(force: true)
            guard draftStore.drafts.count == 2 else {
                throw AITaskSmokeTestError.draftsNotGenerated
            }

            service.confirmDrafts(draftStore.drafts)
            let today = Calendar.current.dateInterval(of: .day, for: Date()) ?? DateInterval(start: Date(), duration: 86_400)
            let descriptor = FetchDescriptor<DailyTask>(
                predicate: #Predicate<DailyTask> { task in
                    task.date >= today.start && task.date < today.end && task.sourceRawValue == "ai"
                }
            )
            let tasks = try context.fetch(descriptor)
            guard tasks.count == 2, tasks.allSatisfy({ $0.itemKind == .task }) else {
                throw AITaskSmokeTestError.confirmFailed
            }

            let noKeyStore = AITaskDraftStore()
            let noKeyService = AITaskService(
                modelContainer: container,
                provider: MockLLMProvider(goalID: goal.id),
                draftStore: noKeyStore,
                apiKeyProvider: { nil }
            )
            await noKeyService.generateDrafts(force: true)
            guard noKeyStore.drafts.isEmpty, noKeyStore.message != nil else {
                throw AITaskSmokeTestError.missingKeyDidNotFallback
            }

            print("AI task smoke test passed.")
        } catch {
            fputs("AI task smoke test failed: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}

private struct MockLLMProvider: LLMProvider {
    let goalID: UUID

    func generateTasks(apiKey: String, systemPrompt: String, userPrompt: String) async throws -> String {
        """
        [
          { "title": "练习 C-G 和弦切换 15 分钟", "note": "慢一点也很好", "estMinutes": 15, "goalId": "\(goalID.uuidString)" },
          { "title": "听一遍昨天练过的歌", "note": null, "estMinutes": 10, "goalId": "\(goalID.uuidString)" }
        ]
        """
    }
}

enum AITaskSmokeTestError: Error {
    case draftsNotGenerated
    case confirmFailed
    case missingKeyDidNotFallback
}
