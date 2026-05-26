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

## Architecture

| File | Role |
|---|---|
| `Models.swift` | All Codable structs (`StatsCache`, `DailyTokenTotals`, `DailyModelBreakdown`, `DailyProjectCosts`, …) |
| `MetricsStore.swift` | `ObservableObject` — parses JSONL, owns all state and computed properties |
| `ContentView.swift` | Navigation shell (sidebar + `NavSection` enum) |
| `OverviewView.swift` | Summary KPIs + charts |
| `ModelsView.swift` | Per-model token breakdown |
| `ActivityView.swift` | Daily activity chart, day-of-week, streak |
| `ScheduleView.swift` | Hourly distribution, top hours, work-hour bars |
| `ProjectsView.swift` | Per-project cost/token table and chart |
| `Components.swift` | Shared UI components (`MetricCard`, `SectionCard`, …) |
| `Theme.swift` | Color palette, `Color.appAccent`, `modelDisplayName()`, `formatTokens()` |

## Data source

Reads `~/.claude/projects/**/*.jsonl` directly — **no cache file dependency**.  
Files under a `subagents/` path component are flagged as subagent sessions.

Relevant JSONL fields (on `type == "assistant"` lines):
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

## Auto-refresh

3-second timer → `checkAndRefreshIfNeeded()` → compares file mtimes → `loadData(silent: true)`.  
Silent refresh never shows the loading spinner; only the very first load does.

## Pricing

`ModelPricingTable` in `Models.swift` maps model IDs to per-MTok prices.  
Use `ModelPricingTable.price(for: model).cost(input:output:cr:cc:)` for cost computation.
