import Foundation
import CSQLite

// MARK: - ArgusDB

final class ArgusDB {

    private var db: OpaquePointer?
    private typealias DestrType = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private let transient: DestrType = unsafeBitCast(-1 as Int, to: DestrType.self)

    enum Err: Error {
        case open(String), prepare(String), exec(String)
    }

    init(path: String) throws {
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            throw Err.open(msg)
        }
        var pErr: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;", nil, nil, &pErr)
        sqlite3_free(pErr)
        try execSQL(schema)
    }

    deinit { sqlite3_close(db) }

    // MARK: - Schema

    private let schema = """
        CREATE TABLE IF NOT EXISTS ingested_files (
            path             TEXT PRIMARY KEY,
            lines_processed  INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS sessions (
            session_id  TEXT PRIMARY KEY,
            project     TEXT NOT NULL DEFAULT 'unknown',
            is_subagent INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS messages (
            file_path         TEXT NOT NULL,
            line_num          INTEGER NOT NULL,
            session_id        TEXT NOT NULL,
            timestamp         TEXT NOT NULL DEFAULT '',
            day               TEXT NOT NULL DEFAULT '',
            hour              INTEGER NOT NULL DEFAULT 0,
            model             TEXT NOT NULL DEFAULT 'unknown',
            input_tokens      INTEGER DEFAULT 0,
            output_tokens     INTEGER DEFAULT 0,
            cache_read_tokens INTEGER DEFAULT 0,
            cache_create_tokens INTEGER DEFAULT 0,
            web_searches      INTEGER DEFAULT 0,
            cost_usd          REAL    DEFAULT 0,
            project           TEXT NOT NULL DEFAULT 'unknown',
            is_subagent       INTEGER DEFAULT 0,
            PRIMARY KEY (file_path, line_num)
        );
        CREATE TABLE IF NOT EXISTS tool_events (
            file_path  TEXT NOT NULL,
            line_num   INTEGER NOT NULL,
            session_id TEXT NOT NULL,
            day        TEXT NOT NULL DEFAULT '',
            count      INTEGER DEFAULT 0,
            PRIMARY KEY (file_path, line_num)
        );
        CREATE INDEX IF NOT EXISTS idx_msg_day     ON messages(day);
        CREATE INDEX IF NOT EXISTS idx_msg_model   ON messages(model);
        CREATE INDEX IF NOT EXISTS idx_msg_project ON messages(project);
        CREATE INDEX IF NOT EXISTS idx_msg_session ON messages(session_id);
        CREATE INDEX IF NOT EXISTS idx_tool_day    ON tool_events(day);
    """

    // MARK: - Low-level helpers

    private func execSQL(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw Err.exec(msg)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw Err.prepare(String(cString: sqlite3_errmsg(db)))
        }
        return stmt!
    }

    private func bindTxt(_ s: OpaquePointer, _ i: Int32, _ v: String) {
        sqlite3_bind_text(s, i, v, Int32(v.utf8.count), transient)
    }
    private func bindInt(_ s: OpaquePointer, _ i: Int32, _ v: Int) {
        sqlite3_bind_int64(s, i, Int64(v))
    }
    private func bindDbl(_ s: OpaquePointer, _ i: Int32, _ v: Double) {
        sqlite3_bind_double(s, i, v)
    }
    private func colTxt(_ s: OpaquePointer, _ i: Int32) -> String {
        sqlite3_column_text(s, i).map { String(cString: $0) } ?? ""
    }
    private func colInt(_ s: OpaquePointer, _ i: Int32) -> Int {
        Int(sqlite3_column_int64(s, i))
    }
    private func colDbl(_ s: OpaquePointer, _ i: Int32) -> Double {
        sqlite3_column_double(s, i)
    }

    // MARK: - Project name

    private func resolvedProject(cwd: String?, fileURL: URL) -> String {
        if let cwd = cwd, !cwd.isEmpty {
            let name = URL(fileURLWithPath: cwd).lastPathComponent
            return name.isEmpty ? "unknown" : name
        }
        let parts = fileURL.pathComponents
        guard let idx = parts.firstIndex(of: "projects"), idx + 1 < parts.count else { return "unknown" }
        let segs = parts[idx + 1].split(separator: "-").filter { !$0.isEmpty }
        if let gi = segs.firstIndex(of: "git"), gi + 1 < segs.count {
            return segs[(gi + 1)...].joined(separator: "-")
        }
        return segs.suffix(2).joined(separator: "-")
    }

    // MARK: - Ingestion

    func ingestFiles(_ files: [(url: URL, isSubagent: Bool)]) throws {
        // Load already-processed line counts
        var linesProcessed: [String: Int] = [:]
        do {
            let q = try prepare("SELECT path, lines_processed FROM ingested_files")
            while sqlite3_step(q) == SQLITE_ROW { linesProcessed[colTxt(q, 0)] = colInt(q, 1) }
            sqlite3_finalize(q)
        }

        // Load known sessions
        var sessionProjects: [String: String] = [:]
        do {
            let q = try prepare("SELECT session_id, project FROM sessions")
            while sqlite3_step(q) == SQLITE_ROW { sessionProjects[colTxt(q, 0)] = colTxt(q, 1) }
            sqlite3_finalize(q)
        }

        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        let cal = Calendar.current
        func parseDate(_ s: String) -> Date? { isoFrac.date(from: s) ?? isoPlain.date(from: s) }

        try execSQL("BEGIN")

        let sessInsert = try prepare(
            "INSERT OR IGNORE INTO sessions(session_id, project, is_subagent) VALUES(?,?,?)")
        let msgInsert  = try prepare("""
            INSERT OR IGNORE INTO messages
            (file_path,line_num,session_id,timestamp,day,hour,model,
             input_tokens,output_tokens,cache_read_tokens,cache_create_tokens,
             web_searches,cost_usd,project,is_subagent)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """)
        let toolInsert = try prepare(
            "INSERT OR IGNORE INTO tool_events(file_path,line_num,session_id,day,count) VALUES(?,?,?,?,?)")
        let fileUpsert = try prepare(
            "INSERT OR REPLACE INTO ingested_files(path,lines_processed) VALUES(?,?)")

        for (fileURL, isSubagent) in files {
            let path = fileURL.path
            let startLine = linesProcessed[path] ?? 0

            guard let data = try? Data(contentsOf: fileURL),
                  let text = String(data: data, encoding: .utf8) else { continue }

            let allLines = text.split(separator: "\n", omittingEmptySubsequences: true)
            guard allLines.count > startLine else { continue }
            let newLines = allLines[startLine...]

            // Pass 1: collect cwds for unknown sessions
            var newCwds: [String: String] = [:]
            for line in newLines {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                let sid = obj["sessionId"] as? String ?? ""
                guard !sid.isEmpty, newCwds[sid] == nil, sessionProjects[sid] == nil,
                      let cwd = obj["cwd"] as? String, !cwd.isEmpty else { continue }
                newCwds[sid] = cwd
            }

            // Insert newly-discovered sessions
            for (sid, cwd) in newCwds {
                let proj = resolvedProject(cwd: cwd, fileURL: fileURL)
                bindTxt(sessInsert, 1, sid)
                bindTxt(sessInsert, 2, proj)
                bindInt(sessInsert, 3, isSubagent ? 1 : 0)
                sqlite3_step(sessInsert)
                sqlite3_reset(sessInsert)
                sessionProjects[sid] = proj
            }

            // Pass 2: insert messages and tool events
            var lineNum = startLine
            for line in newLines {
                lineNum += 1
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }

                let type = obj["type"] as? String ?? ""
                let sid  = obj["sessionId"] as? String ?? ""
                let ts   = obj["timestamp"] as? String ?? ""
                let day  = ts.isEmpty ? "" : String(ts.prefix(10))

                if type == "assistant", let msg = obj["message"] as? [String: Any] {
                    let model  = msg["model"] as? String ?? "unknown"
                    let usage  = msg["usage"] as? [String: Any] ?? [:]
                    let input  = usage["input_tokens"]                as? Int ?? 0
                    let output = usage["output_tokens"]               as? Int ?? 0
                    let cr     = usage["cache_read_input_tokens"]     as? Int ?? 0
                    let cc     = usage["cache_creation_input_tokens"] as? Int ?? 0
                    let ws     = (usage["server_tool_use"] as? [String: Any])?["web_search_requests"] as? Int ?? 0

                    guard input + output + cr + cc > 0 else { continue }

                    let hour = parseDate(ts).map { cal.component(.hour, from: $0) } ?? 0
                    let proj = sessionProjects[sid] ?? resolvedProject(cwd: nil, fileURL: fileURL)
                    let cost = ModelPricingTable.price(for: model).cost(input: input, output: output, cr: cr, cc: cc)

                    bindTxt(msgInsert,  1, path);   bindInt(msgInsert,  2, lineNum)
                    bindTxt(msgInsert,  3, sid);    bindTxt(msgInsert,  4, ts)
                    bindTxt(msgInsert,  5, day);    bindInt(msgInsert,  6, hour)
                    bindTxt(msgInsert,  7, model);  bindInt(msgInsert,  8, input)
                    bindInt(msgInsert,  9, output); bindInt(msgInsert, 10, cr)
                    bindInt(msgInsert, 11, cc);     bindInt(msgInsert, 12, ws)
                    bindDbl(msgInsert, 13, cost);   bindTxt(msgInsert, 14, proj)
                    bindInt(msgInsert, 15, isSubagent ? 1 : 0)
                    sqlite3_step(msgInsert)
                    sqlite3_reset(msgInsert)
                }

                if type == "user", let msg = obj["message"] as? [String: Any], !day.isEmpty {
                    let toolCount = (msg["content"] as? [[String: Any]])?.filter {
                        $0["type"] as? String == "tool_result"
                    }.count ?? 0
                    if toolCount > 0 {
                        bindTxt(toolInsert, 1, path); bindInt(toolInsert, 2, lineNum)
                        bindTxt(toolInsert, 3, sid);  bindTxt(toolInsert, 4, day)
                        bindInt(toolInsert, 5, toolCount)
                        sqlite3_step(toolInsert)
                        sqlite3_reset(toolInsert)
                    }
                }
            }

            bindTxt(fileUpsert, 1, path); bindInt(fileUpsert, 2, allLines.count)
            sqlite3_step(fileUpsert); sqlite3_reset(fileUpsert)
        }

        sqlite3_finalize(sessInsert)
        sqlite3_finalize(msgInsert)
        sqlite3_finalize(toolInsert)
        sqlite3_finalize(fileUpsert)

        try execSQL("COMMIT")
    }

    // MARK: - Build StatsCache from DB

    func buildStatsCache() throws -> StatsCache {
        let (dailyTotals, dailyModelBreakdown) = try queryDailyBreakdown()
        let modelUsage          = try queryModelUsage()
        let dailyActivity       = try queryDailyActivity()
        let hourCounts          = try queryHourCounts()
        let dailyHourCounts     = try queryDailyHourCounts()
        let dailyWorkHours      = try queryDailyWorkHours()
        let projectStats        = try queryProjectStats()
        let dailyProjectCosts   = try queryDailyProjectCosts()
        let (totSess, totMsg, longestSess, firstDate, avgOut) = try querySessionAggregates()
        let (subCnt, dirCnt)    = try queryAgentCounts()
        let sessions            = try querySessions()
        let (subCost, dirCost)  = try queryAgentTypeCosts()

        let dailyCosts = Dictionary(uniqueKeysWithValues: dailyTotals.map { ($0.date, $0.estimatedCostUSD) })

        return StatsCache(
            version: nil,
            lastComputedDate: dailyTotals.last?.date,
            dailyActivity: dailyActivity,
            dailyModelTokens: nil,
            modelUsage: modelUsage.isEmpty ? nil : modelUsage,
            totalSessions: totSess,
            totalMessages: totMsg,
            longestSession: longestSess,
            firstSessionDate: firstDate,
            hourCounts: hourCounts.isEmpty ? nil : hourCounts,
            totalSpeculationTimeSavedMs: nil,
            dailyCosts: dailyCosts.isEmpty ? nil : dailyCosts,
            projectStats: projectStats.isEmpty ? nil : projectStats,
            dailyWorkHours: dailyWorkHours.isEmpty ? nil : dailyWorkHours,
            subagentSessionCount: subCnt,
            directSessionCount: dirCnt,
            avgOutputTokensPerSession: avgOut,
            dailyTotals: dailyTotals.isEmpty ? nil : dailyTotals,
            dailyModelBreakdown: dailyModelBreakdown.isEmpty ? nil : dailyModelBreakdown,
            dailyHourCounts: dailyHourCounts.isEmpty ? nil : dailyHourCounts,
            dailyProjectCosts: dailyProjectCosts.isEmpty ? nil : dailyProjectCosts,
            sessions: sessions.isEmpty ? nil : sessions,
            subagentCostUSD: subCost,
            directCostUSD: dirCost
        )
    }

    // MARK: - Queries

    private func queryDailyBreakdown() throws -> ([DailyTokenTotals], [DailyModelBreakdown]) {
        let stmt = try prepare("""
            SELECT day, model,
                SUM(input_tokens), SUM(output_tokens),
                SUM(cache_read_tokens), SUM(cache_create_tokens), SUM(web_searches)
            FROM messages WHERE day != ''
            GROUP BY day, model ORDER BY day
        """)
        var byDay: [String: [String: (Int, Int, Int, Int, Int)]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let day = colTxt(stmt, 0); let model = colTxt(stmt, 1)
            byDay[day, default: [:]][model] = (colInt(stmt,2), colInt(stmt,3), colInt(stmt,4), colInt(stmt,5), colInt(stmt,6))
        }
        sqlite3_finalize(stmt)

        var totals: [DailyTokenTotals] = []
        var breakdown: [DailyModelBreakdown] = []

        for (day, modelMap) in byDay.sorted(by: { $0.key < $1.key }) {
            let mts = modelMap.mapValues { t in
                ModelTokenStats(inputTokens: t.0, outputTokens: t.1,
                                cacheReadInputTokens: t.2, cacheCreationInputTokens: t.3,
                                webSearchRequests: t.4, costUSD: nil)
            }
            breakdown.append(DailyModelBreakdown(date: day, modelTokens: mts))

            let totIn  = modelMap.values.reduce(0) { $0 + $1.0 }
            let totOut = modelMap.values.reduce(0) { $0 + $1.1 }
            let totCR  = modelMap.values.reduce(0) { $0 + $1.2 }
            let totCC  = modelMap.values.reduce(0) { $0 + $1.3 }
            let totWS  = modelMap.values.reduce(0) { $0 + $1.4 }
            let cost   = modelMap.reduce(0.0) { s, p in
                s + ModelPricingTable.price(for: p.key).cost(input: p.value.0, output: p.value.1, cr: p.value.2, cc: p.value.3)
            }
            let savings = modelMap.reduce(0.0) { s, p in
                let pr = ModelPricingTable.price(for: p.key)
                return s + max(0, Double(p.value.2) * (pr.inputPerMTok - pr.cacheReadPerMTok) / 1_000_000)
            }
            totals.append(DailyTokenTotals(date: day, inputTokens: totIn, outputTokens: totOut,
                                           cacheReadTokens: totCR, cacheCreateTokens: totCC,
                                           webSearchCount: totWS, estimatedCostUSD: cost, cacheSavingsUSD: savings))
        }
        return (totals, breakdown)
    }

    private func queryModelUsage() throws -> [String: ModelTokenStats] {
        let stmt = try prepare("""
            SELECT model, SUM(input_tokens), SUM(output_tokens),
                SUM(cache_read_tokens), SUM(cache_create_tokens), SUM(web_searches)
            FROM messages GROUP BY model
        """)
        defer { sqlite3_finalize(stmt) }
        var result: [String: ModelTokenStats] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let model = colTxt(stmt, 0)
            result[model] = ModelTokenStats(
                inputTokens: colInt(stmt,1), outputTokens: colInt(stmt,2),
                cacheReadInputTokens: colInt(stmt,3), cacheCreationInputTokens: colInt(stmt,4),
                webSearchRequests: colInt(stmt,5), costUSD: nil)
        }
        return result
    }

    private func queryDailyActivity() throws -> [DailyActivity] {
        let stmt = try prepare("""
            SELECT m.day,
                COUNT(*) AS msg_count,
                COUNT(DISTINCT m.session_id) AS sess_count,
                COALESCE(SUM(te.count), 0) AS tool_count
            FROM messages m
            LEFT JOIN (SELECT day, SUM(count) AS count FROM tool_events GROUP BY day) te
                ON te.day = m.day
            WHERE m.day != ''
            GROUP BY m.day ORDER BY m.day
        """)
        defer { sqlite3_finalize(stmt) }
        var result: [DailyActivity] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(DailyActivity(
                date: colTxt(stmt,0), messageCount: colInt(stmt,1),
                sessionCount: colInt(stmt,2), toolCallCount: colInt(stmt,3)))
        }
        return result
    }

    private func queryHourCounts() throws -> [String: Int] {
        let stmt = try prepare("SELECT hour, COUNT(*) FROM messages GROUP BY hour")
        defer { sqlite3_finalize(stmt) }
        var result: [String: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW { result["\(colInt(stmt,0))"] = colInt(stmt,1) }
        return result
    }

    private func queryDailyHourCounts() throws -> [String: [String: Int]] {
        let stmt = try prepare("""
            SELECT day, hour, COUNT(*) FROM messages WHERE day != ''
            GROUP BY day, hour ORDER BY day
        """)
        defer { sqlite3_finalize(stmt) }
        var result: [String: [String: Int]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let day = colTxt(stmt,0)
            result[day, default: [:]]["\(colInt(stmt,1))"] = colInt(stmt,2)
        }
        return result
    }

    private func queryDailyWorkHours() throws -> [DailyWorkHours] {
        let stmt = try prepare("""
            SELECT day, MIN(hour), MAX(hour) FROM messages
            WHERE day != '' GROUP BY day ORDER BY day
        """)
        defer { sqlite3_finalize(stmt) }
        var result: [DailyWorkHours] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(DailyWorkHours(date: colTxt(stmt,0), firstHour: colInt(stmt,1), lastHour: colInt(stmt,2)))
        }
        return result
    }

    private func queryProjectStats() throws -> [ProjectStats] {
        let stmt = try prepare("""
            SELECT project,
                SUM(input_tokens), SUM(output_tokens),
                SUM(cache_read_tokens), SUM(cache_create_tokens), SUM(web_searches),
                COUNT(DISTINCT session_id), COUNT(*), SUM(cost_usd)
            FROM messages GROUP BY project ORDER BY SUM(cost_usd) DESC
        """)
        defer { sqlite3_finalize(stmt) }
        var result: [ProjectStats] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(ProjectStats(
                project: colTxt(stmt,0),
                inputTokens: colInt(stmt,1), outputTokens: colInt(stmt,2),
                cacheReadInputTokens: colInt(stmt,3), cacheCreationInputTokens: colInt(stmt,4),
                webSearchRequests: colInt(stmt,5), sessionCount: colInt(stmt,6),
                messageCount: colInt(stmt,7), estimatedCostUSD: colDbl(stmt,8)))
        }
        return result
    }

    private func queryDailyProjectCosts() throws -> [DailyProjectCosts] {
        let stmt = try prepare("""
            SELECT day, project, SUM(cost_usd), SUM(output_tokens), COUNT(*), SUM(web_searches)
            FROM messages WHERE day != ''
            GROUP BY day, project ORDER BY day
        """)
        defer { sqlite3_finalize(stmt) }
        var costs:   [String: [String: Double]] = [:]
        var outputs: [String: [String: Int]]    = [:]
        var msgs:    [String: [String: Int]]    = [:]
        var ws:      [String: [String: Int]]    = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let day = colTxt(stmt,0); let proj = colTxt(stmt,1)
            costs[day,   default: [:]][proj] = colDbl(stmt,2)
            outputs[day, default: [:]][proj] = colInt(stmt,3)
            msgs[day,    default: [:]][proj] = colInt(stmt,4)
            ws[day,      default: [:]][proj] = colInt(stmt,5)
        }
        let days = Set(costs.keys)
        return days.map { day in
            DailyProjectCosts(date: day, costs: costs[day] ?? [:], outputs: outputs[day] ?? [:],
                              messages: msgs[day] ?? [:], webSearches: ws[day] ?? [:])
        }.sorted { $0.date < $1.date }
    }

    private func querySessionAggregates() throws -> (Int, Int, LongestSessionInfo?, String?, Int) {
        var totalMessages = 0
        do {
            let s = try prepare("SELECT COUNT(*) FROM messages")
            if sqlite3_step(s) == SQLITE_ROW { totalMessages = colInt(s,0) }
            sqlite3_finalize(s)
        }

        var totalSessions = 0
        do {
            let s = try prepare("SELECT COUNT(DISTINCT session_id) FROM messages")
            if sqlite3_step(s) == SQLITE_ROW { totalSessions = colInt(s,0) }
            sqlite3_finalize(s)
        }

        var longestSession: LongestSessionInfo?
        do {
            let s = try prepare("SELECT session_id, COUNT(*) AS c FROM messages GROUP BY session_id ORDER BY c DESC LIMIT 1")
            if sqlite3_step(s) == SQLITE_ROW {
                longestSession = LongestSessionInfo(sessionId: colTxt(s,0), duration: nil, messageCount: colInt(s,1), timestamp: nil)
            }
            sqlite3_finalize(s)
        }

        var firstDate: String?
        do {
            let s = try prepare("SELECT MIN(timestamp) FROM messages WHERE timestamp != ''")
            if sqlite3_step(s) == SQLITE_ROW {
                let v = colTxt(s,0); if !v.isEmpty { firstDate = v }
            }
            sqlite3_finalize(s)
        }

        var avgOut = 0
        do {
            let s = try prepare("""
                SELECT CAST(SUM(output_tokens) AS REAL) / NULLIF(COUNT(DISTINCT session_id),0)
                FROM messages
            """)
            if sqlite3_step(s) == SQLITE_ROW { avgOut = Int(colDbl(s,0)) }
            sqlite3_finalize(s)
        }

        return (totalSessions, totalMessages, longestSession, firstDate, avgOut)
    }

    private func queryAgentCounts() throws -> (Int, Int) {
        var sub = 0, direct = 0
        let s = try prepare("SELECT is_subagent, COUNT(DISTINCT session_id) FROM messages GROUP BY is_subagent")
        while sqlite3_step(s) == SQLITE_ROW {
            if colInt(s,0) == 1 { sub = colInt(s,1) } else { direct = colInt(s,1) }
        }
        sqlite3_finalize(s)
        return (sub, direct)
    }

    func querySessions() throws -> [SessionSummary] {
        let stmt = try prepare("""
            SELECT m.session_id, m.project, MIN(m.day), COUNT(*),
                SUM(m.output_tokens), SUM(m.cost_usd), MAX(m.is_subagent),
                (SELECT model FROM messages WHERE session_id = m.session_id
                 GROUP BY model ORDER BY COUNT(*) DESC LIMIT 1)
            FROM messages m WHERE m.day != ''
            GROUP BY m.session_id ORDER BY SUM(m.cost_usd) DESC
        """)
        defer { sqlite3_finalize(stmt) }
        var result: [SessionSummary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(SessionSummary(
                sessionId: colTxt(stmt, 0),
                project: colTxt(stmt, 1),
                firstDay: colTxt(stmt, 2),
                messageCount: colInt(stmt, 3),
                outputTokens: colInt(stmt, 4),
                costUSD: colDbl(stmt, 5),
                isSubagent: colInt(stmt, 6) == 1,
                topModel: colTxt(stmt, 7)
            ))
        }
        return result
    }

    func queryAgentTypeCosts() throws -> (Double?, Double?) {
        var subCost: Double? = nil
        var dirCost: Double? = nil
        let s = try prepare("SELECT is_subagent, SUM(cost_usd) FROM messages GROUP BY is_subagent")
        defer { sqlite3_finalize(s) }
        while sqlite3_step(s) == SQLITE_ROW {
            let cost = colDbl(s, 1)
            if colInt(s, 0) == 1 { subCost = cost } else { dirCost = cost }
        }
        return (subCost, dirCost)
    }
}
