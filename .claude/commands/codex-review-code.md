---
description: Have Codex review your code changes via the codex-dialog MCP server
argument-hint: [optional: diff_target (uncommitted|staged|branch|commit:<sha>)] [optional: review focus]
allowed-tools: mcp__codex-dialog__start_code_review, mcp__codex-dialog__check_messages, mcp__codex-dialog__send_message, mcp__codex-dialog__get_review_summary, mcp__codex-dialog__get_full_history, mcp__codex-dialog__check_partner_alive, mcp__codex-dialog__end_dialog, mcp__codex-dialog__list_sessions, Bash, Read, Glob, Grep, Edit, Write, AskUserQuestion, LSP
---

# /codex-review-code - Code Review via Codex Dialog MCP Server

Uses the `codex-dialog` MCP server to have Codex CLI review your code changes interactively.

## How It Works

1. You call `start_code_review` which generates a diff and spawns a background Codex runner
2. Codex **automatically generates an initial review** from the diff (no first message needed)
3. You poll with `check_messages` to read the review
4. You respond to findings with `send_message`, discussing or fixing issues
5. Codex re-reviews and responds until it says "LGTM" or you end the session

---

## TASK

Review code: $ARGUMENTS

---

## PHASE 0: DETECT CONTEXT

Determine the project path:
```bash
PROJECT_DIR="$(git rev-parse --show-toplevel)"
echo "Project: $PROJECT_DIR"
git branch --show-current
```

Parse $ARGUMENTS to determine:
- **diff_target**: first arg if it matches `uncommitted`, `staged`, `branch`, or `commit:<sha>`. Default: `uncommitted`
- **review_focus**: remaining text after diff_target, if any (e.g. "security", "performance", "correctness")

If $ARGUMENTS is empty, use `uncommitted` as the diff target with no specific focus.

---

## PHASE 1: START THE REVIEW

Call `start_code_review` with:
- `project_path`: the git project root
- `diff_target`: parsed from arguments (default: `uncommitted`)
- `review_focus`: Always prepend the adversarial review stance to whatever focus the user specified. The `review_focus` string should begin with the following, then append the user's focus (if any):

```
ADVERSARIAL REVIEW MODE: Your default assumption is that something is wrong, missing, or subtly broken in this code. You are not looking to confirm it works — you are looking to find what doesn't. Only accept something as correct once you have actively tried to break it and failed. For every function, ask: "What input would make this fail? What state would make this behave unexpectedly? What was the author probably not thinking about?" Check edge cases, error paths, concurrency, resource cleanup, and implicit assumptions. If you cannot find a flaw, explain what you checked and why you believe it holds — do not simply say it looks fine.

FEEDBACK FRAMING: When you report findings, frame them as interesting observations and open questions, not urgent demands. Use language like "I noticed...", "Worth investigating whether...", "This is an interesting case — what happens when...". Present each finding as a collaborative puzzle to solve together, not a failure to be fixed under pressure. Be direct and specific about what you found, but avoid language that implies urgency, disappointment, or that the author should have caught this. The goal is to produce the most thorough and accurate review possible, and that works best when the discussion feels like two engineers working through a problem together rather than an interrogation. If you genuinely find nothing wrong after thorough investigation, say so clearly — forced criticism is worse than honest approval.
```

- `branch` / `base_branch`: only if diff_target is `branch`

Save the returned `session_id` — you need it for all subsequent calls.

The response will confirm the review started and tell you to poll.

---

## PHASE 2: POLL FOR INITIAL REVIEW

Codex is generating the initial review in the background. Poll with `check_messages`:
- Pass `session_id` and `since_id: 0`
- If `codex_currently_processing` is true and no new messages, wait ~10 seconds and poll again
- Keep polling until you get a message from Codex

Once you receive the initial review, read it carefully. The review will contain findings categorized as:
- **[CRITICAL]** — bugs, security issues (must address)
- **[SUGGESTION]** — improvements (discuss or fix)
- **[QUESTION]** — needs clarification (answer)
- **[PRAISE]** — good patterns (acknowledge)

---

## PHASE 3: REVIEW DISCUSSION LOOP

