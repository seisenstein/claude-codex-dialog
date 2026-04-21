#!/bin/bash
# PostToolUse hook for mcp__codex-dialog__check_messages
# Sets a marker when Codex returns findings that need investigation.
# Does NOT set the marker for LGTM / approval-only messages.

INPUT=$(cat)

# The hook receives JSON with tool_response containing escaped JSON.
# Check for codex findings in the full payload (handles both escaped and unescaped quotes).
if echo "$INPUT" | grep -qE '\\?"from\\?":\s*\\?"codex\\?"'; then
    if echo "$INPUT" | grep -qE '\[(CRITICAL|CORRECTNESS|ARCHITECTURE|SECURITY|ROBUSTNESS|SUGGESTION|QUESTION)\]'; then
        touch /tmp/codex-dialog-needs-investigation
    fi
fi

exit 0
