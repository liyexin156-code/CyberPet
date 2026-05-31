import Foundation
import SwiftData

@Model
final class PetStateRecord {
    @Attribute(.unique) var id: String
    var fullness: Int
    var mood: Int
    var level: Int
    var xp: Int
    var lastUpdated: Date

    init(
        id: String = "default",
        fullness: Int = 60,
        mood: Int = 60,
        level: Int = 1,
        xp: Int = 0,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.fullness = fullness
        self.mood = mood
        self.level = level
        self.xp = xp
        self.lastUpdated = lastUpdated
    }
}

enum PetRewardKind: Equatable {
    case eat
    case drink

    var animationState: PetAnimationState {
        switch self {
        case .eat: .eat
        case .drink: .drink
        }
    }
}
