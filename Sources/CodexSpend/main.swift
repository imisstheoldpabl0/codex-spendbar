import AppKit
import Darwin
import Foundation

struct TokenUsage {
    var inputTokens: Int64 = 0
    var cachedInputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var reasoningOutputTokens: Int64 = 0
    var totalTokens: Int64 = 0

    var uncachedInputTokens: Int64 {
        max(inputTokens - cachedInputTokens, 0)
    }

    var visibleOutputTokens: Int64 {
        max(outputTokens - reasoningOutputTokens, 0)
    }

    mutating func add(_ other: TokenUsage) {
        inputTokens += other.inputTokens
        cachedInputTokens += other.cachedInputTokens
        outputTokens += other.outputTokens
        reasoningOutputTokens += other.reasoningOutputTokens
        totalTokens += other.totalTokens
    }
}

struct CostBreakdown {
    var uncachedInput: Double = 0
    var cachedInput: Double = 0
    var visibleOutput: Double = 0
    var reasoningOutput: Double = 0

    var total: Double {
        uncachedInput + cachedInput + visibleOutput + reasoningOutput
    }

    mutating func add(_ other: CostBreakdown) {
        uncachedInput += other.uncachedInput
        cachedInput += other.cachedInput
        visibleOutput += other.visibleOutput
        reasoningOutput += other.reasoningOutput
    }
}

struct CreditBreakdown {
    var uncachedInput: Double = 0
    var cachedInput: Double = 0
    var visibleOutput: Double = 0
    var reasoningOutput: Double = 0

    var total: Double {
        uncachedInput + cachedInput + visibleOutput + reasoningOutput
    }

    mutating func add(_ other: CreditBreakdown) {
        uncachedInput += other.uncachedInput
        cachedInput += other.cachedInput
        visibleOutput += other.visibleOutput
        reasoningOutput += other.reasoningOutput
    }
}

let defaultMonthlyCreditBudgetCredits: Double = 7000
let monthlyCreditDollarRatePerCredit: Double = 200.0 / 5000.0

struct RequestUsage {
    let timestamp: Date
    let turnID: String
    let threadID: String
    let title: String
    let cwd: String
    let model: String
    let effort: String
    let speed: String
    let planType: String
    let usage: TokenUsage
    let cost: CostBreakdown
    let credits: CreditBreakdown
    let rateLabel: String
    let creditRateLabel: String
    let hasKnownPrice: Bool
    let hasKnownCreditPrice: Bool
}

struct ThreadMeta {
    let model: String
    let effort: String
    let title: String
    let cwd: String
    let lastActivityMS: Int64
}

struct UsageAggregate {
    var requests: Int = 0
    var usage = TokenUsage()
    var cost = CostBreakdown()
    var credits = CreditBreakdown()
    var unknownPriceRequests: Int = 0
    var unknownCreditPriceRequests: Int = 0

    mutating func add(_ request: RequestUsage) {
        requests += 1
        usage.add(request.usage)
        cost.add(request.cost)
        credits.add(request.credits)
        if !request.hasKnownPrice {
            unknownPriceRequests += 1
        }
        if !request.hasKnownCreditPrice {
            unknownCreditPriceRequests += 1
        }
    }
}

struct DaySummary {
    let date: Date
    let aggregate: UsageAggregate
}

struct MonthSummary {
    let monthStart: Date
    let aggregate: UsageAggregate
}

struct ModelSummary {
    let key: String
    let aggregate: UsageAggregate
}

struct ThreadSummary {
    let title: String
    let cwd: String
    let threadID: String
    let aggregate: UsageAggregate
    let breakdowns: [ThreadBreakdownSummary]
    let lastActivityMS: Int64
}

struct ThreadBreakdownSummary {
    let model: String
    let effort: String
    let speed: String
    let aggregate: UsageAggregate
}

struct ProjectSummary {
    let project: String
    let cwd: String
    let aggregate: UsageAggregate
}

struct SpendSnapshot {
    let generatedAt: Date
    let currentMonthStart: Date
    let currentMonth: UsageAggregate
    let currentMonthUnpricedCreditRequests: [RequestUsage]
    let days: [DaySummary]
    let today: UsageAggregate
    let allTime: UsageAggregate
    let months: [MonthSummary]
    let byModel: [ModelSummary]
    let byThread: [ThreadSummary]
    let byProject: [ProjectSummary]
    let recentRequests: [RequestUsage]
    let firstRequestAt: Date?
    let lastRequestAt: Date?
    let parseErrorCount: Int
    let filesScanned: Int

    static func empty(generatedAt: Date = Date()) -> SpendSnapshot {
        let calendar = Calendar.autoupdatingCurrent
        let currentMonthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: generatedAt)
        ) ?? calendar.startOfDay(for: generatedAt)
        return SpendSnapshot(
            generatedAt: generatedAt,
            currentMonthStart: currentMonthStart,
            currentMonth: UsageAggregate(),
            currentMonthUnpricedCreditRequests: [],
            days: [],
            today: UsageAggregate(),
            allTime: UsageAggregate(),
            months: [],
            byModel: [],
            byThread: [],
            byProject: [],
            recentRequests: [],
            firstRequestAt: nil,
            lastRequestAt: nil,
            parseErrorCount: 0,
            filesScanned: 0
        )
    }

    func plainTextSummary(
        currency: CurrencyState = CurrencyStore().load(),
        preferences: AppPreferences = PreferencesStore().load()
    ) -> String {
        let monthlyCreditBudgetCredits = preferences.monthlyCreditBudgetCredits
        let monthlyCreditBudgetUSD = monthlyCreditBudgetCredits * monthlyCreditDollarRatePerCredit
        var lines: [String] = []
        lines.append("Codex Spend")
        lines.append("Generated: \(Formatters.fullDateTime.string(from: generatedAt))")
        lines.append("Currency: \(currency.code.rawValue)")
        lines.append("Current month: \(Formatters.credits(currentMonth.credits.total)) credits spent · \(Formatters.money(currentMonth.cost.total, currency: currency))")
        let remainingCredits = monthlyCreditBudgetCredits - currentMonth.credits.total
        lines.append("Monthly budget: \(Formatters.credits(monthlyCreditBudgetCredits)) credits · \(Formatters.money(monthlyCreditBudgetUSD, currency: currency))")
        if remainingCredits < 0 {
            lines.append("Over budget: \(Formatters.credits(abs(remainingCredits))) credits")
        } else {
            lines.append("Remaining per Month: \(Formatters.credits(remainingCredits)) credits of \(Formatters.credits(monthlyCreditBudgetCredits))")
        }
        if !currentMonthUnpricedCreditRequests.isEmpty {
            lines.append("Unpriced credit requests: \(currentMonthUnpricedCreditRequests.count)")
            for request in currentMonthUnpricedCreditRequests {
                lines.append("  \(Formatters.shortTime.string(from: request.timestamp)) · \(request.model.isEmpty ? "unknown model" : request.model) · unpriced")
            }
        }
        lines.append("Today: \(Formatters.money(today.cost.total, currency: currency)) · \(Formatters.tokens(today.usage.totalTokens)) tokens · \(today.requests) turns")
        lines.append("All time: \(Formatters.money(allTime.cost.total, currency: currency)) · \(Formatters.tokens(allTime.usage.totalTokens)) tokens · \(allTime.requests) turns")
        lines.append("Today categories:")
        lines.append("  Input: \(Formatters.tokens(today.usage.uncachedInputTokens)) · \(Formatters.money(today.cost.uncachedInput, currency: currency))")
        lines.append("  Cached input: \(Formatters.tokens(today.usage.cachedInputTokens)) · \(Formatters.money(today.cost.cachedInput, currency: currency))")
        lines.append("  Output: \(Formatters.tokens(today.usage.visibleOutputTokens)) · \(Formatters.money(today.cost.visibleOutput, currency: currency))")
        lines.append("  Reasoning: \(Formatters.tokens(today.usage.reasoningOutputTokens)) · \(Formatters.money(today.cost.reasoningOutput, currency: currency))")
        lines.append("Recent days:")
        for day in days {
            lines.append("  \(Formatters.shortDay.string(from: day.date)): \(Formatters.money(day.aggregate.cost.total, currency: currency)) · \(Formatters.tokens(day.aggregate.usage.totalTokens)) · \(day.aggregate.requests) turns")
        }
        lines.append("Recent months:")
        for month in months.filter({ $0.monthStart != currentMonthStart }).prefix(12) {
            lines.append("  \(Formatters.month.string(from: month.monthStart)): \(Formatters.money(month.aggregate.cost.total, currency: currency)) · \(Formatters.tokens(month.aggregate.usage.totalTokens)) · \(month.aggregate.requests) turns")
        }
        lines.append("By model:")
        for summary in byModel.prefix(8) {
            lines.append("  \(summary.key): \(Formatters.money(summary.aggregate.cost.total, currency: currency)) · \(Formatters.tokens(summary.aggregate.usage.totalTokens)) · \(summary.aggregate.requests) turns")
        }
        lines.append("By project:")
        for summary in byProject.prefix(8) {
            lines.append("  \(summary.project): \(Formatters.money(summary.aggregate.cost.total, currency: currency)) · \(Formatters.tokens(summary.aggregate.usage.totalTokens)) · \(summary.aggregate.requests) turns")
        }
        lines.append("By thread:")
        for summary in byThread.prefix(8) {
            lines.append("  \(summary.title): \(Formatters.money(summary.aggregate.cost.total, currency: currency)) · \(Formatters.tokens(summary.aggregate.usage.totalTokens)) · \(summary.aggregate.requests) turns")
        }
        if parseErrorCount > 0 {
            lines.append("Skipped malformed records: \(parseErrorCount)")
        }
        lines.append("Files scanned: \(filesScanned)")
        return lines.joined(separator: "\n")
    }
}

struct PricingRates {
    let inputPerMillion: Double
    let cachedInputPerMillion: Double
    let outputPerMillion: Double
}

struct PriceEstimate {
    let cost: CostBreakdown
    let rateLabel: String
    let hasKnownPrice: Bool
}

enum PricingTable {
    private static let longContextInputThreshold: Int64 = 272_000

