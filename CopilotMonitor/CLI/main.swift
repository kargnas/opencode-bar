import ArgumentParser
import Foundation

// MARK: - Formatters

enum FormatterError: LocalizedError {
    case encodingFailed
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode data to JSON"
        case .invalidData:
            return "Invalid data format"
        }
    }
}

struct JSONFormatter {
    static func format(_ results: [ProviderIdentifier: ProviderResult]) throws -> String {
        var jsonDict: [String: [String: Any]] = [:]
        
        for (identifier, result) in results {
            var providerDict: [String: Any] = [:]
            
            switch result.usage {
            case .payAsYouGo(let utilization, let cost, let resetsAt):
                providerDict["type"] = "pay-as-you-go"
                providerDict["utilization"] = utilization
                if let cost = cost {
                    providerDict["cost"] = cost
                }
                if let resetsAt = resetsAt {
                    let formatter = ISO8601DateFormatter()
                    providerDict["resetsAt"] = formatter.string(from: resetsAt)
                }
                
            case .quotaBased(let remaining, let entitlement, let overagePermitted):
                providerDict["type"] = "quota-based"
                providerDict["remaining"] = remaining
                providerDict["entitlement"] = entitlement
                providerDict["overagePermitted"] = overagePermitted
                providerDict["usagePercentage"] = result.usage.usagePercentage
            }
            
            jsonDict[identifier.rawValue] = providerDict
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted, .sortedKeys])
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw FormatterError.encodingFailed
        }
        
        return jsonString
    }
}

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
        
        output += formatHeader()
        output += "\n"
        output += formatSeparator()
        output += "\n"
        
        let sortedResults = results.sorted { a, b in
            a.key.displayName < b.key.displayName
        }
        
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
        case .quotaBased:
            return String(format: "%.0f%%", percentage)
        }
    }
    
    private static func formatMetrics(_ result: ProviderResult) -> String {
        switch result.usage {
        case .payAsYouGo(_, let cost, let resetsAt):
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

// MARK: - Commands

struct OpenCodeBar: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "opencodebar",
        abstract: "AI provider usage monitor",
        version: "1.0.0",
        subcommands: [
            StatusCommand.self,
            ListCommand.self,
            ProviderCommand.self
        ],
        defaultSubcommand: StatusCommand.self
    )
}

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Display current usage status for all providers"
    )
    
    @Flag(name: .long, help: "Output as JSON instead of table")
    var json: Bool = false
    
    mutating func run() throws {
        let jsonFlag = self.json
        let semaphore = DispatchSemaphore(value: 0)
        var error: Error?
        var output: String?
        
        Task {
            do {
                let manager = CLIProviderManager()
                let results = await manager.fetchAll()
                
                guard !results.isEmpty else {
                    output = jsonFlag ? "{}" : "No provider data available. Check your OpenCode authentication."
                    semaphore.signal()
                    return
                }
                
                if jsonFlag {
                    output = try JSONFormatter.format(results)
                } else {
                    output = TableFormatter.format(results)
                }
            } catch let e {
                error = e
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = error {
            throw error
        }
        
        if let output = output {
            print(output)
        }
    }
}

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all configured AI providers"
    )
    
    @Flag(name: .long, help: "Output as JSON instead of table")
    var json: Bool = false
    
    mutating func run() throws {
        let providers = ProviderIdentifier.allCases
        
        if json {
            let providerList = providers.map { provider in
                [
                    "id": provider.rawValue,
                    "name": provider.displayName
                ]
            }
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(providerList)
            
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
        } else {
            print("Available Providers:")
            print(String(repeating: "─", count: 50))
            
            for provider in providers.sorted(by: { $0.displayName < $1.displayName }) {
                let idPadded = provider.rawValue.padding(toLength: 20, withPad: " ", startingAt: 0)
                print("\(idPadded)  \(provider.displayName)")
            }
            
            print(String(repeating: "─", count: 50))
            print("Total: \(providers.count) providers")
        }
    }
}

struct ProviderCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "provider",
        abstract: "Get details for a specific provider"
    )
    
    @Argument(help: "Provider name (e.g., claude, openrouter, copilot)")
    var name: String
    
    @Flag(name: .long, help: "Output as JSON instead of table")
    var json: Bool = false
    
    mutating func run() throws {
        let providerName = self.name
        let jsonFlag = self.json
        
        guard let identifier = findProvider(name: providerName) else {
            if jsonFlag {
                let error = ["error": "Provider '\(providerName)' not found"]
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted]
                if let jsonData = try? encoder.encode(error),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    print(jsonString)
                }
            } else {
                print("Error: Provider '\(providerName)' not found")
                print("\nAvailable providers:")
                for provider in ProviderIdentifier.allCases.sorted(by: { $0.displayName < $1.displayName }) {
                    print("  - \(provider.rawValue) (\(provider.displayName))")
                }
            }
            throw ExitCode.failure
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var error: Error?
        var output: String?
        
        Task {
            do {
                let manager = CLIProviderManager()
                let results = await manager.fetchAll()
                
                guard let result = results[identifier] else {
                    if jsonFlag {
                        let errorDict = ["error": "Failed to fetch data for '\(identifier.displayName)'"]
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted]
                        if let jsonData = try? encoder.encode(errorDict),
                           let jsonString = String(data: jsonData, encoding: .utf8) {
                            output = jsonString
                        }
                    } else {
                        output = "Error: Failed to fetch data for '\(identifier.displayName)'\nThis provider may not be configured or authentication may have failed."
                    }
                    error = ExitCode.failure
                    semaphore.signal()
                    return
                }
                
                if jsonFlag {
                    let singleResult = [identifier: result]
                    output = try JSONFormatter.format(singleResult)
                } else {
                    let singleResult = [identifier: result]
                    output = TableFormatter.format(singleResult)
                }
            } catch let e {
                error = e
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = error {
            if let output = output {
                print(output)
            }
            throw error
        }
        
        if let output = output {
            print(output)
        }
    }
    
    private func findProvider(name: String) -> ProviderIdentifier? {
        let lowercasedName = name.lowercased()
        
        if let provider = ProviderIdentifier(rawValue: lowercasedName) {
            return provider
        }
        
        for provider in ProviderIdentifier.allCases {
            if provider.rawValue.lowercased() == lowercasedName {
                return provider
            }
        }
        
        for provider in ProviderIdentifier.allCases {
            if provider.displayName.lowercased() == lowercasedName {
                return provider
            }
        }
        
        for provider in ProviderIdentifier.allCases {
            if provider.displayName.lowercased().contains(lowercasedName) {
                return provider
            }
        }
        
        return nil
    }
}

OpenCodeBar.main()
