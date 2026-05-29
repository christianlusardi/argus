# ArgusAI

A native macOS app that monitors your [Claude Code](https://claude.ai/code) usage like a satellite — tokens, costs, projects, activity patterns — updated in real time.

> *Argus, the hundred-eyed giant of Greek mythology, never slept. He watched everything.*

![ArgusAI screenshot](screenshot.png)

---

## What it does

ArgusAI reads the local log files that Claude Code writes on your machine and turns them into a dashboard:

| Tab | What you see |
|---|---|
| **Overview** | Total messages, tokens, cost, cache hit rate, web searches, current streak, forecast, account breakdown; **click any point on the Daily Cost chart** to open a breakdown by model, project, and raw SQL |
| **Models** | Token breakdown and cost per model (Opus, Sonnet, Haiku) with interactive crosshair |
| **Activity** | Daily message chart (with crosshair tooltip), Output/Context Ratio trend, day-of-week heatmap, current + best-ever streak |
| **Schedule** | Hourly usage distribution (with tooltip), **cost per hour of day**, average start/end time, work hours |
| **Projects** | Cost and token usage by repository — **sortable columns** (click any header) |
| **Sessions** | Per-session table with **search**, **sortable columns**, pagination ("Load more") |
| **Platform** | Operational KPIs: total cost, requests, avg cost/tokens per request, token trend (with crosshair), daily cost chart, response time, cost per user |

Everything updates automatically every 3 seconds. No data leaves your machine.

---

## Requirements

- macOS 26 (Tahoe) or later
- Apple Silicon Mac (M1 or later)
- [Claude Code](https://claude.ai/code) installed and used at least once

---

## Install

1. Download the latest zip from the [Releases](../../releases) page
2. Unzip it
3. **Right-click** `ArgusAI.app` → **Open**
4. Click **Open** in the security dialog (macOS asks this only the first time for apps not from the App Store)

That's it. No installer, no setup.

---

## Build from source

If you want to build it yourself:

```bash
git clone <this-repo>
cd test-cocoa
bash build.sh
open ArgusAI.app
```

To create a distributable zip:

```bash
bash dist.sh
# → ArgusAI-1.0-YYYYMMDD.zip
```

**Requirements to build:** Xcode Command Line Tools (`xcode-select --install`)

---

## How it works

Claude Code writes a `.jsonl` log file for every conversation, stored at:

```
~/.claude/projects/**/*.jsonl
```

Every 3 seconds ArgusAI checks for new data and silently updates the dashboard. Under the hood it uses an embedded SQLite database (`~/.claude/argusai.db`) for fast incremental ingestion:

```
JSONL files → incremental ingest (new lines only) → SQLite → dashboard
```

On each refresh, only the lines added since the last run are read and inserted. All KPI queries run against indexed SQL tables, so the dashboard stays snappy even with hundreds of sessions.

ArgusAI looks at `assistant` messages and reads:

- `message.usage.input_tokens` / `output_tokens`
- `message.usage.cache_read_input_tokens` / `cache_creation_input_tokens`
- `message.content[]` tool_use blocks — `name == "WebSearch"` are counted as web searches
- `message.model`
- `sessionId`, `timestamp`, `cwd` (to group by project)

It also reads `user` messages to capture human-typed turns for response time calculation (time from user message to first assistant token).

Cost estimates use [Anthropic's public pricing](https://www.anthropic.com/pricing). They are estimates, not your actual bill.

### Ad-hoc queries

Because all data lives in SQLite, you can run your own queries any time:

```bash
sqlite3 ~/.claude/argusai.db
```

Useful tables: `messages`, `sessions`, `tool_events`, `user_turns`, `account_timeline`. Example:

```sql
-- cost by project, last 30 days
SELECT project, ROUND(SUM(cost_usd),2) AS cost, COUNT(*) AS messages
FROM messages
WHERE day >= date('now', '-30 days')
GROUP BY project ORDER BY cost DESC;

-- cost by account
SELECT account_uuid, ROUND(SUM(cost_usd),2) AS cost
FROM messages
GROUP BY account_uuid ORDER BY cost DESC;
```

---

## Privacy

**All data stays on your machine.** ArgusAI never connects to the internet. It only reads files in `~/.claude/projects/` that Claude Code already created.

---

## Filters

### Time range
Use the **TIME RANGE** section in the sidebar to scope everything to:

- **Today** — current day only
- **7 days** — last 7 days
- **30 days** — last 30 days
- **All time** — since you started using Claude Code
- **Custom** — pick any **Da** (from) and **Al** (to) date with the calendar pickers that appear below; selecting a date activates the custom filter automatically

The active preset is highlighted with a blue dot, just like the navigation items.

### Account filter
If you use Claude Code with **multiple accounts or API keys**, ArgusAI tracks each one separately and shows an **ACCOUNT** picker in the sidebar. Selecting an account scopes all tabs — costs, tokens, sessions, projects — to that identity only.

ArgusAI detects the active auth automatically, following Claude Code's own priority:

1. `ANTHROPIC_API_KEY` environment variable
2. `apiKeyHelper` script in `~/.claude/settings.json`
3. API key stored in the macOS Keychain (set via `/config`)
4. OAuth account (`~/.claude.json`)

Each API key and each OAuth account is treated as a **distinct identity** with its own history. A setup with 3 API keys and 2 OAuth accounts produces 5 separate entries, all filterable and individually charted in the "By Account" Overview card.

The ACCOUNT section is hidden when you only have one identity — it only appears when there's something to distinguish.

### Project filter
If you work across **multiple repositories**, ArgusAI shows a **PROJECT** picker in the sidebar. Selecting a project scopes every tab — costs, tokens, sessions, activity, schedule — to that repository only.

The PROJECT section is hidden when you only have one project — it only appears when there's something to distinguish.

---

## Export

| Shortcut | Action |
|---|---|
| **Cmd+E** | Export all sessions as CSV |
| **Cmd+Shift+E** | Export all sessions as JSON |
| **Cmd+R** | Force refresh |

---

## Notifications

- **Daily limit alert** — set a cost threshold in the sidebar; fires once per day when today's spend crosses it
- **Weekly summary** — every Monday at 09:00 a notification shows last week's total cost and message count

## Menu bar

The menu bar extra shows today's cost at a glance. While Claude Code is actively running a session, the waveform icon fills solid and a green dot appears.

---

## Troubleshooting

**"ArgusAI can't be opened because it is from an unidentified developer"**
→ Right-click the app → Open → Open. You only need to do this once.

**The app shows no data**
→ Make sure you have used Claude Code at least once. Check that `~/.claude/projects/` exists and contains `.jsonl` files.

**Numbers look stale**
→ The app auto-refreshes every 3 seconds. If you just finished a session, wait a moment. You can also click **Refresh** in the sidebar.

**App won't launch on my Mac**
→ This build requires Apple Silicon (M1/M2/M3/M4) and macOS 26 (Tahoe). Intel Macs are not supported in the current release.
