import Foundation

struct DailyUsage: Codable {
    let date: Date              // UTC date
    let includedRequests: Double // Included requests
    let billedRequests: Double   // Add-on billed requests
    let grossAmount: Double      // Gross amount
    let billedAmount: Double     // Add-on billed amount
    
    // ⚠️ Fixed UTC calendar: Date is stored in UTC, so weekday check also uses UTC
    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()
    
    var dayOfWeek: Int { Self.utcCalendar.component(.weekday, from: date) }
    var isWeekend: Bool { dayOfWeek == 1 || dayOfWeek == 7 }
}

struct UsageHistory: Codable {
    let fetchedAt: Date
    let days: [DailyUsage]       // ⚠️ Stores full month data (separate from 7-day UI display)
    
    var totalIncludedRequests: Double { days.reduce(0) { $0 + $1.includedRequests } }
    var totalBilledAmount: Double { days.reduce(0) { $0 + $1.billedAmount } }
    
    // Recent 7 days slice for UI
    var recentDays: [DailyUsage] { Array(days.prefix(7)) }
}
