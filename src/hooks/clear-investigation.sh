#!/bin/bash
# PostToolUse hook for Read, Grep, Glob, LSP
# Clears the investigation marker — Claude has looked at code.

rm -f /tmp/codex-dialog-needs-investigation
exit 0
