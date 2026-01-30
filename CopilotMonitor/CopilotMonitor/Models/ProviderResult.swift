import Foundation

struct ProviderResult {
    let usage: ProviderUsage
    let details: DetailedUsage?
}

struct DetailedUsage: Codable {
    let dailyUsage: Double?
    let weeklyUsage: Double?
    let monthlyUsage: Double?
    let totalCredits: Double?
    let remainingCredits: Double?
    let limit: Double?
    let limitRemaining: Double?
    let resetPeriod: String?
}

extension DetailedUsage {
    var hasAnyValue: Bool {
        return dailyUsage != nil || weeklyUsage != nil || monthlyUsage != nil 
            || totalCredits != nil || remainingCredits != nil 
            || limit != nil || limitRemaining != nil || resetPeriod != nil
    }
}
