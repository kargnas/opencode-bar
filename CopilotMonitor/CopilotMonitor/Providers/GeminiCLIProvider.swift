import Foundation
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "GeminiCLIProvider")

// MARK: - Gemini CLI API Response Models

/// Response structure from Gemini CLI quota API
struct GeminiQuotaResponse: Codable {
    struct Bucket: Codable {
        let modelId: String
        let remainingFraction: Double
        let resetTime: String
    }
    
    let buckets: [Bucket]
}

// MARK: - GeminiCLIProvider Implementation

/// Provider for Google Gemini CLI quota tracking via cloudcode-pa.googleapis.com
/// Uses OAuth token refresh from antigravity-accounts.json
final class GeminiCLIProvider: ProviderProtocol {
    let identifier: ProviderIdentifier = .geminiCLI
    let type: ProviderType = .quotaBased
    
    private let tokenManager: TokenManager
    private let session: URLSession
    
    init(tokenManager: TokenManager = .shared, session: URLSession = .shared) {
        self.tokenManager = tokenManager
        self.session = session
    }
    
    // MARK: - ProviderProtocol Implementation
    
    /// Fetches Gemini CLI quota data from cloudcode-pa.googleapis.com
    /// - Returns: ProviderResult with remaining quota percentage (worst-case across all models)
    /// - Throws: ProviderError if fetch fails
    func fetch() async throws -> ProviderResult {
        // Refresh OAuth access token using stored refresh token
        guard let accessToken = try await tokenManager.refreshGeminiAccessTokenFromStorage() else {
            logger.error("Failed to refresh Gemini access token")
            throw ProviderError.authenticationFailed("Unable to refresh Gemini OAuth token")
        }
        
        // Build request
        guard let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota") else {
            logger.error("Invalid Gemini quota API URL")
            throw ProviderError.networkError("Invalid API endpoint")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)
        
        // Execute request
        let (data, response) = try await session.data(for: request)
        
        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Invalid response type from Gemini API")
            throw ProviderError.networkError("Invalid response type")
        }
        
        // Handle authentication errors
        if httpResponse.statusCode == 401 {
            logger.warning("Gemini API returned 401 - token expired")
            throw ProviderError.authenticationFailed("Token expired or invalid")
        }
        
        // Handle other HTTP errors
        guard (200...299).contains(httpResponse.statusCode) else {
            logger.error("Gemini API returned status \(httpResponse.statusCode)")
            throw ProviderError.networkError("HTTP \(httpResponse.statusCode)")
        }
        
        // Parse response
        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(GeminiQuotaResponse.self, from: data)
            
            guard !response.buckets.isEmpty else {
                logger.error("Gemini API response contains no buckets")
                throw ProviderError.decodingError("Empty buckets array")
            }
            
            // Build per-model quota breakdown
            var modelBreakdown: [String: Double] = [:]
            var minFraction = 1.0
            
            for bucket in response.buckets {
                let percentage = bucket.remainingFraction * 100.0
                modelBreakdown[bucket.modelId] = percentage
                minFraction = min(minFraction, bucket.remainingFraction)
            }
            
            // Convert minimum fraction (0.0-1.0) to percentage (0-100)
            let remainingPercentage = minFraction * 100.0
            
            // Find earliest reset time
            let resetDates = response.buckets.compactMap { bucket -> Date? in
                let formatter = ISO8601DateFormatter()
                return formatter.date(from: bucket.resetTime)
            }
            let earliestReset = resetDates.min()
            
            logger.info("Gemini CLI quota fetched: \(remainingPercentage)% remaining (min across \(response.buckets.count) models), resets at \(earliestReset?.description ?? "unknown")")
            
            // Return as quota-based usage with remaining percentage
            // Using 100 as entitlement since we're working with percentages
            let usage = ProviderUsage.quotaBased(
                remaining: Int(remainingPercentage),
                entitlement: 100,
                overagePermitted: false
            )
            
            // Create DetailedUsage with per-model breakdown
            let details = DetailedUsage(modelBreakdown: modelBreakdown)
            return ProviderResult(usage: usage, details: details)
        } catch let error as DecodingError {
            logger.error("Failed to decode Gemini response: \(error.localizedDescription)")
            throw ProviderError.decodingError("Invalid response format: \(error.localizedDescription)")
        } catch {
            logger.error("Unexpected error parsing Gemini response: \(error.localizedDescription)")
            throw ProviderError.providerError("Failed to parse response: \(error.localizedDescription)")
        }
    }
}
