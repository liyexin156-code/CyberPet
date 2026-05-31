import Foundation
import SwiftData

struct AITaskDraft: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var note: String?
    var estMinutes: Int?
    var goalId: UUID?
}

protocol LLMProvider {
    func generateTasks(
        apiKey: String,
        systemPrompt: String,
        userPrompt: String
    ) async throws -> String
}

struct ClaudeLLMProvider: LLMProvider {
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-sonnet-4-5"

    func generateTasks(apiKey: String, systemPrompt: String, userPrompt: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(ClaudeRequest(
            model: model,
            maxTokens: 1200,
            system: systemPrompt,
            messages: [
                ClaudeMessage(role: "user", content: userPrompt)
            ]
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw AITaskServiceError.requestFailed
        }

        let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        let text = decoded.content
            .filter { $0.type == "text" }
            .map(\.text)
            .joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AITaskServiceError.emptyResponse
        }
        return text
    }
}

@MainActor
final class AITaskDraftStore: ObservableObject {
    @Published var drafts: [AITaskDraft] = []
    @Published var message: String?
    @Published var isGenerating = false
}

@MainActor
final class AITaskService: ObservableObject {
    private let modelContainer: ModelContainer
    private let provider: LLMProvider
    private let draftStore: AITaskDraftStore
    private let apiKeyProvider: () -> String?
    private let calendar = Calendar.current

    init(
        modelContainer: ModelContainer,
        provider: LLMProvider = ClaudeLLMProvider(),
        draftStore: AITaskDraftStore,
        apiKeyProvider: @escaping () -> String? = { KeychainService.readAnthropicAPIKey() }
    ) {
        self.modelContainer = modelContainer
        self.provider = provider
        self.draftStore = draftStore
        self.apiKeyProvider = apiKeyProvider
    }

    func generateOnFirstLaunchIfNeeded() {
        guard UserDefaults.standard.string(forKey: "lastAIGenerationDate") != todayKey(),
              !hasAITasksToday()
        else { return }

        Task {
            await generateDrafts(force: false)
        }
    }

    func generateDrafts(force: Bool) async {
        guard !draftStore.isGenerating else { return }
        draftStore.isGenerating = true
        draftStore.message = nil
        defer { draftStore.isGenerating = false }

        do {
            let apiKey = try apiKeyOrThrow()
            let context = ModelContext(modelContainer)
            let goals = try activeGoals(in: context)
            guard !goals.isEmpty else {
                draftStore.message = "先写下一个长期目标，我再帮你拆小任务。"
                return
            }

            let recentTasks = try recentTaskSummaries(in: context)
            let count = min(max(UserDefaults.standard.integer(forKey: "dailyAITaskCount"), 3), 5)
            if UserDefaults.standard.object(forKey: "dailyAITaskCount") == nil {
                UserDefaults.standard.set(3, forKey: "dailyAITaskCount")
            }
            let response = try await provider.generateTasks(
                apiKey: apiKey,
                systemPrompt: Self.systemPrompt,
                userPrompt: userPrompt(goals: goals, recentTasks: recentTasks, count: count)
            )
            let drafts = try parseDrafts(from: response)
            draftStore.drafts = Array(drafts.prefix(count))
            draftStore.message = draftStore.drafts.isEmpty ? "现在没想出合适的小任务，先手动加几个吧。" : "我先想了这些，可以改一改再确认。"
            UserDefaults.standard.set(todayKey(), forKey: "lastAIGenerationDate")
        } catch {
            draftStore.message = "现在连不上，先手动加几个吧。"
        }
    }

    func confirmDrafts(_ drafts: [AITaskDraft], context: ModelContext? = nil) {
        let context = context ?? ModelContext(modelContainer)
        let today = calendar.startOfDay(for: Date())

        for draft in drafts {
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            context.insert(DailyTask(
                date: today,
                title: title,
                note: draft.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                estMinutes: draft.estMinutes,
                goalId: draft.goalId,
                source: .ai
            ))
        }

        do {
            try context.save()
            draftStore.drafts = []
            draftStore.message = "已放进今天的小任务。"
        } catch {
            draftStore.message = "保存时有点卡住了，稍后再试试。"
        }
    }

