---
description: Have Codex review an implementation plan via the codex-dialog MCP server
argument-hint: [optional: path/to/plan.md]
allowed-tools: mcp__codex-dialog__start_dialog, mcp__codex-dialog__check_messages, mcp__codex-dialog__send_message, mcp__codex-dialog__get_full_history, mcp__codex-dialog__check_partner_alive, mcp__codex-dialog__end_dialog, mcp__codex-dialog__list_sessions, Bash, Read, Glob, Grep, Edit, Write, AskUserQuestion, LSP
---

# /codex-review-plan - Plan Review via Codex Dialog MCP Server

Uses the `codex-dialog` MCP server to have Codex CLI review an implementation plan interactively.

## How It Works

1. You read the plan file and call `start_dialog` with a structured review prompt
2. Codex reviews the plan and responds with findings
3. You poll with `check_messages` to read the review
4. You investigate findings in the codebase, respond via `send_message`
5. Discussion continues until Codex approves or you escalate to the user

---

## TASK

Review plan: $ARGUMENTS

---

## PHASE 0: DETECT CONTEXT

### Step 0.1: Find the Plan File

**If $ARGUMENTS contains a file path**, use it directly.

**If $ARGUMENTS is empty**, auto-detect:
```bash
PROJECT_DIR="$(git rev-parse --show-toplevel)"
echo "Project: $PROJECT_DIR"
git branch --show-current
```

Search for plan files in the project:
```bash
ls -t "$PROJECT_DIR"/.codex-reviews/*/plan-v*.md 2>/dev/null | head -5
ls -t "$PROJECT_DIR"/plan*.md "$PROJECT_DIR"/PLAN.md "$PROJECT_DIR"/.claude/plan*.md 2>/dev/null | head -5
```

If no plan found, use **AskUserQuestion** to ask the user for the path.

### Step 0.2: Read the Plan

Read the plan file contents. You'll include this in the dialog prompt.

---

## PHASE 1: START THE REVIEW DIALOG

Call `start_dialog` with:
- `project_path`: the git project root
- `problem_description`: a structured prompt — see below

The `problem_description` must include the full plan content AND the adversarial review instructions:

```
## Plan Review Request

### Your Review Stance

ADVERSARIAL REVIEW MODE: Your default assumption is that this plan has gaps, incorrect assumptions, or will fail in ways the author hasn't anticipated. You are not here to confirm the plan is good — you are here to find what's wrong with it. Only accept a part of the plan as sound once you have actively tried to poke holes in it and failed.

For every step in the plan, ask yourself:
- "What happens if this assumption is wrong?"
- "What dependency is being taken for granted here?"
- "What's the failure mode the author probably hasn't considered?"
- "Is there a simpler way to achieve this that was overlooked?"
- "Does the codebase actually support what this plan assumes?"

Read the actual codebase to verify claims. Do not take the plan's description of the current state at face value — check it.

### How to Frame Your Feedback

Present findings as interesting observations and open questions, not urgent demands. Use language like "I noticed...", "Worth investigating whether...", "This is an interesting case — what happens when...", "I checked the codebase and found that actually...". 

Frame each finding as a collaborative puzzle to solve together, not a failure on the author's part. Be direct and specific about what you found, but avoid language that implies the author was careless or should have caught this. The goal is to produce the best possible plan, and that happens when the discussion feels like two engineers thinking through a problem together.

If you genuinely find the plan to be solid after thorough investigation, say so clearly and explain what you checked — forced criticism is worse than honest approval.

### Review Dimensions

Examine the plan for:
- **Feasibility** — can this actually be built as described? Does the codebase support it?
- **Completeness** — are there missing steps, edge cases, or dependencies?
- **Correctness** — are the technical assumptions sound? Verify against actual code.
- **Risk** — what could go wrong? What's underestimated?
- **Alternatives** — are there simpler or better approaches the plan missed?
- **Ordering** — are the steps in the right order? Are there hidden dependencies between steps?

You have access to the full project codebase at the project_path. Read relevant files to verify assumptions made in the plan.

### The Plan

<plan>
[FULL PLAN CONTENT HERE]
</plan>

### Response Format

For each significant finding, categorize as:
- [CRITICAL] — plan is flawed or will fail
- [SUGGESTION] — improvement that would strengthen the plan
- [QUESTION] — needs clarification or investigation
- [PRAISE] — good decisions worth noting

At the end, give an overall verdict:
- **APPROVE** — plan is solid, proceed with implementation
- **NEEDS_DISCUSSION** — some issues need resolution first
- **MAJOR_CONCERNS** — significant problems that must be addressed
```

