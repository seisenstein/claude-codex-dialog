---
description: Have Codex audit files or directories for bugs, architecture issues, and correctness
argument-hint: <file or directory paths> [optional: focus area]
allowed-tools: mcp__codex-dialog__start_dialog, mcp__codex-dialog__check_messages, mcp__codex-dialog__send_message, mcp__codex-dialog__get_full_history, mcp__codex-dialog__check_partner_alive, mcp__codex-dialog__end_dialog, mcp__codex-dialog__list_sessions, Bash, Read, Glob, Grep, Edit, Write, AskUserQuestion, LSP
---

# /codex-audit - Comprehensive Code Audit via Codex Dialog MCP Server

Uses the `codex-dialog` MCP server to have Codex CLI perform a deep audit of existing code — not changes, but the code as it stands. Reviews architecture, correctness, methodology, potential bugs, unwanted behavior, and more.

## How It Works

1. You read the target files and call `start_dialog` with a structured audit prompt
2. You send the code contents to Codex via `send_message`
3. Codex audits the code and responds with findings
4. You investigate findings, discuss, and fix issues
5. Discussion continues until Codex is satisfied or you escalate to the user

---

## TASK

Audit code: $ARGUMENTS

---

## PHASE 0: DETECT CONTEXT AND GATHER FILES

### Step 0.1: Determine Project Root

```bash
PROJECT_DIR="$(git rev-parse --show-toplevel)"
echo "Project: $PROJECT_DIR"
```

### Step 0.2: Parse Arguments

Parse $ARGUMENTS to determine:
- **targets**: file paths, directory paths, or glob patterns to audit. Can be multiple, space-separated.
- **focus**: if the last argument(s) look like a focus area rather than a path (e.g. "security", "error handling", "concurrency"), treat it as the review focus.

Examples:
- `src/` — audit all source files in src/
- `src/auth.ts src/session.ts` — audit specific files
- `src/api/ security` — audit src/api/ with security focus
- `**/*.py` — audit all Python files

If $ARGUMENTS is empty, use **AskUserQuestion** to ask what files to audit.

### Step 0.3: Collect File Contents

Read all target files. For directories, use Glob to discover files, filtering out:
- `node_modules/`, `dist/`, `build/`, `.git/`, `__pycache__/`, `venv/`
- Binary files, images, lock files
- Files over 500 lines (note them as "skipped — too large, review separately")

Build a manifest of files to send. If the total content exceeds ~40,000 characters, prioritize:
1. Files the user explicitly named
2. Entry points and main modules
3. Files with the most logic (not config/boilerplate)

Note any files that were skipped so Codex knows what it hasn't seen.

---

## PHASE 1: START THE AUDIT DIALOG

Call `start_dialog` with:
- `project_path`: the git project root
- `problem_description`: A brief summary like: "Comprehensive code audit of [target files]. Codex will review for bugs, architecture issues, correctness, and potential problems."

Save the returned `session_id`.

### Step 1.1: Send the Audit Prompt

Use `send_message` to send the code and audit instructions. The message should follow this structure:

```
## Code Audit Request

### Your Audit Stance

ADVERSARIAL AUDIT MODE: Your default assumption is that there are bugs, design flaws, or subtle correctness issues hiding in this code. You are not here to confirm it works — you are here to find what doesn't, what could break, and what was missed. Only accept something as correct once you have actively tried to break it and failed.

For every function, module, and interaction, ask yourself:
- "What input would make this fail?"
- "What state would make this behave unexpectedly?"
- "What was the author probably not thinking about?"
- "What happens under load, concurrency, or partial failure?"
- "What implicit assumptions does this code make that aren't enforced?"
- "If I were trying to cause this system to misbehave, how would I do it?"

You have full access to the project codebase. Read any file you need to understand context, dependencies, and how these files interact with the rest of the system.

### How to Frame Your Findings

Present findings as interesting observations and open questions, not urgent demands. Use language like "I noticed...", "Worth investigating whether...", "This is an interesting case — what happens when...". Frame each finding as a collaborative puzzle to solve together. Be direct and specific, but avoid language that implies urgency or disappointment. If you genuinely find the code to be solid after thorough investigation, say so clearly and explain what you checked — forced criticism is worse than honest approval.

### What to Audit

Examine this code comprehensively for:

**Correctness & Logic**
- Logic errors, off-by-one errors, incorrect conditions
- Unhandled edge cases (null, empty, boundary values, overflow)
- Race conditions, deadlocks, ordering dependencies
- Incorrect error propagation or swallowed errors

**Architecture & Design**
- Coupling between modules that shouldn't know about each other
- Abstraction leaks, broken encapsulation
- Violation of the module's own contract or API promises
- Missing or misleading abstractions
- State management issues (shared mutable state, stale references)

**Robustness & Error Handling**
- Failure modes that aren't handled or are handled incorrectly
- Resource leaks (file handles, connections, memory, event listeners)
- Missing cleanup in error paths
- Partial failure scenarios (what if step 3 of 5 fails?)

**Security**
- Input validation gaps (injection, traversal, overflow)
- Authentication/authorization bypasses
- Information leakage in errors or logs
- Unsafe deserialization or eval-like patterns

**Methodology & Practices**
- Code that's correct now but fragile to future changes
- Implicit ordering dependencies that aren't documented or enforced
- Magic numbers, undocumented assumptions
- Test coverage gaps for critical paths

[USER FOCUS AREA IF SPECIFIED]

### Files to Audit

[FILE CONTENTS HERE — each file prefixed with === path/to/file.ext ===]

[LIST OF SKIPPED FILES IF ANY]

### Response Format

For each finding, categorize as:
- [CRITICAL] — bugs, security issues, data loss risk
- [ARCHITECTURE] — design problems, coupling, abstraction issues
- [CORRECTNESS] — logic errors, edge cases, race conditions
- [ROBUSTNESS] — error handling, resource management, failure modes
- [SECURITY] — vulnerabilities, input validation, auth issues
- [SUGGESTION] — improvements, better patterns, maintainability
- [QUESTION] — needs investigation or clarification

For each finding, include:
1. The specific file and location
2. What you found
3. Why it matters (what could go wrong)
4. What you checked to verify this is a real issue

At the end, give an overall assessment of the code's health.
```

