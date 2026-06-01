import Combine
import Foundation

enum AppLanguage: String, CaseIterable {
    case chinese
    case english

    var toggled: AppLanguage {
        switch self {
        case .chinese: .english
        case .english: .chinese
        }
    }

    var locale: Locale {
        switch self {
        case .chinese: Locale(identifier: "zh-Hans")
        case .english: Locale(identifier: "en")
        }
    }
}

enum LocalizationKey: String, CaseIterable {
    case menuStretch
    case menuWalk
    case menuIdle
    case menuSleep
    case menuSideLie
    case menuSit
    case menuHappy
    case menuRoam
    case menuSleepy
    case menuSniff
    case menuPee
    case menuPoop
    case menuShake
    case menuScratch
    case menuDrinkWater
    case menuLanguageSwitch
    case menuQuit

    case appTitle
    case startupErrorTitle
    case startupErrorMessage
    case todayTab
    case scheduleTab
    case thoughtBubbleAlwaysVisible
    case thoughtBubbleHelp
    case fullness
    case mood
    case todayTasksTitle
    case todayTasksSubtitle
    case addTaskPlaceholder
    case noteOptionalPlaceholder
    case addButton
    case emptyTodayTitle
    case emptyTodayDescription
    case reminder
    case deleteTaskHelp
    case scheduleTitle
    case newScheduleButton
    case newScheduleHelp
    case emptyScheduleTitle
    case emptyScheduleDescription
    case newScheduleTitle
    case editScheduleTitle
    case titlePlaceholder
    case scheduleKindPicker
    case scheduleRulePicker
    case taskKind
    case reminderKind
    case recurrenceDaily
    case recurrenceWeekly
    case recurrenceDate
    case recurrenceInterval
    case enableReminderTime
    case enableSchedule
    case deleteButton
    case saveButton
    case chooseWeekdays
    case datePicker
    case repeatYearly
    case inactiveSummary
    case everyPrefix
    case everyDay
    case weeklyPrefix
    case noWeekdaySelected
    case noDateSelected
    case yearlySuffix
    case reminderTimeTitle
    case intervalDurationTitle
    case hourUnit
    case minuteUnit
    case secondUnit
    case totalSecondsPlaceholder
    case allCaredForToday
    case completeHelp
    case notificationTaskTitle
    case notificationReminderTitle
    case aiNoGoalMessage
    case aiNoDraftsMessage
    case aiDraftsReadyMessage
    case aiOfflineMessage
    case aiConfirmedMessage
    case aiSaveFailedMessage
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    static let userDefaultsKey = "CyberPet.AppLanguage"

