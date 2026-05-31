import Foundation

enum PetAutonomousBehaviorKind: String {
    case idle
    case walk
    case sit
    case sniff
    case yawn
    case stretch
    case shake
    case scratch
    case lieDown
    case sleep
    case listless
}

// Mouse Attention ("鼠标吸引"): a fast cursor pass near the dog makes it trot
// after the cursor for a few steps, then lose interest. Just walking — no
// eye/head tracking. Never catches the cursor, never follows forever.
enum MouseAttentionConfig {
    // Trigger gating — a *fast* pass *near* the dog only.
    static let triggerRadius: CGFloat = 250          // px from the dog
    static let triggerVelocity: CGFloat = 600        // px/s; slow moves never trigger
    static let sampleMinInterval: TimeInterval = 0.004
    static let sampleMaxGap: TimeInterval = 0.12     // a pause resets the velocity baseline

    // Follow: trot toward the cursor for a few steps, stopping short of it.
    static let followStepsRange: ClosedRange<Int> = 1...3
    static let followMaxStepDistance: CGFloat = 120
    static let followStopGap: CGFloat = 60           // stay this far from the cursor (don't catch it)
    static let followMinStep: CGFloat = 24           // already close enough -> stop
    static let followSpeedPointsPerSecond: CGFloat = 135
    static let followGiveUpRadius: CGFloat = 320      // cursor now too far -> give up

    // Cooldown so the dog doesn't obsessively chase the cursor.
    static let cooldownRange: ClosedRange<TimeInterval> = 8...20
}

enum PetAutonomousBehaviorConfig {
    struct WeightedChoice {
        let kind: PetAutonomousBehaviorKind
        let weight: Double
    }

    struct RewardFeedbackTiming {
        let itemDropDuration: TimeInterval
        let approachDuration: TimeInterval
        let animationTimePerFrame: TimeInterval
        let holdDuration: TimeInterval
        let returnDuration: TimeInterval
        let itemFadeOutDuration: TimeInterval
    }

    static let idleGapRange: ClosedRange<TimeInterval> = 2.5...7.0
    static let firstBehaviorDelayRange: ClosedRange<TimeInterval> = 0.8...1.2

    // Entry animation — window slides in from the screen's right edge.
    // Tune entryRunSpeedPointsPerSecond to taste; the duration is derived
    // automatically from distance / speed, so it adapts to any screen width.
    static let entryRunSpeedPointsPerSecond: CGFloat = 220
    static let manualRunSpeedPointsPerSecond: CGFloat = 650
    // UserDefaults key that controls whether the entry animation plays.
    // Default is true; toggle via UserDefaults or a settings UI toggle.
    static let entryAnimationEnabledKey = "petEntryAnimationEnabled"
    static let reminderPauseBeforeNextBehavior: TimeInterval = 4.6
    static let manualPerformanceDurationRange: ClosedRange<TimeInterval> = 15...30
    static let manualPerformanceStepGap: TimeInterval = 0.35
    static let manualSleepLieDownHold: TimeInterval = 1.4
    static let manualSideLieHoldDuration: TimeInterval = 180

    static let idleHoldRange: ClosedRange<TimeInterval> = 4.0...9.0
    static let sitHoldRange: ClosedRange<TimeInterval> = 4.0...8.0
    static let sniffHoldRange: ClosedRange<TimeInterval> = 4.0...7.0
    static let activeOneShotHoldRange: ClosedRange<TimeInterval> = 3.0...5.5
    static let stretchHoldRange: ClosedRange<TimeInterval> = 2.0...5.0
    static let lieDownHoldRange: ClosedRange<TimeInterval> = 20.0...45.0
    static let sleepHoldRange: ClosedRange<TimeInterval> = 12.0...28.0
    static let listlessHoldRange: ClosedRange<TimeInterval> = 14.0...28.0

    static let walkDistanceRange: ClosedRange<Double> = 72...190
    static let walkVerticalDriftRange: ClosedRange<Double> = -24...30
    static let walkDurationRange: ClosedRange<TimeInterval> = 1.2...2.4
    static let minimumWalkDistance: Double = 28

    // While sniffing, the pet creeps slowly forward (nose to the ground) instead
    // of staying put. The short distance spread over the long sniff hold makes
    // for a deliberately slow drift.
    static let sniffWalkDistanceRange: ClosedRange<Double> = 24...60

