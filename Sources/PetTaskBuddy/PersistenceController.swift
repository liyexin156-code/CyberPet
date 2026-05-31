import Foundation
import SwiftData

enum PersistenceController {
    static func makeModelContainer(storeFileName: String = "PetTaskBuddy.store") throws -> ModelContainer {
        let schema = Schema([
            DailyTask.self,
            PetStateRecord.self,
            ScheduleItem.self,
            Goal.self
        ])

        let storeURL = try applicationSupportDirectory()
            .appendingPathComponent(storeFileName)
        let configuration = ModelConfiguration(
            "PetTaskBuddy",
            schema: schema,
            url: storeURL
        )

        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func applicationSupportDirectory() throws -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = baseURL.appendingPathComponent("PetTaskBuddy", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
