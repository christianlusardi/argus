# /rate — Rate this session for ArgusAI

Ask the user to rate the quality of this Claude Code session on a scale of **1 to 5**:

| Stars | Meaning |
|---|---|
| ⭐ (1) | Poor — not helpful, major mistakes, wasted time |
| ⭐⭐ (2) | Fair — partially helpful, some issues |
| ⭐⭐⭐ (3) | Good — generally useful |
| ⭐⭐⭐⭐ (4) | Great — very helpful, smooth |
| ⭐⭐⭐⭐⭐ (5) | Excellent — exceptional, saved significant time |

Also ask for a **one-sentence optional comment** (press Enter to skip).

Then:

1. **Find the current session ID** by running this bash command:
   ```bash
   find ~/.claude/projects -name "*.jsonl" -newer ~/.claude -maxdepth 5 2>/dev/null | xargs ls -t 2>/dev/null | head -1 | xargs tail -1 2>/dev/null | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('sessionId','unknown'))" 2>/dev/null || echo "unknown"
   ```
   If that fails or returns "unknown", try:
   ```bash
   ls -t $(find ~/.claude/projects -name "*.jsonl" 2>/dev/null) 2>/dev/null | head -1 | xargs tail -1 2>/dev/null | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('sessionId','unknown'))" 2>/dev/null || echo "unknown"
   ```

2. **Get the current UTC timestamp** in ISO8601 format:
   ```bash
   date -u +"%Y-%m-%dT%H:%M:%SZ"
   ```

3. **Write the feedback entry** by appending a single JSON line to `~/.claude/argusai_feedback.jsonl`:
   ```bash
   echo '{"type":"feedback","sessionId":"SESSION_ID","timestamp":"TIMESTAMP","rating":RATING,"comment":"COMMENT"}' >> ~/.claude/argusai_feedback.jsonl
   ```
   Replace SESSION_ID, TIMESTAMP, RATING, COMMENT with the actual values. Escape any double-quotes in the comment with `\"`. If the comment is empty, use an empty string `""`.

4. **Confirm** to the user: tell them their rating (e.g. "⭐⭐⭐⭐ saved!") and that it will appear in **ArgusAI → Sessions** tab after the next refresh (≤ 3 seconds).

Do not ask for any other information. Keep the interaction short and friendly.
