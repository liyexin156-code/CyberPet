import XCTest
@testable import PetTaskBuddy

final class ThoughtBubbleHitRegionTests: XCTestCase {
    func testOnlyInteractiveBubbleBandAcceptsMouseEvents() {
        let region = ThoughtBubbleHitRegion(windowSize: CGSize(width: 310, height: 230))

        XCTAssertFalse(region.contains(CGPoint(x: 155, y: 220)))
        XCTAssertFalse(region.contains(CGPoint(x: 18, y: 28)))
        XCTAssertFalse(region.contains(CGPoint(x: 292, y: 28)))
        XCTAssertTrue(region.contains(CGPoint(x: 155, y: 24)))
        XCTAssertTrue(region.contains(CGPoint(x: 155, y: 92)))
    }
}
