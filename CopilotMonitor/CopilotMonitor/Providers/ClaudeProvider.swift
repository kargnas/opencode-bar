import Foundation
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "ClaudeProvider")

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
    
    struct ExtraUsage: Codable {
        let is_enabled: Bool?
        
        enum CodingKeys: String, CodingKey {
            case is_enabled = "is_enabled"
        }
    }
    
    let five_hour: UsageWindow?
    let seven_day: UsageWindow?
    let seven_day_sonnet: UsageWindow?
    let seven_day_opus: UsageWindow?
    let extra_usage: ExtraUsage?
    
    enum CodingKeys: String, CodingKey {
        case five_hour = "five_hour"
        case seven_day = "seven_day"
        case seven_day_sonnet = "seven_day_sonnet"
        case seven_day_opus = "seven_day_opus"
        case extra_usage = "extra_usage"
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
            
            // Parse reset times - try with fractional seconds first, then without
            func parseISO8601Date(_ string: String) -> Date? {
                let formatterWithFrac = ISO8601DateFormatter()
                formatterWithFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatterWithFrac.date(from: string) {
                    return date
                }
                
                let formatterWithoutFrac = ISO8601DateFormatter()
                formatterWithoutFrac.formatOptions = [.withInternetDateTime]
                return formatterWithoutFrac.date(from: string)
            }
            
            let fiveHourReset = response.five_hour?.resets_at.flatMap { parseISO8601Date($0) }
            let sevenDayReset = sevenDay.resets_at.flatMap { parseISO8601Date($0) }
            
            logger.info("Claude reset times - 5h: \(fiveHourReset?.description ?? "nil"), 7d: \(sevenDayReset?.description ?? "nil")")
            
            let fiveHourUsage = response.five_hour?.utilization
            let sonnetUsage = response.seven_day_sonnet?.utilization
            let sonnetReset = response.seven_day_sonnet?.resets_at.flatMap { parseISO8601Date($0) }
            let opusUsage = response.seven_day_opus?.utilization
            let opusReset = response.seven_day_opus?.resets_at.flatMap { parseISO8601Date($0) }
            
            let extraUsageEnabled = response.extra_usage?.is_enabled
            
            logger.info("Claude usage fetched: 7d=\(utilization)%, 5h=\(fiveHourUsage?.description ?? "N/A")%, sonnet=\(sonnetUsage?.description ?? "N/A")%, opus=\(opusUsage?.description ?? "N/A")%")
            
            let usage = ProviderUsage.quotaBased(
                remaining: Int(remaining),
                entitlement: 100,
                overagePermitted: false
            )
            
            let details = DetailedUsage(
                fiveHourUsage: fiveHourUsage,
                fiveHourReset: fiveHourReset,
                sevenDayUsage: utilization,
                sevenDayReset: sevenDayReset,
                sonnetUsage: sonnetUsage,
                sonnetReset: sonnetReset,
                opusUsage: opusUsage,
                opusReset: opusReset,
                extraUsageEnabled: extraUsageEnabled,
                authSource: "~/.local/share/opencode/auth.json"
            )
            
            return ProviderResult(usage: usage, details: details)
        } catch let error as DecodingError {
            logger.error("Failed to decode Claude response: \(error.localizedDescription)")
            throw ProviderError.decodingError("Invalid response format: \(error.localizedDescription)")
        } catch {
            logger.error("Unexpected error parsing Claude response: \(error.localizedDescription)")
            throw ProviderError.providerError("Failed to parse response: \(error.localizedDescription)")
        }
    }
}
