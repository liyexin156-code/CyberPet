import XCTest

final class LocalizationSourceTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testLocalizationManagerDefinesPersistentChineseEnglishLanguage() throws {
        let source = try source("Sources/PetTaskBuddy/LocalizationManager.swift")

        XCTAssertTrue(source.contains("enum AppLanguage"))
        XCTAssertTrue(source.contains("case chinese"))
        XCTAssertTrue(source.contains("case english"))
        XCTAssertTrue(source.contains("UserDefaults"))
        XCTAssertTrue(source.contains("toggleLanguage()"))
        XCTAssertTrue(source.contains("Language: English"))
        XCTAssertTrue(source.contains("语言：中文"))
        XCTAssertTrue(source.contains("Sleep"))
        XCTAssertTrue(source.contains("Sniff"))
        XCTAssertTrue(source.contains("Pee"))
        XCTAssertTrue(source.contains("Lie Down"))
        XCTAssertTrue(source.contains("Drink Water"))
        XCTAssertTrue(source.contains("Quit"))
        XCTAssertTrue(source.contains("Today's Tasks"))
        XCTAssertTrue(source.contains("Schedule"))
    }

    func testPetContextMenuUsesLocalizationAndLanguageToggle() throws {
        let source = try source("Sources/PetTaskBuddy/PetScene.swift")

        XCTAssertTrue(source.contains("LocalizationManager.shared.string(.menuSleep)"))
        XCTAssertTrue(source.contains("LocalizationManager.shared.string(.menuLanguageSwitch)"))
        XCTAssertTrue(source.contains("#selector(ContextMenuTarget.toggleLanguage)"))
        XCTAssertTrue(source.contains("func toggleLanguage()"))
        XCTAssertTrue(source.contains("LocalizationManager.shared.toggleLanguage()"))

        XCTAssertFalse(source.contains("title: \"睡觉\""))
        XCTAssertFalse(source.contains("title: \"嗅闻一下\""))
        XCTAssertFalse(source.contains("title: \"尿尿\""))
        XCTAssertFalse(source.contains("title: \"侧躺\""))
        XCTAssertFalse(source.contains("title: \"退出\""))
    }

    func testTaskViewsSubscribeToLocalizationChanges() throws {
        let mainPanel = try source("Sources/PetTaskBuddy/MainPanelWindowController.swift")
        let thoughtBubble = try source("Sources/PetTaskBuddy/ThoughtBubbleWindowController.swift")

        XCTAssertTrue(mainPanel.contains(".environmentObject(LocalizationManager.shared)"))
        XCTAssertTrue(mainPanel.contains("@EnvironmentObject private var localization: LocalizationManager"))
        XCTAssertTrue(mainPanel.contains("localization.string(.todayTasksTitle)"))
        XCTAssertTrue(mainPanel.contains("localization.string(.scheduleTitle)"))
        XCTAssertTrue(mainPanel.contains("localization.string(.addButton)"))

        XCTAssertTrue(thoughtBubble.contains(".environmentObject(LocalizationManager.shared)"))
        XCTAssertTrue(thoughtBubble.contains("@EnvironmentObject private var localization: LocalizationManager"))
        XCTAssertTrue(thoughtBubble.contains("localization.string(.allCaredForToday)"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
