import Foundation

struct AnimationManifest: Decodable {
    struct Transition: Decodable {
        let crossfadeMs: Int
    }

    struct State: Decodable {
        enum StateType: String, Decodable {
            case loop
            case oneshot
            case once
        }

        let frames: Int
        let fps: Double
        let type: StateType
        let returnTo: String?
    }

    let frameSize: Int
    let scale: Double
    let transition: Transition?
    let states: [String: State]
    let bridges: [String: String]?
}

enum PetAnimationState: String, CaseIterable {
    case idle
    case walk
    case run
    case happy
    case listless
    case eat
    case drink
    case sleep
    case stretch
    case sitFront = "sit_front"
    case sniff
    case lookFront = "look_front"
    case lieDown = "lie_down"
    case shake
    case scratch
    case pee
    case poop
}
