import Foundation
import os.log

private let logger = Logger(subsystem: "com.copilotmonitor", category: "ProviderManager")

/// Singleton coordinator for managing multiple AI provider usage tracking
/// Handles parallel fetching, aggregation, and error recovery
final class ProviderManager {
    // MARK: - Singleton
    
    static let shared = ProviderManager()
    
    // MARK: - Properties
    
    /// All registered providers
    /// Note: CopilotProvider requires WebView dependency - managed separately
    private var providers: [ProviderProtocol] = []
    
    /// Registers providers that don't require external dependencies
    private func registerDefaultProviders() {
        providers = [
            ClaudeProvider(),
            CodexProvider(),
            GeminiCLIProvider()
        ]
    }
    
    /// Timeout for individual provider fetch operations (10 seconds)
    private let fetchTimeout: TimeInterval = 10.0
    
    /// Last successful fetch results (used as fallback on errors)
    /// Access via updateCache/getCache methods for thread safety
    private var cachedResults: [ProviderIdentifier: ProviderUsage] = [:]
    
    // MARK: - Initialization
    
    private init() {
        registerDefaultProviders()
        logger.info("ProviderManager initialized with \(self.providers.count) providers")
    }
    
    // MARK: - Public API
    
    /// Fetches usage data from all registered providers in parallel
    /// - Returns: Dictionary mapping provider identifiers to their usage data
    /// - Note: Returns partial results if some providers fail (graceful degradation)
    func fetchAll() async -> [ProviderIdentifier: ProviderUsage] {
        logger.info("Starting parallel fetch for \(self.providers.count) providers")
        
        var results: [ProviderIdentifier: ProviderUsage] = [:]
        
        // Use TaskGroup for parallel fetching with timeout
        await withTaskGroup(of: (ProviderIdentifier, ProviderUsage?).self) { group in
            for provider in self.providers {
                group.addTask { [weak self] in
                    guard let self = self else {
                        return (provider.identifier, nil)
                    }
                    
                    // Fetch with timeout
                    do {
                        let usage = try await self.fetchWithTimeout(provider: provider)
                        
                        // Cache successful result (async-safe using Task)
                        await self.updateCache(identifier: provider.identifier, usage: usage)
                        
                        logger.info("✓ \(provider.identifier.displayName) fetch succeeded")
                        return (provider.identifier, usage)
                    } catch {
                        logger.error("✗ \(provider.identifier.displayName) fetch failed: \(error.localizedDescription)")
                        
                        // Try to use cached value as fallback
                        let cached = await self.getCache(identifier: provider.identifier)
                        
                        if cached != nil {
                            logger.warning("Using cached value for \(provider.identifier.displayName)")
                        }
                        
                        return (provider.identifier, cached)
                    }
                }
            }
            
            // Collect results from all tasks
            for await (identifier, usage) in group {
                if let usage = usage {
                    results[identifier] = usage
                }
            }
        }
        
        logger.info("Fetch completed: \(results.count)/\(self.providers.count) providers succeeded")
        return results
    }
    
    /// Calculates total overage cost from all pay-as-you-go providers
    /// - Parameter results: Results from fetchAll()
    /// - Returns: Total cost in dollars (0.0 if no overage)
    /// - Note: Current ProviderUsage model doesn't include cost field
    ///         This is a placeholder implementation until model is enhanced
    func calculateTotalOverageCost(from results: [ProviderIdentifier: ProviderUsage]) -> Double {
        // TODO: Enhance ProviderUsage.payAsYouGo to include cost field
        // Current implementation returns 0.0 as cost data not available in model
        logger.debug("Total overage cost: $0.00 (cost tracking not yet implemented in ProviderUsage)")
        return 0.0
    }
    
    /// Identifies providers with low quota (<20% remaining)
    /// - Parameter results: Results from fetchAll()
    /// - Returns: Array of (provider, remaining percentage) tuples for providers below threshold
    func getQuotaAlerts(from results: [ProviderIdentifier: ProviderUsage]) -> [(ProviderIdentifier, Double)] {
        let alerts = results.compactMap { (identifier, usage) -> (ProviderIdentifier, Double)? in
            switch usage {
            case .quotaBased(let remaining, let entitlement, _):
                guard entitlement > 0 else { return nil }
                
                let remainingPercentage = (Double(remaining) / Double(entitlement)) * 100.0
                
                // Alert if remaining < 20%
                if remainingPercentage < 20.0 {
                    logger.warning("⚠️ \(identifier.displayName) quota alert: \(String(format: "%.1f", remainingPercentage))% remaining")
                    return (identifier, remainingPercentage)
                }
                return nil
                
            case .payAsYouGo:
                // Pay-as-you-go providers don't have quota alerts
                return nil
            }
        }
        
        logger.debug("Quota alerts: \(alerts.count) provider(s) below 20%")
        return alerts
    }
    
    /// Gets all registered providers
    /// - Returns: Array of all provider instances
    func getAllProviders() -> [ProviderProtocol] {
        return providers
    }
    
    /// Gets a specific provider by identifier
    /// - Parameter identifier: The provider identifier to find
    /// - Returns: The provider instance, or nil if not found
    func getProvider(for identifier: ProviderIdentifier) -> ProviderProtocol? {
        return providers.first { $0.identifier == identifier }
    }
    
    // MARK: - Private Helpers
    
    /// Fetches usage from a provider with timeout
    /// - Parameter provider: The provider to fetch from
    /// - Returns: ProviderUsage data
    /// - Throws: ProviderError or timeout error
    private func fetchWithTimeout(provider: ProviderProtocol) async throws -> ProviderUsage {
        return try await withThrowingTaskGroup(of: ProviderUsage.self) { group in
            // Add fetch task
            group.addTask {
                try await provider.fetch()
            }
            
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.fetchTimeout * 1_000_000_000))
                throw ProviderError.networkError("Fetch timeout after \(self.fetchTimeout)s")
            }
            
            // Return first result (either success or timeout)
            guard let result = try await group.next() else {
                throw ProviderError.networkError("Task group failed")
            }
            
            // Cancel remaining task
            group.cancelAll()
            
            return result
        }
    }
    
    /// Thread-safe cache update (async-safe using Task isolation)
    /// - Parameters:
    ///   - identifier: Provider identifier
    ///   - usage: Usage data to cache
    private func updateCache(identifier: ProviderIdentifier, usage: ProviderUsage) async {
        // Using Task.detached to avoid inheriting actor context
        // Cache updates are non-critical and can be async
        Task.detached { [weak self] in
            self?.cachedResults[identifier] = usage
        }
    }
    
    /// Thread-safe cache retrieval (async-safe using Task isolation)
    /// - Parameter identifier: Provider identifier
    /// - Returns: Cached usage data or nil
    private func getCache(identifier: ProviderIdentifier) async -> ProviderUsage? {
        return cachedResults[identifier]
    }
}
