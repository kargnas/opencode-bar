import XCTest
@testable import OpenCode_Bar

final class ZaiCodingPlanProviderTests: XCTestCase {

    func testProviderIdentifier() {
        let provider = ZaiCodingPlanProvider()
        XCTAssertEqual(provider.identifier, .zaiCodingPlan)
    }

    func testProviderType() {
        let provider = ZaiCodingPlanProvider()
        XCTAssertEqual(provider.type, .quotaBased)
    }
}