Save the returned `session_id`.

Then use `send_message` to send the plan review prompt as your first message to kick off the dialog.

---

## PHASE 2: POLL FOR INITIAL REVIEW

Poll with `check_messages`:
- Pass `session_id` and `since_id: 0`
- If `codex_currently_processing` is true and no new messages, wait ~10 seconds and poll again
- Keep polling until you get a response from Codex

Read the review carefully once it arrives.

---

## PHASE 3: DISCUSSION LOOP

For each round (max 5 rounds or until APPROVE):

### Step 3.1: Investigate Findings

**Treat each finding as useful signal, not pressure.** Codex's job is to be adversarial — to assume the plan has problems and try to prove it. That means many findings will reveal real gaps, but some will be based on misunderstandings of the codebase or the plan's intent. Both outcomes are valuable. There is no urgency.

For each finding Codex raised:
1. **Read the actual codebase** at locations mentioned — use LSP for go-to-definition, find-references, etc.
2. **Understand before reacting.** Before deciding whether a finding is valid, make sure you understand what Codex is actually claiming. Re-read the finding. Re-read the relevant code. Check surrounding context.
3. Determine: AGREE / PARTIALLY AGREE / DISAGREE
4. Provide evidence from actual code (file paths, line numbers, snippets)

**If you're struggling with a finding:**
- That's useful information — it may mean the finding has identified genuine complexity in the plan.
- Before responding, write a brief analysis of what makes this hard. What are the competing constraints?
- After 2 attempts to resolve the same finding, step back. Re-read the plan section in question and the finding side by side. The resolution may require rethinking the plan's approach, not just tweaking it.
- Never dismiss a finding just because it's hard to address. If Codex found a real problem, the plan needs to account for it even if the answer isn't obvious.

### Step 3.2: Respond and Update Plan

Use `send_message` to respond with:
- Your verdict on each finding, with code evidence
- If you agree: describe how the plan should change and make the edit
- If you disagree: explain why with references to actual code

**You have full permission to disagree with Codex.** If a finding doesn't hold up after investigation, say so directly and explain why. Honest technical disagreement, backed by evidence, is more valuable than agreeing just to move forward.

If findings warrant plan changes, update the plan file and mention what changed in your response.

### Step 3.3: Poll for Follow-up

Poll with `check_messages` (using the latest `since_id`) until Codex responds.

Codex will:
- Accept or push back on your responses
- Raise follow-up concerns
- Say **APPROVE** when satisfied

### Step 3.4: Check Verdict

If Codex's response contains "APPROVE", the review is complete — go to Phase 4.

Otherwise, continue the loop.

**If there's persistent disagreement (2+ rounds on the same issue):** Ask the user to decide using AskUserQuestion. Frame it neutrally: present both positions with the evidence each side has, and let the user make the call. This is a normal and healthy outcome — it means the review process is working.

---

## PHASE 4: COMPLETION

Report results:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 CODEX PLAN REVIEW  COMPLETE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 Plan: [plan file path]
 Verdict: [APPROVED / IN PROGRESS / MAX ROUNDS]
 Discussion Rounds: [count]
 Plan Updated: [yes/no]
 Session: [session_id]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Call `end_dialog` to clean up the session.

---

## TROUBLESHOOTING

- **Codex not responding:** Use `check_partner_alive` to check if the runner is still running.
- **Runner died:** Start a new dialog with `start_dialog`.
- **Want full context:** Use `get_full_history` for the complete conversation.
- **Multiple sessions:** Use `list_sessions` to see all active/completed sessions.

---

## KEY PRINCIPLES

1. **Use the MCP tools** — all communication goes through the codex-dialog server
2. **Poll patiently** — Codex needs time to read the codebase and review (up to 5 min per turn)
3. **Evidence-based** — verify every finding against actual code before agreeing or disagreeing
4. **Update the plan** — if findings are valid, actually fix the plan file
5. **User is arbiter** — when you and Codex can't agree, ask the user
6. **Findings are signal, not pressure** — each finding is information to investigate, not a demand to rush. Take the time to understand before acting. A thoughtful response is always better than a fast one.
7. **Honest over agreeable** — if Codex is wrong, say so with evidence. If Codex is right, update the plan properly. Never make a superficial plan edit just to resolve a finding.