    @Published private(set) var language: AppLanguage

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let rawValue = userDefaults.string(forKey: Self.userDefaultsKey),
           let savedLanguage = AppLanguage(rawValue: rawValue) {
            language = savedLanguage
        } else {
            language = .chinese
        }
    }

    func setLanguage(_ language: AppLanguage) {
        guard self.language != language else { return }
        self.language = language
        userDefaults.set(language.rawValue, forKey: Self.userDefaultsKey)
    }

    func toggleLanguage() {
        setLanguage(language.toggled)
    }

    func string(_ key: LocalizationKey) -> String {
        Self.strings[language]?[key] ?? Self.strings[.chinese]?[key] ?? key.rawValue
    }

    func string(_ key: LocalizationKey, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: language.locale, arguments: arguments)
    }

    private static let strings: [AppLanguage: [LocalizationKey: String]] = [
        .chinese: [
            .menuStretch: "伸懒腰",
            .menuWalk: "走一小段",
            .menuIdle: "待机",
            .menuSleep: "睡觉",
            .menuSideLie: "侧躺",
            .menuSit: "坐一会儿",
            .menuHappy: "兴奋一下",
            .menuRoam: "无聊乱逛",
            .menuSleepy: "疲惫想睡",
            .menuSniff: "嗅闻一下",
            .menuPee: "尿尿",
            .menuPoop: "拉屎",
            .menuShake: "抖抖毛",
            .menuScratch: "挠挠痒",
            .menuDrinkWater: "喝水",
            .menuLanguageSwitch: "Language: English",
            .menuQuit: "退出",

            .appTitle: "桌宠任务伙伴",
            .startupErrorTitle: "任务数据暂时打不开",
            .startupErrorMessage: "请稍后再试，或检查本机存储权限。",
            .todayTab: "今日",
            .scheduleTab: "日程",
            .thoughtBubbleAlwaysVisible: "思考泡泡常驻显示",
            .thoughtBubbleHelp: "关闭后，悬停到狗狗时再显示思考泡泡",
            .fullness: "饱食度",
            .mood: "心情",
            .todayTasksTitle: "今天的小任务",
            .todayTasksSubtitle: "写下一个今天愿意照顾的小目标。",
            .addTaskPlaceholder: "添加一个小任务",
            .noteOptionalPlaceholder: "备注，可不填",
            .addButton: "添加",
            .emptyTodayTitle: "今天还很清爽",
            .emptyTodayDescription: "先加一件很小、能开始的事就好。",
            .reminder: "提醒",
            .deleteTaskHelp: "删除任务",
            .scheduleTitle: "日程",
            .newScheduleButton: "新建",
            .newScheduleHelp: "新建日程",
            .emptyScheduleTitle: "还没有固定日程",
            .emptyScheduleDescription: "把每天或每周会重复的小事放在这里。",
            .newScheduleTitle: "新建日程",
            .editScheduleTitle: "编辑日程",
            .titlePlaceholder: "标题",
            .scheduleKindPicker: "类型",
            .scheduleRulePicker: "规则",
            .taskKind: "任务",
            .reminderKind: "提醒",
            .recurrenceDaily: "每天",
            .recurrenceWeekly: "周几",
            .recurrenceDate: "特定日期",
            .recurrenceInterval: "间隔",
            .enableReminderTime: "启用提醒时间",
            .enableSchedule: "启用这条日程",
            .deleteButton: "删除",
            .saveButton: "保存",
            .chooseWeekdays: "选择星期",
            .datePicker: "日期",
            .repeatYearly: "每年重复",
            .inactiveSummary: "已停用",
            .everyPrefix: "每",
            .everyDay: "每天",
            .weeklyPrefix: "每周",
            .noWeekdaySelected: "未选星期",
            .noDateSelected: "未选日期",
            .yearlySuffix: "每年",
            .reminderTimeTitle: "提醒时刻",
            .intervalDurationTitle: "间隔时长",
            .hourUnit: "时",
            .minuteUnit: "分",
            .secondUnit: "秒",
            .totalSecondsPlaceholder: "总秒数，比如 90",
            .allCaredForToday: "今天都照顾好啦～",
            .completeHelp: "完成",
            .notificationTaskTitle: "今天的小任务",
            .notificationReminderTitle: "温柔提醒",
            .aiNoGoalMessage: "先写下一个长期目标，我再帮你拆小任务。",
            .aiNoDraftsMessage: "现在没想出合适的小任务，先手动加几个吧。",
            .aiDraftsReadyMessage: "我先想了这些，可以改一改再确认。",
            .aiOfflineMessage: "现在连不上，先手动加几个吧。",
            .aiConfirmedMessage: "已放进今天的小任务。",
            .aiSaveFailedMessage: "保存时有点卡住了，稍后再试试。"
        ],
        .english: [
            .menuStretch: "Stretch",
            .menuWalk: "Walk",
            .menuIdle: "Idle",
            .menuSleep: "Sleep",
            .menuSideLie: "Lie Down",
            .menuSit: "Sit",
            .menuHappy: "Happy",
            .menuRoam: "Roam",
            .menuSleepy: "Sleepy",
            .menuSniff: "Sniff",
            .menuPee: "Pee",
            .menuPoop: "Poop",
            .menuShake: "Shake",
            .menuScratch: "Scratch",
            .menuDrinkWater: "Drink Water",
            .menuLanguageSwitch: "语言：中文",
            .menuQuit: "Quit",

            .appTitle: "CyberPet Tasks",
            .startupErrorTitle: "Task data cannot be opened",
            .startupErrorMessage: "Please try again later, or check local storage permissions.",
            .todayTab: "Today",
            .scheduleTab: "Schedule",
            .thoughtBubbleAlwaysVisible: "Keep Thought Bubble Visible",
            .thoughtBubbleHelp: "When off, show the thought bubble only while hovering over the dog",
            .fullness: "Fullness",
            .mood: "Mood",
            .todayTasksTitle: "Today's Tasks",
            .todayTasksSubtitle: "Write down one small goal you want to care for today.",
            .addTaskPlaceholder: "Add a small task",
            .noteOptionalPlaceholder: "Note, optional",
            .addButton: "Add",
            .emptyTodayTitle: "All Clear Today",
            .emptyTodayDescription: "Add one tiny thing you can start.",
            .reminder: "Reminder",
            .deleteTaskHelp: "Delete Task",
            .scheduleTitle: "Schedule",
            .newScheduleButton: "New",
            .newScheduleHelp: "New Schedule",
            .emptyScheduleTitle: "No Fixed Schedule",
            .emptyScheduleDescription: "Put small recurring things here.",
            .newScheduleTitle: "New Schedule",
            .editScheduleTitle: "Edit Schedule",
            .titlePlaceholder: "Title",
            .scheduleKindPicker: "Type",
            .scheduleRulePicker: "Rule",
            .taskKind: "Task",
            .reminderKind: "Reminder",
            .recurrenceDaily: "Daily",
            .recurrenceWeekly: "Weekly",
            .recurrenceDate: "Date",
            .recurrenceInterval: "Interval",
            .enableReminderTime: "Enable Reminder Time",
            .enableSchedule: "Enable This Schedule",
            .deleteButton: "Delete",
            .saveButton: "Save",
            .chooseWeekdays: "Choose Weekdays",
            .datePicker: "Date",
            .repeatYearly: "Repeat Yearly",
            .inactiveSummary: "Inactive",
            .everyPrefix: "Every",
            .everyDay: "Every Day",
            .weeklyPrefix: "Every ",
            .noWeekdaySelected: "No Weekdays Selected",
            .noDateSelected: "No Date Selected",
            .yearlySuffix: "Yearly",
            .reminderTimeTitle: "Reminder Time",
            .intervalDurationTitle: "Interval",
            .hourUnit: "h",
            .minuteUnit: "min",
            .secondUnit: "sec",
            .totalSecondsPlaceholder: "Total seconds, for example 90",
            .allCaredForToday: "All cared for today",
            .completeHelp: "Complete",
            .notificationTaskTitle: "Today's Tasks",
            .notificationReminderTitle: "Gentle Reminder",
            .aiNoGoalMessage: "Write down a long-term goal first, then I can help split it into small tasks.",
            .aiNoDraftsMessage: "I could not find a good small task yet. Add a few manually for now.",
            .aiDraftsReadyMessage: "I drafted these first. You can edit them before confirming.",
            .aiOfflineMessage: "I cannot connect right now. Add a few manually for now.",
            .aiConfirmedMessage: "Added to today's tasks.",
            .aiSaveFailedMessage: "Saving got stuck. Please try again later."
        ]
    ]
}

extension ScheduleItemKind {
    var localizationKey: LocalizationKey {
        switch self {
        case .task: .taskKind
        case .reminder: .reminderKind
        }
    }
}

extension RecurrenceType {
    var localizationKey: LocalizationKey {
        switch self {
        case .daily: .recurrenceDaily
        case .weekly: .recurrenceWeekly
        case .date: .recurrenceDate
        case .interval: .recurrenceInterval
        }
    }
}
