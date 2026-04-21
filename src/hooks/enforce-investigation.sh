#!/bin/bash
# PreToolUse hook for mcp__codex-dialog__send_message
# Blocks the send if Claude hasn't read any code since receiving Codex findings.

STATE_FILE="/tmp/codex-dialog-needs-investigation"

if [ -f "$STATE_FILE" ]; then
    cat >&2 <<'MSG'
BLOCKED: You have not investigated Codex's claims. Before responding to Codex, you MUST:

1. Read the ACTUAL CODE at every file/line Codex referenced — use Read, Grep, or Glob
2. Verify each claim against the codebase yourself
3. Form your own opinion based on what the code actually does
4. Only then write your response with evidence (file paths, line numbers, what you found)

Do NOT accept or reject findings based on whether they "sound right."
Do NOT paraphrase Codex's claims back as agreement without checking.
Go read the code NOW, then come back and send your message.
MSG
    exit 2
fi

exit 0
