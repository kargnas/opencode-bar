import XCTest
@testable import OpenCode_Bar

final class OpenRouterProviderTests: XCTestCase {
    
    var provider: OpenRouterProvider!
    
    override func setUp() {
        super.setUp()
        provider = OpenRouterProvider()
    }
    
    override func tearDown() {
        provider = nil
        super.tearDown()
    }
    
    func testProviderIdentifier() {
        XCTAssertEqual(provider.identifier, .openRouter)
    }
    
    func testProviderType() {
        XCTAssertEqual(provider.type, .payAsYouGo)
    }
    
    func testOpenRouterCreditsFixtureDecoding() throws {
        let fixture = try loadFixture(named: "openrouter_credits_response")
        
        guard let dict = fixture as? [String: Any] else {
            XCTFail("Fixture should be a dictionary")
            return
        }
        
        guard let data = dict["data"] as? [String: Any] else {
            XCTFail("data should be a dictionary")
            return
        }
        
        let totalCredits = data["total_credits"] as? Double
        let totalUsage = data["total_usage"] as? Double
        
        XCTAssertNotNil(totalCredits)
        XCTAssertNotNil(totalUsage)
        XCTAssertEqual(totalCredits, 6685.0)
        XCTAssertEqual(totalUsage, 6548.72)
    }
    
    func testOpenRouterKeyFixtureDecoding() throws {
        let fixture = try loadFixture(named: "openrouter_key_response")
        
        guard let dict = fixture as? [String: Any] else {
            XCTFail("Fixture should be a dictionary")
            return
        }
        
        guard let data = dict["data"] as? [String: Any] else {
            XCTFail("data should be a dictionary")
            return
        }
        
        let limit = data["limit"] as? Double
        let limitRemaining = data["limit_remaining"] as? Double
        let usageDaily = data["usage_daily"] as? Double
        let usageWeekly = data["usage_weekly"] as? Double
        let usageMonthly = data["usage_monthly"] as? Double
        
        XCTAssertNotNil(limit)
        XCTAssertNotNil(limitRemaining)
        XCTAssertNotNil(usageDaily)
        XCTAssertNotNil(usageWeekly)
        XCTAssertNotNil(usageMonthly)
        XCTAssertEqual(limit, 100.0)
        XCTAssertEqual(limitRemaining, 99.99)
        XCTAssertEqual(usageDaily, 0.004)
        XCTAssertEqual(usageWeekly, 0.5)
        XCTAssertEqual(usageMonthly, 37.41)
    }
    
    func testUtilizationCalculation() {
        // Test: (6548.72 / 6685.0) * 100 = 97.96%
        let totalCredits = 6685.0
        let totalUsage = 6548.72
        let utilization = (totalUsage / totalCredits) * 100.0
        
        XCTAssertEqual(utilization, 97.96, accuracy: 0.01)
    }
    
    func testZeroDivisionProtection() {
        // Test: total_credits = 0 should return 0% utilization
        let totalCredits = 0.0
        let totalUsage = 0.0
        let utilization = totalCredits > 0 ? (totalUsage / totalCredits) * 100.0 : 0.0
        
        XCTAssertEqual(utilization, 0.0)
    }
    
    func testProviderUsagePayAsYouGoModel() {
        let usage = ProviderUsage.payAsYouGo(utilization: 97.96, cost: nil, resetsAt: nil)
        
        XCTAssertEqual(usage.usagePercentage, 97.96)
        XCTAssertTrue(usage.isWithinLimit)
        XCTAssertNil(usage.remainingQuota)
        XCTAssertNil(usage.totalEntitlement)
    }
    
    private func loadFixture(named: String) throws -> Any {
        let testBundle = Bundle(for: type(of: self))
        
        guard let url = testBundle.url(forResource: named, withExtension: "json") else {
            throw NSError(domain: "FixtureError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture file not found: \(named)"])
        }
        
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        return json
    }
}
