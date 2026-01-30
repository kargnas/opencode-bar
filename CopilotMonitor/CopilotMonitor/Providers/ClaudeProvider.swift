import Foundation
import os.log

private let logger = Logger(subsystem: "com.copilotmonitor", category: "ClaudeProvider")

// MARK: - Claude API Response Models

/// Response structure from Claude usage API
struct ClaudeUsageResponse: Codable {
    struct UsageWindow: Codable {
        let utilization: Double
        let resets_at: String?
        
        enum CodingKeys: String, CodingKey {
            case utilization
            case resets_at = "resets_at"
        }
    }
    
    let seven_day: UsageWindow?
    
    enum CodingKeys: String, CodingKey {
        case seven_day = "seven_day"
    }
}

// MARK: - ClaudeProvider Implementation

/// Provider for Anthropic Claude API usage tracking
/// Uses quota-based model with 7-day rolling window
final class ClaudeProvider: ProviderProtocol {
    let identifier: ProviderIdentifier = .claude
    let type: ProviderType = .quotaBased
    
    private let tokenManager: TokenManager
    private let session: URLSession
    
    init(tokenManager: TokenManager = .shared, session: URLSession = .shared) {
        self.tokenManager = tokenManager
        self.session = session
    }
    
    // MARK: - ProviderProtocol Implementation
    
    /// Fetches Claude usage data from Anthropic API
    /// - Returns: ProviderResult with remaining quota percentage
    /// - Throws: ProviderError if fetch fails
    func fetch() async throws -> ProviderResult {
        // Get access token from TokenManager
        guard let accessToken = tokenManager.getAnthropicAccessToken() else {
            logger.error("Claude access token not found")
            throw ProviderError.authenticationFailed("Anthropic access token not available")
        }
        
        // Build request
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            logger.error("Invalid Claude API URL")
            throw ProviderError.networkError("Invalid API endpoint")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        
        // Execute request
        let (data, response) = try await session.data(for: request)
        
        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Invalid response type from Claude API")
            throw ProviderError.networkError("Invalid response type")
        }
        
        // Handle authentication errors
        if httpResponse.statusCode == 401 {
            logger.warning("Claude API returned 401 - token expired")
            throw ProviderError.authenticationFailed("Token expired or invalid")
        }
        
        // Handle other HTTP errors
        guard (200...299).contains(httpResponse.statusCode) else {
            logger.error("Claude API returned status \(httpResponse.statusCode)")
            throw ProviderError.networkError("HTTP \(httpResponse.statusCode)")
        }
        
        // Parse response
        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(ClaudeUsageResponse.self, from: data)
            
            guard let sevenDay = response.seven_day else {
                logger.error("Claude API response missing seven_day window")
                throw ProviderError.decodingError("Missing seven_day usage window")
            }
            
            // Parse utilization (0-100)
            let utilization = sevenDay.utilization
            
            // Calculate remaining percentage (100 - utilization)
            let remaining = 100 - utilization
            
            // Parse reset time
            var resetDate: Date? = nil
            if let resetsAtString = sevenDay.resets_at {
                let formatter = ISO8601DateFormatter()
                resetDate = formatter.date(from: resetsAtString)
            }
            
            logger.info("Claude usage fetched: \(utilization)% used, resets at \(resetDate?.description ?? "unknown")")
            
            // Return as quota-based usage with remaining percentage as Int
            // Note: ProviderUsage.quotaBased expects Int, so we convert percentage to Int
            let usage = ProviderUsage.quotaBased(
                remaining: Int(remaining),
                entitlement: 100,
                overagePermitted: false
            )
            return ProviderResult(usage: usage, details: nil)
        } catch let error as DecodingError {
            logger.error("Failed to decode Claude response: \(error.localizedDescription)")
            throw ProviderError.decodingError("Invalid response format: \(error.localizedDescription)")
        } catch {
            logger.error("Unexpected error parsing Claude response: \(error.localizedDescription)")
            throw ProviderError.providerError("Failed to parse response: \(error.localizedDescription)")
        }
    }
}
