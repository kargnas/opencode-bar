import Foundation
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "NanoGptProvider")

private struct NanoGptSubscriptionUsageResponse: Decodable {
    struct Limits: Decodable {
        let daily: Int?
        let monthly: Int?

        private enum CodingKeys: String, CodingKey {
            case daily
            case monthly
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            daily = NanoGptSubscriptionUsageResponse.decodeInt(container, forKey: .daily)
            monthly = NanoGptSubscriptionUsageResponse.decodeInt(container, forKey: .monthly)
        }
    }

    struct WindowUsage: Decodable {
        let used: Int?
        let remaining: Int?
        let percentUsed: Double?
        let resetAt: Int64?

        private enum CodingKeys: String, CodingKey {
            case used
            case remaining
            case percentUsed
            case resetAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            used = NanoGptSubscriptionUsageResponse.decodeInt(container, forKey: .used)
            remaining = NanoGptSubscriptionUsageResponse.decodeInt(container, forKey: .remaining)
            percentUsed = NanoGptSubscriptionUsageResponse.decodeDouble(container, forKey: .percentUsed)
            resetAt = NanoGptSubscriptionUsageResponse.decodeInt64(container, forKey: .resetAt)
        }
    }

    struct Period: Decodable {
        let currentPeriodEnd: String?
    }

    let active: Bool?
    let limits: Limits?
    let daily: WindowUsage?
    let monthly: WindowUsage?
    let period: Period?
    let state: String?
    let graceUntil: String?
}

private struct NanoGptBalanceResponse: Decodable {
    let usdBalance: String?
    let nanoBalance: String?

    private enum CodingKeys: String, CodingKey {
        case usdBalance = "usd_balance"
        case nanoBalance = "nano_balance"
    }
}

private extension NanoGptSubscriptionUsageResponse {
    static func decodeInt<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, forKey key: Key) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    static func decodeInt64<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, forKey key: Key) -> Int64? {
        if let value = try? container.decodeIfPresent(Int64.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Int64(value)
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Int64(value)
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return Int64(value)
        }
        return nil
    }

    static func decodeDouble<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, forKey key: Key) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }
}

final class NanoGptProvider: ProviderProtocol {
    let identifier: ProviderIdentifier = .nanoGpt
    let type: ProviderType = .quotaBased

    private let tokenManager: TokenManager
    private let session: URLSession

    init(tokenManager: TokenManager = .shared, session: URLSession = .shared) {
        self.tokenManager = tokenManager
        self.session = session
    }

    func fetch() async throws -> ProviderResult {
        logger.info("Nano-GPT fetch started")

        guard let apiKey = tokenManager.getNanoGptAPIKey() else {
            logger.error("Nano-GPT API key not found")
            throw ProviderError.authenticationFailed("Nano-GPT API key not available")
        }

        async let usageResponseTask = fetchSubscriptionUsage(apiKey: apiKey)
        async let balanceResponseTask = fetchBalance(apiKey: apiKey)

        let usageResponse = try await usageResponseTask
        let balanceResponse = try? await balanceResponseTask

        guard let monthlyLimit = usageResponse.limits?.monthly,
              monthlyLimit > 0 else {
            logger.error("Nano-GPT monthly limit missing")
            throw ProviderError.decodingError("Missing Nano-GPT monthly limit")
        }

        let monthlyUsed = usageResponse.monthly?.used ?? 0
        let monthlyRemaining = usageResponse.monthly?.remaining ?? max(0, monthlyLimit - monthlyUsed)
        let monthlyPercentUsed = normalizedPercent(
            usageResponse.monthly?.percentUsed,
            used: monthlyUsed,
            total: monthlyLimit
        )

        let usage = ProviderUsage.quotaBased(
            remaining: max(0, monthlyRemaining),
            entitlement: monthlyLimit,
            overagePermitted: false
        )

        let dailyLimit = usageResponse.limits?.daily
        let dailyUsed = usageResponse.daily?.used
        let dailyPercentUsed = normalizedPercent(
            usageResponse.daily?.percentUsed,
            used: dailyUsed,
            total: dailyLimit
        )

        let details = DetailedUsage(
            totalCredits: parseDouble(balanceResponse?.nanoBalance),
            resetPeriod: formatISO8601(usageResponse.period?.currentPeriodEnd),
            creditsBalance: parseDouble(balanceResponse?.usdBalance),
            authSource: tokenManager.lastFoundAuthPath?.path ?? "~/.local/share/opencode/auth.json",
            tokenUsagePercent: dailyPercentUsed,
            tokenUsageReset: dateFromMilliseconds(usageResponse.daily?.resetAt),
            tokenUsageUsed: dailyUsed,
            tokenUsageTotal: dailyLimit,
            mcpUsagePercent: monthlyPercentUsed,
            mcpUsageReset: dateFromMilliseconds(usageResponse.monthly?.resetAt),
            mcpUsageUsed: monthlyUsed,
            mcpUsageTotal: monthlyLimit
        )

        logger.info(
            "Nano-GPT usage fetched: daily=\(dailyPercentUsed?.description ?? "n/a")% used, monthly=\(monthlyPercentUsed?.description ?? "n/a")% used"
        )

        return ProviderResult(usage: usage, details: details)
    }

