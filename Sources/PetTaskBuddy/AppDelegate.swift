import AppKit
import SwiftData

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petWindowController: PetWindowController?
    private var mainPanelWindowController: MainPanelWindowController?
    private var modelContainer: ModelContainer?
    private var petStateEngine: PetStateEngine?
    private var reminderService: ReminderService?
    private var scheduleCoordinator: ScheduleCoordinator?
    private var thoughtBubbleWindowController: ThoughtBubbleWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItemService.registerMainAppIfPossible()

        do {
            let container = try PersistenceController.makeModelContainer()
            let engine = try PetStateEngine(modelContainer: container)
            let reminders = ReminderService()
            let scheduler = ScheduleCoordinator(modelContainer: container, reminderService: reminders)
            modelContainer = container
            petStateEngine = engine
            reminderService = reminders
            scheduleCoordinator = scheduler
            thoughtBubbleWindowController = ThoughtBubbleWindowController(
                modelContainer: container,
                petStateEngine: engine
            )
            mainPanelWindowController = MainPanelWindowController(
                modelContainer: container,
                petStateEngine: engine,
                scheduleCoordinator: scheduler
            )
            petWindowController = PetWindowController(
                mainPanelWindowController: mainPanelWindowController,
                petStateEngine: engine,
                reminderService: reminders,
                thoughtBubbleWindowController: thoughtBubbleWindowController
            )
            reminders.requestAuthorization()
            scheduler.start()
        } catch {
            presentStartupError(error)
            NSApp.terminate(nil)
            return
        }

        petWindowController?.show()
        if CommandLine.arguments.contains("--smoke-test-rewards") {
            let smokeTestController = petWindowController
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                smokeTestController?.runRewardSmokeTest {
                    NSApp.terminate(nil)
                }
            }
        } else if CommandLine.arguments.contains("--smoke-test-reminder-pet-action") {
            PetDebugLog.write("Reminder pet action smoke requested")
            petWindowController?.runReminderPetActionSmokeTest {
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func presentStartupError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "任务数据暂时打不开"
        alert.informativeText = "请稍后再试，或检查本机存储权限。\n\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.runModal()
    }
}
