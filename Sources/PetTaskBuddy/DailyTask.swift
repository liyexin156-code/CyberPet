import Foundation
import SwiftData

enum DailyTaskSource: String, Codable, CaseIterable {
    case ai
    case manual
    case schedule
}

enum ScheduleItemKind: String, Codable, CaseIterable, Identifiable {
    case task
    case reminder

    var id: String { rawValue }
}

@Model
final class DailyTask {
    @Attribute(.unique) var id: UUID
    var date: Date
    var title: String
    var note: String?
    var estMinutes: Int?
    var goalId: UUID?
    var scheduleItemId: UUID?
    var sourceRawValue: String
    var itemKindRawValue: String?
    var isCompleted: Bool
    var completedAt: Date?

    var source: DailyTaskSource {
        get { DailyTaskSource(rawValue: sourceRawValue) ?? .manual }
        set { sourceRawValue = newValue.rawValue }
    }

    var itemKind: ScheduleItemKind {
        get { ScheduleItemKind(rawValue: itemKindRawValue ?? ScheduleItemKind.task.rawValue) ?? .task }
        set { itemKindRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        date: Date,
        title: String,
        note: String? = nil,
        estMinutes: Int? = nil,
        goalId: UUID? = nil,
        scheduleItemId: UUID? = nil,
        source: DailyTaskSource = .manual,
        itemKind: ScheduleItemKind = .task,
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.note = note
        self.estMinutes = estMinutes
        self.goalId = goalId
        self.scheduleItemId = scheduleItemId
        self.sourceRawValue = source.rawValue
        self.itemKindRawValue = itemKind.rawValue
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }
}
