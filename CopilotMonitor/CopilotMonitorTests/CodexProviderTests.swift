import XCTest
@testable import CopilotMonitor

final class CodexProviderTests: XCTestCase {
    
    var provider: CodexProvider!
    
    override func setUp() {
        super.setUp()
        provider = CodexProvider()
    }
    
    override func tearDown() {
        provider = nil
        super.tearDown()
    }
    
    func testProviderIdentifier() {
        XCTAssertEqual(provider.identifier, .codex)
    }
    
    func testProviderType() {
        XCTAssertEqual(provider.type, .quotaBased)
    }
    
    func testCodexFixtureDecoding() throws {
        let fixture = try loadFixture(named: "codex_response")
        
        guard let dict = fixture as? [String: Any] else {
            XCTFail("Fixture should be a dictionary")
            return
        }
        
        XCTAssertNotNil(dict["plan_type"])
        XCTAssertNotNil(dict["rate_limit"])
        
        guard let rateLimit = dict["rate_limit"] as? [String: Any] else {
            XCTFail("rate_limit should be a dictionary")
            return
        }
        
        guard let primaryWindow = rateLimit["primary_window"] as? [String: Any] else {
            XCTFail("primary_window should be a dictionary")
            return
        }
        
        let usedPercent = primaryWindow["used_percent"] as? Double
        let resetAfterSeconds = primaryWindow["reset_after_seconds"] as? Int
        
        XCTAssertNotNil(usedPercent)
        XCTAssertNotNil(resetAfterSeconds)
        XCTAssertEqual(usedPercent, 9.0)
        XCTAssertEqual(resetAfterSeconds, 7252)
    }
    
    func testProviderUsageQuotaBasedModel() {
        let usage = ProviderUsage.quotaBased(remaining: 91, entitlement: 100, overagePermitted: false)
        
        XCTAssertEqual(usage.usagePercentage, 9.0)
        XCTAssertTrue(usage.isWithinLimit)
        XCTAssertEqual(usage.remainingQuota, 91)
        XCTAssertEqual(usage.totalEntitlement, 100)
        XCTAssertNil(usage.resetTime)
    }
    
    func testProviderUsageStatusMessage() {
        let usage = ProviderUsage.quotaBased(remaining: 91, entitlement: 100, overagePermitted: false)
        
        let message = usage.statusMessage
        XCTAssertTrue(message.contains("91"))
        XCTAssertTrue(message.contains("remaining"))
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
