import Foundation

/// Defines the type of provider based on billing model
enum ProviderType {
    /// Pay-as-you-go model (e.g., Claude, Codex)
    case payAsYouGo
    /// Quota-based model with monthly reset (e.g., Copilot, Gemini CLI)
    case quotaBased
}

/// Identifies the specific AI provider
enum ProviderIdentifier: String, CaseIterable {
    /// GitHub Copilot
    case copilot
    /// Anthropic Claude
    case claude
    /// OpenAI Codex/ChatGPT
    case codex
    /// Google Gemini CLI
    case geminiCLI = "gemini_cli"
    
    /// Human-readable name for the provider
    var displayName: String {
        switch self {
        case .copilot:
            return "GitHub Copilot"
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .geminiCLI:
            return "Gemini CLI"
        }
    }
}

/// Protocol for fetching usage data from AI providers
protocol ProviderProtocol: AnyObject {
    /// The identifier for this provider
    var identifier: ProviderIdentifier { get }
    
    /// The type of billing model this provider uses
    var type: ProviderType { get }
    
    /// Fetches current usage data from the provider
    /// - Returns: ProviderUsage containing current usage information
    /// - Throws: ProviderError if fetch fails
    func fetch() async throws -> ProviderUsage
}

/// Errors that can occur during provider operations
enum ProviderError: LocalizedError {
    /// Authentication token is missing or invalid
    case authenticationFailed(String)
    /// Network request failed
    case networkError(String)
    /// Failed to parse API response
    case decodingError(String)
    /// Provider-specific error
    case providerError(String)
    /// Unsupported operation for this provider
    case unsupported(String)
    
    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        case .providerError(let message):
            return "Provider error: \(message)"
        case .unsupported(let message):
            return "Unsupported: \(message)"
        }
    }
}
