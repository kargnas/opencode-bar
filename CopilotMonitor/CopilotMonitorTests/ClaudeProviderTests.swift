import XCTest
@testable import OpenCode_Bar

final class ClaudeProviderTests: XCTestCase {
    
    func testProviderIdentifier() {
        let provider = ClaudeProvider()
        XCTAssertEqual(provider.identifier, .claude)
    }
    
    func testProviderType() {
        let provider = ClaudeProvider()
        XCTAssertEqual(provider.type, .quotaBased)
    }
    
    func testClaudeUsageResponseDecoding() throws {
        let fixtureData = loadFixture(named: "claude_response.json")
        let decoder = JSONDecoder()
        let response = try decoder.decode(ClaudeUsageResponse.self, from: fixtureData)
        
        XCTAssertNotNil(response.seven_day)
        XCTAssertEqual(response.seven_day?.utilization, 4.0)
        XCTAssertEqual(response.seven_day?.resets_at, "2026-02-05T15:00:00Z")
    }
    
    func testClaudeUsageResponseWithHighUtilization() throws {
        let customResponse = """
        {
          "seven_day": {
            "utilization": 85.5,
            "resets_at": "2026-02-05T15:00:00Z"
          }
        }
        """
        let decoder = JSONDecoder()
        let response = try decoder.decode(ClaudeUsageResponse.self, from: customResponse.data(using: .utf8)!)
        
        XCTAssertEqual(response.seven_day?.utilization, 85.5)
    }
    
    func testClaudeUsageResponseWithNullResetTime() throws {
        let customResponse = """
        {
          "seven_day": {
            "utilization": 42.0,
            "resets_at": null
          }
        }
        """
        let decoder = JSONDecoder()
        let response = try decoder.decode(ClaudeUsageResponse.self, from: customResponse.data(using: .utf8)!)
        
        XCTAssertEqual(response.seven_day?.utilization, 42.0)
        XCTAssertNil(response.seven_day?.resets_at)
    }
    
    func testClaudeUsageResponseMissingSevenDay() throws {
        let responseWithoutSevenDay = """
        {
          "five_hour": {
            "utilization": 23.0,
            "resets_at": "2026-01-29T20:00:00Z"
          }
        }
        """
        let decoder = JSONDecoder()
        let response = try decoder.decode(ClaudeUsageResponse.self, from: responseWithoutSevenDay.data(using: .utf8)!)
        
        XCTAssertNil(response.seven_day)
    }
    
    private func loadFixture(named: String) -> Data {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: named, withExtension: nil) else {
            fatalError("Fixture \(named) not found")
        }
        guard let data = try? Data(contentsOf: url) else {
            fatalError("Could not load fixture \(named)")
        }
        return data
    }
}
