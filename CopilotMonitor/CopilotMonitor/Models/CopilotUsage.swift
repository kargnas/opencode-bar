import Foundation

struct CopilotUsage: Codable {
    let netBilledAmount: Double
    let netQuantity: Double
    let discountQuantity: Double
    let userPremiumRequestEntitlement: Int
    let filteredUserPremiumRequestEntitlement: Int
    
    // Plan and reset date info (from /copilot_internal/user API)
    let copilotPlan: String?
    let quotaResetDateUTC: Date?

    init(netBilledAmount: Double, netQuantity: Double, discountQuantity: Double, userPremiumRequestEntitlement: Int, filteredUserPremiumRequestEntitlement: Int, copilotPlan: String? = nil, quotaResetDateUTC: Date? = nil) {
        self.netBilledAmount = netBilledAmount
        self.netQuantity = netQuantity
        self.discountQuantity = discountQuantity
        self.userPremiumRequestEntitlement = userPremiumRequestEntitlement
        self.filteredUserPremiumRequestEntitlement = filteredUserPremiumRequestEntitlement
        self.copilotPlan = copilotPlan
        self.quotaResetDateUTC = quotaResetDateUTC
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        netBilledAmount = (try? container.decodeIfPresent(Double.self, forKey: .netBilledAmount)) ?? 0.0
        netQuantity = (try? container.decodeIfPresent(Double.self, forKey: .netQuantity)) ?? 0.0
        discountQuantity = (try? container.decodeIfPresent(Double.self, forKey: .discountQuantity)) ?? 0.0
        userPremiumRequestEntitlement = (try? container.decodeIfPresent(Int.self, forKey: .userPremiumRequestEntitlement)) ?? 0
        filteredUserPremiumRequestEntitlement = (try? container.decodeIfPresent(Int.self, forKey: .filteredUserPremiumRequestEntitlement)) ?? 0
        copilotPlan = try? container.decodeIfPresent(String.self, forKey: .copilotPlan)
        quotaResetDateUTC = try? container.decodeIfPresent(Date.self, forKey: .quotaResetDateUTC)
    }

    var usedRequests: Int { return Int(discountQuantity) }
    var limitRequests: Int { return userPremiumRequestEntitlement }
    var usagePercentage: Double {
        guard limitRequests > 0 else { return 0 }
        return (Double(usedRequests) / Double(limitRequests)) * 100
    }
    
    /// Human-readable plan name from API response (e.g., "individual_pro" -> "Pro")
    var planDisplayName: String? {
        guard let plan = copilotPlan else { return nil }
        switch plan.lowercased() {
        case "individual_pro":
            return "Pro"
        case "individual_free":
            return "Free"
        case "business":
            return "Business"
        case "enterprise":
            return "Enterprise"
        default:
            // Fallback: capitalize the plan name
            return plan.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

struct CachedUsage: Codable {
    let usage: CopilotUsage
    let timestamp: Date
}