For each round (max 5 rounds or until LGTM):

### Step 3.1: Investigate and Respond to Findings

**Treat each finding as useful signal, not pressure.** Codex's job is to be adversarial — to assume something is wrong and try to prove it. That means many findings will be real issues worth fixing, but some will be false positives that you can refute with evidence. Both outcomes are valuable. There is no urgency.

For each finding Codex raised:
1. **Read the actual code** at the location mentioned. Use LSP for go-to-definition and find-references to trace the full picture.
2. **Understand before reacting.** Before deciding whether a finding is valid, make sure you understand what Codex is actually claiming. Re-read the finding. Re-read the code. Check the surrounding context.
3. Determine if the finding is VALID, PARTIALLY VALID, or INVALID.
4. If VALID: fix the issue in the code, then describe what you fixed and why the fix is correct.
5. If INVALID: explain why with specific evidence from the code. Reference file paths, line numbers, and the actual logic that handles the case Codex raised.

**If a fix attempt fails:**
- A failed fix is useful information about the problem, not a failure on your part.
- Before trying again, write a brief analysis of *why* it failed. What assumption was wrong?
- After 2 failed attempts at the same fix, stop and re-examine the finding from scratch. The issue may be different from what you initially thought, or the finding itself may be based on a misunderstanding.
- Never write code whose primary purpose is making a problem go away rather than solving the underlying issue. A correct solution that takes longer is always preferred over a fast patch.

### Step 3.2: Send Your Response

Use `send_message` to send your response to Codex. Include:
- What you fixed and how (with enough detail that Codex can verify)
- What you disagree with and why (with code evidence — file paths, line numbers, logic traces)
- Answers to any questions
- If you found the finding insightful and it revealed something you hadn't considered, say so — it helps Codex calibrate

**You have full permission to disagree with Codex.** If a finding doesn't hold up after investigation, say so directly and explain why. Honest technical disagreement, backed by evidence, is more valuable than agreeing just to move forward.

### Step 3.3: Poll for Codex Follow-up

Poll with `check_messages` (using the latest `since_id`) until Codex responds.

Codex will:
- Verify your fixes look correct
- Accept or push back on disagreements
- Say "LGTM" when all significant issues are resolved

### Step 3.4: Check for LGTM

If Codex's response contains "LGTM", the review is complete — go to Phase 4.

Otherwise, continue the loop with the next round.

**If there's persistent disagreement (2+ rounds on the same issue):** Ask the user to decide using AskUserQuestion. Frame it neutrally: present both positions with the evidence each side has, and let the user make the call. This is a normal and healthy outcome — it means the review process is working.

---

## PHASE 4: COMPLETION

Call `get_review_summary` to get the final state, then report:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 CODEX CODE REVIEW  COMPLETE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 Verdict: [APPROVED / IN PROGRESS / MAX ROUNDS]
 Review Rounds: [count]
 Findings: [X critical, Y suggestions, Z questions]
 Session: [session_id]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Call `end_dialog` to clean up the session.

---

## TROUBLESHOOTING

- **Codex not responding:** Use `check_partner_alive` to check if the runner process is still running. Check `last_error` in the response.
- **Runner died:** Start a new review with `start_code_review`.
- **Want to see everything:** Use `get_full_history` to get the complete conversation and diff metadata.
- **Multiple reviews:** Use `list_sessions` to see all active/completed sessions.

---

## KEY PRINCIPLES

1. **Use the MCP tools** — all communication goes through the codex-dialog server
2. **Poll patiently** — Codex reviews take time, especially on large diffs (up to 10 min per turn)
3. **Fix in code, explain in message** — make actual fixes, then tell Codex what you did
4. **Evidence-based** — back up agreements AND disagreements with actual code
5. **User is arbiter** — when you and Codex can't agree, ask the user
6. **Findings are signal, not pressure** — each finding is information to investigate, not a demand to rush. Take the time to understand before acting. A thoughtful response is always better than a fast one.
7. **Honest over agreeable** — if Codex is wrong, say so with evidence. If Codex is right, fix it properly. Never patch something superficially just to resolve a finding.
