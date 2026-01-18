import Foundation

struct CopilotUsage: Codable {
    let netBilledAmount: Double
    let netQuantity: Double
    let discountQuantity: Double
    let userPremiumRequestEntitlement: Int
    let filteredUserPremiumRequestEntitlement: Int
    
    init(netBilledAmount: Double, netQuantity: Double, discountQuantity: Double, userPremiumRequestEntitlement: Int, filteredUserPremiumRequestEntitlement: Int) {
        self.netBilledAmount = netBilledAmount
        self.netQuantity = netQuantity
        self.discountQuantity = discountQuantity
        self.userPremiumRequestEntitlement = userPremiumRequestEntitlement
        self.filteredUserPremiumRequestEntitlement = filteredUserPremiumRequestEntitlement
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        netBilledAmount = (try? container.decodeIfPresent(Double.self, forKey: .netBilledAmount)) ?? 0.0
        netQuantity = (try? container.decodeIfPresent(Double.self, forKey: .netQuantity)) ?? 0.0
        discountQuantity = (try? container.decodeIfPresent(Double.self, forKey: .discountQuantity)) ?? 0.0
        userPremiumRequestEntitlement = (try? container.decodeIfPresent(Int.self, forKey: .userPremiumRequestEntitlement)) ?? 0
        filteredUserPremiumRequestEntitlement = (try? container.decodeIfPresent(Int.self, forKey: .filteredUserPremiumRequestEntitlement)) ?? 0
    }
    
    var usedRequests: Int { return Int(discountQuantity) }
    var limitRequests: Int { return userPremiumRequestEntitlement }
    var usagePercentage: Double {
        guard limitRequests > 0 else { return 0 }
        return (Double(usedRequests) / Double(limitRequests)) * 100
    }
}

struct CachedUsage: Codable {
    let usage: CopilotUsage
    let timestamp: Date
}
