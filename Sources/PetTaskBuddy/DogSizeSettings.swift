import CoreGraphics
import Foundation

@MainActor
final class DogSizeSettings {
    static let shared = DogSizeSettings()
    nonisolated static let userDefaultsKey = "CyberPet.DogScalePercent"
    nonisolated static let minimumPercent: Double = 50
    nonisolated static let maximumPercent: Double = 200
    nonisolated static let defaultPercent: Double = 100

    private let userDefaults: UserDefaults
    private(set) var percent: Double

    var scale: CGFloat {
        CGFloat(percent / 100)
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if userDefaults.object(forKey: Self.userDefaultsKey) == nil {
            percent = Self.defaultPercent
        } else {
            percent = Self.clampedPercent(userDefaults.double(forKey: Self.userDefaultsKey))
        }
    }

    func setPercent(_ percent: Double) {
        self.percent = Self.clampedPercent(percent)
        userDefaults.set(self.percent, forKey: Self.userDefaultsKey)
    }

    func reset() {
        setPercent(Self.defaultPercent)
    }

    nonisolated static func clampedPercent(_ percent: Double) -> Double {
        min(max(percent, minimumPercent), maximumPercent)
    }

    nonisolated static func clampedScale(_ scale: CGFloat) -> CGFloat {
        CGFloat(clampedPercent(Double(scale) * 100) / 100)
    }
}
