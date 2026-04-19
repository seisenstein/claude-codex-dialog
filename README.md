# claude-codex-dialog

An MCP server that enables back-and-forth discussions between [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Codex CLI](https://github.com/openai/codex). Spawns background runners that manage conversation turns, letting the two AI assistants collaboratively analyze problems, review code, and debate solutions.

## Features

- **General Dialog** — Open-ended technical discussions between Claude and Codex about any problem
- **Code Review** — Codex automatically reviews a git diff and discusses findings with Claude, going back and forth on fixes
- **Plan Review** — Codex adversarially reviews an implementation plan (the HOW) before any code is written, catching feasibility and ordering issues early
- **Spec Review** — Codex adversarially reviews a product/feature specification (the WHAT/WHY) for gaps, ambiguity, scope creep, and untestable acceptance criteria before a plan or code gets written
- **Code Audit** — Codex performs a comprehensive audit of existing files (not just changes) for bugs, architecture issues, correctness, security, and more

## How it works

### Dialog mode
1. Claude calls `start_dialog` with a problem description
2. The server spawns a background runner process
3. Claude sends messages via `send_message`, and the runner invokes Codex to respond
4. Claude waits for replies by arming a Monitor on the session's `conversation.jsonl`, then reads the content with `check_messages` once notified
5. The conversation continues back and forth until ended or a turn/idle limit is reached

### Code review mode
1. Claude calls `start_code_review` with a project path and branch info
2. The server generates a git diff and spawns a review runner
3. Codex **automatically generates an initial review** from the diff — no first message needed
4. Claude waits for the review via Monitor, then reads it via `check_messages` and responds with fixes or discussion
5. Back and forth continues until Codex says "LGTM" or the session is ended
6. Review findings are categorized as `[CRITICAL]`, `[CORRECTNESS]`, `[ARCHITECTURE]`, `[SECURITY]`, `[ROBUSTNESS]`, `[SUGGESTION]`, `[QUESTION]`, `[PRAISE]` (optional), or `[NIT]` (cosmetic, grouped at the end)

### Code audit mode
1. Claude reads the target files and calls `start_dialog` with the code and an audit prompt
2. Codex performs a deep adversarial audit — architecture, correctness, edge cases, security, resource management
3. Claude investigates findings, fixes valid issues, and pushes back on false positives
4. Discussion continues until the audit is complete

## Prerequisites

- [Node.js](https://nodejs.org/) >= 18
- [Codex CLI](https://github.com/openai/codex) installed and available on your PATH (or specify a custom command)

## Install

```bash
git clone https://github.com/clptvn/claude-codex-dialog.git
cd claude-codex-dialog
npm run setup
```

This installs dependencies, registers the MCP server in your Claude Code settings, and installs the `/codex-review-code`, `/codex-review-plan`, `/codex-review-spec`, and `/codex-audit` slash commands globally.

Restart Claude Code after installation to pick up the new MCP server.

To uninstall:
```bash
npm run uninstall
```

## MCP Tools

### Dialog

| Tool | Description |
|------|-------------|
| `start_dialog` | Start a new discussion session with Codex CLI |

### Code Review

| Tool | Description |
|------|-------------|
| `start_code_review` | Start a review session — Codex auto-generates an initial review from the git diff |
| `get_review_summary` | Get review metadata, structured findings, and approval status |

### Shared (work with both dialog and review sessions)

| Tool | Description |
|------|-------------|
| `send_message` | Send a message to Codex in an ongoing session |
| `check_messages` | Read new messages from Codex (use a Monitor on the session's `conversation.jsonl` to wait for notifications; call this tool to fetch content) |
| `get_full_history` | Get the complete conversation history |
| `check_partner_alive` | Check if the Codex runner process is still running |
| `end_dialog` | End the session and get the final conversation |
| `list_sessions` | List all dialog and review sessions |

## Usage

### Slash commands

After installation, four slash commands are available in Claude Code:

```
/codex-review-code                    Review uncommitted changes
/codex-review-code staged             Review only staged changes
/codex-review-code branch             Review current branch vs main
/codex-review-code commit:<sha>       Review a specific commit
/codex-review-code staged security    Review staged changes with security focus
/codex-review-code uncommitted rounds:7   Review with a custom 7-round soft budget

/codex-review-plan                    Review an auto-detected plan file
/codex-review-plan path/to/plan.md    Review a specific plan file
/codex-review-plan rounds:3           Review with a tighter 3-round budget

/codex-review-spec                    Review an auto-detected spec file
/codex-review-spec docs/specs/foo.md  Review a specific spec file
/codex-review-spec rounds:3           Review with a tighter 3-round budget

/codex-audit src/                     Audit all source files for bugs and issues
/codex-audit src/auth.ts src/db.ts    Audit specific files
/codex-audit src/api/ security        Audit with a security focus
/codex-audit src/ rounds:8            Audit with a looser 8-round budget
```

### Natural language

You can also ask Claude directly:

**Dialog:**
> "Start a dialog with Codex about how to refactor the authentication module"

**Code review:**
> "Have Codex review my changes on this branch"

Claude will use the MCP tools to manage the discussion automatically. Session data is stored in `~/.claude/dialogs/`.

## Configuration

Both runners have sensible defaults. The review runner uses longer timeouts to account for both sides investigating code:

| Setting | Dialog | Review |
|---------|--------|--------|
| Soft round budget (default) | 5 | 5 |
| Hard round cap | soft + 5 | soft + 5 |
| Codex timeout per invocation | 5 min | 10 min |
| Idle timeout | 15 min | 30 min |
| Poll interval | 3s | 5s |

These can be adjusted in `src/dialog-runner.mjs` and `src/review-runner.mjs` respectively.

### Round budget

Each session has a **soft round budget** (default 5) that the runner injects into every Codex prompt. The purpose is to push Codex to deliver **complete feedback in each message** rather than drip-feeding findings across rounds — wording is explicit about "dump everything you found" and "thoroughness, not speed." If the conversation needs more, a **hard cap** of soft+5 still allows overflow without fabricating urgency; once hit, the runner refuses further Codex turns.

Every `check_messages`, `send_message`, and `check_partner_alive` response includes a `budget` object: `{ max_rounds, hard_cap, rounds_used, rounds_remaining, hard_rounds_remaining, past_soft_cap }` so Claude can track where it stands.

Override per-session with `max_rounds` in `start_dialog` / `start_code_review`, or via the `rounds:N` arg on any slash command.

## License

MIT
