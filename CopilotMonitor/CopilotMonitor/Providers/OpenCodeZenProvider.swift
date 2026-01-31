import Foundation
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "OpenCodeZenProvider")

/// Provider for OpenCode Zen usage tracking via CLI stats
/// Uses pay-as-you-go billing model with cost-based tracking
final class OpenCodeZenProvider: ProviderProtocol {
    let identifier: ProviderIdentifier = .openCodeZen
    let type: ProviderType = .payAsYouGo
    
    // MARK: - Configuration
    
    /// Path to opencode CLI binary
    private let opencodePath: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".opencode/bin/opencode")
    }()
    
    // MARK: - Data Structures
    
    /// Parsed statistics from opencode stats command
    private struct OpenCodeStats {
        let totalCost: Double
        let avgCostPerDay: Double
        let sessions: Int
        let messages: Int
        let modelCosts: [String: Double]
    }
    
    /// Cache structure for daily history
    private struct DailyHistoryCache: Codable {
        let date: Date
        let cost: Double
        let fetchedAt: Date
    }
    
    private let cacheKey = "opencodezen.dailyhistory.cache"
    
    // MARK: - ProviderProtocol
    
    func fetch() async throws -> ProviderResult {
        guard FileManager.default.fileExists(atPath: opencodePath.path) else {
            logger.error("OpenCode CLI not found at \(self.opencodePath.path)")
            throw ProviderError.providerError("OpenCode CLI not found at \(opencodePath.path)")
        }
        
        let output = try await runOpenCodeStats(days: 7)
        let stats = try parseStats(output)
        
        let dailyHistory = await fetchDailyHistory()
        
        let monthlyLimit = 1000.0
        let utilization = min((stats.totalCost / monthlyLimit) * 100, 100)
        
        logger.info("Successfully fetched OpenCode Zen usage: $\(String(format: "%.2f", stats.totalCost)) (\(String(format: "%.1f", utilization))% of $\(monthlyLimit) limit)")
        
        let details = DetailedUsage(
            modelBreakdown: stats.modelCosts,
            sessions: stats.sessions,
            messages: stats.messages,
            avgCostPerDay: stats.avgCostPerDay,
            dailyHistory: dailyHistory,
            monthlyCost: stats.totalCost
        )
        
        return ProviderResult(
            usage: .payAsYouGo(utilization: utilization, cost: stats.totalCost, resetsAt: nil),
            details: details
        )
    }
    
    private func fetchDailyHistory() async -> [DailyUsage] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today) else {
            return []
        }
        
        // Load cached data for days older than 2 days ago
        var cachedData: [Date: Double] = [:]
        let cache = loadHistoryCache()
        for item in cache {
            let itemDate = calendar.startOfDay(for: item.date)
            if itemDate < twoDaysAgo {
                cachedData[itemDate] = item.cost
            }
        }
        
        // Only fetch today and yesterday (days 1 and 2)
        var cumulativeCosts: [Int: Double] = [:]
        await withTaskGroup(of: (Int, Double?).self) { group in
            for days in 1...2 {
                group.addTask {
                    do {
                        let output = try await self.runOpenCodeStats(days: days)
                        if let cost = self.parseTotalCost(output) {
                            return (days, cost)
                        }
                    } catch {
                        logger.warning("Failed to fetch stats for \(days) days: \(error.localizedDescription)")
                    }
                    return (days, nil)
                }
            }
            for await (days, cost) in group {
                if let cost = cost {
                    cumulativeCosts[days] = cost
                }
            }
        }
        
        // Build daily history and update cache
        var dailyHistory: [DailyUsage] = []
        var newCache: [DailyHistoryCache] = []
        
        for day in 1...7 {
            guard let date = calendar.date(byAdding: .day, value: -(day - 1), to: today) else { continue }
            let dateStart = calendar.startOfDay(for: date)
            var dailyCost: Double
            
            if day <= 2 {
                // Today/yesterday: calculate from fresh data
                let currentCumulative = cumulativeCosts[day] ?? 0
                let previousCumulative = day > 1 ? (cumulativeCosts[day - 1] ?? 0) : 0
                dailyCost = max(0, currentCumulative - previousCumulative)
                newCache.append(DailyHistoryCache(date: dateStart, cost: dailyCost, fetchedAt: Date()))
            } else {
                // Older days: load from cache
                dailyCost = cachedData[dateStart] ?? 0
                if let existingCacheItem = cache.first(where: { calendar.startOfDay(for: $0.date) == dateStart }) {
                    newCache.append(existingCacheItem)
                }
            }
            
            dailyHistory.append(DailyUsage(
                date: date,
                includedRequests: 0,
                billedRequests: 0,
                grossAmount: dailyCost,
                billedAmount: dailyCost
            ))
        }
        
        saveHistoryCache(newCache)
        return dailyHistory
    }
    
    private func parseTotalCost(_ output: String) -> Double? {
        let totalCostPattern = #"│Total Cost\s+\$([0-9.]+)"#
        guard let match = output.range(of: totalCostPattern, options: .regularExpression) else {
            return nil
        }
        let costStr = String(output[match])
            .replacingOccurrences(of: #"│Total Cost\s+\$"#, with: "", options: .regularExpression)
        return Double(costStr)
    }
    
    private func loadHistoryCache() -> [DailyHistoryCache] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return [] }
        return (try? JSONDecoder().decode([DailyHistoryCache].self, from: data)) ?? []
    }
    
    private func saveHistoryCache(_ cache: [DailyHistoryCache]) {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
    
    // MARK: - Private Helpers
    
    private func runOpenCodeStats(days: Int) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = opencodePath
            process.arguments = ["stats", "--days", "\(days)", "--models", "10"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            var outputData = Data()
            
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    outputData.append(data)
                }
            }
            
            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                
                let remainingData = pipe.fileHandleForReading.readDataToEndOfFile()
                if !remainingData.isEmpty {
                    outputData.append(remainingData)
                }
                
                if proc.terminationStatus != 0 {
                    continuation.resume(throwing: ProviderError.providerError("OpenCode CLI failed with exit code \(proc.terminationStatus)"))
                    return
                }
                
                guard let output = String(data: outputData, encoding: .utf8) else {
                    continuation.resume(throwing: ProviderError.decodingError("Failed to decode CLI output"))
                    return
                }
                
                continuation.resume(returning: output)
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ProviderError.networkError("Failed to execute CLI: \(error.localizedDescription)"))
            }
        }
    }
    
    /// Parses opencode stats output using regex patterns
    /// - Parameter output: Raw CLI output string
    /// - Returns: Structured OpenCodeStats data
    /// - Throws: ProviderError if parsing fails
    private func parseStats(_ output: String) throws -> OpenCodeStats {
        // Parse Total Cost: │Total Cost\s+\$([0-9.]+)
        let totalCostPattern = #"│Total Cost\s+\$([0-9.]+)"#
        guard let totalCostMatch = output.range(of: totalCostPattern, options: .regularExpression) else {
            logger.error("Cannot parse total cost from output")
            throw ProviderError.decodingError("Cannot parse total cost")
        }
        let totalCostStr = String(output[totalCostMatch])
            .replacingOccurrences(of: #"│Total Cost\s+\$"#, with: "", options: .regularExpression)
        guard let totalCost = Double(totalCostStr) else {
            logger.error("Invalid total cost value: \(totalCostStr)")
            throw ProviderError.decodingError("Invalid total cost value")
        }
        
        // Parse Avg Cost/Day: │Avg Cost/Day\s+\$([0-9.]+)
        let avgCostPattern = #"│Avg Cost/Day\s+\$([0-9.]+)"#
        guard let avgCostMatch = output.range(of: avgCostPattern, options: .regularExpression) else {
            logger.error("Cannot parse avg cost from output")
            throw ProviderError.decodingError("Cannot parse avg cost")
        }
        let avgCostStr = String(output[avgCostMatch])
            .replacingOccurrences(of: #"│Avg Cost/Day\s+\$"#, with: "", options: .regularExpression)
        guard let avgCost = Double(avgCostStr) else {
            logger.error("Invalid avg cost value: \(avgCostStr)")
            throw ProviderError.decodingError("Invalid avg cost value")
        }
        
        // Parse Sessions: │Sessions\s+([0-9,]+)
        let sessionsPattern = #"│Sessions\s+([0-9,]+)"#
        guard let sessionsMatch = output.range(of: sessionsPattern, options: .regularExpression) else {
            logger.error("Cannot parse sessions from output")
            throw ProviderError.decodingError("Cannot parse sessions")
        }
        let sessionsStr = String(output[sessionsMatch])
            .replacingOccurrences(of: #"│Sessions\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: ",", with: "")
        let sessions = Int(sessionsStr) ?? 0
        
        // Parse Messages: │Messages\s+([0-9,]+)
        let messagesPattern = #"│Messages\s+([0-9,]+)"#
        guard let messagesMatch = output.range(of: messagesPattern, options: .regularExpression) else {
            logger.error("Cannot parse messages from output")
            throw ProviderError.decodingError("Cannot parse messages")
        }
        let messagesStr = String(output[messagesMatch])
            .replacingOccurrences(of: #"│Messages\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: ",", with: "")
        let messages = Int(messagesStr) ?? 0
        
        // Parse Model costs: │ (\S+)\s+.*│\s+Cost\s+\$([0-9.]+)
        var modelCosts: [String: Double] = [:]
        let modelPattern = #"│ (\S+)\s+.*│\s+Cost\s+\$([0-9.]+)"#
        do {
            let modelRegex = try NSRegularExpression(pattern: modelPattern)
            let matches = modelRegex.matches(in: output, range: NSRange(output.startIndex..., in: output))
            
            for match in matches {
                if let modelRange = Range(match.range(at: 1), in: output),
                   let costRange = Range(match.range(at: 2), in: output),
                   let cost = Double(output[costRange]) {
                    let modelName = String(output[modelRange])
                    modelCosts[modelName] = cost
                }
            }
            
            logger.debug("Parsed \(modelCosts.count) model costs")
        } catch {
            logger.warning("Failed to parse model costs: \(error.localizedDescription)")
            // Non-fatal: continue without model breakdown
        }
        
        return OpenCodeStats(
            totalCost: totalCost,
            avgCostPerDay: avgCost,
            sessions: sessions,
            messages: messages,
            modelCosts: modelCosts
        )
    }
    
}
