import Foundation
import Combine
import UserNotifications
import AppKit

enum DateFilter: String, CaseIterable {
    case today      = "Today"
    case sevenDays  = "7d"
    case thirtyDays = "30d"
    case all        = "All"
}

class MetricsStore: ObservableObject {
    @Published var stats: StatsCache?
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastRefresh: Date?
    @Published var dateFilter: DateFilter = .all
    @Published var alertThreshold: Double = UserDefaults.standard.double(forKey: "argusai.alertThreshold") {
        didSet { UserDefaults.standard.set(alertThreshold, forKey: "argusai.alertThreshold") }
    }

    private let projectsURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/projects")

    private var refreshTimer: Timer?
    private var lastParseDate: Date = .distantPast
    private var parsing = false
    private var initialLoadDone = false
    private let parseQueue = DispatchQueue(label: "com.claudemetrics.parse", qos: .userInitiated)

    private let db: ArgusDB? = {
        let dbURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/argusai.db")
        return try? ArgusDB(path: dbURL.path)
    }()

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        loadData()
        scheduleAutoRefresh()
    }

    deinit { refreshTimer?.invalidate() }

    private func scheduleAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkAndRefreshIfNeeded()
        }
    }

    private func checkAndRefreshIfNeeded() {
        let threshold = lastParseDate
        parseQueue.async { [weak self] in
            guard let self else { return }
            let changed = self.findJSONLFiles().contains { url in
                (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate).map { $0 > threshold } ?? false
            }
            if changed {
                DispatchQueue.main.async { self.loadData(silent: true) }
            }
        }
    }

    func loadData(silent: Bool = false) {
        guard !parsing else { return }
        parsing = true
        if !silent || !initialLoadDone { isLoading = true }
        error = nil
        let startTime = Date()
        parseQueue.async { [weak self] in
            guard let self else { return }
            do {
                let cache = try self.buildStatsFromDB()
                DispatchQueue.main.async {
                    self.stats = cache
                    self.isLoading = false
                    self.lastRefresh = Date()
                    self.lastParseDate = startTime
                    self.parsing = false
                    self.initialLoadDone = true
                    self.checkAlerts()
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error.localizedDescription
                    self.isLoading = false
                    self.parsing = false
                }
            }
        }
    }

    // MARK: - File discovery

    private func findJSONLFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: projectsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
    }

    // MARK: - DB-backed build

    private func buildStatsFromDB() throws -> StatsCache {
        guard let db = db else { throw NSError(domain: "ArgusDB", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database unavailable"]) }
        let files = findJSONLFiles().map { url in
            (url: url, isSubagent: url.pathComponents.contains("subagents"))
        }
        try db.ingestFiles(files)
        return try db.buildStatsCache()
    }

    // MARK: - LEGACY (unused — DB path is authoritative)
    /* keeping Accumulator + buildStatsFromJSONL below for reference only
    private struct Accumulator {
        // Token stats per model
        var modelTokens: [String: (input: Int, output: Int, cacheRead: Int, cacheCreate: Int, webSearch: Int)] = [:]
        // Daily activity
        var dailyMessages: [String: Int] = [:]
        var dailySessions: [String: Set<String>] = [:]
        var dailyToolCalls: [String: Int] = [:]
        // Per-day per-model full tokens — tuple: (input, output, cr, cc, ws)
        var dailyModelFull: [String: [String: (input: Int, output: Int, cr: Int, cc: Int, ws: Int)]] = [:]
        // Hour distribution
        var hourCounts: [Int: Int] = [:]
        // Session tracking
        var allSessions: Set<String> = []
        var sessionMsgCounts: [String: Int] = [:]
        var sessionOutputTokens: [String: Int] = [:]
        var sessionCwds: [String: String] = [:]
        // Project tracking: project → model → tokens
        var projectModelTokens: [String: [String: (input: Int, output: Int, cr: Int, cc: Int, ws: Int)]] = [:]
        var projectSessions: [String: Set<String>] = [:]
        var projectMessages: [String: Int] = [:]
        // Work hours per day
        var dailyWorkHours: [String: (first: Int, last: Int)] = [:]
        // Per-day hourly counts: day -> hour -> count
        var dailyHours: [String: [Int: Int]] = [:]
        // Per-day per-project data
        var dailyProjOutput:     [String: [String: Int]]    = [:]
        var dailyProjCost:       [String: [String: Double]] = [:]
        var dailyProjMessages:   [String: [String: Int]]    = [:]
        var dailyProjWebSearches:[String: [String: Int]]    = [:]
        // Subagent vs direct
        var subagentSessions: Set<String> = []
        var directSessions: Set<String> = []
        // Timestamps
        var firstDate: Date?
        var lastDay: String?
    }

    private func buildStatsFromJSONL() throws -> StatsCache {
        let files = findJSONLFiles()
        var acc = Accumulator()
        let cal = Calendar.current

        let isoFrac  = ISO8601DateFormatter(); isoFrac.formatOptions  = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter(); isoPlain.formatOptions = [.withInternetDateTime]
        func parseDate(_ s: String) -> Date? { isoFrac.date(from: s) ?? isoPlain.date(from: s) }

        for fileURL in files {
            let isSubagent = fileURL.pathComponents.contains("subagents")

            guard let data = try? Data(contentsOf: fileURL),
                  let text = String(data: data, encoding: .utf8) else { continue }

            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }

                let type      = obj["type"]      as? String ?? ""
                let sessionId = obj["sessionId"] as? String ?? ""
                let tsStr     = obj["timestamp"] as? String ?? ""
                let day       = tsStr.isEmpty ? nil : String(tsStr.prefix(10))

                // Record cwd for session (first occurrence wins)
                if acc.sessionCwds[sessionId] == nil, let cwd = obj["cwd"] as? String, !cwd.isEmpty {
                    acc.sessionCwds[sessionId] = cwd
                }

                if type == "assistant", let msg = obj["message"] as? [String: Any] {
                    let model  = msg["model"] as? String ?? "unknown"
                    let usage  = msg["usage"] as? [String: Any] ?? [:]
                    let input  = usage["input_tokens"]                as? Int ?? 0
                    let output = usage["output_tokens"]               as? Int ?? 0
                    let cr     = usage["cache_read_input_tokens"]     as? Int ?? 0
                    let cc     = usage["cache_creation_input_tokens"] as? Int ?? 0
                    let wsTool = usage["server_tool_use"]             as? [String: Any]
                    let ws     = wsTool?["web_search_requests"]       as? Int ?? 0

                    guard input + output + cr + cc > 0 else { continue }

                    // Model-level aggregates
                    var t = acc.modelTokens[model] ?? (0, 0, 0, 0, 0)
                    t.input += input; t.output += output
                    t.cacheRead += cr; t.cacheCreate += cc; t.webSearch += ws
                    acc.modelTokens[model] = t

                    if let d = day {
                        // Daily messages + sessions
                        acc.dailyMessages[d] = (acc.dailyMessages[d] ?? 0) + 1
                        if acc.dailySessions[d] == nil { acc.dailySessions[d] = [] }
                        acc.dailySessions[d]!.insert(sessionId)
                        // Daily model full tokens
                        if acc.dailyModelFull[d] == nil { acc.dailyModelFull[d] = [:] }
                        var dm = acc.dailyModelFull[d]![model] ?? (0, 0, 0, 0, 0)
                        dm.0 += input; dm.1 += output; dm.2 += cr; dm.3 += cc; dm.4 += ws
                        acc.dailyModelFull[d]![model] = dm
                        if acc.lastDay == nil || d > acc.lastDay! { acc.lastDay = d }
                    }

                    if let date = parseDate(tsStr) {
                        let h = cal.component(.hour, from: date)
                        acc.hourCounts[h] = (acc.hourCounts[h] ?? 0) + 1
                        if acc.firstDate == nil || date < acc.firstDate! { acc.firstDate = date }
                        if let d = day {
                            if let existing = acc.dailyWorkHours[d] {
                                acc.dailyWorkHours[d] = (first: min(existing.first, h), last: max(existing.last, h))
                            } else {
                                acc.dailyWorkHours[d] = (first: h, last: h)
                            }
                            if acc.dailyHours[d] == nil { acc.dailyHours[d] = [:] }
                            acc.dailyHours[d]![h] = (acc.dailyHours[d]![h] ?? 0) + 1
                        }
                    }

                    // Session aggregates
                    acc.allSessions.insert(sessionId)
                    acc.sessionMsgCounts[sessionId]    = (acc.sessionMsgCounts[sessionId] ?? 0) + 1
                    acc.sessionOutputTokens[sessionId] = (acc.sessionOutputTokens[sessionId] ?? 0) + output
                    if isSubagent { acc.subagentSessions.insert(sessionId) }
                    else          { acc.directSessions.insert(sessionId) }

                    // Project aggregates
                    let proj = projectName(cwd: acc.sessionCwds[sessionId], fileURL: fileURL)
                    if acc.projectModelTokens[proj] == nil { acc.projectModelTokens[proj] = [:] }
                    var pm = acc.projectModelTokens[proj]![model] ?? (0, 0, 0, 0, 0)
                    pm.0 += input; pm.1 += output; pm.2 += cr; pm.3 += cc; pm.4 += ws
                    acc.projectModelTokens[proj]![model] = pm
                    if acc.projectSessions[proj] == nil { acc.projectSessions[proj] = [] }
                    acc.projectSessions[proj]!.insert(sessionId)
                    acc.projectMessages[proj] = (acc.projectMessages[proj] ?? 0) + 1

                    // Daily project data
                    if let d = day {
                        let msgCost = ModelPricingTable.price(for: model).cost(input: input, output: output, cr: cr, cc: cc)
                        if acc.dailyProjOutput[d]      == nil { acc.dailyProjOutput[d]      = [:] }
                        if acc.dailyProjCost[d]        == nil { acc.dailyProjCost[d]        = [:] }
                        if acc.dailyProjMessages[d]    == nil { acc.dailyProjMessages[d]    = [:] }
                        if acc.dailyProjWebSearches[d] == nil { acc.dailyProjWebSearches[d] = [:] }
                        acc.dailyProjOutput[d]![proj]      = (acc.dailyProjOutput[d]![proj]      ?? 0) + output
                        acc.dailyProjCost[d]![proj]        = (acc.dailyProjCost[d]![proj]        ?? 0) + msgCost
                        acc.dailyProjMessages[d]![proj]    = (acc.dailyProjMessages[d]![proj]    ?? 0) + 1
                        acc.dailyProjWebSearches[d]![proj] = (acc.dailyProjWebSearches[d]![proj] ?? 0) + ws
                    }
                }

                if type == "user", let msg = obj["message"] as? [String: Any], let d = day {
                    if let arr = msg["content"] as? [[String: Any]] {
                        let toolCount = arr.filter { $0["type"] as? String == "tool_result" }.count
                        if toolCount > 0 {
                            acc.dailyToolCalls[d] = (acc.dailyToolCalls[d] ?? 0) + toolCount
                        }
                    }
                }
            }
        }

        // MARK: Build StatsCache

        let modelUsage: [String: ModelTokenStats] = acc.modelTokens.mapValues {
            ModelTokenStats(inputTokens: $0.input, outputTokens: $0.output,
                            cacheReadInputTokens: $0.cacheRead, cacheCreationInputTokens: $0.cacheCreate,
                            webSearchRequests: $0.webSearch, costUSD: nil)
        }

        let allDays = Set(acc.dailyMessages.keys).union(acc.dailySessions.keys).union(acc.dailyToolCalls.keys)
        let dailyActivity: [DailyActivity] = allDays.map { d in
            DailyActivity(date: d,
                          messageCount: acc.dailyMessages[d] ?? 0,
                          sessionCount: acc.dailySessions[d]?.count ?? 0,
                          toolCallCount: acc.dailyToolCalls[d] ?? 0)
        }.sorted { $0.date < $1.date }

        let dailyModelTokens: [DailyModelTokens] = acc.dailyModelFull.map { d, modelMap in
            DailyModelTokens(date: d, tokensByModel: modelMap.mapValues { $0.1 })
        }.sorted { $0.date < $1.date }

        let hourCounts = Dictionary(uniqueKeysWithValues: acc.hourCounts.map { ("\($0.key)", $0.value) })

        let longestSession: LongestSessionInfo? = acc.sessionMsgCounts
            .max(by: { $0.value < $1.value })
            .map { LongestSessionInfo(sessionId: $0.key, duration: nil, messageCount: $0.value, timestamp: nil) }

        let firstDateStr: String? = acc.firstDate.map {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.string(from: $0)
        }

        // Daily costs + full daily token totals (enables date-filtered KPIs)
        let dailyCosts: [String: Double] = acc.dailyModelFull.mapValues { modelMap in
            modelMap.reduce(0.0) { cost, pair in
                cost + ModelPricingTable.price(for: pair.key).cost(
                    input: pair.value.0, output: pair.value.1, cr: pair.value.2, cc: pair.value.3)
            }
        }

        let dailyTotals: [DailyTokenTotals] = acc.dailyModelFull.map { d, modelMap in
            let totInput  = modelMap.values.reduce(0) { $0 + $1.0 }
            let totOutput = modelMap.values.reduce(0) { $0 + $1.1 }
            let totCR     = modelMap.values.reduce(0) { $0 + $1.2 }
            let totCC     = modelMap.values.reduce(0) { $0 + $1.3 }
            let totWS     = modelMap.values.reduce(0) { $0 + $1.4 }
            let cost    = dailyCosts[d] ?? 0
            let savings = modelMap.reduce(0.0) { s, pair in
                let price = ModelPricingTable.price(for: pair.key)
                let cr = Double(pair.value.2)
                return s + max(0, cr * (price.inputPerMTok - price.cacheReadPerMTok) / 1_000_000)
            }
            return DailyTokenTotals(date: d, inputTokens: totInput, outputTokens: totOutput,
                                    cacheReadTokens: totCR, cacheCreateTokens: totCC,
                                    webSearchCount: totWS, estimatedCostUSD: cost, cacheSavingsUSD: savings)
        }.sorted { $0.date < $1.date }

        // Project stats
        let projectStats: [ProjectStats] = acc.projectModelTokens.map { proj, modelMap in
            let totInput  = modelMap.values.reduce(0) { $0 + $1.0 }
            let totOutput = modelMap.values.reduce(0) { $0 + $1.1 }
            let totCR     = modelMap.values.reduce(0) { $0 + $1.2 }
            let totCC     = modelMap.values.reduce(0) { $0 + $1.3 }
            let totWS     = modelMap.values.reduce(0) { $0 + $1.4 }
            let cost = modelMap.reduce(0.0) { c, pair in
                c + ModelPricingTable.price(for: pair.key).cost(
                    input: pair.value.0, output: pair.value.1, cr: pair.value.2, cc: pair.value.3)
            }
            return ProjectStats(project: proj,
                                inputTokens: totInput, outputTokens: totOutput,
                                cacheReadInputTokens: totCR, cacheCreationInputTokens: totCC,
                                webSearchRequests: totWS,
                                sessionCount: acc.projectSessions[proj]?.count ?? 0,
                                messageCount: acc.projectMessages[proj] ?? 0,
                                estimatedCostUSD: cost)
        }.sorted { $0.estimatedCostUSD > $1.estimatedCostUSD }

        // Daily work hours
        let dailyWorkHours: [DailyWorkHours] = acc.dailyWorkHours.map { d, range in
            DailyWorkHours(date: d, firstHour: range.first, lastHour: range.last)
        }.sorted { $0.date < $1.date }

        // Avg output tokens per session
        let avgOut = acc.allSessions.isEmpty ? 0 :
            acc.sessionOutputTokens.values.reduce(0, +) / acc.allSessions.count

        let totalMessages = dailyActivity.reduce(0) { $0 + $1.messageCount }

        // Daily model breakdown (for filtered model KPIs)
        let dailyModelBreakdown: [DailyModelBreakdown] = acc.dailyModelFull.map { d, modelMap in
            let modelTokens = modelMap.mapValues { t in
                ModelTokenStats(inputTokens: t.0, outputTokens: t.1,
                                cacheReadInputTokens: t.2, cacheCreationInputTokens: t.3,
                                webSearchRequests: t.4, costUSD: nil)
            }
            return DailyModelBreakdown(date: d, modelTokens: modelTokens)
        }.sorted { $0.date < $1.date }

        // Daily hour counts (for filtered schedule KPIs)
        let dailyHourCounts: [String: [String: Int]] = acc.dailyHours.mapValues { hourMap in
            Dictionary(uniqueKeysWithValues: hourMap.map { ("\($0.key)", $0.value) })
        }

        // Daily project costs (for filtered project KPIs)
        let dailyProjectCosts: [DailyProjectCosts] = acc.dailyProjCost.keys.map { d in
            DailyProjectCosts(
                date: d,
                costs:       acc.dailyProjCost[d]        ?? [:],
                outputs:     acc.dailyProjOutput[d]       ?? [:],
                messages:    acc.dailyProjMessages[d]     ?? [:],
                webSearches: acc.dailyProjWebSearches[d]  ?? [:]
            )
        }.sorted { $0.date < $1.date }

        return StatsCache(
            version: nil,
            lastComputedDate: acc.lastDay,
            dailyActivity: dailyActivity,
            dailyModelTokens: dailyModelTokens,
            modelUsage: modelUsage.isEmpty ? nil : modelUsage,
            totalSessions: acc.allSessions.count,
            totalMessages: totalMessages,
            longestSession: longestSession,
            firstSessionDate: firstDateStr,
            hourCounts: hourCounts.isEmpty ? nil : hourCounts,
            totalSpeculationTimeSavedMs: nil,
            dailyCosts: dailyCosts.isEmpty ? nil : dailyCosts,
            projectStats: projectStats.isEmpty ? nil : projectStats,
            dailyWorkHours: dailyWorkHours.isEmpty ? nil : dailyWorkHours,
            subagentSessionCount: acc.subagentSessions.count,
            directSessionCount: acc.directSessions.count,
            avgOutputTokensPerSession: avgOut,
            dailyTotals: dailyTotals.isEmpty ? nil : dailyTotals,
            dailyModelBreakdown: dailyModelBreakdown.isEmpty ? nil : dailyModelBreakdown,
            dailyHourCounts: dailyHourCounts.isEmpty ? nil : dailyHourCounts,
            dailyProjectCosts: dailyProjectCosts.isEmpty ? nil : dailyProjectCosts
        )
    }
    */

    // MARK: - Computed properties

    var totalEstimatedCost: Double {
        (stats?.modelUsage ?? [:]).reduce(0) { sum, pair in
            sum + ModelPricingTable.price(for: pair.key).cost(for: pair.value)
        }
    }
    var totalOutputTokens: Int  { stats?.modelUsage?.values.reduce(0) { $0 + $1.outputTokens } ?? 0 }
    var totalInputTokens:  Int  { stats?.modelUsage?.values.reduce(0) { $0 + $1.inputTokens  } ?? 0 }
    var totalCacheTokens:  Int  {
        stats?.modelUsage?.values.reduce(0) { $0 + $1.cacheReadInputTokens + $1.cacheCreationInputTokens } ?? 0
    }

    var sortedModels: [(model: String, stats: ModelTokenStats)] {
        (stats?.modelUsage ?? [:]).map { (model: $0.key, stats: $0.value) }
            .sorted { $0.stats.outputTokens > $1.stats.outputTokens }
    }

    var recentActivity: [DailyActivity] {
        (stats?.dailyActivity ?? []).sorted { $0.date < $1.date }
    }

    var filteredActivity: [DailyActivity] {
        switch dateFilter {
        case .all: return recentActivity
        case .today:
            let start = Calendar.current.startOfDay(for: Date())
            return recentActivity.filter { $0.dateValue >= start }
        case .sevenDays:
            let cut = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            return recentActivity.filter { $0.dateValue >= cut }
        case .thirtyDays:
            let cut = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            return recentActivity.filter { $0.dateValue >= cut }
        }
    }

    var filteredTotalMessages: Int {
        dateFilter == .all ? (stats?.totalMessages ?? 0)
                           : filteredActivity.reduce(0) { $0 + $1.messageCount }
    }
    var filteredTotalSessions: Int {
        dateFilter == .all ? (stats?.totalSessions ?? 0)
                           : filteredActivity.reduce(0) { $0 + $1.sessionCount }
    }

    var hourlyData: [(hour: Int, count: Int)] {
        let counts = stats?.hourCounts ?? [:]
        return (0..<24).map { h in (hour: h, count: counts["\(h)"] ?? 0) }
    }

    var modelCosts: [(model: String, cost: Double)] {
        (stats?.modelUsage ?? [:])
            .map { (model: $0.key, cost: ModelPricingTable.price(for: $0.key).cost(for: $0.value)) }
            .sorted { $0.cost > $1.cost }
    }

    var peakHour: Int? {
        hourlyData.max(by: { $0.count < $1.count }).flatMap { $0.count > 0 ? $0.hour : nil }
    }

    // Cache
    var cacheHitRate: Double {
        let read  = stats?.modelUsage?.values.reduce(0) { $0 + $1.cacheReadInputTokens  } ?? 0
        let write = stats?.modelUsage?.values.reduce(0) { $0 + $1.cacheCreationInputTokens } ?? 0
        let total = read + write
        guard total > 0 else { return 0 }
        return Double(read) / Double(total)
    }

    var cacheSavingsUSD: Double {
        (stats?.modelUsage ?? [:]).reduce(0.0) { sum, pair in
            let price = ModelPricingTable.price(for: pair.key)
            let cr = Double(pair.value.cacheReadInputTokens)
            return sum + max(0, cr * (price.inputPerMTok - price.cacheReadPerMTok) / 1_000_000)
        }
    }

    // Streak
    var currentStreak: Int {
        let days = Set(recentActivity.map(\.date))
        let cal  = Calendar.current
        let fmt  = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        var date = Date()
        if !days.contains(fmt.string(from: date)) {
            date = cal.date(byAdding: .day, value: -1, to: date)!
        }
        var streak = 0
        while days.contains(fmt.string(from: date)) {
            streak += 1
            date = cal.date(byAdding: .day, value: -1, to: date)!
        }
        return streak
    }

    var totalWebSearches: Int {
        stats?.modelUsage?.values.reduce(0) { $0 + ($1.webSearchRequests ?? 0) } ?? 0
    }

    // MARK: - Date-filtered aggregates

    private var filteredDailyTotals: [DailyTokenTotals] {
        let all = stats?.dailyTotals ?? []
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        switch dateFilter {
        case .all: return all
        case .today:
            let start = Calendar.current.startOfDay(for: Date())
            return all.filter { (fmt.date(from: $0.date) ?? .distantPast) >= start }
        case .sevenDays:
            let cut = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            return all.filter { (fmt.date(from: $0.date) ?? .distantPast) >= cut }
        case .thirtyDays:
            let cut = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            return all.filter { (fmt.date(from: $0.date) ?? .distantPast) >= cut }
        }
    }

    var filteredTotalCost:    Double { filteredDailyTotals.reduce(0) { $0 + $1.estimatedCostUSD } }
    var filteredOutputTokens: Int    { filteredDailyTotals.reduce(0) { $0 + $1.outputTokens } }
    var filteredInputTokens:  Int    { filteredDailyTotals.reduce(0) { $0 + $1.inputTokens } }
    var filteredCacheTokens:  Int    { filteredDailyTotals.reduce(0) { $0 + $1.cacheReadTokens + $1.cacheCreateTokens } }
    var filteredWebSearches:  Int    { filteredDailyTotals.reduce(0) { $0 + $1.webSearchCount } }
    var filteredCacheSavings: Double { filteredDailyTotals.reduce(0) { $0 + $1.cacheSavingsUSD } }

    var filteredCacheHitRate: Double {
        let read  = filteredDailyTotals.reduce(0) { $0 + $1.cacheReadTokens }
        let write = filteredDailyTotals.reduce(0) { $0 + $1.cacheCreateTokens }
        let total = read + write
        guard total > 0 else { return 0 }
        return Double(read) / Double(total)
    }

    var filteredDailyCostData: [(date: String, cost: Double)] {
        filteredDailyTotals.map { (date: $0.date, cost: $0.estimatedCostUSD) }
    }

    // MARK: - Filtered model stats

    private var filteredModelBreakdownDays: [DailyModelBreakdown] {
        let all = stats?.dailyModelBreakdown ?? []
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        switch dateFilter {
        case .all: return all
        case .today:
            let start = Calendar.current.startOfDay(for: Date())
            return all.filter { (fmt.date(from: $0.date) ?? .distantPast) >= start }
        case .sevenDays:
            let cut = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            return all.filter { (fmt.date(from: $0.date) ?? .distantPast) >= cut }
        case .thirtyDays:
            let cut = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            return all.filter { (fmt.date(from: $0.date) ?? .distantPast) >= cut }
        }
    }

    var filteredModelUsage: [String: ModelTokenStats] {
        var merged: [String: (Int, Int, Int, Int, Int)] = [:]
        for day in filteredModelBreakdownDays {
            for (model, s) in day.modelTokens {
                var t = merged[model] ?? (0, 0, 0, 0, 0)
                t.0 += s.inputTokens; t.1 += s.outputTokens
                t.2 += s.cacheReadInputTokens; t.3 += s.cacheCreationInputTokens
                t.4 += s.webSearchRequests ?? 0
                merged[model] = t
            }
        }
        return merged.mapValues { t in
            ModelTokenStats(inputTokens: t.0, outputTokens: t.1,
                            cacheReadInputTokens: t.2, cacheCreationInputTokens: t.3,
                            webSearchRequests: t.4, costUSD: nil)
        }
    }

    var filteredSortedModels: [(model: String, stats: ModelTokenStats)] {
        filteredModelUsage.map { (model: $0.key, stats: $0.value) }
            .sorted { $0.stats.outputTokens > $1.stats.outputTokens }
    }

    var filteredModelCosts: [(model: String, cost: Double)] {
        filteredModelUsage
            .map { (model: $0.key, cost: ModelPricingTable.price(for: $0.key).cost(for: $0.value)) }
            .sorted { $0.cost > $1.cost }
    }

    // MARK: - Filtered hourly data

    private var filteredDailyHourCounts: [String: [String: Int]] {
        let all = stats?.dailyHourCounts ?? [:]
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        switch dateFilter {
        case .all: return all
        case .today:
            let start = Calendar.current.startOfDay(for: Date())
            return all.filter { (fmt.date(from: $0.key) ?? .distantPast) >= start }
        case .sevenDays:
            let cut = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            return all.filter { (fmt.date(from: $0.key) ?? .distantPast) >= cut }
        case .thirtyDays:
            let cut = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            return all.filter { (fmt.date(from: $0.key) ?? .distantPast) >= cut }
        }
    }

    var filteredHourlyData: [(hour: Int, count: Int)] {
        var counts = [Int: Int]()
        for (_, hourMap) in filteredDailyHourCounts {
            for (hStr, c) in hourMap {
                if let h = Int(hStr) { counts[h] = (counts[h] ?? 0) + c }
            }
        }
        return (0..<24).map { h in (hour: h, count: counts[h] ?? 0) }
    }

    var filteredPeakHour: Int? {
        filteredHourlyData.max(by: { $0.count < $1.count }).flatMap { $0.count > 0 ? $0.hour : nil }
    }

    // MARK: - Filtered project stats

    private var filteredDailyProjCosts: [DailyProjectCosts] {
        let all = stats?.dailyProjectCosts ?? []
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        switch dateFilter {
        case .all: return all
        case .today:
            let start = Calendar.current.startOfDay(for: Date())
            return all.filter { (fmt.date(from: $0.date) ?? .distantPast) >= start }
        case .sevenDays:
            let cut = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            return all.filter { (fmt.date(from: $0.date) ?? .distantPast) >= cut }
        case .thirtyDays:
            let cut = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            return all.filter { (fmt.date(from: $0.date) ?? .distantPast) >= cut }
        }
    }

    var filteredSortedProjects: [ProjectStats] {
        var costs:    [String: Double] = [:]
        var outputs:  [String: Int]    = [:]
        var messages: [String: Int]    = [:]
        var webSearches: [String: Int] = [:]
        for day in filteredDailyProjCosts {
            for (proj, v) in day.costs       { costs[proj]       = (costs[proj]       ?? 0) + v }
            for (proj, v) in day.outputs     { outputs[proj]     = (outputs[proj]     ?? 0) + v }
            for (proj, v) in day.messages    { messages[proj]    = (messages[proj]    ?? 0) + v }
            for (proj, v) in day.webSearches { webSearches[proj] = (webSearches[proj] ?? 0) + v }
        }
        return costs.keys.map { proj in
            ProjectStats(project: proj,
                         inputTokens: 0, outputTokens: outputs[proj] ?? 0,
                         cacheReadInputTokens: 0, cacheCreationInputTokens: 0,
                         webSearchRequests: webSearches[proj] ?? 0,
                         sessionCount: 0,
                         messageCount: messages[proj] ?? 0,
                         estimatedCostUSD: costs[proj] ?? 0)
        }.sorted { $0.estimatedCostUSD > $1.estimatedCostUSD }
    }

    // Daily costs (all-time, for all-time charts in Models tab)
    var dailyCostData: [(date: String, cost: Double)] {
        (stats?.dailyCosts ?? [:]).map { (date: $0.key, cost: $0.value) }.sorted { $0.date < $1.date }
    }

    // Projects (all-time)
    var sortedProjects: [ProjectStats] { stats?.projectStats ?? [] }

    // Day of week — uses filteredActivity so it responds to the filter
    var dayOfWeekData: [(day: String, count: Int)] {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        var counts = [Int: Int]()
        for a in filteredActivity {
            guard let d = fmt.date(from: a.date) else { continue }
            let dow = cal.component(.weekday, from: d)
            counts[dow] = (counts[dow] ?? 0) + a.messageCount
        }
        // Mon=2..Sun=1, display Mon-Sun
        let order = [2, 3, 4, 5, 6, 7, 1]
        let names = [2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat", 1: "Sun"]
        return order.map { (day: names[$0]!, count: counts[$0] ?? 0) }
    }

    // Work hours
    var workHoursData: [DailyWorkHours] {
        let all = stats?.dailyWorkHours?.sorted { $0.date < $1.date } ?? []
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        switch dateFilter {
        case .all: return all
        case .today:
            let start = Calendar.current.startOfDay(for: Date())
            return all.filter { (fmt.date(from: $0.date) ?? .distantPast) >= start }
        case .sevenDays:
            let cut = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            return all.filter { (fmt.date(from: $0.date) ?? .distantPast) >= cut }
        case .thirtyDays:
            let cut = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            return all.filter { (fmt.date(from: $0.date) ?? .distantPast) >= cut }
        }
    }

    var avgStartHour: Double? {
        let h = workHoursData.map { Double($0.firstHour) }
        return h.isEmpty ? nil : h.reduce(0, +) / Double(h.count)
    }
    var avgEndHour: Double? {
        let h = workHoursData.map { Double($0.lastHour) }
        return h.isEmpty ? nil : h.reduce(0, +) / Double(h.count)
    }

    var avgOutputTokensPerSession: Int { stats?.avgOutputTokensPerSession ?? 0 }
    var subagentSessionCount:      Int { stats?.subagentSessionCount ?? 0 }
    var directSessionCount:        Int { stats?.directSessionCount  ?? 0 }

    // MARK: - Sessions

    var filteredSessions: [SessionSummary] {
        let all = stats?.sessions ?? []
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        switch dateFilter {
        case .all: return all
        case .today:
            let start = Calendar.current.startOfDay(for: Date())
            return all.filter { (fmt.date(from: $0.firstDay) ?? .distantPast) >= start }
        case .sevenDays:
            let cut = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            return all.filter { (fmt.date(from: $0.firstDay) ?? .distantPast) >= cut }
        case .thirtyDays:
            let cut = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            return all.filter { (fmt.date(from: $0.firstDay) ?? .distantPast) >= cut }
        }
    }

    // MARK: - Menu bar

    var menuBarLabel: String {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let todayCost = (stats?.dailyTotals ?? [])
            .filter { (fmt.date(from: $0.date) ?? .distantPast) >= todayStart }
            .reduce(0.0) { $0 + $1.estimatedCostUSD }
        if todayCost == 0 && stats == nil { return "$-.--" }
        return formatCost(todayCost)
    }

    // MARK: - Burn rate / forecast

    var burnRatePerDay: Double {
        let last7 = (stats?.dailyTotals ?? []).suffix(7)
        guard !last7.isEmpty else { return 0 }
        return last7.reduce(0.0) { $0 + $1.estimatedCostUSD } / Double(last7.count)
    }

    var currentMonthCost: Double {
        let cal = Calendar.current
        let now = Date()
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return (stats?.dailyTotals ?? []).filter { day in
            guard let d = fmt.date(from: day.date) else { return false }
            return cal.isDate(d, equalTo: now, toGranularity: .month)
        }.reduce(0.0) { $0 + $1.estimatedCostUSD }
    }

    var daysLeftInMonth: Int {
        let cal = Calendar.current
        let now = Date()
        let range = cal.range(of: .day, in: .month, for: now)!
        let today = cal.component(.day, from: now)
        return range.count - today
    }

    var projectedMonthCost: Double {
        currentMonthCost + burnRatePerDay * Double(daysLeftInMonth)
    }

    // MARK: - Week-over-week comparison

    private var previousPeriodDailyTotals: [DailyTokenTotals] {
        let all = stats?.dailyTotals ?? []
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let now = Date()
        switch dateFilter {
        case .all: return []
        case .today:
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
            let yStart = Calendar.current.startOfDay(for: yesterday)
            let yEnd   = Calendar.current.startOfDay(for: now)
            return all.filter {
                let d = fmt.date(from: $0.date) ?? .distantPast
                return d >= yStart && d < yEnd
            }
        case .sevenDays:
            let w2start = Calendar.current.date(byAdding: .day, value: -14, to: now)!
            let w2end   = Calendar.current.date(byAdding: .day, value: -7,  to: now)!
            return all.filter {
                let d = fmt.date(from: $0.date) ?? .distantPast
                return d >= w2start && d < w2end
            }
        case .thirtyDays:
            let m2start = Calendar.current.date(byAdding: .day, value: -60, to: now)!
            let m2end   = Calendar.current.date(byAdding: .day, value: -30, to: now)!
            return all.filter {
                let d = fmt.date(from: $0.date) ?? .distantPast
                return d >= m2start && d < m2end
            }
        }
    }

    var previousPeriodCost: Double { previousPeriodDailyTotals.reduce(0) { $0 + $1.estimatedCostUSD } }

    var costDeltaPct: Double? {
        let prev = previousPeriodCost
        guard prev > 0 else { return nil }
        return (filteredTotalCost - prev) / prev
    }

    var previousPeriodMessages: Int {
        // Use filteredActivity pattern shifted by period
        let all = stats?.dailyActivity ?? []
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let now = Date()
        let filtered: [DailyActivity]
        switch dateFilter {
        case .all: return 0
        case .today:
            let yStart = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -1, to: now)!)
            let yEnd   = Calendar.current.startOfDay(for: now)
            filtered = all.filter {
                let d = fmt.date(from: $0.date) ?? .distantPast
                return d >= yStart && d < yEnd
            }
        case .sevenDays:
            let w2start = Calendar.current.date(byAdding: .day, value: -14, to: now)!
            let w2end   = Calendar.current.date(byAdding: .day, value: -7,  to: now)!
            filtered = all.filter {
                let d = fmt.date(from: $0.date) ?? .distantPast
                return d >= w2start && d < w2end
            }
        case .thirtyDays:
            let m2start = Calendar.current.date(byAdding: .day, value: -60, to: now)!
            let m2end   = Calendar.current.date(byAdding: .day, value: -30, to: now)!
            filtered = all.filter {
                let d = fmt.date(from: $0.date) ?? .distantPast
                return d >= m2start && d < m2end
            }
        }
        return filtered.reduce(0) { $0 + $1.messageCount }
    }

    var messagesDeltaPct: Double? {
        let prev = Double(previousPeriodMessages)
        guard prev > 0 else { return nil }
        return (Double(filteredTotalMessages) - prev) / prev
    }

    // MARK: - Subagent analytics

    var filteredSubagentCost: Double {
        filteredSessions.filter { $0.isSubagent }.reduce(0) { $0 + $1.costUSD }
    }

    var filteredDirectCost: Double {
        filteredSessions.filter { !$0.isSubagent }.reduce(0) { $0 + $1.costUSD }
    }

    // MARK: - Alerts

    private func checkAlerts() {
        let threshold = alertThreshold
        guard threshold > 0 else { return }
        let todayCost = filteredTotalCostToday
        guard todayCost >= threshold else { return }

        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let todayStr = fmt.string(from: Date())
        let lastAlertDay = UserDefaults.standard.string(forKey: "argusai.lastAlertDay") ?? ""
        guard lastAlertDay != todayStr else { return }

        UserDefaults.standard.set(todayStr, forKey: "argusai.lastAlertDay")
        let content = UNMutableNotificationContent()
        content.title = "ArgusAI Daily Limit Reached"
        content.body = String(format: "Today's cost %@ has reached your limit of %@",
                              formatCost(todayCost), formatCost(threshold))
        content.sound = .default
        let req = UNNotificationRequest(identifier: "argusai.dailylimit.\(todayStr)",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    private var filteredTotalCostToday: Double {
        let start = Calendar.current.startOfDay(for: Date())
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return (stats?.dailyTotals ?? [])
            .filter { (fmt.date(from: $0.date) ?? .distantPast) >= start }
            .reduce(0.0) { $0 + $1.estimatedCostUSD }
    }

    // MARK: - Export CSV

    @MainActor func exportCSV() {
        var csv = "session_id,project,date,messages,output_tokens,cost_usd,is_subagent,model\n"
        for s in (stats?.sessions ?? []) {
            let line = "\"\(s.sessionId)\",\"\(s.project)\",\(s.firstDay),\(s.messageCount),\(s.outputTokens),\(s.costUSD),\(s.isSubagent ? 1 : 0),\"\(s.topModel)\"\n"
            csv += line
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        let dateFmt = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "argusai-\(dateFmt.string(from: Date())).csv"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
