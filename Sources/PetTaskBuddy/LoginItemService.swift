import Foundation
import ServiceManagement

enum LoginItemService {
    static func registerMainAppIfPossible() {
        guard !CommandLine.arguments.contains("--skip-login-item-registration") else {
            NSLog("[LoginItem] Skipping registration because --skip-login-item-registration was provided.")
            return
        }

        guard Bundle.main.bundleURL.pathExtension == "app" else {
            NSLog("[LoginItem] Skipping registration because PetTaskBuddy is not running from an app bundle.")
            return
        }

        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            switch service.status {
            case .enabled:
                NSLog("[LoginItem] PetTaskBuddy is already registered as a login item.")
            default:
                do {
                    try service.register()
                    NSLog("[LoginItem] Registered PetTaskBuddy as a login item.")
                } catch {
                    NSLog("[LoginItem] Failed to register login item: \(error.localizedDescription)")
                }
            }
        } else {
            NSLog("[LoginItem] SMAppService login items require macOS 13 or newer. Use the LaunchAgent fallback on older macOS versions.")
        }
    }
}
