import Foundation

/// Represents usage data from an AI provider
/// Uses enum with associated values to support different billing models
enum ProviderUsage {
    /// Pay-as-you-go model: tracks utilization percentage and reset time
    /// - utilization: Current usage as percentage (0-100+)
    /// - resetsAt: When the usage window resets
    case payAsYouGo(utilization: Double, resetsAt: Date?)
    
    /// Quota-based model: tracks remaining quota and entitlement
    /// - remaining: Remaining quota (can be negative if overage permitted)
    /// - entitlement: Total monthly quota
    /// - overagePermitted: Whether overage is allowed
    case quotaBased(remaining: Int, entitlement: Int, overagePermitted: Bool)
    
    // MARK: - Computed Properties
    
    /// Usage as a percentage (0-100)
    /// For quota-based: (used / entitlement) * 100
    /// For pay-as-you-go: utilization value
    var usagePercentage: Double {
        switch self {
        case .payAsYouGo(let utilization, _):
            return utilization
        case .quotaBased(let remaining, let entitlement, _):
            guard entitlement > 0 else { return 0 }
            let used = entitlement - remaining
            return (Double(used) / Double(entitlement)) * 100
        }
    }
    
    /// Whether usage is within normal limits
    /// For quota-based: remaining >= 0
    /// For pay-as-you-go: utilization <= 100
    var isWithinLimit: Bool {
        switch self {
        case .payAsYouGo(let utilization, _):
            return utilization <= 100
        case .quotaBased(let remaining, _, _):
            return remaining >= 0
        }
    }
    
    /// Human-readable status message
    var statusMessage: String {
        switch self {
        case .payAsYouGo(let utilization, let resetsAt):
            let percentStr = String(format: "%.1f%%", utilization)
            if let resetsAt = resetsAt {
                let formatter = RelativeDateTimeFormatter()
                let relativeTime = formatter.localizedString(for: resetsAt, relativeTo: Date())
                return "\(percentStr) used, resets \(relativeTime)"
            }
            return "\(percentStr) used"
            
        case .quotaBased(let remaining, let entitlement, let overagePermitted):
            let used = entitlement - remaining
            if remaining >= 0 {
                return "\(remaining) of \(entitlement) remaining"
            } else {
                let overage = abs(remaining)
                let message = "\(overage) over limit"
                return overagePermitted ? "\(message) (overage allowed)" : message
            }
        }
    }
    
    /// Remaining quota for quota-based providers
    /// Returns nil for pay-as-you-go providers
    var remainingQuota: Int? {
        switch self {
        case .quotaBased(let remaining, _, _):
            return remaining
        case .payAsYouGo:
            return nil
        }
    }
    
    /// Total entitlement for quota-based providers
    /// Returns nil for pay-as-you-go providers
    var totalEntitlement: Int? {
        switch self {
        case .quotaBased(_, let entitlement, _):
            return entitlement
        case .payAsYouGo:
            return nil
        }
    }
    
    /// Reset time for pay-as-you-go providers
    /// Returns nil for quota-based providers
    var resetTime: Date? {
        switch self {
        case .payAsYouGo(_, let resetsAt):
            return resetsAt
        case .quotaBased:
            return nil
        }
    }
}

// MARK: - Codable Support

extension ProviderUsage: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case utilization
        case resetsAt
        case remaining
        case entitlement
        case overagePermitted
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "payAsYouGo":
            let utilization = (try? container.decodeIfPresent(Double.self, forKey: .utilization)) ?? 0.0
            let resetsAt = try? container.decodeIfPresent(Date.self, forKey: .resetsAt)
            self = .payAsYouGo(utilization: utilization, resetsAt: resetsAt)
            
        case "quotaBased":
            let remaining = (try? container.decodeIfPresent(Int.self, forKey: .remaining)) ?? 0
            let entitlement = (try? container.decodeIfPresent(Int.self, forKey: .entitlement)) ?? 0
            let overagePermitted = (try? container.decodeIfPresent(Bool.self, forKey: .overagePermitted)) ?? false
            self = .quotaBased(remaining: remaining, entitlement: entitlement, overagePermitted: overagePermitted)
            
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown ProviderUsage type: \(type)"
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .payAsYouGo(let utilization, let resetsAt):
            try container.encode("payAsYouGo", forKey: .type)
            try container.encode(utilization, forKey: .utilization)
            try container.encodeIfPresent(resetsAt, forKey: .resetsAt)
            
        case .quotaBased(let remaining, let entitlement, let overagePermitted):
            try container.encode("quotaBased", forKey: .type)
            try container.encode(remaining, forKey: .remaining)
            try container.encode(entitlement, forKey: .entitlement)
            try container.encode(overagePermitted, forKey: .overagePermitted)
        }
    }
}

// MARK: - Equatable Support

extension ProviderUsage: Equatable {
    static func == (lhs: ProviderUsage, rhs: ProviderUsage) -> Bool {
        switch (lhs, rhs) {
        case let (.payAsYouGo(lUtil, lReset), .payAsYouGo(rUtil, rReset)):
            return lUtil == rUtil && lReset == rReset
        case let (.quotaBased(lRem, lEnt, lOver), .quotaBased(rRem, rEnt, rOver)):
            return lRem == rRem && lEnt == rEnt && lOver == rOver
        default:
            return false
        }
    }
}
