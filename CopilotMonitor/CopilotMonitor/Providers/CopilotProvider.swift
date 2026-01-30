import Foundation
import WebKit
import os.log

private let logger = Logger(subsystem: "com.copilotmonitor", category: "CopilotProvider")

// MARK: - CopilotProvider Implementation

/// Provider for GitHub Copilot usage tracking
/// Uses quota-based model with overage cost calculation
final class CopilotProvider: ProviderProtocol {
    let identifier: ProviderIdentifier = .copilot
    let type: ProviderType = .quotaBased
    
    private let webView: WKWebView
    private let cacheKey = "cached_copilot_usage"
    
    /// Initialize with WebView for API access
    /// - Parameter webView: WebView instance from AuthManager for authenticated requests
    init(webView: WKWebView) {
        self.webView = webView
    }
    
    // MARK: - ProviderProtocol Implementation
    
    /// Fetches Copilot usage data from GitHub internal API
    /// - Returns: ProviderResult.quotaBased with remaining, entitlement, and overage
    /// - Throws: ProviderError if fetch fails (falls back to cached data)
    func fetch() async throws -> ProviderResult {
        logger.info("CopilotProvider: Starting fetch")
        
        guard let customerId = await fetchCustomerId() else {
            logger.warning("CopilotProvider: Failed to get customer ID, trying cache")
            return try loadCachedUsage()
        }
        
        logger.info("CopilotProvider: Customer ID obtained - \(customerId)")
        
        guard let usage = await fetchUsageData(customerId: customerId) else {
            logger.warning("CopilotProvider: Failed to fetch usage data, trying cache")
            return try loadCachedUsage()
        }
        
        saveCache(usage: usage)
        
        let remaining = usage.limitRequests - usage.usedRequests
        
        logger.info("CopilotProvider: Fetch successful - used: \(usage.usedRequests), limit: \(usage.limitRequests), remaining: \(remaining)")
        
        let providerUsage = ProviderUsage.quotaBased(
            remaining: remaining,
            entitlement: usage.limitRequests,
            overagePermitted: true
        )
        return ProviderResult(usage: providerUsage, details: nil)
    }
    
    // MARK: - Customer ID Fetching
    
    /// Attempts to fetch customer ID using multiple strategies
    /// - Returns: Customer ID string or nil if all strategies fail
    private func fetchCustomerId() async -> String? {
        // Strategy 1: API endpoint
        if let apiId = await fetchCustomerIdFromAPI() {
            return apiId
        }
        
        // Strategy 2: DOM extraction
        if let domId = await fetchCustomerIdFromDOM() {
            return domId
        }
        
        // Strategy 3: HTML regex
        if let htmlId = await fetchCustomerIdFromHTML() {
            return htmlId
        }
        
        return nil
    }
    