    static func estimate(for model: String, speed: String, usage: TokenUsage, modelContextWindow: Int64?) -> PriceEstimate {
        guard let rates = rates(for: model, speed: speed, usage: usage, modelContextWindow: modelContextWindow) else {
            return PriceEstimate(cost: CostBreakdown(), rateLabel: "unpriced", hasKnownPrice: false)
        }

        let million = 1_000_000.0
        let cost = CostBreakdown(
            uncachedInput: Double(usage.uncachedInputTokens) / million * rates.rates.inputPerMillion,
            cachedInput: Double(usage.cachedInputTokens) / million * rates.rates.cachedInputPerMillion,
            visibleOutput: Double(usage.visibleOutputTokens) / million * rates.rates.outputPerMillion,
            reasoningOutput: Double(usage.reasoningOutputTokens) / million * rates.rates.outputPerMillion
        )

        return PriceEstimate(cost: cost, rateLabel: rates.label, hasKnownPrice: true)
    }

    private static func rates(for model: String, speed: String, usage: TokenUsage, modelContextWindow: Int64?) -> (rates: PricingRates, label: String)? {
        let canonicalModel = canonical(model)
        let tier = normalizedSpeed(speed)
        let longContext = isLikelyLongContext(model: canonicalModel, usage: usage, modelContextWindow: modelContextWindow)

        if tier == "fast", let rates = fastRates[canonicalModel] {
            return (rates, "fast")
        }

        if tier == "flex", longContext, let rates = flexLongContextRates[canonicalModel] {
            return (rates, "flex long-context")
        }

        if tier == "flex", let rates = flexRates[canonicalModel] {
            return (rates, "flex")
        }

        if longContext, let rates = longContextRates[canonicalModel] {
            return (rates, "standard long-context")
        }

        if let rates = standardRates[canonicalModel] {
            return (rates, "standard")
        }

        return nil
    }

    private static func canonical(_ model: String) -> String {
        let lower = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.hasPrefix("gpt-5.1-codex-max") {
            return "gpt-5.1-codex"
        }
        return lower
    }

    static func normalizedSpeed(_ speed: String) -> String {
        let lower = speed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower == "fast" || lower == "priority" {
            return "fast"
        }
        if lower == "flex" {
            return "flex"
        }
        return "standard"
    }

    private static func isLikelyLongContext(model: String, usage: TokenUsage, modelContextWindow: Int64?) -> Bool {
        guard model == "gpt-5.5" || model == "gpt-5.4" else {
            return false
        }

        return usage.inputTokens > longContextInputThreshold
    }

    private static let standardRates: [String: PricingRates] = [
        "gpt-5.5": PricingRates(inputPerMillion: 5.00, cachedInputPerMillion: 0.50, outputPerMillion: 30.00),
        "gpt-5.4": PricingRates(inputPerMillion: 2.50, cachedInputPerMillion: 0.25, outputPerMillion: 15.00),
        "gpt-5.4-mini": PricingRates(inputPerMillion: 0.75, cachedInputPerMillion: 0.075, outputPerMillion: 4.50),
        "gpt-5.4-nano": PricingRates(inputPerMillion: 0.20, cachedInputPerMillion: 0.02, outputPerMillion: 1.25),
        "gpt-5.3-codex": PricingRates(inputPerMillion: 1.75, cachedInputPerMillion: 0.175, outputPerMillion: 14.00),
        "gpt-5.2-codex": PricingRates(inputPerMillion: 1.75, cachedInputPerMillion: 0.175, outputPerMillion: 14.00),
        "gpt-5.1-codex": PricingRates(inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.00),
        "gpt-5-codex": PricingRates(inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.00),
        "gpt-5.2": PricingRates(inputPerMillion: 1.75, cachedInputPerMillion: 0.175, outputPerMillion: 14.00),
        "gpt-5.1": PricingRates(inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.00),
        "gpt-5": PricingRates(inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.00)
    ]

    private static let longContextRates: [String: PricingRates] = [
        "gpt-5.5": PricingRates(inputPerMillion: 10.00, cachedInputPerMillion: 1.00, outputPerMillion: 45.00),
        "gpt-5.4": PricingRates(inputPerMillion: 5.00, cachedInputPerMillion: 0.50, outputPerMillion: 22.50)
    ]

    private static let fastRates: [String: PricingRates] = [
        "gpt-5.5": PricingRates(inputPerMillion: 12.50, cachedInputPerMillion: 1.25, outputPerMillion: 75.00),
        "gpt-5.4": PricingRates(inputPerMillion: 5.00, cachedInputPerMillion: 0.50, outputPerMillion: 30.00),
        "gpt-5.4-mini": PricingRates(inputPerMillion: 1.50, cachedInputPerMillion: 0.15, outputPerMillion: 9.00),
        "gpt-5.3-codex": PricingRates(inputPerMillion: 3.50, cachedInputPerMillion: 0.35, outputPerMillion: 28.00)
    ]

    private static let flexRates: [String: PricingRates] = [
        "gpt-5.5": PricingRates(inputPerMillion: 2.50, cachedInputPerMillion: 0.25, outputPerMillion: 15.00),
        "gpt-5.4": PricingRates(inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 7.50),
        "gpt-5.4-mini": PricingRates(inputPerMillion: 0.375, cachedInputPerMillion: 0.0375, outputPerMillion: 2.25),
        "gpt-5.3-codex": PricingRates(inputPerMillion: 0.875, cachedInputPerMillion: 0.0875, outputPerMillion: 7.00)
    ]

    private static let flexLongContextRates: [String: PricingRates] = [
        "gpt-5.5": PricingRates(inputPerMillion: 5.00, cachedInputPerMillion: 0.50, outputPerMillion: 22.50),
        "gpt-5.4": PricingRates(inputPerMillion: 2.50, cachedInputPerMillion: 0.25, outputPerMillion: 11.25)
    ]
}

enum CreditPricingTable {
    static func estimate(for model: String, planType: String, usage: TokenUsage) -> CreditEstimate {
        guard let rates = rates(for: model, planType: planType) else {
            return CreditEstimate(credits: CreditBreakdown(), rateLabel: "unpriced", hasKnownPrice: false)
        }

        let million = 1_000_000.0
        let credits = CreditBreakdown(
            uncachedInput: Double(usage.uncachedInputTokens) / million * rates.rates.inputPerMillion,
            cachedInput: Double(usage.cachedInputTokens) / million * rates.rates.cachedInputPerMillion,
            visibleOutput: Double(usage.visibleOutputTokens) / million * rates.rates.outputPerMillion,
            reasoningOutput: Double(usage.reasoningOutputTokens) / million * rates.rates.outputPerMillion
        )

        return CreditEstimate(credits: credits, rateLabel: rates.label, hasKnownPrice: true)
    }

    private static func rates(for model: String, planType: String) -> (rates: PricingRates, label: String)? {
        let canonicalModel = canonical(model, planType: planType)
        switch canonicalModel {
        case "gpt-image-2:image":
            return (PricingRates(inputPerMillion: 200.00, cachedInputPerMillion: 50.00, outputPerMillion: 750.00), "image")
        case "gpt-image-2:text":
            return (PricingRates(inputPerMillion: 125.00, cachedInputPerMillion: 31.25, outputPerMillion: 250.00), "text")
        case "gpt-5.5":
            return (PricingRates(inputPerMillion: 125.00, cachedInputPerMillion: 12.50, outputPerMillion: 750.00), "standard")
        case "gpt-5.4":
            return (PricingRates(inputPerMillion: 62.50, cachedInputPerMillion: 6.25, outputPerMillion: 375.00), "standard")
        case "gpt-5.4-mini":
            return (PricingRates(inputPerMillion: 18.75, cachedInputPerMillion: 1.875, outputPerMillion: 113.00), "standard")
        case "gpt-5.3-codex-spark":
            return nil
        default:
            return nil
        }
    }

    private static func canonical(_ model: String, planType: String) -> String {
        let lower = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let plan = planType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if lower.contains("gpt-image-2") {
            let imageHint = lower.contains("(image)") || lower.contains(":image") || lower.contains(" image ") || lower.hasSuffix(" image") || plan.contains("image")
            let textHint = lower.contains("(text)") || lower.contains(":text") || lower.contains(" text ") || lower.hasSuffix(" text") || plan.contains("text")

            if imageHint && !textHint {
                return "gpt-image-2:image"
            }
            if textHint && !imageHint {
                return "gpt-image-2:text"
            }
            return "gpt-image-2:text"
        }

        if lower.hasPrefix("gpt-5.1-codex-max") {
            return "gpt-5.1-codex"
        }

        if lower.contains("spark") {
            return "gpt-5.3-codex-spark"
        }

        return lower
    }
}

struct CreditEstimate {
    let credits: CreditBreakdown
    let rateLabel: String
    let hasKnownPrice: Bool
}

enum CurrencyCode: String, CaseIterable {
    case usd = "USD"
    case eur = "EUR"
}

enum TrendChartMode: String, CaseIterable {
    case blocks = "Blocks"
    case line = "Line"
    case ascii = "ASCII"
}

struct AppPreferences {
    var dailyWarningUSD: Double
    var requestWarningUSD: Double
    var spikeMultiplier: Double
    var monthlyCreditBudgetCredits: Double
    var chartMode: TrendChartMode
    var showEstimateLabels: Bool
}

final class PreferencesStore {
    private let defaults = UserDefaults.standard
    private let dailyWarningKey = "dailyWarningUSD"
    private let requestWarningKey = "requestWarningUSD"
    private let spikeMultiplierKey = "spikeMultiplier"
    private let monthlyCreditBudgetKey = "monthlyCreditBudgetCredits"
    private let chartModeKey = "chartMode"
    private let showEstimateLabelsKey = "showEstimateLabels"

    func load() -> AppPreferences {
        let daily = defaults.object(forKey: dailyWarningKey) as? Double ?? 25
        let request = defaults.object(forKey: requestWarningKey) as? Double ?? 3
        let spike = defaults.object(forKey: spikeMultiplierKey) as? Double ?? 2
        let monthlyCreditBudget = defaults.object(forKey: monthlyCreditBudgetKey) as? Double ?? defaultMonthlyCreditBudgetCredits
        let mode = TrendChartMode(rawValue: defaults.string(forKey: chartModeKey) ?? "") ?? .blocks
        let showLabels = defaults.object(forKey: showEstimateLabelsKey) as? Bool ?? false
        return AppPreferences(
            dailyWarningUSD: max(daily, 0),
            requestWarningUSD: max(request, 0),
            spikeMultiplier: max(spike, 1),
            monthlyCreditBudgetCredits: max(monthlyCreditBudget, 0),
            chartMode: mode,
            showEstimateLabels: showLabels
        )
    }