    private func apiKeyOrThrow() throws -> String {
        guard let key = apiKeyProvider(), !key.isEmpty else {
            throw AITaskServiceError.missingAPIKey
        }
        return key
    }

    private func activeGoals(in context: ModelContext) throws -> [Goal] {
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { $0.isActive == true },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    private func recentTaskSummaries(in context: ModelContext) throws -> [DailyTask] {
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date())
        let descriptor = FetchDescriptor<DailyTask>(
            predicate: #Predicate<DailyTask> { task in
                task.date >= start && task.itemKindRawValue != "reminder"
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
            .filter { $0.itemKind == .task }
    }

    private func hasAITasksToday() -> Bool {
        let context = ModelContext(modelContainer)
        let interval = calendar.dateInterval(of: .day, for: Date()) ?? DateInterval(start: Date(), duration: 86_400)
        let descriptor = FetchDescriptor<DailyTask>(
            predicate: #Predicate<DailyTask> { task in
                task.date >= interval.start && task.date < interval.end && task.sourceRawValue == "ai"
            }
        )
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    private func userPrompt(goals: [Goal], recentTasks: [DailyTask], count: Int) -> String {
        let goalLines = goals.map { goal in
            "- id: \(goal.id.uuidString); title: \(goal.title); detail: \(goal.detail ?? "")"
        }.joined(separator: "\n")
        let recentLines = recentTasks.prefix(40).map { task in
            "- date: \(dateString(task.date)); title: \(task.title); completed: \(task.isCompleted)"
        }.joined(separator: "\n")

        return """
        N = \(count)

        Active long-term goals:
        \(goalLines)

        Recent completion history from the last 7 days:
        \(recentLines.isEmpty ? "暂无" : recentLines)
        """
    }

    private func parseDrafts(from response: String) throws -> [AITaskDraft] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { throw AITaskServiceError.parseFailed }
        let decoded = try JSONDecoder().decode([AITaskDraftPayload].self, from: data)
        return decoded.map {
            AITaskDraft(
                title: $0.title,
                note: $0.note,
                estMinutes: $0.estMinutes,
                goalId: $0.goalId.flatMap(UUID.init(uuidString:))
            )
        }
    }

    private func todayKey() -> String {
        dateString(Date())
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static let systemPrompt = """
    You are a gentle task planner who understands behavioral science. Given the user's long-term goals and their recent completion history, generate N small, easy-to-start, "human-friendly" tasks for today. Strictly follow these rules:
    1. Make each task small enough to have almost no starting friction — focus on the smallest first step (e.g. "Open guitar and practice C–G switching for 10 min", not "Practice guitar").
    2. Be concrete and immediately actionable; state the exact action, never vague.
    3. Describe controllable behaviors, not outcomes (write "walk briskly for 15 min", not "lose weight").
    4. Each task contains exactly one clear next action.
    5. Control quantity and time: N tasks total, each ideally ≤30 min, and the sum must be realistically doable in one day — do not overload.
    6. Progress gradually based on recent history: if they've been completing well, you may add a little; if they've recently been missing tasks, make tasks even smaller and easier to win — never add more, never blame.
    7. Include at least one easy "quick win" so the user gets a sense of completion early.
    8. Keep tasks tied to the goals so the user sees why. In "note", optionally give an anchor time (e.g. "after lunch") or a fallback "minimum version".
    9. Use the user's language. Return ONLY a strict JSON array [{title, note, estMinutes, goalId}], with no extra text.
    """
}

private struct AITaskDraftPayload: Decodable {
    let title: String
    let note: String?
    let estMinutes: Int?
    let goalId: String?
}

private struct ClaudeRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [ClaudeMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }
}

private struct ClaudeMessage: Encodable {
    let role: String
    let content: String
}

private struct ClaudeResponse: Decodable {
    let content: [ClaudeContentBlock]
}

private struct ClaudeContentBlock: Decodable {
    let type: String
    let text: String
}

enum AITaskServiceError: Error {
    case missingAPIKey
    case requestFailed
    case emptyResponse
    case parseFailed
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