    /// Fetch customer ID from GitHub API endpoint
    private func fetchCustomerIdFromAPI() async -> String? {
        logger.info("CopilotProvider: [Step 1] Trying API (/api/v3/user)")
        
        let userApiJS = """
        return await (async function() {
            try {
                const response = await fetch('/api/v3/user', {
                    headers: { 'Accept': 'application/json' }
                });
                if (!response.ok) return JSON.stringify({ error: 'HTTP ' + response.status });
                const data = await response.json();
                return JSON.stringify(data);
            } catch (e) {
                return JSON.stringify({ error: e.toString() });
            }
        })()
        """
        
        do {
            let result = try await webView.callAsyncJavaScript(userApiJS, arguments: [:], in: nil, contentWorld: .defaultClient)
            
            if let jsonString = result as? String,
               let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = json["id"] as? Int {
                logger.info("CopilotProvider: API ID obtained - \(id)")
                return String(id)
            }
        } catch {
            logger.error("CopilotProvider: API call error - \(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// Extract customer ID from DOM script tag
    private func fetchCustomerIdFromDOM() async -> String? {
        logger.info("CopilotProvider: [Step 2] Trying DOM extraction")
        
        let extractionJS = """
        return (function() {
            const el = document.querySelector('script[data-target="react-app.embeddedData"]');
            if (el) {
                try {
                    const data = JSON.parse(el.textContent);
                    if (data && data.payload && data.payload.customer && data.payload.customer.customerId) {
                        return data.payload.customer.customerId.toString();
                    }
                } catch(e) {}
            }
            return null;
        })()
        """
        
        if let extracted = try? await evalJSONString(extractionJS) {
            logger.info("CopilotProvider: DOM extraction successful - \(extracted)")
            return extracted
        }
        
        return nil
    }
    
    /// Extract customer ID from HTML using regex patterns
    private func fetchCustomerIdFromHTML() async -> String? {
        logger.info("CopilotProvider: [Step 3] Trying HTML regex")
        
        let htmlJS = "return document.documentElement.outerHTML"
        guard let html = try? await webView.callAsyncJavaScript(htmlJS, arguments: [:], in: nil, contentWorld: .defaultClient) as? String else {
            return nil
        }
        
        let patterns = [
            #"customerId":(\d+)"#,
            #"customerId&quot;:(\d+)"#,
            #"customer_id=(\d+)"#,
            #"data-customer-id="(\d+)""#
        ]
        
        for pattern in patterns {
            if let customerId = extractCustomerIdWithPattern(pattern, from: html) {
                logger.info("CopilotProvider: HTML extraction successful - \(customerId)")
                return customerId
            }
        }
        
        return nil
    }
    
    /// Extract customer ID using regex pattern
    private func extractCustomerIdWithPattern(_ pattern: String, from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range])
    }
    
    // MARK: - Usage Data Fetching
    
    /// Fetch usage data from GitHub billing API
    /// - Parameter customerId: GitHub customer ID
    /// - Returns: CopilotUsage or nil if fetch fails
    private func fetchUsageData(customerId: String) async -> CopilotUsage? {
        let cardJS = """
        return await (async function() {
            try {
                const res = await fetch('/settings/billing/copilot_usage_card?customer_id=\(customerId)&period=3', {
                    headers: { 'Accept': 'application/json', 'x-requested-with': 'XMLHttpRequest' }
                });
                const text = await res.text();
                try {
                    const json = JSON.parse(text);
                    json._debug_timestamp = new Date().toISOString();
                    return json;
                } catch (e) {
                    return { error: 'JSON Parse Error', body: text };
                }
            } catch(e) { return { error: e.toString() }; }
        })()
        """
        
        do {
            let result = try await webView.callAsyncJavaScript(cardJS, arguments: [:], in: nil, contentWorld: .defaultClient)
            
            guard let rootDict = result as? [String: Any] else {
                logger.error("CopilotProvider: Invalid response type")
                return nil
            }
            
            if let usage = parseUsageFromResponse(rootDict) {
                logger.info("CopilotProvider: Usage data parsed successfully")
                return usage
            }
        } catch {
            logger.error("CopilotProvider: JS execution error - \(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// Parse CopilotUsage from API response dictionary
    /// - Parameter rootDict: Raw response from API
    /// - Returns: Parsed CopilotUsage or nil if parsing fails
    private func parseUsageFromResponse(_ rootDict: [String: Any]) -> CopilotUsage? {
        // Unwrap payload or data wrapper if present
        var dict = rootDict
        if let payload = rootDict["payload"] as? [String: Any] {
            dict = payload
        } else if let data = rootDict["data"] as? [String: Any] {
            dict = data
        }
        
        logger.info("CopilotProvider: Parsing data (Keys: \(dict.keys.joined(separator: ", ")))")
        
        // Extract values with fallback key names
        let netBilledAmount = parseDoubleValue(from: dict, keys: ["netBilledAmount", "net_billed_amount"])
        let netQuantity = parseDoubleValue(from: dict, keys: ["netQuantity", "net_quantity"])
        let discountQuantity = parseDoubleValue(from: dict, keys: ["discountQuantity", "discount_quantity"])
        let limit = parseIntValue(from: dict, keys: ["userPremiumRequestEntitlement", "user_premium_request_entitlement", "quantity"])
        let filteredLimit = parseIntValue(from: dict, keys: ["filteredUserPremiumRequestEntitlement"])
        
        return CopilotUsage(
            netBilledAmount: netBilledAmount,
            netQuantity: netQuantity,
            discountQuantity: discountQuantity,
            userPremiumRequestEntitlement: limit,
            filteredUserPremiumRequestEntitlement: filteredLimit
        )
    }
    
    /// Parse double value from dictionary with multiple possible keys
    private func parseDoubleValue(from dict: [String: Any], keys: [String]) -> Double {
        for key in keys {
            if let value = dict[key] as? Double {
                return value
            }
            if let value = dict[key] as? Int {
                return Double(value)
            }
            if let value = dict[key] as? NSNumber {
                return value.doubleValue
            }
        }
        return 0.0
    }
    
    /// Parse integer value from dictionary with multiple possible keys
    private func parseIntValue(from dict: [String: Any], keys: [String]) -> Int {
        for key in keys {
            if let value = dict[key] as? Int {
                return value
            }
            if let value = dict[key] as? Double {
                return Int(value)
            }
        }
        return 0
    }
    
    // MARK: - Helper Methods
    
    /// Evaluate JavaScript and return result as String
    private func evalJSONString(_ js: String) async throws -> String {
        let result = try await webView.callAsyncJavaScript(js, arguments: [:], in: nil, contentWorld: .defaultClient)
        
        if let json = result as? String {
            return json
        } else if let dict = result as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict),
                  let json = String(data: data, encoding: .utf8) {
            return json
        } else {
            throw ProviderError.providerError("Invalid JavaScript result type")
        }
    }
    
    // MARK: - Caching
    
    /// Save usage data to UserDefaults cache
    private func saveCache(usage: CopilotUsage) {
        let cached = CachedUsage(usage: usage, timestamp: Date())
        if let encoded = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(encoded, forKey: cacheKey)
            logger.info("CopilotProvider: Cache saved")
        }
    }
    
    /// Load cached usage data and convert to ProviderResult
    /// - Throws: ProviderError.providerError if no cache available
    private func loadCachedUsage() throws -> ProviderResult {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(CachedUsage.self, from: data) else {
            logger.error("CopilotProvider: No cached data available")
            throw ProviderError.providerError("No cached data available")
        }
        
        let usage = cached.usage
        let remaining = usage.limitRequests - usage.usedRequests
        
        logger.info("CopilotProvider: Using cached data from \(cached.timestamp)")
        
        let providerUsage = ProviderUsage.quotaBased(
            remaining: remaining,
            entitlement: usage.limitRequests,
            overagePermitted: true
        )
        return ProviderResult(usage: providerUsage, details: nil)
    }
}
