import Foundation
import WebKit

enum UsageFetcherError: LocalizedError {
    case noCustomerId
    case noUsageData
    case invalidJSResult
    case parsingFailed(String)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .noCustomerId:
            return "Customer ID not found"
        case .noUsageData:
            return "Usage data not found"
        case .invalidJSResult:
            return "Invalid JS result"
        case .parsingFailed(let detail):
            return "Parsing failed: \(detail)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

final class UsageFetcher {
    static func fetchUsage(from webView: WKWebView) async throws -> CopilotUsage {
        let customerId = try await extractCustomerId(from: webView)
        let usage = try await fetchUsageData(from: webView, customerId: customerId)
        return usage
    }
    
    private static func extractCustomerId(from webView: WKWebView) async throws -> String {
        print("Extracting Customer ID...")
        let js = """
        (function() {
            const el = document.querySelector('script[data-target="react-app.embeddedData"]');
            if (!el) return 'no_element';
            try {
                const data = JSON.parse(el.textContent);
                const id = data?.payload?.customer?.customerId;
                return id ? id.toString() : 'no_id_in_json';
            } catch(e) {
                return 'parse_error: ' + e.message;
            }
        })();
        """
        
        let result = try await webView.callAsyncJavaScript(
            js,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        
        NSLog("JS Result for Customer ID: %@", String(describing: result))
        
        guard let customerId = result as? String, !customerId.contains("_error"), customerId != "no_element", customerId != "no_id_in_json" else {
            NSLog("Failed to get Customer ID")
            throw UsageFetcherError.noCustomerId
        }
        
        NSLog("Got Customer ID: %@", customerId)
        return customerId
    }
    
    private static func fetchUsageData(from webView: WKWebView, customerId: String) async throws -> CopilotUsage {
        print("Fetching usage data for ID: \(customerId)...")
        let js = """
        (async function() {
            try {
                const response = await fetch('/settings/billing/copilot_usage_card?customer_id=\(customerId)&period=3');
                if (!response.ok) return { error: 'HTTP ' + response.status };
                return await response.json();
            } catch (e) {
                return { error: 'fetch_error: ' + e.message };
            }
        })();
        """
        
        let result = try await webView.callAsyncJavaScript(
            js,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        
        print("JS Result for Usage Data: \(String(describing: result))")
        
        guard let dict = result as? [String: Any] else {
            print("Usage data result is not a dictionary")
            throw UsageFetcherError.noUsageData
        }
        
        if let errorMsg = dict["error"] as? String {
            print("Server returned error: \(errorMsg)")
            throw UsageFetcherError.parsingFailed(errorMsg)
        }
        
        let netBilledAmount = (dict["netBilledAmount"] as? Double) ?? (dict["netBilledAmount"] as? Int).map { Double($0) } ?? (dict["netBilledAmount"] as? NSNumber)?.doubleValue ?? 0.0
        let netQuantity = (dict["netQuantity"] as? Double) ?? (dict["netQuantity"] as? Int).map { Double($0) } ?? (dict["netQuantity"] as? NSNumber)?.doubleValue ?? 0.0
        let discountQuantity = (dict["discountQuantity"] as? Double) ?? (dict["discountQuantity"] as? Int).map { Double($0) } ?? (dict["discountQuantity"] as? NSNumber)?.doubleValue ?? 0.0
        let userPremiumRequestEntitlement = (dict["userPremiumRequestEntitlement"] as? Int) ?? (dict["userPremiumRequestEntitlement"] as? Double).map { Int($0) } ?? (dict["userPremiumRequestEntitlement"] as? NSNumber)?.intValue ?? 0
        let filteredUserPremiumRequestEntitlement = (dict["filteredUserPremiumRequestEntitlement"] as? Int) ?? (dict["filteredUserPremiumRequestEntitlement"] as? Double).map { Int($0) } ?? (dict["filteredUserPremiumRequestEntitlement"] as? NSNumber)?.intValue ?? 0
        
        print("Parsed values: discountQuantity=\(discountQuantity), userPremiumRequestEntitlement=\(userPremiumRequestEntitlement)")
        
        let usage = CopilotUsage(
            netBilledAmount: netBilledAmount,
            netQuantity: netQuantity,
            discountQuantity: discountQuantity,
            userPremiumRequestEntitlement: userPremiumRequestEntitlement,
            filteredUserPremiumRequestEntitlement: filteredUserPremiumRequestEntitlement
        )
        
        print("Successfully created usage object")
        return usage
    }
}
