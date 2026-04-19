#!/usr/bin/env bash
set -euo pipefail

# ── Claude Codex Dialog - Uninstaller ───────────────────────────────────────

CLAUDE_JSON="$HOME/.claude.json"
COMMANDS_DIR="$HOME/.claude/commands"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " claude-codex-dialog uninstaller"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Remove slash commands
if [ -f "$COMMANDS_DIR/codex-review-code.md" ]; then
    rm "$COMMANDS_DIR/codex-review-code.md"
    echo "  Removed /codex-review-code ✓"
fi

if [ -f "$COMMANDS_DIR/codex-review-plan.md" ]; then
    rm "$COMMANDS_DIR/codex-review-plan.md"
    echo "  Removed /codex-review-plan ✓"
fi

if [ -f "$COMMANDS_DIR/codex-review-spec.md" ]; then
    rm "$COMMANDS_DIR/codex-review-spec.md"
    echo "  Removed /codex-review-spec ✓"
fi

if [ -f "$COMMANDS_DIR/codex-audit.md" ]; then
    rm "$COMMANDS_DIR/codex-audit.md"
    echo "  Removed /codex-audit ✓"
fi

# Remove MCP server from ~/.claude.json
if [ -f "$CLAUDE_JSON" ] && grep -q '"codex-dialog"' "$CLAUDE_JSON" 2>/dev/null; then
    node -e "
        const fs = require('fs');
        const config = JSON.parse(fs.readFileSync('$CLAUDE_JSON', 'utf-8'));
        if (config.mcpServers && config.mcpServers['codex-dialog']) {
            delete config.mcpServers['codex-dialog'];
            if (Object.keys(config.mcpServers).length === 0) {
                delete config.mcpServers;
            }
        }
        fs.writeFileSync('$CLAUDE_JSON', JSON.stringify(config, null, 2) + '\n');
    "
    echo "  Removed MCP server from ~/.claude.json ✓"
fi

echo ""
echo "  Uninstalled. Restart Claude Code to apply changes."
echo ""
