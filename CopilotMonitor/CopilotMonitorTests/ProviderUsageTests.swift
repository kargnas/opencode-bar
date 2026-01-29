import XCTest

/// Basic test suite for provider usage models and fixtures
final class ProviderUsageTests: XCTestCase {
    
    // MARK: - Fixture Loading Tests
    
    /// Test that Claude fixture JSON can be loaded and decoded
    func testClaudeFixtureLoading() throws {
        let fixture = try loadFixture(named: "claude_response")
        XCTAssertNotNil(fixture)
        
        // Verify structure
        let dict = fixture as? [String: Any]
        XCTAssertNotNil(dict?["five_hour"])
        XCTAssertNotNil(dict?["seven_day"])
    }
    
    /// Test that Codex fixture JSON can be loaded and decoded
    func testCodexFixtureLoading() throws {
        let fixture = try loadFixture(named: "codex_response")
        XCTAssertNotNil(fixture)
        
        // Verify structure
        let dict = fixture as? [String: Any]
        XCTAssertNotNil(dict?["plan_type"])
        XCTAssertNotNil(dict?["rate_limit"])
    }
    
    /// Test that Copilot fixture JSON can be loaded and decoded
    func testCopilotFixtureLoading() throws {
        let fixture = try loadFixture(named: "copilot_response")
        XCTAssertNotNil(fixture)
        
        // Verify structure
        let dict = fixture as? [String: Any]
        XCTAssertNotNil(dict?["copilot_plan"])
        XCTAssertNotNil(dict?["quota_snapshots"])
    }
    
    /// Test that Gemini fixture JSON can be loaded and decoded
    func testGeminiFixtureLoading() throws {
        let fixture = try loadFixture(named: "gemini_response")
        XCTAssertNotNil(fixture)
        
        // Verify structure
        let dict = fixture as? [String: Any]
        XCTAssertNotNil(dict?["buckets"])
    }
    
    // MARK: - Helper Methods
    
    /// Load a JSON fixture file from the test bundle resources
    /// - Parameter named: The name of the fixture file (without .json extension)
    /// - Returns: Decoded JSON object
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
