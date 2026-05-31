import Foundation

enum PetLayout {
    static let spriteDisplayScale: Double = 0.76
}

enum ThoughtBubbleLayout {
    static let scale: Double = 0.86
    static let windowSize = CGSize(width: 310, height: 230)
    static let verticalSpacing: Double = 4
    static let bottomPadding: Double = 2
    static let petTopOverlap: Double = 38
    static let pillHorizontalPadding: Double = 10
    static let pillVerticalPadding: Double = 6
    static let pillFloatOffset: Double = 2
    static let pillInitialRiseOffset: Double = 12
    static let overflowOffsetX: Double = 28
    static let bubbleOffsets: [Double] = [-22, 20, -8, 28]
    static let dotSpacing: Double = 3
    static let dotSizes: [Double] = [5, 8, 11]
}