    static let dailyWeights: [WeightedChoice] = [
        .init(kind: .idle, weight: 36),
        .init(kind: .sleep, weight: 30),
        .init(kind: .sit, weight: 18),
        .init(kind: .walk, weight: 10),
        .init(kind: .stretch, weight: 6)
    ]

    static func timePerFrame(for state: PetAnimationState) -> TimeInterval {
        switch state {
        case .run:
            1.0 / 16.0
        case .walk:
            0.28
        case .stretch:
            0.36
        case .sitFront, .idle, .sleep:
            0.45
        case .sniff, .lookFront, .shake, .scratch:
            0.30
        case .happy, .listless, .eat, .drink, .lieDown, .pee:
            0.35
        }
    }

    static let sleepWakeStretchChance = 0.45
    static let nightStartHour = 23
    static let nightEndHour = 7

    static let eatRewardTiming = RewardFeedbackTiming(
        itemDropDuration: 0.45,
        approachDuration: 0.75,
        animationTimePerFrame: 0.70,
        holdDuration: 1.45,
        returnDuration: 0.65,
        itemFadeOutDuration: 0.18
    )

    static let drinkRewardTiming = RewardFeedbackTiming(
        itemDropDuration: 0.45,
        approachDuration: 0.75,
        animationTimePerFrame: 0.65,
        holdDuration: 1.55,
        returnDuration: 0.65,
        itemFadeOutDuration: 0.18
    )

    static func rewardTiming(for kind: PetRewardKind) -> RewardFeedbackTiming {
        switch kind {
        case .eat:
            eatRewardTiming
        case .drink:
            drinkRewardTiming
        }
    }

    static let calmWeights: [WeightedChoice] = [
        .init(kind: .lieDown, weight: 38),
        .init(kind: .sleep, weight: 24),
        .init(kind: .idle, weight: 10),
        .init(kind: .sit, weight: 8),
        .init(kind: .sniff, weight: 6),
        .init(kind: .stretch, weight: 5),
        .init(kind: .walk, weight: 4),
        .init(kind: .yawn, weight: 3),
        .init(kind: .scratch, weight: 2)
    ]

    static let happyWeights: [WeightedChoice] = [
        .init(kind: .lieDown, weight: 24),
        .init(kind: .sleep, weight: 12),
        .init(kind: .idle, weight: 14),
        .init(kind: .walk, weight: 12),
        .init(kind: .sit, weight: 10),
        .init(kind: .sniff, weight: 10),
        .init(kind: .stretch, weight: 8),
        .init(kind: .yawn, weight: 5),
        .init(kind: .shake, weight: 3),
        .init(kind: .scratch, weight: 2)
    ]

    static let lowMoodWeights: [WeightedChoice] = [
        .init(kind: .sleep, weight: 36),
        .init(kind: .lieDown, weight: 34),
        .init(kind: .listless, weight: 18),
        .init(kind: .idle, weight: 6),
        .init(kind: .sit, weight: 3),
        .init(kind: .sniff, weight: 2),
        .init(kind: .walk, weight: 1)
    ]

    static let nightWeights: [WeightedChoice] = [
        .init(kind: .sleep, weight: 62),
        .init(kind: .lieDown, weight: 24),
        .init(kind: .listless, weight: 6),
        .init(kind: .idle, weight: 3),
        .init(kind: .sit, weight: 2),
        .init(kind: .stretch, weight: 2),
        .init(kind: .walk, weight: 1)
    ]

    static func holdRange(for kind: PetAutonomousBehaviorKind) -> ClosedRange<TimeInterval> {
        switch kind {
        case .idle:
            idleHoldRange
        case .sit:
            sitHoldRange
        case .sniff:
            sniffHoldRange
        case .stretch:
            stretchHoldRange
        case .yawn, .shake, .scratch:
            activeOneShotHoldRange
        case .lieDown:
            lieDownHoldRange
        case .sleep:
            sleepHoldRange
        case .listless:
            listlessHoldRange
        case .walk:
            walkDurationRange
        }
    }
}

enum PetManualPerformanceKind {
    case stretch
    case walk
    case idle
    case sleep
    case sideLie
    case sit
    case sniff
    case happy
    case roam
    case sleepy
    case shake
    case scratch
}
