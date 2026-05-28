# ArgusAI

Native macOS dark-themed app that monitors Claude Code usage metrics in real time.

## Build & Run

```bash
bash build.sh          # compile
open ArgusAI.app       # run
```

**NEVER use `swift build`** — the project uses a hand-written `build.sh` with an explicit `SOURCES` array.  
When adding a new `.swift` file, add it to the `SOURCES=(...)` list in `build.sh`.

Build target is **macOS 26** (`-target arm64-apple-macosx26.0`). Required for Liquid Glass APIs (`glassEffect`).

## Release

```bash
bash release.sh 1.2.0   # oppure senza argomento: chiede la versione interattivamente
```

`release.sh` esegue in ordine:
1. **Flight checklist** — verifica `swiftc`, `git`, `codesign`, `gh`; installa Homebrew e gh CLI se mancanti; controlla autenticazione GitHub e che il tag non esista già
2. **Build** — `bash build.sh` (firma ad-hoc inclusa)
3. **Zip** — `ditto -c -k --keepParent ArgusAI.app ArgusAI-vX.Y.Z-YYYYMMDD.zip`
4. **Fingerprint** — SHA256 + MD5 del zip (salvati anche in `.sha256`)
5. **Tag Git** — `git tag -a vX.Y.Z` + push su origin
6. **GitHub Release** — `gh release create` con zip allegato e note complete (changelog automatico, tabella hash, istruzioni Gatekeeper)

> `dist.sh` crea solo lo zip locale senza pubblicare — utile per distribuire manualmente.

## Architecture

| File | Role |
|---|---|
| `Models.swift` | All Codable structs (`StatsCache`, `DailyTokenTotals`, `DailyModelBreakdown`, `DailyProjectCosts`, …) |
| `Database.swift` | `ArgusDB` — SQLite ingestion + all KPI queries; owns `~/.claude/argusai.db` |
| `MetricsStore.swift` | `ObservableObject` — calls `ArgusDB`, owns all state and computed properties |
| `ContentView.swift` | Navigation shell (sidebar + `NavSection` enum) |
| `OverviewView.swift` | Summary KPIs + charts |
| `ModelsView.swift` | Per-model token breakdown |
| `ActivityView.swift` | Daily activity chart, day-of-week, streak |
| `ScheduleView.swift` | Hourly distribution, top hours, work-hour bars |
| `ProjectsView.swift` | Per-project cost/token table and chart |
| `SessionsView.swift` | Per-session table (id, project, date, msgs, output, cost, model, sub badge) |
| `Components.swift` | Shared UI components (`MetricCard`, `SectionCard`, `DeltaBadge`, …) |
| `Theme.swift` | Color palette, `Color.appAccent`, `modelDisplayName()`, `formatTokens()` |
| `Sources/CSQLite/` | Module map + shim header that bridges system `libsqlite3` into Swift |

## Data pipeline

```
~/.claude/projects/**/*.jsonl  →  ArgusDB.ingestFiles()  →  ~/.claude/argusai.db  →  ArgusDB.buildStatsCache()  →  views
```

- JSONL files are the source of truth (written by Claude Code, never modified by ArgusAI).
- `ArgusDB` tracks `lines_processed` per file in the `ingested_files` table — only new lines are read on each 3s refresh.
- All KPI queries run as SQL against indexed tables; **never re-parse JSONL in Swift**.

### Adding a new data point

1. Add a column to `messages` in the schema string inside `Database.swift`
2. Populate it in the ingestion loop (Pass 2, the `type == "assistant"` branch)
3. Add a query method and wire it into `buildStatsCache()`
4. Add the field to `StatsCache` in `Models.swift`
5. Add a `filteredXxx` computed property in `MetricsStore.swift`

### DB schema (key tables)

| Table | Key columns |
|---|---|
| `messages` | `(file_path, line_num)` PK · `session_id` · `day` · `hour` · `model` · `input/output/cr/cc/ws tokens` · `cost_usd` · `project` · `is_subagent` |
| `sessions` | `session_id` PK · `project` · `is_subagent` |
| `tool_events` | `(file_path, line_num)` PK · `session_id` · `day` · `count` |
| `ingested_files` | `path` PK · `lines_processed` |

Relevant JSONL fields ingested (on `type == "assistant"` lines):
- `message.usage.{input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens}`
- `message.usage.server_tool_use.web_search_requests`
- `message.model`
- `sessionId`, `timestamp`, `cwd`

