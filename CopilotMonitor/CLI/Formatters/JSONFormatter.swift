import Foundation

struct JSONFormatter {
    static func format(_ results: [ProviderIdentifier: ProviderResult]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let jsonData = try encoder.encode(results)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw FormatterError.encodingFailed
        }
        
        return jsonString
    }
}

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
