import Foundation

struct TableFormatter {
    private static let columnWidths = (
        provider: 20,
        type: 15,
        usage: 10,
        metrics: 30
    )
    
    static func format(_ results: [ProviderIdentifier: ProviderResult]) -> String {
        guard !results.isEmpty else {
            return "No provider data available"
        }
        
        var output = ""
        
        // Header
        output += formatHeader()
        output += "\n"
        
        // Separator
        output += formatSeparator()
        output += "\n"
        
        // Sort providers by display name for consistent output
        let sortedResults = results.sorted { a, b in
            a.key.displayName < b.key.displayName
        }
        
        // Rows
        for (identifier, result) in sortedResults {
            output += formatRow(identifier: identifier, result: result)
            output += "\n"
        }
        
        return output
    }
    
    private static func formatHeader() -> String {
        let provider = "Provider".padding(toLength: columnWidths.provider, withPad: " ", startingAt: 0)
        let type = "Type".padding(toLength: columnWidths.type, withPad: " ", startingAt: 0)
        let usage = "Usage".padding(toLength: columnWidths.usage, withPad: " ", startingAt: 0)
        let metrics = "Key Metrics"
        
        return "\(provider)  \(type)  \(usage)  \(metrics)"
    }
    
    private static func formatSeparator() -> String {
        let totalWidth = columnWidths.provider + columnWidths.type + columnWidths.usage + 30 + 6
        return String(repeating: "─", count: totalWidth)
    }
    
    private static func formatRow(identifier: ProviderIdentifier, result: ProviderResult) -> String {
        let providerName = identifier.displayName
        let providerPadded = providerName.padding(toLength: columnWidths.provider, withPad: " ", startingAt: 0)
        
        let typeStr = getProviderType(result)
        let typePadded = typeStr.padding(toLength: columnWidths.type, withPad: " ", startingAt: 0)
        
        let usageStr = formatUsagePercentage(result)
        let usagePadded = usageStr.padding(toLength: columnWidths.usage, withPad: " ", startingAt: 0)
        
        let metricsStr = formatMetrics(result)
        
        return "\(providerPadded)  \(typePadded)  \(usagePadded)  \(metricsStr)"
    }
    
    private static func getProviderType(_ result: ProviderResult) -> String {
        switch result.usage {
        case .payAsYouGo:
            return "Pay-as-you-go"
        case .quotaBased:
            return "Quota-based"
        }
    }
    
    private static func formatUsagePercentage(_ result: ProviderResult) -> String {
        let percentage = result.usage.usagePercentage
        
        switch result.usage {
        case .payAsYouGo:
            return String(format: "%.1f%%", percentage)
        case .quotaBased(let remaining, let entitlement, _):
            let used = entitlement - remaining
            return String(format: "%.0f%%", percentage)
        }
    }
    
    private static func formatMetrics(_ result: ProviderResult) -> String {
        switch result.usage {
        case .payAsYouGo(let utilization, let cost, let resetsAt):
            var metrics = ""
            
            if let cost = cost {
                metrics += String(format: "$%.2f spent", cost)
            } else {
                metrics += "Cost unavailable"
            }
            
            if let resetsAt = resetsAt {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                let resetDate = formatter.string(from: resetsAt)
                metrics += " (resets \(resetDate))"
            }
            
            return metrics
            
        case .quotaBased(let remaining, let entitlement, let overagePermitted):
            let used = entitlement - remaining
            
            if remaining >= 0 {
                return "\(remaining)/\(entitlement) remaining"
            } else {
                let overage = abs(remaining)
                if overagePermitted {
                    return "\(overage) overage (allowed)"
                } else {
                    return "\(overage) overage (not allowed)"
                }
            }
        }
    }
}