## Date filtering

`MetricsStore.dateFilter: DateFilter` (`.today` / `.sevenDays` / `.thirtyDays` / `.all`) drives all views.

**Pattern:** every KPI has a `filteredXxx` computed property in `MetricsStore` that slices the relevant `[DailyXxx]` array from `StatsCache` by date, then aggregates. Never read raw all-time stats directly in views; always use the `filtered*` variant.

## Window & UI style

- Borderless window: `.windowStyle(.hiddenTitleBar)` in `ClaudeMetricsApp.swift` + `WindowConfigurator` (NSViewRepresentable) in `ContentView.swift`
- Sidebar top padding is **38pt** to clear the traffic light buttons
- Cards use **macOS 26 Liquid Glass**: `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))` — use this for any new card component, never `Color.appSurface` + clipShape

When adding a new filter-aware property, add all four cases to the switch. `.today` uses `Calendar.current.startOfDay(for: Date())` as cutoff; `.sevenDays` / `.thirtyDays` use `Calendar.current.date(byAdding: .day, value: -N, to: Date())`.

Key per-day structures stored in `StatsCache`:
| Field | Used for |
|---|---|
| `dailyTotals: [DailyTokenTotals]` | Overview KPIs (cost, tokens, cache, web searches) |
| `dailyModelBreakdown: [DailyModelBreakdown]` | Models tab |
| `dailyHourCounts: [String: [String: Int]]` | Schedule tab hourly chart |
| `dailyProjectCosts: [DailyProjectCosts]` | Projects tab |
| `dailyWorkHours: [DailyWorkHours]` | Schedule work-hour bars |
| `dailyActivity: [DailyActivity]` | Activity chart, day-of-week, streak |
| `sessions: [SessionSummary]?` | Sessions tab |
| `subagentCostUSD: Double?` | Agent Type breakdown |
| `directCostUSD: Double?` | Agent Type breakdown |

## Features

| Feature | Where |
|---|---|
| **Sessions tab** | `SessionsView.swift` — per-session table; `filteredSessions` in `MetricsStore` |
| **Menu bar extra** | `ClaudeMetricsApp.swift` — `MenuBarExtra` with today cost+msgs, week cost, alert dot |
| **Delta badges** | `DeltaBadge` in `Components.swift`; `costDeltaPct`/`messagesDeltaPct` in `MetricsStore` (week-over-week) |
| **Daily limit alert** | `alertThreshold` (`@Published`, persisted in UserDefaults); `UNNotificationCenter` fires once per day when today's cost ≥ threshold |
| **Forecast** | `burnRatePerDay`, `currentMonthCost`, `daysLeftInMonth`, `projectedMonthCost` in `MetricsStore` |
| **Agent Type breakdown** | `filteredSubagentCost`, `filteredDirectCost` in `MetricsStore`; two-segment bar in `OverviewView` |
| **CSV export** | `exportCSV()` in `MetricsStore` — `NSSavePanel` + writes session CSV; Cmd+E shortcut |
| **Daily Cost chart** | `OverviewDailyCostChart` in `OverviewView` — golden area+line chart |

### Menu bar label
`store.menuBarLabel` returns today's cost formatted as `"$X.XX"`. Updated on every refresh.

### Daily limit alert flow
1. User sets threshold in sidebar (`TextField` bound to `store.alertThreshold`)
2. On each `loadData()`, `checkAlerts()` compares `todayCost` to threshold
3. If ≥ threshold and `argusai.lastAlertDay` ≠ today → fires `UNNotificationRequest`, saves today's date to UserDefaults

### Week-over-week comparison
`previousPeriodDailyTotals` shifts the current window back by one period:
- `.today` → yesterday
- `.sevenDays` → [-14d, -7d]
- `.thirtyDays` → [-60d, -30d]
- `.all` → [] (no delta)

`DeltaBadge` shows ↑ in red (spending more) and ↓ in green (spending less).

## Auto-refresh

3-second timer → `checkAndRefreshIfNeeded()` → compares file mtimes → `loadData(silent: true)`.  
Silent refresh never shows the loading spinner; only the very first load does.

## Pricing

`ModelPricingTable` in `Models.swift` maps model IDs to per-MTok prices.  
Use `ModelPricingTable.price(for: model).cost(input:output:cr:cc:)` for cost computation.