    func save(_ preferences: AppPreferences) {
        defaults.set(preferences.dailyWarningUSD, forKey: dailyWarningKey)
        defaults.set(preferences.requestWarningUSD, forKey: requestWarningKey)
        defaults.set(preferences.spikeMultiplier, forKey: spikeMultiplierKey)
        defaults.set(preferences.monthlyCreditBudgetCredits, forKey: monthlyCreditBudgetKey)
        defaults.set(preferences.chartMode.rawValue, forKey: chartModeKey)
        defaults.set(preferences.showEstimateLabels, forKey: showEstimateLabelsKey)
    }
}

final class CalculationStateStore {
    private let defaults = UserDefaults.standard
    private let currentMonthAnchorKey = "currentMonthAnchorDate"

    func loadCurrentMonthAnchor() -> Date? {
        defaults.object(forKey: currentMonthAnchorKey) as? Date
    }

    func resetCurrentMonthAnchor() {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let currentMonthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? calendar.startOfDay(for: now)
        defaults.set(currentMonthStart, forKey: currentMonthAnchorKey)
    }

    func clearCurrentMonthAnchor() {
        defaults.removeObject(forKey: currentMonthAnchorKey)
    }
}

struct CurrencyState {
    let code: CurrencyCode
    let usdToEUR: Double
    let rateDate: String

    var conversionRate: Double {
        switch code {
        case .usd:
            return 1
        case .eur:
            return usdToEUR
        }
    }
}

final class CurrencyStore {
    private let defaults = UserDefaults.standard
    private let currencyKey = "currencyCode"
    private let usdToEURKey = "usdToEUR"
    private let rateDateKey = "usdToEURDate"
    private let fetchedAtKey = "usdToEURFetchedAt"
    private let fallbackUSDToEUR = 0.85866
    private let fallbackRateDate = "2026-06-01"

    func load() -> CurrencyState {
        let rawCode = defaults.string(forKey: currencyKey) ?? CurrencyCode.usd.rawValue
        let code = CurrencyCode(rawValue: rawCode) ?? .usd
        let storedRate = defaults.double(forKey: usdToEURKey)
        let rate = storedRate > 0 ? storedRate : fallbackUSDToEUR
        let date = defaults.string(forKey: rateDateKey) ?? fallbackRateDate
        return CurrencyState(code: code, usdToEUR: rate, rateDate: date)
    }

    func setCurrency(_ code: CurrencyCode) -> CurrencyState {
        defaults.set(code.rawValue, forKey: currencyKey)
        return load()
    }

    func refreshEURRateIfNeeded(force: Bool = false, completion: @escaping (CurrencyState) -> Void) {
        let lastFetched = defaults.object(forKey: fetchedAtKey) as? Date
        if !force, let lastFetched, Date().timeIntervalSince(lastFetched) < 12 * 60 * 60 {
            completion(load())
            return
        }

        guard let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=USD&symbols=EUR") else {
            completion(load())
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else {
                return
            }

            defer {
                completion(self.load())
            }

            guard let data,
                  let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                  let rates = object["rates"] as? [String: Any],
                  let eur = rates["EUR"] as? NSNumber else {
                return
            }

            self.defaults.set(eur.doubleValue, forKey: self.usdToEURKey)
            self.defaults.set((object["date"] as? String) ?? self.fallbackRateDate, forKey: self.rateDateKey)
            self.defaults.set(Date(), forKey: self.fetchedAtKey)
        }.resume()
    }
}

struct LoginItemStatus {
    let isInstalled: Bool
    let matchesCurrentExecutable: Bool
}

final class LoginItemManager {
    private let label = "com.local.codex-spend"
    private let fileManager = FileManager.default

