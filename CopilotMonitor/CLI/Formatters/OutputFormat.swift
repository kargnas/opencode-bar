import Foundation
import ArgumentParser

/// Defines the output format for CLI commands
enum OutputFormat: String, ExpressibleByArgument {
    case table
    case json
    
    var description: String {
        switch self {
        case .table:
            return "Human-readable table format (default)"
        case .json:
            return "JSON format for scripting"
        }
    }
}
