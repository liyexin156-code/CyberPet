import Foundation
import SwiftData

enum RecurrenceType: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly
    case date
    case interval

    var id: String { rawValue }
}

struct Recurrence: Codable, Equatable {
    var type: RecurrenceType
    var weekdays: [Int]?
    var date: Date?
    var yearlyRepeat: Bool
}

@Model
final class ScheduleItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var note: String?
    var kindRawValue: String
    var recurrenceTypeRawValue: String
    var weekdaysRawValue: String?
    var recurrenceDate: Date?
    var yearlyRepeat: Bool
    var reminderHour: Int?
    var reminderMinute: Int?
    var reminderSecond: Int?
    var intervalSeconds: Int?
    var isActive: Bool
    var createdAt: Date

    var kind: ScheduleItemKind {
        get { ScheduleItemKind(rawValue: kindRawValue) ?? .task }
        set { kindRawValue = newValue.rawValue }
    }

    var recurrence: Recurrence {
        get {
            Recurrence(
                type: RecurrenceType(rawValue: recurrenceTypeRawValue) ?? .daily,
                weekdays: weekdays,
                date: recurrenceDate,
                yearlyRepeat: yearlyRepeat
            )
        }
        set {
            recurrenceTypeRawValue = newValue.type.rawValue
            weekdays = newValue.weekdays
            recurrenceDate = newValue.date
            yearlyRepeat = newValue.yearlyRepeat
        }
    }

    var weekdays: [Int]? {
        get {
            guard let weekdaysRawValue, !weekdaysRawValue.isEmpty else { return nil }
            return weekdaysRawValue
                .split(separator: ",")
                .compactMap { Int($0) }
                .filter { (1...7).contains($0) }
        }
        set {
            weekdaysRawValue = newValue?
                .filter { (1...7).contains($0) }
                .sorted()
                .map(String.init)
                .joined(separator: ",")
        }
    }

    var reminderTime: DateComponents? {
        get {
            guard let reminderHour, let reminderMinute else { return nil }
            return DateComponents(hour: reminderHour, minute: reminderMinute, second: reminderSecond ?? 0)
        }
        set {
            reminderHour = newValue?.hour
            reminderMinute = newValue?.minute
            reminderSecond = newValue?.second
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        note: String? = nil,
        kind: ScheduleItemKind,
        recurrence: Recurrence,
        reminderTime: DateComponents? = nil,
        intervalSeconds: Int? = nil,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.kindRawValue = kind.rawValue
        self.recurrenceTypeRawValue = recurrence.type.rawValue
        self.weekdaysRawValue = recurrence.weekdays?
            .filter { (1...7).contains($0) }
            .sorted()
            .map(String.init)
            .joined(separator: ",")
        self.recurrenceDate = recurrence.date
        self.yearlyRepeat = recurrence.yearlyRepeat
        self.reminderHour = reminderTime?.hour
        self.reminderMinute = reminderTime?.minute
        self.reminderSecond = reminderTime?.second
        self.intervalSeconds = intervalSeconds
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

extension ScheduleItem {
    func matches(date: Date, calendar: Calendar = .current) -> Bool {
        let recurrence = recurrence
        switch recurrence.type {
        case .interval:
            return true
        case .daily:
            return true
        case .weekly:
            let weekday = calendar.component(.weekday, from: date)
            return recurrence.weekdays?.contains(weekday) ?? false
        case .date:
            guard let recurrenceDate = recurrence.date else { return false }
            if recurrence.yearlyRepeat {
                return calendar.component(.month, from: recurrenceDate) == calendar.component(.month, from: date)
                    && calendar.component(.day, from: recurrenceDate) == calendar.component(.day, from: date)
            }
            return calendar.isDate(recurrenceDate, inSameDayAs: date)
        }
    }

    func reminderDate(on day: Date, calendar: Calendar = .current) -> Date? {
        guard let reminderTime else { return nil }
        return calendar.date(
            bySettingHour: reminderTime.hour ?? 9,
            minute: reminderTime.minute ?? 0,
            second: reminderTime.second ?? 0,
            of: day
        )
    }
}