---

## PHASE 2: POLL FOR INITIAL AUDIT

Poll with `check_messages`:
- Pass `session_id` and `since_id` (the id of the message you just sent)
- If `codex_currently_processing` is true and no new messages, wait ~10 seconds and poll again
- Keep polling until you get a response from Codex
- Audits can take longer than diff reviews — be patient (up to 10 minutes)

Read the audit carefully once it arrives.

---

## PHASE 3: AUDIT DISCUSSION LOOP

For each round (max 5 rounds or until Codex is satisfied):

### Step 3.1: Investigate Findings

**Treat each finding as useful signal, not pressure.** Codex's job is to be adversarial — to assume something is wrong and try to prove it. Many findings will reveal real issues, but some will be false positives. Both outcomes are valuable. There is no urgency.

For each finding Codex raised:
1. **Read the actual code** at the location mentioned. Use LSP for go-to-definition, find-references, type information to trace the full picture.
2. **Understand before reacting.** Make sure you understand what Codex is actually claiming before deciding whether it's valid.
3. Determine if the finding is VALID, PARTIALLY VALID, or INVALID.
4. If VALID: fix the issue in the code, then describe what you fixed and why the fix is correct.
5. If INVALID: explain why with specific evidence — file paths, line numbers, the actual logic that handles the case.

**If a fix attempt fails:**
- A failed fix is useful information, not a failure on your part.
- Before trying again, analyze *why* it failed. What assumption was wrong?
- After 2 failed attempts at the same fix, stop and re-examine from scratch.
- Never write code whose primary purpose is making a problem go away rather than solving the underlying issue.

### Step 3.2: Send Your Response

Use `send_message` to respond with:
- What you fixed and how (with enough detail for Codex to verify)
- What you disagree with and why (with code evidence)
- What you found surprising or insightful
- Any follow-up areas you'd like Codex to look at based on what you've learned

**You have full permission to disagree with Codex.** Honest technical disagreement backed by evidence is more valuable than agreeing to move forward.

### Step 3.3: Poll for Follow-up

Poll with `check_messages` until Codex responds.

Codex will:
- Verify fixes look correct
- Accept or push back on disagreements
- Raise follow-up issues if fixes introduced new concerns
- Give a final assessment when satisfied

### Step 3.4: Check Completion

If Codex indicates the audit is complete (no more findings, or remaining issues acknowledged), go to Phase 4.

Otherwise, continue the loop.

**If there's persistent disagreement (2+ rounds on the same issue):** Ask the user to decide using AskUserQuestion.

---

## PHASE 4: COMPLETION

Report results:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 CODEX CODE AUDIT  COMPLETE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 Files Audited: [count] ([list])
 Discussion Rounds: [count]
 Findings: [X critical, Y architecture, Z correctness, ...]
 Fixes Applied: [count]
 Session: [session_id]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Call `end_dialog` to clean up the session.

---

## TROUBLESHOOTING

- **Codex not responding:** Use `check_partner_alive` to check runner status.
- **Runner died:** Start a new dialog with `start_dialog`.
- **Too many files:** Break the audit into multiple sessions by directory or module.
- **Want full context:** Use `get_full_history` for the complete conversation.

---

## KEY PRINCIPLES

1. **Use the MCP tools** — all communication goes through the codex-dialog server
2. **Poll patiently** — comprehensive audits take time (up to 10 min per turn)
3. **Fix in code, explain in message** — make actual fixes, then tell Codex what you did
4. **Evidence-based** — back up agreements AND disagreements with actual code
5. **User is arbiter** — when you and Codex can't agree, ask the user
6. **Findings are signal, not pressure** — each finding is information to investigate, not a demand to rush
7. **Honest over agreeable** — if Codex is wrong, say so with evidence. If Codex is right, fix it properly
8. **Depth over breadth** — a thorough audit of fewer files beats a shallow scan of everything
