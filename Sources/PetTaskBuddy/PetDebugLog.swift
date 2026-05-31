import Foundation

enum PetDebugLog {
    private static let subsystem = "[PetTaskBuddy]"

    static func write(_ message: String) {
        let line = "\(timestamp()) \(subsystem) \(message)\n"
        NSLog("%@", line.trimmingCharacters(in: .newlines))

        guard let logsDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs", isDirectory: true)
        else { return }

        do {
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            let logURL = logsDirectory.appendingPathComponent("PetTaskBuddy.log")
            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: logURL, options: .atomic)
            }
        } catch {
            NSLog("[PetTaskBuddy] Failed to write debug log: \(error.localizedDescription)")
        }
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
