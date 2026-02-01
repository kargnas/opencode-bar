import Foundation
import Combine
import os.log

/// ViewModel managing multi-provider usage state
/// Extracts state management from StatusBarController for modern SwiftUI architecture
/// Uses ObservableObject for macOS 13.0+ compatibility
@MainActor
final class ProviderViewModel: ObservableObject {
    // MARK: - State Properties
    
    /// Current provider results from last fetch
    @Published var providerResults: [ProviderIdentifier: ProviderResult] = [:]
    
    /// Providers currently being fetched (for loading indicators)
    @Published var loadingProviders: Set<ProviderIdentifier> = []
    
    /// Last error message from fetch operations
    @Published var lastError: String?
    
    /// Timestamp of last successful update
    @Published var lastUpdated: Date?
    
    // MARK: - Dependencies
    
    private let providerManager = ProviderManager.shared
    
    // MARK: - Public API
    
    /// Refreshes all provider data
    /// - Note: Updates loadingProviders during fetch for UI loading states
    func refresh() async {
        let logger = Logger(subsystem: "com.opencodeproviders", category: "ProviderViewModel")
        logger.info("🔵 [ProviderViewModel] refresh() started")
        
        var enabledProviders: [ProviderIdentifier] = []
        for identifier in ProviderIdentifier.allCases {
            if await providerManager.getProvider(for: identifier) != nil {
                enabledProviders.append(identifier)
            }
        }
        let enabledNames = enabledProviders.map { $0.displayName }.joined(separator: ", ")
        logger.debug("🔵 [ProviderViewModel] enabledProviders: \(enabledNames)")
        
        self.loadingProviders = Set(enabledProviders)
        logger.debug("🟡 [ProviderViewModel] loadingProviders set to \(enabledProviders.count) providers")
        
        // Fetch all providers in parallel
        logger.debug("🟡 [ProviderViewModel] Calling providerManager.fetchAll()")
        let fetchResult = await providerManager.fetchAll()
        logger.info("🟢 [ProviderViewModel] fetchAll() returned \(fetchResult.results.count) results, \(fetchResult.errors.count) errors")
        
        // Update state
        self.providerResults = fetchResult.results
        logger.debug("🟢 [ProviderViewModel] providerResults updated")
        
        self.lastUpdated = Date()
        logger.debug("🟢 [ProviderViewModel] lastUpdated set")
        
        self.lastError = fetchResult.errors.isEmpty ? nil : "Some providers failed"
        logger.debug("🟢 [ProviderViewModel] lastError: \(self.lastError ?? "none")")
        
        let cost = await providerManager.calculateTotalOverageCost(from: fetchResult.results)
        self.totalOverageCost = cost
        logger.debug("🟢 [ProviderViewModel] totalOverageCost calculated: $\(String(format: "%.2f", cost))")
        
        let alerts = await providerManager.getQuotaAlerts(from: fetchResult.results)
        self.quotaAlerts = alerts
        logger.debug("🟢 [ProviderViewModel] quotaAlerts: \(alerts.count) alerts")
        
        // Clear loading state
        self.loadingProviders.removeAll()
        logger.info("🟢 [ProviderViewModel] refresh() completed - loadingProviders cleared")
    }
    
    // MARK: - Computed Properties for UI
    
    /// Filters quota-based providers from current results
    var quotaProviders: [ProviderResult] {
        providerResults.values.filter { 
            if case .quotaBased = $0.usage { return true }
            return false
        }
    }
    
    /// Filters pay-as-you-go providers from current results
    var paygProviders: [ProviderResult] {
        providerResults.values.filter {
            if case .payAsYouGo = $0.usage { return true }
            return false
        }
    }
    
    /// Calculates total overage cost across all pay-as-you-go providers
    @Published private(set) var totalOverageCost: Double = 0.0
    
    /// Returns providers with quota below 20% threshold
    /// - Returns: Array of (identifier, remaining percentage) tuples
    @Published private(set) var quotaAlerts: [(ProviderIdentifier, Double)] = []
}
