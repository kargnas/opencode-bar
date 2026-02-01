import Foundation
import Combine

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
        // Mark all enabled providers as loading
        loadingProviders = Set(ProviderIdentifier.allCases.filter { 
            providerManager.getProvider(for: $0) != nil 
        })
        
        // Fetch all providers in parallel
        let results = await providerManager.fetchAll()
        
        // Update state
        providerResults = results
        lastUpdated = Date()
        lastError = nil
        
        // Clear loading state
        loadingProviders.removeAll()
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
    var totalOverageCost: Double {
        providerManager.calculateTotalOverageCost(from: providerResults)
    }
    
    /// Returns providers with quota below 20% threshold
    /// - Returns: Array of (identifier, remaining percentage) tuples
    var quotaAlerts: [(ProviderIdentifier, Double)] {
        providerManager.getQuotaAlerts(from: providerResults)
    }
}