    private var launchAgentURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/LaunchAgents/com.local.codex-spend.plist")
    }

    var currentExecutablePath: String {
        Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
    }

    func status() -> LoginItemStatus {
        guard fileManager.fileExists(atPath: launchAgentURL.path),
              let contents = try? String(contentsOf: launchAgentURL, encoding: .utf8) else {
            return LoginItemStatus(isInstalled: false, matchesCurrentExecutable: false)
        }

        return LoginItemStatus(
            isInstalled: true,
            matchesCurrentExecutable: contents.contains(currentExecutablePath)
        )
    }

    func setEnabled(_ enabled: Bool) {
        let currentStatus = status()
        if enabled {
            guard !currentStatus.isInstalled || !currentStatus.matchesCurrentExecutable else {
                return
            }
            install()
        } else {
            guard currentStatus.isInstalled else {
                return
            }
            uninstall()
        }
    }

    private func install() {
        let escapedExecutable = currentExecutablePath
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(label)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(escapedExecutable)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <false/>
        </dict>
        </plist>
        """

        runLaunchctl(["bootout", "gui/\(getuid())", launchAgentURL.path])
        try? fileManager.createDirectory(at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? plist.write(to: launchAgentURL, atomically: true, encoding: .utf8)
    }

    private func uninstall() {
        runLaunchctl(["bootout", "gui/\(getuid())", launchAgentURL.path])
        try? fileManager.removeItem(at: launchAgentURL)
    }

    private func runLaunchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}

final class Formatters {
    static let shortDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }()

    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let fullDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    static func money(_ usdValue: Double, currency: CurrencyState) -> String {
        let converted = usdValue * currency.conversionRate
        let symbol = currency.code == .usd ? "$" : "€"
        if converted == 0 {
            return "\(symbol)0.00"
        }
        if abs(converted) < 0.01 {
            return String(format: "\(symbol)%.4f", converted)
        }
        return String(format: "\(symbol)%.2f", converted)
    }

    static func credits(_ value: Double) -> String {
        if value == 0 {
            return "0"
        }

        var formatted = String(format: "%.3f", value)
        while formatted.contains(".") && formatted.hasSuffix("0") {
            formatted.removeLast()
        }
        if formatted.hasSuffix(".") {
            formatted.removeLast()
        }
        return formatted
    }

    static func tokens(_ value: Int64) -> String {
        let absolute = abs(value)
        if absolute >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        }
        if absolute >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000.0)
        }
        return "\(value)"
    }

    static func ratio(_ value: Double) -> String {
        String(format: "%.1fx", value)
    }
}

enum TrendRenderer {
    static func render(values: [Double], mode: TrendChartMode, width: Int? = nil) -> String {
        let pointCount = max(width ?? defaultWidth(for: mode), 1)
        let trimmed = bucket(values, maxPoints: pointCount)
        guard let maxValue = trimmed.max(), maxValue > 0 else {
            return String(repeating: "0", count: max(trimmed.count, 1))
        }

        let palette: [Character]
        switch mode {
        case .blocks:
            palette = Array("▁▂▃▄▅▆▇█")
        case .line:
            palette = Array("⣀⣄⣤⣦⣶⣷⣿")
        case .ascii:
            palette = Array("._-=+#%@")
        }

        return String(trimmed.map { value in
            let normalized = min(max(value / maxValue, 0), 1)
            let index = min(Int((normalized * Double(palette.count - 1)).rounded()), palette.count - 1)
            return palette[index]
        })
    }

    private static func defaultWidth(for mode: TrendChartMode) -> Int {
        switch mode {
        case .blocks:
            return 18
        case .line, .ascii:
            return 30
        }
    }

    private static func bucket(_ values: [Double], maxPoints: Int) -> [Double] {
        guard values.count > maxPoints else {
            return values
        }

        return (0..<maxPoints).map { index in
            let start = Int((Double(index) * Double(values.count) / Double(maxPoints)).rounded(.down))
            let end = Int((Double(index + 1) * Double(values.count) / Double(maxPoints)).rounded(.up))
            let slice = values[start..<min(max(end, start + 1), values.count)]
            return slice.max() ?? 0
        }
    }
}

final class DateParsers {
    private let fractionalISO: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let wholeSecondISO: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func parse(_ value: String) -> Date? {
        fractionalISO.date(from: value) ?? wholeSecondISO.date(from: value)
    }
}

final class CodexUsageStore {
    private let fileManager = FileManager.default
    private let homeURL = URL(fileURLWithPath: NSHomeDirectory())
    private let dateParsers = DateParsers()
    private let uuidRegex = try! NSRegularExpression(
        pattern: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
    )

    func loadSnapshot(recentDays: Int = 30, currentMonthAnchor: Date? = nil) -> SpendSnapshot {
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        let todayStart = calendar.startOfDay(for: now)
        let anchor = currentMonthAnchor ?? now
        let currentMonthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: anchor)
        ) ?? todayStart
        let recentWindowStart = calendar.date(byAdding: .day, value: -(max(recentDays, 1) - 1), to: todayStart) ?? todayStart

        let defaultSpeed = readDefaultSpeed()
        let threadMeta = loadThreadMetadata()
        var parseErrorCount = 0
        let files = sessionFiles(modifiedSince: nil)
        var requests = parseWithRipgrep(
            defaultSpeed: defaultSpeed,
            threadMeta: threadMeta,
            parseErrorCount: &parseErrorCount
        )

        if requests.isEmpty {
            for file in files {
                requests.append(contentsOf: parseSessionFile(
                    file,
                    windowStart: nil,
                    defaultSpeed: defaultSpeed,
                    threadMeta: threadMeta,
                    parseErrorCount: &parseErrorCount
                ))
            }
        }

        requests.sort { $0.timestamp < $1.timestamp }

        var todayAggregate = UsageAggregate()
        var allTimeAggregate = UsageAggregate()
        var dailyByStart: [Date: UsageAggregate] = [:]
        var monthlyByStart: [Date: UsageAggregate] = [:]
        var modelAggregates: [String: UsageAggregate] = [:]
        var threadAggregates: [String: UsageAggregate] = [:]
        var threadBreakdownAggregates: [String: [ThreadBreakdownKey: UsageAggregate]] = [:]
        var threadTitles: [String: String] = [:]
        var threadCWDs: [String: String] = [:]
        var projectAggregates: [String: UsageAggregate] = [:]
        var projectCWDs: [String: String] = [:]

        for request in requests {
            allTimeAggregate.add(request)

            let dayStart = calendar.startOfDay(for: request.timestamp)
            if request.timestamp >= recentWindowStart {
                dailyByStart[dayStart, default: UsageAggregate()].add(request)
            }

            if let monthStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: request.timestamp)
            ) {
                monthlyByStart[monthStart, default: UsageAggregate()].add(request)
            }

            if calendar.isDate(request.timestamp, inSameDayAs: now) {
                todayAggregate.add(request)
            }

            let key = [
                request.model.isEmpty ? "unknown model" : request.model,
                request.effort.isEmpty ? "unknown effort" : request.effort,
                PricingTable.normalizedSpeed(request.speed)
            ].joined(separator: " · ")
            modelAggregates[key, default: UsageAggregate()].add(request)

            threadAggregates[request.threadID, default: UsageAggregate()].add(request)
            threadTitles[request.threadID] = request.title
            threadCWDs[request.threadID] = request.cwd
            let breakdownKey = ThreadBreakdownKey(
                model: request.model.isEmpty ? "unknown model" : request.model,
                effort: request.effort.isEmpty ? "unknown effort" : request.effort,
                speed: PricingTable.normalizedSpeed(request.speed)
            )
            threadBreakdownAggregates[request.threadID, default: [:]][breakdownKey, default: UsageAggregate()].add(request)

            let project = projectName(from: request.cwd)
            projectAggregates[project, default: UsageAggregate()].add(request)
            if projectCWDs[project, default: ""].isEmpty {
                projectCWDs[project] = request.cwd
            }
        }

        let days = (0..<max(recentDays, 1)).compactMap { offset -> DaySummary? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: todayStart) else {
                return nil
            }
            return DaySummary(date: date, aggregate: dailyByStart[date] ?? UsageAggregate())
        }

        let months = monthlyByStart
            .map { MonthSummary(monthStart: $0.key, aggregate: $0.value) }
            .sorted { $0.monthStart > $1.monthStart }
        let currentMonth = monthlyByStart[currentMonthStart] ?? UsageAggregate()
        let currentMonthUnpricedCreditRequests = Array(requests.filter {
            calendar.isDate($0.timestamp, equalTo: currentMonthStart, toGranularity: .month) && !$0.hasKnownCreditPrice
        }.reversed())

        let byModel = modelAggregates
            .map { ModelSummary(key: $0.key, aggregate: $0.value) }
            .sorted {
                if $0.aggregate.cost.total == $1.aggregate.cost.total {
                    return $0.aggregate.usage.totalTokens > $1.aggregate.usage.totalTokens
                }
                return $0.aggregate.cost.total > $1.aggregate.cost.total
            }

        let threadLastSeenMS = requests.reduce(into: [String: Int64]()) { result, request in
            let timestampMS = Int64(request.timestamp.timeIntervalSince1970 * 1000)
            result[request.threadID] = max(result[request.threadID] ?? 0, timestampMS)
        }

        let byThread = threadAggregates
            .map {
                let threadID = $0.key
                let metaLastSeenMS = threadMeta[threadID]?.lastActivityMS ?? 0
                let lastActivityMS = max(metaLastSeenMS, threadLastSeenMS[threadID] ?? 0)
                return ThreadSummary(
                    title: threadMeta[threadID]?.title ?? threadTitles[threadID] ?? threadID,
                    cwd: threadCWDs[threadID] ?? "",
                    threadID: threadID,
                    aggregate: $0.value,
                    breakdowns: (threadBreakdownAggregates[threadID] ?? [:])
                        .map {
                            ThreadBreakdownSummary(
                                model: $0.key.model,
                                effort: $0.key.effort,
                                speed: $0.key.speed,
                                aggregate: $0.value
                            )
                        }
                        .sorted {
                            if $0.aggregate.cost.total == $1.aggregate.cost.total {
                                return $0.aggregate.usage.totalTokens > $1.aggregate.usage.totalTokens
                            }
                            return $0.aggregate.cost.total > $1.aggregate.cost.total
                        },
                    lastActivityMS: lastActivityMS
                )
            }
            .sorted(by: { lhs, rhs in
                if lhs.lastActivityMS == rhs.lastActivityMS {
                    if lhs.aggregate.cost.total == rhs.aggregate.cost.total {
                        return lhs.aggregate.usage.totalTokens > rhs.aggregate.usage.totalTokens
                    }
                    return lhs.aggregate.cost.total > rhs.aggregate.cost.total
                }
                return lhs.lastActivityMS > rhs.lastActivityMS
            })

        let byProject = projectAggregates
            .map {
                ProjectSummary(
                    project: $0.key,
                    cwd: projectCWDs[$0.key] ?? "",
                    aggregate: $0.value
                )
            }
            .sorted {
                if $0.aggregate.cost.total == $1.aggregate.cost.total {
                    return $0.aggregate.usage.totalTokens > $1.aggregate.usage.totalTokens
                }
                return $0.aggregate.cost.total > $1.aggregate.cost.total
            }

        return SpendSnapshot(
            generatedAt: now,
            currentMonthStart: currentMonthStart,
            currentMonth: currentMonth,
            currentMonthUnpricedCreditRequests: currentMonthUnpricedCreditRequests,
            days: days,
            today: todayAggregate,
            allTime: allTimeAggregate,
            months: months,
            byModel: byModel,
            byThread: byThread,
            byProject: byProject,
            recentRequests: Array(requests.suffix(14).reversed()),
            firstRequestAt: requests.first?.timestamp,
            lastRequestAt: requests.last?.timestamp,
            parseErrorCount: parseErrorCount,
            filesScanned: files.count
        )
    }

    private struct ThreadBreakdownKey: Hashable {
        let model: String
        let effort: String
        let speed: String
    }

    private func projectName(from cwd: String) -> String {
        let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Unknown project"
        }

        let url = URL(fileURLWithPath: trimmed)
        let name = url.lastPathComponent
        if !name.isEmpty {
            return name
        }
        return trimmed
    }

    private func sessionFiles(modifiedSince cutoff: Date?) -> [URL] {
        let roots = [
            homeURL.appendingPathComponent(".codex/sessions"),
            homeURL.appendingPathComponent(".codex/archived_sessions")
        ]
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        var result: [URL] = []

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "jsonl" else {
                    continue
                }

                let values = try? fileURL.resourceValues(forKeys: keys)
                guard values?.isRegularFile == true else {
                    continue
                }

                if let cutoff, let modified = values?.contentModificationDate, modified < cutoff {
                    continue
                }

                result.append(fileURL)
            }
        }

        return result.sorted { $0.path < $1.path }
    }

    private struct SessionParseContext {
        var model: String
        var effort: String
        var speed: String
        let title: String
        let cwd: String
        let threadID: String
        var pending: PendingRequest?
    }

    private struct PendingRequest {
        let turnID: String
        let startedAt: Date
        var timestamp: Date
        let model: String
        let effort: String
        let speed: String
        let threadID: String
        let title: String
        let cwd: String
        var planType: String = ""
        var modelContextWindow: Int64?
        var usage = TokenUsage()
        var cost = CostBreakdown()
        var credits = CreditBreakdown()
        var rateLabel = ""
        var creditRateLabel = ""
        var hasKnownPrice = true
        var hasKnownCreditPrice = true

        var hasUsage: Bool {
            usage.totalTokens > 0 || usage.inputTokens > 0 || usage.outputTokens > 0
        }
    }

    private func parseWithRipgrep(
        defaultSpeed: String,
        threadMeta: [String: ThreadMeta],
        parseErrorCount: inout Int
    ) -> [RequestUsage] {
        guard let rgURL = ripgrepURL() else {
            return []
        }

        let roots = [
            homeURL.appendingPathComponent(".codex/sessions"),
            homeURL.appendingPathComponent(".codex/archived_sessions")
        ].filter { fileManager.fileExists(atPath: $0.path) }

        guard !roots.isEmpty else {
            return []
        }

        let process = Process()
        let output = Pipe()
        process.executableURL = rgURL
        process.arguments = [
            "--json",
            "-n",
            "-j",
            "1",
            "-g",
            "*.jsonl",
            #""type":"turn_context"|"type":"event_msg".*"token_count""#
        ] + roots.map(\.path)
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 || process.terminationStatus == 1,
              let contents = String(data: data, encoding: .utf8) else {
            return []
        }

        var contexts: [String: SessionParseContext] = [:]
        var requests: [RequestUsage] = []

        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let wrapper = parseJSONLine(rawLine),
                  wrapper["type"] as? String == "match",
                  let data = wrapper["data"] as? [String: Any],
                  let pathObject = data["path"] as? [String: Any],
                  let path = pathObject["text"] as? String,
                  let linesObject = data["lines"] as? [String: Any],
                  let lineText = linesObject["text"] as? String else {
                continue
            }

            let fileURL = URL(fileURLWithPath: path)
            guard let context = context(
                for: fileURL,
                defaultSpeed: defaultSpeed,
                threadMeta: threadMeta,
                contexts: &contexts
            ) else {
                continue
            }

            var mutableContext = context
            requests.append(contentsOf: parseMatchedLine(lineText, context: &mutableContext, parseErrorCount: &parseErrorCount))
            contexts[path] = mutableContext
        }

        for var context in contexts.values {
            if let request = finalizePendingRequest(&context) {
                requests.append(request)
            }
        }

        return requests
    }

    private func context(
        for fileURL: URL,
        defaultSpeed: String,
        threadMeta: [String: ThreadMeta],
        contexts: inout [String: SessionParseContext]
    ) -> SessionParseContext? {
        let path = fileURL.path
        if let context = contexts[path] {
            return context
        }

        guard let threadID = extractThreadID(from: fileURL) else {
            return nil
        }

        let meta = threadMeta[threadID]
        let context = SessionParseContext(
            model: meta?.model ?? "",
            effort: meta?.effort ?? "",
            speed: defaultSpeed,
            title: meta?.title ?? threadID,
            cwd: meta?.cwd ?? "",
            threadID: threadID,
            pending: nil
        )
        contexts[path] = context
        return context
    }

    private func parseMatchedLine(
        _ line: String,
        context: inout SessionParseContext,
        parseErrorCount: inout Int
    ) -> [RequestUsage] {
        if line.contains("\"type\":\"turn_context\"") {
            guard let object = parseJSONLine(line),
                  object["type"] as? String == "turn_context",
                  let payload = object["payload"] as? [String: Any] else {
                parseErrorCount += 1
                return []
            }

            var finalized: [RequestUsage] = []
            if let request = finalizePendingRequest(&context) {
                finalized.append(request)
            }

            updateContext(&context, from: payload)
            let timestamp = (object["timestamp"] as? String).flatMap { dateParsers.parse($0) } ?? Date()
            beginPendingRequest(&context, timestamp: timestamp, turnID: nonEmptyString(payload["turn_id"]))
            return finalized
        }

        guard line.contains("\"type\":\"event_msg\""), line.contains("\"token_count\"") else {
            return []
        }

        guard let object = parseJSONLine(line),
              object["type"] as? String == "event_msg",
              let timestampString = object["timestamp"] as? String,
              let timestamp = dateParsers.parse(timestampString),
              let payload = object["payload"] as? [String: Any],
              let payloadType = payload["type"] as? String,
              payloadType == "token_count" else {
            parseErrorCount += 1
            return []
        }

        guard let info = payload["info"] as? [String: Any],
              let lastUsage = info["last_token_usage"] as? [String: Any] else {
            return []
        }

        let usage = TokenUsage(
            inputTokens: int64(lastUsage["input_tokens"]),
            cachedInputTokens: int64(lastUsage["cached_input_tokens"]),
            outputTokens: int64(lastUsage["output_tokens"]),
            reasoningOutputTokens: int64(lastUsage["reasoning_output_tokens"]),
            totalTokens: int64(lastUsage["total_tokens"])
        )

        let rateLimits = payload["rate_limits"] as? [String: Any]
        addUsage(
            usage,
            timestamp: timestamp,
            planType: nonEmptyString(rateLimits?["plan_type"]) ?? "",
            modelContextWindow: int64OrNil(info["model_context_window"]),
            to: &context
        )
        return []
    }

    private func beginPendingRequest(_ context: inout SessionParseContext, timestamp: Date, turnID: String?) {
        context.pending = PendingRequest(
            turnID: turnID ?? "\(context.threadID)-\(Int(timestamp.timeIntervalSince1970 * 1000))",
            startedAt: timestamp,
            timestamp: timestamp,
            model: context.model,
            effort: context.effort,
            speed: context.speed,
            threadID: context.threadID,
            title: context.title,
            cwd: context.cwd
        )
    }

    private func addUsage(
        _ usage: TokenUsage,
        timestamp: Date,
        planType: String,
        modelContextWindow: Int64?,
        to context: inout SessionParseContext
    ) {
        if context.pending == nil {
            beginPendingRequest(&context, timestamp: timestamp, turnID: nil)
        }

        let price = PricingTable.estimate(
            for: context.pending?.model ?? context.model,
            speed: context.pending?.speed ?? context.speed,
            usage: usage,
            modelContextWindow: modelContextWindow
        )
        let creditEstimate = CreditPricingTable.estimate(
            for: context.pending?.model ?? context.model,
            planType: planType,
            usage: usage
        )

        guard var pending = context.pending else {
            return
        }

        pending.usage.add(usage)
        pending.cost.add(price.cost)
        pending.credits.add(creditEstimate.credits)
        pending.timestamp = timestamp
        pending.hasKnownPrice = pending.hasKnownPrice && price.hasKnownPrice
        pending.hasKnownCreditPrice = pending.hasKnownCreditPrice && creditEstimate.hasKnownPrice
        if pending.rateLabel.isEmpty {
            pending.rateLabel = price.rateLabel
        } else if pending.rateLabel != price.rateLabel {
            pending.rateLabel = "mixed"
        }
        if pending.creditRateLabel.isEmpty {
            pending.creditRateLabel = creditEstimate.rateLabel
        } else if pending.creditRateLabel != creditEstimate.rateLabel {
            pending.creditRateLabel = "mixed"
        }
        if !planType.isEmpty {
            pending.planType = planType
        }
        if let modelContextWindow {
            pending.modelContextWindow = modelContextWindow
        }
        context.pending = pending
    }

    private func finalizePendingRequest(_ context: inout SessionParseContext) -> RequestUsage? {
        guard let pending = context.pending, pending.hasUsage else {
            context.pending = nil
            return nil
        }

        context.pending = nil
        return RequestUsage(
            timestamp: pending.timestamp,
            turnID: pending.turnID,
            threadID: pending.threadID,
            title: pending.title,
            cwd: pending.cwd,
            model: pending.model,
            effort: pending.effort,
            speed: pending.speed,
            planType: pending.planType,
            usage: pending.usage,
            cost: pending.cost,
            credits: pending.credits,
            rateLabel: pending.rateLabel.isEmpty ? "unpriced" : pending.rateLabel,
            creditRateLabel: pending.creditRateLabel.isEmpty ? "unpriced" : pending.creditRateLabel,
            hasKnownPrice: pending.hasKnownPrice,
            hasKnownCreditPrice: pending.hasKnownCreditPrice
        )
    }

    private func updateContext(_ context: inout SessionParseContext, from payload: [String: Any]) {
        if let model = nonEmptyString(payload["model"]) {
            context.model = model
        }
        if let effort = nonEmptyString(payload["effort"]) {
            context.effort = effort
        }

        if let collaboration = payload["collaboration_mode"] as? [String: Any],
           let settings = collaboration["settings"] as? [String: Any] {
            if context.model.isEmpty, let model = nonEmptyString(settings["model"]) {
                context.model = model
            }
            if context.effort.isEmpty, let effort = nonEmptyString(settings["reasoning_effort"]) {
                context.effort = effort
            }
            if let speed = nonEmptyString(settings["service_tier"]) ?? nonEmptyString(settings["speed"]) {
                context.speed = speed
            }
        }

        if let speed = nonEmptyString(payload["service_tier"]) ?? nonEmptyString(payload["speed"]) {
            context.speed = speed
        }
    }

    private func ripgrepURL() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/rg",
            "/usr/local/bin/rg",
            "/usr/bin/rg"
        ]

        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }

    private func parseSessionFile(
        _ fileURL: URL,
        windowStart: Date?,
        defaultSpeed: String,
        threadMeta: [String: ThreadMeta],
        parseErrorCount: inout Int
    ) -> [RequestUsage] {
        guard let threadID = extractThreadID(from: fileURL) else {
            return []
        }

        let meta = threadMeta[threadID]
        var currentModel = meta?.model ?? ""
        var currentEffort = meta?.effort ?? ""
        var currentSpeed = defaultSpeed
        let title = meta?.title ?? threadID
        let cwd = meta?.cwd ?? ""
        var context = SessionParseContext(
            model: currentModel,
            effort: currentEffort,
            speed: currentSpeed,
            title: title,
            cwd: cwd,
            threadID: threadID,
            pending: nil
        )

        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            parseErrorCount += 1
            return []
        }

        var requests: [RequestUsage] = []

        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.contains("\"type\":\"turn_context\"") {
                guard let object = parseJSONLine(line),
                      object["type"] as? String == "turn_context",
                      let payload = object["payload"] as? [String: Any] else {
                    if parseJSONLine(line) == nil {
                        parseErrorCount += 1
                    }
                    continue
                }

                if let request = finalizePendingRequest(&context) {
                    requests.append(request)
                }

                updateContext(&context, from: payload)
                let turnTimestamp = (object["timestamp"] as? String).flatMap { dateParsers.parse($0) } ?? Date()
                beginPendingRequest(&context, timestamp: turnTimestamp, turnID: nonEmptyString(payload["turn_id"]))
                currentModel = context.model
                currentEffort = context.effort
                currentSpeed = context.speed

                continue
            }

            guard line.contains("\"type\":\"event_msg\""), line.contains("\"token_count\"") else {
                continue
            }

            guard let object = parseJSONLine(line) else {
                parseErrorCount += 1
                continue
            }

            guard object["type"] as? String == "event_msg" else {
                continue
            }

            guard let timestampString = object["timestamp"] as? String,
                  let timestamp = dateParsers.parse(timestampString) else {
                parseErrorCount += 1
                continue
            }

            if let windowStart, timestamp < windowStart {
                continue
            }

            guard let payload = object["payload"] as? [String: Any],
                  let payloadType = payload["type"] as? String,
                  payloadType == "token_count" else {
                parseErrorCount += 1
                continue
            }

            guard let info = payload["info"] as? [String: Any],
                  let lastUsage = info["last_token_usage"] as? [String: Any] else {
                continue
            }

            let usage = TokenUsage(
                inputTokens: int64(lastUsage["input_tokens"]),
                cachedInputTokens: int64(lastUsage["cached_input_tokens"]),
                outputTokens: int64(lastUsage["output_tokens"]),
                reasoningOutputTokens: int64(lastUsage["reasoning_output_tokens"]),
                totalTokens: int64(lastUsage["total_tokens"])
            )

            let rateLimits = payload["rate_limits"] as? [String: Any]
            let planType = nonEmptyString(rateLimits?["plan_type"]) ?? ""
            let modelContextWindow = int64OrNil(info["model_context_window"])
            addUsage(
                usage,
                timestamp: timestamp,
                planType: planType,
                modelContextWindow: modelContextWindow,
                to: &context
            )
        }

        if let request = finalizePendingRequest(&context) {
            requests.append(request)
        }

        return requests
    }

    private func parseJSONLine(_ line: Substring) -> [String: Any]? {
        parseJSONLine(String(line))
    }

    private func parseJSONLine(_ line: String) -> [String: Any]? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8), options: []),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private func extractThreadID(from fileURL: URL) -> String? {
        let name = fileURL.lastPathComponent as NSString
        let range = NSRange(location: 0, length: name.length)
        let matches = uuidRegex.matches(in: fileURL.lastPathComponent, range: range)
        guard let last = matches.last else {
            return nil
        }
        return name.substring(with: last.range).lowercased()
    }

    private func readDefaultSpeed() -> String {
        let configURL = homeURL.appendingPathComponent(".codex/config.toml")
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
            return "standard"
        }

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard line.hasPrefix("service_tier") else {
                continue
            }
            if line.contains("fast") || line.contains("priority") {
                return "fast"
            }
            if line.contains("flex") {
                return "flex"
            }
        }

        return "standard"
    }

    private struct ThreadRow: Decodable {
        let id: String
        let model: String?
        let reasoning_effort: String?
        let title: String?
        let first_user_message: String?
        let preview: String?
        let cwd: String?
        let updated_at_ms: Int64?
        let recency_at_ms: Int64?
    }

    private func loadThreadMetadata() -> [String: ThreadMeta] {
        let dbURL = homeURL.appendingPathComponent(".codex/state_5.sqlite")
        guard fileManager.fileExists(atPath: dbURL.path) else {
            return [:]
        }

        let process = Process()
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-spendbar-threads-\(UUID().uuidString).json")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        guard let outputHandle = FileHandle(forWritingAtPath: outputURL.path) else {
            return [:]
        }
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-json",
            dbURL.path,
            """
            select
              id,
              coalesce(model, '') as model,
              coalesce(reasoning_effort, '') as reasoning_effort,
              substr(replace(replace(coalesce(title, ''), char(10), ' '), char(9), ' '), 1, 120) as title,
              substr(replace(replace(coalesce(first_user_message, ''), char(10), ' '), char(9), ' '), 1, 120) as first_user_message,
              substr(replace(replace(coalesce(preview, ''), char(10), ' '), char(9), ' '), 1, 120) as preview,
              coalesce(cwd, '') as cwd
              , coalesce(recency_at_ms, updated_at_ms, created_at_ms, 0) as recency_at_ms
              , coalesce(updated_at_ms, created_at_ms, 0) as updated_at_ms
            from threads;
            """
        ]
        process.standardOutput = outputHandle
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return [:]
        }

        let timeout = Date().addingTimeInterval(2)
        while process.isRunning && Date() < timeout {
            Thread.sleep(forTimeInterval: 0.02)
        }

        if process.isRunning {
            process.terminate()
            return [:]
        }

        process.waitUntilExit()
        try? outputHandle.close()
        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: outputURL)
            return [:]
        }

        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        try? FileManager.default.removeItem(at: outputURL)
        guard let rows = try? JSONDecoder().decode([ThreadRow].self, from: data) else {
            return [:]
        }

        var result: [String: ThreadMeta] = [:]
        for row in rows {
            result[row.id.lowercased()] = ThreadMeta(
                model: row.model ?? "",
                effort: row.reasoning_effort ?? "",
                title: preferredThreadTitle(
                    title: row.title ?? "",
                    preview: row.preview ?? "",
                    firstUserMessage: row.first_user_message ?? "",
                    threadID: row.id
                ),
                cwd: row.cwd ?? "",
                lastActivityMS: max(row.recency_at_ms ?? 0, row.updated_at_ms ?? 0)
            )
        }
        return result
    }

    private func preferredThreadTitle(title: String, preview: String, firstUserMessage: String, threadID: String) -> String {
        func collapsed(_ value: String) -> String {
            value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func shortened(_ value: String) -> String {
            let trimmed = collapsed(value)
            if trimmed.count <= 80 {
                return trimmed
            }
            return String(trimmed.prefix(77)) + "..."
        }

        let candidates = [title, preview, firstUserMessage]
            .map(shortened)
            .filter { !$0.isEmpty }
            .filter { normalizedThreadTitle($0) }

        if let candidate = candidates.first {
            return candidate
        }

        return threadID
    }

    private func normalizedThreadTitle(_ title: String) -> Bool {
        let lower = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !lower.isEmpty && lower != "untitled" && lower != "untitled conversation" && lower != "untitled thread"
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func int64(_ value: Any?) -> Int64 {
        int64OrNil(value) ?? 0
    }

    private func int64OrNil(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber {
            return number.int64Value
        }
        if let string = value as? String {
            return Int64(string)
        }
        return nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store = CodexUsageStore()
    private let currencyStore = CurrencyStore()
    private let calculationStateStore = CalculationStateStore()
    private let preferencesStore = PreferencesStore()
    private let loginItemManager = LoginItemManager()
    private var refreshTimer: Timer?
    private var currentSnapshot = SpendSnapshot.empty()
    private var currencyState = CurrencyStore().load()
    private var preferences = PreferencesStore().load()
    private var preferencesController: PreferencesWindowController?
    private var isRefreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if #available(macOS 11.0, *) {
            statusItem.behavior = [.removalAllowed]
        }

        installObservers()
        renderSnapshot()
        refresh()
        refreshEURRateIfNeeded()

        refreshTimer = Timer.scheduledTimer(
            timeInterval: 5 * 60,
            target: self,
            selector: #selector(refresh),
            userInfo: nil,
            repeats: true
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func installObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refresh),
            name: .NSCalendarDayChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refresh),
            name: .NSSystemClockDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refresh),
            name: .NSSystemTimeZoneDidChange,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(refresh),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func refresh() {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else {
                return
            }

            let currentMonthAnchor = self.calculationStateStore.loadCurrentMonthAnchor()
            let snapshot = self.store.loadSnapshot(currentMonthAnchor: currentMonthAnchor)

            DispatchQueue.main.async {
                self.currentSnapshot = snapshot
                self.isRefreshing = false
                self.renderSnapshot()
            }
        }
    }

    private func renderSnapshot() {
        guard let button = statusItem.button else {
            return
        }

        let title = "Codex \(Formatters.money(currentSnapshot.today.cost.total, currency: currencyState))"
        let warning = preferences.dailyWarningUSD > 0 && currentSnapshot.today.cost.total >= preferences.dailyWarningUSD
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .foregroundColor: warning ? NSColor.systemRed : NSColor.labelColor
            ]
        )
        button.toolTip = "Today: \(Formatters.money(currentSnapshot.today.cost.total, currency: currencyState))\(estimateSuffix) · \(Formatters.tokens(currentSnapshot.today.usage.totalTokens)) tokens · \(currentSnapshot.today.requests) turns"
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        addCurrentMonthSection(to: menu)
        menu.addItem(.separator())
        addTodaySection(to: menu)
        menu.addItem(.separator())
        addTrendSection(to: menu)
        menu.addItem(.separator())
        addAllTimeSubmenu(to: menu)
        menu.addItem(.separator())
        addDaysSubmenu(to: menu)
        addMonthsSubmenu(to: menu)
        addModelSubmenu(to: menu)
        addProjectSubmenu(to: menu)
        addThreadSubmenu(to: menu)
        addRecentRequestsSubmenu(to: menu)
        addCurrencySubmenu(to: menu)
        addLoginItemSubmenu(to: menu)
        menu.addItem(.separator())

        let copyItem = NSMenuItem(title: "Copy Today's Summary", action: #selector(copySummary), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        let openSessionsItem = NSMenuItem(title: "Open Codex Sessions", action: #selector(openCodexSessions), keyEquivalent: "")
        openSessionsItem.target = self
        menu.addItem(openSessionsItem)

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())
        menu.addItem(staticItem("Scanned \(currentSnapshot.filesScanned) files · updated \(Formatters.shortTime.string(from: currentSnapshot.generatedAt))"))

        if currentSnapshot.parseErrorCount > 0 {
            menu.addItem(staticItem("Skipped \(currentSnapshot.parseErrorCount) malformed records"))
        }

        let quitItem = NSMenuItem(title: "Quit Codex Spend", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func addCurrentMonthSection(to menu: NSMenu) {
        let currentMonth = currentSnapshot.currentMonth
        let monthlyCreditBudgetCredits = preferences.monthlyCreditBudgetCredits
        let monthlyCreditBudgetUSD = monthlyCreditBudgetCredits * monthlyCreditDollarRatePerCredit
        let spentCredits = currentMonth.credits.total
        let remainingCredits = monthlyCreditBudgetCredits - spentCredits
        let overBudget = remainingCredits < 0

        menu.addItem(headerItem("Current Month"))
        menu.addItem(staticItem(
            "Period: \(Formatters.shortDay.string(from: currentSnapshot.currentMonthStart)) to now"
        ))
        menu.addItem(staticItem(
            "Spend: \(Formatters.credits(spentCredits)) credits · \(Formatters.money(currentMonth.cost.total, currency: currencyState))\(estimateSuffix)",
            warning: overBudget
        ))
        menu.addItem(importantItem(
            overBudget
                ? "Over budget by \(Formatters.credits(abs(remainingCredits))) credits"
                : "Remaining per Month: \(Formatters.credits(remainingCredits)) credits of \(Formatters.credits(monthlyCreditBudgetCredits))",
            warning: overBudget
        ))
        menu.addItem(staticItem(
            "Budget: \(Formatters.credits(monthlyCreditBudgetCredits)) credits · \(Formatters.money(monthlyCreditBudgetUSD, currency: currencyState))"
        ))
        menu.addItem(staticItem("Turns: \(currentMonth.requests) · Tokens: \(Formatters.tokens(currentMonth.usage.totalTokens))"))

        let clearCalculationsItem = NSMenuItem(
            title: "Clear Calculations and start from first of current month",
            action: #selector(clearMonthlyCalculations),
            keyEquivalent: ""
        )
        clearCalculationsItem.target = self
        menu.addItem(clearCalculationsItem)

        if currentMonth.unknownCreditPriceRequests > 0 {
            let unpricedItem = NSMenuItem(
                title: "\(currentMonth.unknownCreditPriceRequests) requests have no known credit price",
                action: nil,
                keyEquivalent: ""
            )
            let unpricedMenu = NSMenu()
            unpricedMenu.autoenablesItems = false
            for request in currentSnapshot.currentMonthUnpricedCreditRequests {
                let model = request.model.isEmpty ? "unknown model" : request.model
                let details = [
                    Formatters.shortTime.string(from: request.timestamp),
                    model,
                    request.title.isEmpty ? request.turnID : request.title
                ].joined(separator: " · ")
                unpricedMenu.addItem(staticItem(details, warning: true))
            }
            unpricedItem.submenu = unpricedMenu
            menu.addItem(unpricedItem)
        }

        if preferences.showEstimateLabels && currentMonth.unknownPriceRequests > 0 {
            menu.addItem(staticItem("\(currentMonth.unknownPriceRequests) requests have no known USD price"))
        }
    }

    private func addTodaySection(to menu: NSMenu) {
        let today = currentSnapshot.today
        menu.addItem(headerItem("Today"))
        menu.addItem(staticItem("Spend: \(Formatters.money(today.cost.total, currency: currencyState))\(estimateSuffix)", warning: isDailyWarning))
        menu.addItem(staticItem("Turns: \(today.requests) · Tokens: \(Formatters.tokens(today.usage.totalTokens))"))
        menu.addItem(staticItem("Input: \(Formatters.tokens(today.usage.uncachedInputTokens)) · \(Formatters.money(today.cost.uncachedInput, currency: currencyState))"))
        menu.addItem(staticItem("Cached input: \(Formatters.tokens(today.usage.cachedInputTokens)) · \(Formatters.money(today.cost.cachedInput, currency: currencyState))"))
        menu.addItem(staticItem("Output: \(Formatters.tokens(today.usage.visibleOutputTokens)) · \(Formatters.money(today.cost.visibleOutput, currency: currencyState))"))
        menu.addItem(staticItem("Reasoning: \(Formatters.tokens(today.usage.reasoningOutputTokens)) · \(Formatters.money(today.cost.reasoningOutput, currency: currencyState))"))

        if let spike = spikeMessage() {
            menu.addItem(staticItem(spike, warning: true))
        }

        if preferences.showEstimateLabels && today.unknownPriceRequests > 0 {
            menu.addItem(staticItem("\(today.unknownPriceRequests) requests have no known price"))
        }
    }

    private func addTrendSection(to menu: NSMenu) {
        let values = currentSnapshot.days.reversed().map { $0.aggregate.cost.total }
        let chart = TrendRenderer.render(values: values, mode: preferences.chartMode)
        menu.addItem(headerItem("Trend"))
        menu.addItem(staticItem("\(preferences.chartMode.rawValue): \(chart)"))

        let item = NSMenuItem(title: "Trend View", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for mode in TrendChartMode.allCases {
            let modeItem = NSMenuItem(title: mode.rawValue, action: #selector(selectTrendMode(_:)), keyEquivalent: "")
            modeItem.target = self
            modeItem.representedObject = mode.rawValue
            modeItem.state = preferences.chartMode == mode ? .on : .off
            submenu.addItem(modeItem)
        }
        item.submenu = submenu
        menu.addItem(item)
    }

    private func addAllTimeSubmenu(to menu: NSMenu) {
        let allTime = currentSnapshot.allTime
        let item = NSMenuItem(title: "All Time", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(staticItem("Spend: \(Formatters.money(allTime.cost.total, currency: currencyState))\(estimateSuffix)"))
        submenu.addItem(staticItem("Turns: \(allTime.requests) · Tokens: \(Formatters.tokens(allTime.usage.totalTokens))"))

        if let first = currentSnapshot.firstRequestAt, let last = currentSnapshot.lastRequestAt {
            submenu.addItem(staticItem("Range: \(Formatters.shortDay.string(from: first)) to \(Formatters.shortDay.string(from: last))"))
        }

        item.submenu = submenu
        menu.addItem(item)
    }

    private func addDaysSubmenu(to menu: NSMenu) {
        let item = NSMenuItem(title: "Recent Days", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let activeDays = currentSnapshot.days.filter { $0.aggregate.requests > 0 }

        if activeDays.isEmpty {
            submenu.addItem(staticItem("No recent usage"))
        } else {
            for day in activeDays {
                let aggregate = day.aggregate
                submenu.addItem(staticItem(
                    "\(Formatters.shortDay.string(from: day.date)): \(Formatters.money(aggregate.cost.total, currency: currencyState)) · \(Formatters.tokens(aggregate.usage.totalTokens)) · \(aggregate.requests) turns",
                    warning: preferences.dailyWarningUSD > 0 && aggregate.cost.total >= preferences.dailyWarningUSD
                ))
            }
        }

        item.submenu = submenu
        menu.addItem(item)
    }

    private func addMonthsSubmenu(to menu: NSMenu) {
        let item = NSMenuItem(title: "Monthly History", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let historicalMonths = currentSnapshot.months.filter { $0.monthStart != currentSnapshot.currentMonthStart }

        if historicalMonths.isEmpty {
            submenu.addItem(staticItem("No historical usage"))
        } else {
            for month in historicalMonths {
                let aggregate = month.aggregate
                submenu.addItem(staticItem(
                    "\(Formatters.month.string(from: month.monthStart)): \(Formatters.money(aggregate.cost.total, currency: currencyState)) · \(Formatters.tokens(aggregate.usage.totalTokens)) · \(aggregate.requests) turns"
                ))
            }
        }

        item.submenu = submenu
        menu.addItem(item)
    }

    private func addModelSubmenu(to menu: NSMenu) {
        let item = NSMenuItem(title: "By Model / Effort / Speed", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        if currentSnapshot.byModel.isEmpty {
            submenu.addItem(staticItem("No usage yet"))
        } else {
            for summary in currentSnapshot.byModel.prefix(16) {
                let aggregate = summary.aggregate
                submenu.addItem(staticItem(
                    "\(summary.key): \(Formatters.money(aggregate.cost.total, currency: currencyState)) · \(Formatters.tokens(aggregate.usage.totalTokens)) · \(aggregate.requests) turns"
                ))
            }
        }

        item.submenu = submenu
        menu.addItem(item)
    }

    private func addProjectSubmenu(to menu: NSMenu) {
        let item = NSMenuItem(title: "By Project Folder", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        if currentSnapshot.byProject.isEmpty {
            submenu.addItem(staticItem("No project metadata yet"))
        } else {
            for summary in currentSnapshot.byProject.prefix(16) {
                let aggregate = summary.aggregate
                submenu.addItem(staticItem(
                    "\(summary.project): \(Formatters.money(aggregate.cost.total, currency: currencyState)) · \(Formatters.tokens(aggregate.usage.totalTokens)) · \(aggregate.requests) turns"
                ))
            }
        }

        item.submenu = submenu
        menu.addItem(item)
    }

    private func addThreadSubmenu(to menu: NSMenu) {
        let item = NSMenuItem(title: "By Conversation", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        if currentSnapshot.byThread.isEmpty {
            submenu.addItem(staticItem("No conversation metadata yet"))
        } else {
            for summary in currentSnapshot.byThread.prefix(16) {
                let conversationItem = NSMenuItem(title: conversationTitle(summary), action: nil, keyEquivalent: "")
                let conversationMenu = NSMenu()
                conversationMenu.autoenablesItems = false
                let aggregate = summary.aggregate

                conversationMenu.addItem(staticItem("Spend: \(Formatters.money(aggregate.cost.total, currency: currencyState))\(estimateSuffix)"))
                conversationMenu.addItem(staticItem("Turns: \(aggregate.requests) · Tokens: \(Formatters.tokens(aggregate.usage.totalTokens))"))
                if !summary.cwd.isEmpty {
                    conversationMenu.addItem(staticItem("Folder: \(summary.cwd)"))
                }
                conversationMenu.addItem(staticItem("Thread ID: \(summary.threadID)"))

                if summary.breakdowns.isEmpty {
                    conversationMenu.addItem(staticItem("No model breakdown available"))
                } else {
                    conversationMenu.addItem(headerItem("Models / Effort / Speed"))
                    for breakdown in summary.breakdowns.prefix(12) {
                        conversationMenu.addItem(staticItem(
                            "\(breakdownLabel(breakdown)): \(Formatters.money(breakdown.aggregate.cost.total, currency: currencyState)) · \(Formatters.tokens(breakdown.aggregate.usage.totalTokens)) · \(breakdown.aggregate.requests) turns"
                        ))
                    }
                }

                conversationItem.submenu = conversationMenu
                submenu.addItem(conversationItem)
            }
        }

        item.submenu = submenu
        menu.addItem(item)
    }

    private func conversationTitle(_ summary: ThreadSummary) -> String {
        let title = summary.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            return summary.threadID
        }
        return title
    }

    private func breakdownLabel(_ summary: ThreadBreakdownSummary) -> String {
        let model = summary.model.isEmpty ? "unknown model" : summary.model
        let effort = summary.effort.isEmpty ? "unknown effort" : summary.effort
        let speed = summary.speed.isEmpty ? "standard" : summary.speed
        return "\(model) · \(effort) · \(speed)"
    }

    private func addRecentRequestsSubmenu(to menu: NSMenu) {
        let item = NSMenuItem(title: "Recent Prompt Turns", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        if currentSnapshot.recentRequests.isEmpty {
            submenu.addItem(staticItem("No usage yet"))
        } else {
            for request in currentSnapshot.recentRequests {
                let model = request.model.isEmpty ? "unknown" : request.model
                let effort = request.effort.isEmpty ? "effort?" : request.effort
                let speed = PricingTable.normalizedSpeed(request.speed)
                submenu.addItem(staticItem(
                    "\(Formatters.shortTime.string(from: request.timestamp)) \(model) \(effort) \(speed): \(Formatters.money(request.cost.total, currency: currencyState)) · \(Formatters.tokens(request.usage.totalTokens))",
                    warning: isRequestWarning(request)
                ))
            }
        }

        item.submenu = submenu
        menu.addItem(item)
    }

    private func addLoginItemSubmenu(to menu: NSMenu) {
        let status = loginItemManager.status()
        let item = NSMenuItem(title: "Start at Login", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(staticItem(status.isInstalled ? "Status: On" : "Status: Off"))
        if status.isInstalled && !status.matchesCurrentExecutable {
            submenu.addItem(staticItem("LaunchAgent points to another build", warning: true))
        }

        let toggleTitle = status.isInstalled ? "Disable Start at Login" : "Enable Start at Login"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleLoginItem), keyEquivalent: "")
        toggleItem.target = self
        submenu.addItem(toggleItem)

        item.submenu = submenu
        menu.addItem(item)
    }

    private func addCurrencySubmenu(to menu: NSMenu) {
        let item = NSMenuItem(title: "Currency", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let usdItem = NSMenuItem(title: "USD", action: #selector(selectUSD), keyEquivalent: "")
        usdItem.target = self
        usdItem.state = currencyState.code == .usd ? .on : .off
        submenu.addItem(usdItem)

        let eurItem = NSMenuItem(title: "EUR", action: #selector(selectEUR), keyEquivalent: "")
        eurItem.target = self
        eurItem.state = currencyState.code == .eur ? .on : .off
        submenu.addItem(eurItem)

        submenu.addItem(.separator())
        submenu.addItem(staticItem("1 USD = €\(String(format: "%.5f", currencyState.usdToEUR))"))
        submenu.addItem(staticItem("Rate date: \(currencyState.rateDate)"))

        let updateRateItem = NSMenuItem(title: "Update EUR Rate", action: #selector(updateEURRate), keyEquivalent: "")
        updateRateItem.target = self
        submenu.addItem(updateRateItem)

        item.submenu = submenu
        menu.addItem(item)
    }

    private func headerItem(_ title: String) -> NSMenuItem {
        let item = staticItem(title)
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor
            ]
        )
        return item
    }

    private func importantItem(_ title: String, warning: Bool = false) -> NSMenuItem {
        let item = staticItem(title, warning: warning)
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: warning ? NSColor.systemRed : NSColor.labelColor
            ]
        )
        return item
    }

    private func staticItem(_ title: String, warning: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(noop), keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        if warning {
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .foregroundColor: NSColor.systemRed,
                    .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
                ]
            )
        }
        return item
    }

    @objc private func noop() {}

    @objc private func clearMonthlyCalculations() {
        calculationStateStore.clearCurrentMonthAnchor()
        calculationStateStore.resetCurrentMonthAnchor()
        refresh()
    }

    private var estimateSuffix: String {
        preferences.showEstimateLabels ? " estimated" : ""
    }

    private var isDailyWarning: Bool {
        preferences.dailyWarningUSD > 0 && currentSnapshot.today.cost.total >= preferences.dailyWarningUSD
    }

    private func isRequestWarning(_ request: RequestUsage) -> Bool {
        preferences.requestWarningUSD > 0 && request.cost.total >= preferences.requestWarningUSD
    }

    private func spikeMessage() -> String? {
        let comparisonDays = currentSnapshot.days
            .dropFirst()
            .prefix(7)
            .filter { $0.aggregate.requests > 0 }

        guard !comparisonDays.isEmpty else {
            return nil
        }

        let average = comparisonDays.map { $0.aggregate.cost.total }.reduce(0, +) / Double(comparisonDays.count)
        guard average > 0 else {
            return nil
        }

        let ratio = currentSnapshot.today.cost.total / average
        guard ratio >= preferences.spikeMultiplier else {
            return nil
        }

        return "Spike: today is \(Formatters.ratio(ratio)) the recent active-day average"
    }

    @objc private func selectTrendMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = TrendChartMode(rawValue: rawValue) else {
            return
        }

        preferences.chartMode = mode
        preferencesStore.save(preferences)
        renderSnapshot()
    }

    @objc private func toggleLoginItem() {
        let shouldEnable = !loginItemManager.status().isInstalled
        loginItemManager.setEnabled(shouldEnable)
        renderSnapshot()
    }

    @objc private func openPreferences() {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController(
                currencyStore: currencyStore,
                preferencesStore: preferencesStore,
                loginItemManager: loginItemManager
            ) { [weak self] currency, preferences in
                guard let self else {
                    return
                }
                self.currencyState = currency
                self.preferences = preferences
                self.renderSnapshot()
                self.refreshEURRateIfNeeded()
            }
        }

        preferencesController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func selectUSD() {
        currencyState = currencyStore.setCurrency(.usd)
        renderSnapshot()
    }

    @objc private func selectEUR() {
        currencyState = currencyStore.setCurrency(.eur)
        renderSnapshot()
        refreshEURRateIfNeeded()
    }

    @objc private func updateEURRate() {
        refreshEURRateIfNeeded(force: true)
    }

    private func refreshEURRateIfNeeded(force: Bool = false) {
        currencyStore.refreshEURRateIfNeeded(force: force) { [weak self] state in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.currencyState = state
                self.renderSnapshot()
            }
        }
    }

    @objc private func copySummary() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentSnapshot.plainTextSummary(currency: currencyState), forType: .string)
    }

    @objc private func openCodexSessions() {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions")
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

final class PreferencesWindowController: NSWindowController {
    private let currencyStore: CurrencyStore
    private let preferencesStore: PreferencesStore
    private let loginItemManager: LoginItemManager
    private let onSave: (CurrencyState, AppPreferences) -> Void

    private let currencyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let chartPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let dailyWarningField = NSTextField(frame: .zero)
    private let requestWarningField = NSTextField(frame: .zero)
    private let spikeMultiplierField = NSTextField(frame: .zero)
    private let monthlyCreditBudgetField = NSTextField(frame: .zero)
    private let showEstimateLabelsCheckbox = NSButton(checkboxWithTitle: "Show estimate labels", target: nil, action: nil)
    private let startAtLoginCheckbox = NSButton(checkboxWithTitle: "Start at login", target: nil, action: nil)

    init(
        currencyStore: CurrencyStore,
        preferencesStore: PreferencesStore,
        loginItemManager: LoginItemManager,
        onSave: @escaping (CurrencyState, AppPreferences) -> Void
    ) {
        self.currencyStore = currencyStore
        self.preferencesStore = preferencesStore
        self.loginItemManager = loginItemManager
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Spend Preferences"
        window.center()

        super.init(window: window)
        buildContent()
        loadValues()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildContent() {
        guard let contentView = window?.contentView else {
            return
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20)
        ])

        currencyPopup.addItems(withTitles: CurrencyCode.allCases.map(\.rawValue))
        chartPopup.addItems(withTitles: TrendChartMode.allCases.map(\.rawValue))

        stack.addArrangedSubview(row("Currency", currencyPopup))
        stack.addArrangedSubview(row("Daily warning threshold (USD equivalent)", dailyWarningField))
        stack.addArrangedSubview(row("Per-request warning threshold (USD equivalent)", requestWarningField))
        stack.addArrangedSubview(row("Spike multiplier", spikeMultiplierField))
        stack.addArrangedSubview(row("Monthly credit budget", monthlyCreditBudgetField))
        stack.addArrangedSubview(row("Trend chart", chartPopup))
        stack.addArrangedSubview(showEstimateLabelsCheckbox)
        stack.addArrangedSubview(startAtLoginCheckbox)

        let privacyText = NSTextField(labelWithString: "Privacy: usage is read from local ~/.codex files. The only network call is the optional USD/EUR reference-rate refresh.")
        privacyText.lineBreakMode = .byWordWrapping
        privacyText.maximumNumberOfLines = 3
        privacyText.textColor = .secondaryLabelColor
        privacyText.translatesAutoresizingMaskIntoConstraints = false
        privacyText.widthAnchor.constraint(equalToConstant: 420).isActive = true
        stack.addArrangedSubview(privacyText)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.alignment = .centerY

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded

        buttonRow.addArrangedSubview(saveButton)
        buttonRow.addArrangedSubview(cancelButton)
        stack.addArrangedSubview(buttonRow)
    }

    private func row(_ label: String, _ control: NSView) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.alignment = .centerY

        let labelView = NSTextField(labelWithString: label)
        labelView.alignment = .right
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.widthAnchor.constraint(equalToConstant: 230).isActive = true

        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: 180).isActive = true

        stack.addArrangedSubview(labelView)
        stack.addArrangedSubview(control)
        return stack
    }

    private func loadValues() {
        let currency = currencyStore.load()
        let preferences = preferencesStore.load()

        currencyPopup.selectItem(withTitle: currency.code.rawValue)
        chartPopup.selectItem(withTitle: preferences.chartMode.rawValue)
        dailyWarningField.stringValue = String(format: "%.2f", preferences.dailyWarningUSD)
        requestWarningField.stringValue = String(format: "%.2f", preferences.requestWarningUSD)
        spikeMultiplierField.stringValue = String(format: "%.2f", preferences.spikeMultiplier)
        monthlyCreditBudgetField.stringValue = String(format: "%.0f", preferences.monthlyCreditBudgetCredits)
        showEstimateLabelsCheckbox.state = preferences.showEstimateLabels ? .on : .off
        startAtLoginCheckbox.state = loginItemManager.status().isInstalled ? .on : .off
    }

    @objc private func save() {
        let currencyCode = CurrencyCode(rawValue: currencyPopup.titleOfSelectedItem ?? "") ?? .usd
        let currency = currencyStore.setCurrency(currencyCode)
        let chartMode = TrendChartMode(rawValue: chartPopup.titleOfSelectedItem ?? "") ?? .blocks

        let preferences = AppPreferences(
            dailyWarningUSD: max(dailyWarningField.doubleValue, 0),
            requestWarningUSD: max(requestWarningField.doubleValue, 0),
            spikeMultiplier: max(spikeMultiplierField.doubleValue, 1),
            monthlyCreditBudgetCredits: max(monthlyCreditBudgetField.doubleValue, 0),
            chartMode: chartMode,
            showEstimateLabels: showEstimateLabelsCheckbox.state == .on
        )

        preferencesStore.save(preferences)
        loginItemManager.setEnabled(startAtLoginCheckbox.state == .on)
        onSave(currency, preferences)
        window?.close()
    }

    @objc private func cancel() {
        window?.close()
    }
}

if CommandLine.arguments.contains("--print-summary") {
    print(CodexUsageStore().loadSnapshot().plainTextSummary(currency: CurrencyStore().load()))
    exit(EXIT_SUCCESS)
}

if let bundleIdentifier = Bundle.main.bundleIdentifier {
    let currentPID = ProcessInfo.processInfo.processIdentifier
    let existingInstances = NSRunningApplication
        .runningApplications(withBundleIdentifier: bundleIdentifier)
        .filter { $0.processIdentifier != currentPID && !$0.isTerminated }

    if let existingInstance = existingInstances.first {
        existingInstance.activate(options: [])
        exit(EXIT_SUCCESS)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