    private func fetchSubscriptionUsage(apiKey: String) async throws -> NanoGptSubscriptionUsageResponse {
        guard let url = URL(string: "https://nano-gpt.com/api/subscription/v1/usage") else {
            throw ProviderError.networkError("Invalid Nano-GPT usage endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)

        do {
            return try JSONDecoder().decode(NanoGptSubscriptionUsageResponse.self, from: data)
        } catch {
            logger.error("Failed to decode Nano-GPT usage: \(error.localizedDescription)")
            throw ProviderError.decodingError("Invalid Nano-GPT usage response")
        }
    }

    private func fetchBalance(apiKey: String) async throws -> NanoGptBalanceResponse {
        guard let url = URL(string: "https://nano-gpt.com/api/check-balance") else {
            throw ProviderError.networkError("Invalid Nano-GPT balance endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)

        do {
            return try JSONDecoder().decode(NanoGptBalanceResponse.self, from: data)
        } catch {
            logger.error("Failed to decode Nano-GPT balance: \(error.localizedDescription)")
            throw ProviderError.decodingError("Invalid Nano-GPT balance response")
        }
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("Invalid response type")
        }

        if httpResponse.statusCode == 401 {
            throw ProviderError.authenticationFailed("Invalid Nano-GPT API key")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            logger.error("Nano-GPT HTTP \(httpResponse.statusCode): \(body, privacy: .public)")
            throw ProviderError.networkError("HTTP \(httpResponse.statusCode)")
        }
    }

    private func normalizedPercent(_ percentValue: Double?, used: Int?, total: Int?) -> Double? {
        if let percentValue {
            if percentValue <= 1.0 {
                return min(max(percentValue * 100.0, 0), 100)
            }
            return min(max(percentValue, 0), 100)
        }

        guard let used, let total, total > 0 else {
            return nil
        }

        return min(max((Double(used) / Double(total)) * 100.0, 0), 100)
    }

    private func dateFromMilliseconds(_ milliseconds: Int64?) -> Date? {
        guard let milliseconds else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000.0)
    }

    private func formatISO8601(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }

        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let formatterWithoutFractional = ISO8601DateFormatter()
        formatterWithoutFractional.formatOptions = [.withInternetDateTime]

        let date = formatterWithFractional.date(from: value) ?? formatterWithoutFractional.date(from: value)
        guard let date else { return nil }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "yyyy-MM-dd HH:mm z"
        displayFormatter.timeZone = TimeZone.current
        return displayFormatter.string(from: date)
    }

    private func parseDouble(_ value: String?) -> Double? {
        guard let value, !value.isEmpty else { return nil }
        return Double(value)
    }
}
