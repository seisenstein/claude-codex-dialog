# /codex-review-spec — Codex-Driven Feature Spec Review

**Status:** Draft
**Author:** Product Manager (AI-assisted)
**Date:** 2026-04-19
**Effort estimate:** Small (1–4 hours)
**Implementation approach:** Solo agent

## Summary

Add a fourth Codex review command — `/codex-review-spec` — that runs an adversarial
spec-quality review on a product/feature specification document (the kind produced by the
`product-manager` skill). It reuses the existing `codex-dialog` MCP server and the same
round-budget mechanics as `/codex-review-plan`, but targets a different artifact:
product specs (the WHAT/WHY) rather than implementation plans (the HOW) or code (the RESULT).
The value is catching ambiguity, missing flows, untestable acceptance criteria, and
scope-creep **before** the spec gets handed to a coding agent or C3 orchestrator.

## User Stories

```
As a product manager, I want Codex to adversarially review my spec before I hand it to
engineering so that ambiguities and gaps get caught when they're cheap to fix.

As a developer using the product-manager skill, I want one command that verifies a spec is
complete and testable so that implementation doesn't stall on "wait, what does this mean?"
clarifications.

As a C3 conductor, I want a spec that has survived adversarial review so that parallel
tracks don't drift from incompatible interpretations of underspecified behavior.
```

## User Flow

### Happy path

1. User runs `/codex-review-spec` (optionally with a path and/or `rounds:N`).
2. Command auto-detects the spec file if not passed (see detection order below), reads it,
   and calls `start_dialog` with a spec-review system prompt.
3. Codex reads the spec *and* relevant codebase context (integration points named in the
   spec), then returns an adversarial review organized by finding category.
4. Claude Code investigates each finding (reading the spec, reading the codebase where
   relevant) and sends a consolidated response that either edits the spec, disagrees with
   evidence, or acknowledges.
5. Loop continues until Codex returns `APPROVE` or the hard round cap hits.
6. Command prints a completion block and calls `end_dialog`.

### Alternate flows

- **Path passed explicitly:** `/codex-review-spec docs/specs/foo.md` skips auto-detection.
  This is the preferred invocation when the caller already knows the path — e.g. when
  Claude just finished producing the spec via the `product-manager` skill in the same
  session. The command doc should explicitly guide callers: *"If you just wrote the spec
  and know the path, pass it as an argument — do not rely on auto-detection."*
- **Round budget override:** `/codex-review-spec rounds:3` passes `max_rounds` to the
  server; without the token, `max_rounds` is omitted and the server default (5) applies.
  Mirrors the exact parsing rules used by `/codex-review-plan`.
- **Multiple spec candidates found:** if auto-detection returns multiple plausible files,
  ask the user via `AskUserQuestion` which one to review. Never silently pick.
- **Persistent disagreement (2+ rounds on the same issue):** escalate to the user via
  `AskUserQuestion` with both positions summarized — same pattern as plan/code review.

### Error flows

- **No spec found and no path passed:** use `AskUserQuestion` to request the path rather
  than guessing.
- **Monitor timeout with no event:** call `check_partner_alive`; if the runner died,
  restart with a fresh `start_dialog`; inspect `~/.claude/dialogs/<SESSION_ID>/last_error.txt`.
- **Spec file is empty / not markdown:** abort with a clear message; don't start a dialog.
- **Hard cap reached:** report the partial result honestly (findings raised, findings
  resolved, findings open) and end the dialog. Don't fabricate approval.

## UI/UX Specification

### Layout

Pure CLI slash command — no UI surface. Output style matches `/codex-review-plan` exactly:
a completion banner at the end with session id, verdict, rounds used, and whether the spec
file was updated.

### States

- **Startup:** prints detected spec path + `session_id`.
- **Waiting on Codex:** silent while the Monitor is armed (no polling chatter).
- **Per round:** short summary of what was agreed/disagreed/edited.
- **Completion:** banner block identical in structure to `/codex-review-plan`'s completion
  block (see *Acceptance Criteria*).

### Interactions

No mouse/keyboard interactivity beyond the slash command invocation and any
`AskUserQuestion` prompts raised during escalation. Pure conversational flow.

## Data Model

No new data model. Reuses the existing `codex-dialog` session format stored under
`~/.claude/dialogs/<session_id>/` (conversation.jsonl + metadata files). No schema change
to the MCP server.

## API Specification

No new MCP tools. Uses the existing tool surface of the `codex-dialog` server:

- `start_dialog` — with a spec-review `problem_description` (see *Prompt*).
- `send_message` / `check_messages` / `get_full_history` / `check_partner_alive` /
  `end_dialog` / `list_sessions` — same as the other review commands.
- `Monitor` on `~/.claude/dialogs/<SESSION_ID>/conversation.jsonl` using
  `tail -F -n 0 ... | grep -m 1 ... '"from":"(codex|system)"'` — identical wake-up signal
  to the existing commands.

### Spec-review prompt (the key artifact)

The `problem_description` Codex receives is the only thing that meaningfully differs from
`/codex-review-plan`. It must include:

**1. Adversarial stance, spec-flavored:**

> ADVERSARIAL SPEC REVIEW MODE: Your default assumption is that this spec has gaps,
> ambiguous requirements, untestable acceptance criteria, or flows that fall apart at the
> edges. You are not here to confirm the spec is good — you are here to find what's
> missing, unclear, or inconsistent. A coding agent will implement directly from this
> document; anything ambiguous becomes an arbitrary decision downstream. Assume every
> ambiguity will be resolved in the wrong direction.
>
> For every section, ask:
> - "Could two engineers read this and build meaningfully different things?"
> - "What happens on the error path this spec doesn't mention?"
> - "Is this acceptance criterion something I could write a test for, or is it opinion?"
> - "Does the claimed integration point actually exist in the codebase?"
> - "What user need is being asserted without evidence?"
> - "What's in v1 that should be in v2 — is the scope cut honest?"

**2. Severity bar + feedback framing** (identical language to `/codex-review-plan` for
consistency — collaborative tone, honest approval when warranted, no forced criticism).

**3. Review dimensions specific to specs:**

- **Completeness** — all user flows covered? error/empty/loading states specified?
- **Clarity / Ambiguity** — is every requirement unambiguous? Could two readers diverge?
- **Testability** — are acceptance criteria framed as testable statements?
- **Scope hygiene** — is v1 honestly bounded? Any feature creep smuggled in as "while we're
  at it"?
- **Data-model coherence** — do entities, fields, and relationships hang together?
  Any implied-but-unstated foreign keys?
- **UX soundness** — does the described flow actually solve the stated user problem? Any
  steps that feel tacked on?
- **Feasibility sanity** — does the codebase actually support the claimed integration
  points? (This is a sanity check, not a deep technical review — that's `/codex-review-plan`'s job.)
- **Alignment** — does the feature as described match the stated user stories? Are any
  stories unserved by the flow?

**4. Finding taxonomy (spec-specific, do not inflate categories):**

- `[GAP]` — missing requirement, flow, state, or acceptance criterion.
- `[AMBIGUITY]` — requirement that two readers would interpret differently.
- `[SCOPE]` — v1/v2 boundary issue or unstated scope creep.
- `[FEASIBILITY]` — assumes something the codebase doesn't support (caught at spec time,
  not plan time).
- `[UX]` — flow or state design problem.
- `[TESTABILITY]` — acceptance criterion that isn't testable as written.
- `[SUGGESTION]` — concrete improvement with demonstrable benefit; not a stylistic tweak.
- `[QUESTION]` — genuinely needs clarification; used sparingly.
- `[PRAISE]` — optional; call out a design decision genuinely worth keeping.
- `[NIT]` — cosmetic / wording. Group into one trailing section or omit entirely.

**5. Verdict at the end of each Codex turn:** `APPROVE` / `NEEDS_DISCUSSION` /
`MAJOR_CONCERNS` — identical keywords to `/codex-review-plan` so the loop-exit check is
literally one string check (`"APPROVE"`).

**6. Full spec content** wrapped in `<spec>...</spec>` tags at the end of the prompt.

## Acceptance Criteria

Testable statements. These drive the implementation check at the end.

- [ ] Given a project with a spec file at `docs/specs/foo.md`, when I run
  `/codex-review-spec`, then the command auto-detects `foo.md` and starts a dialog.
- [ ] Given an explicit path argument (e.g. `/codex-review-spec docs/specs/foo.md`),
  when the command runs, then auto-detection is skipped and the argument path is used
  directly — even if other spec files exist that would otherwise be detected.
- [ ] Given multiple candidate spec files, when auto-detection runs, then
  `AskUserQuestion` is invoked to disambiguate (no silent pick).
- [ ] Given no spec file found and no path argument, when I run `/codex-review-spec`,
  then `AskUserQuestion` asks for the path rather than erroring out.
- [ ] Given `rounds:N` in the arguments, when the command calls `start_dialog`, then
  `max_rounds=N` is passed; otherwise `max_rounds` is omitted.
- [ ] Given Codex returns a message containing `APPROVE`, when Claude's loop-exit check
  runs, then the loop ends and Phase 4 (completion banner) executes.
- [ ] Given Codex returns `MAJOR_CONCERNS` or `NEEDS_DISCUSSION`, when the budget has
  remaining rounds, then Claude continues the loop.
- [ ] Given a finding is resolved by editing the spec file, when Claude sends its
  response, then the response includes what changed in the spec (not just agreement).
- [ ] Given the same issue persists across 2+ rounds with unresolved disagreement, when
  Claude detects it, then `AskUserQuestion` is invoked to let the user arbitrate.
- [ ] Given the hard cap is reached, when the command ends, then the completion banner
  reports "MAX ROUNDS" rather than claiming approval.
- [ ] Given the install script runs, when the user has `codex` on PATH, then
  `codex-review-spec.md` is installed at `~/.claude/commands/codex-review-spec.md` and the
  uninstall script removes it.
- [ ] Given the README describes installed commands, when the user reads it, then
  `/codex-review-spec` is listed alongside the other three with a usage example.

## Scope Boundaries

### In scope (v1)

- New slash command `/codex-review-spec` with path auto-detection + `rounds:N` override.
- Spec-flavored adversarial prompt with the finding taxonomy defined above.
- Auto-detection of spec files in `docs/specs/`, `.claude/specs/`, `specs/`, and root
  `spec*.md` / `SPEC.md`.
- Install + uninstall script updates.
- README update with usage examples.
- Identical round-budget / Monitor-based waiting mechanics to the other three commands.

### Out of scope (v1)

- **New MCP tools.** Reuse the existing `start_dialog` / `send_message` / etc. entirely.
  No server-side changes.
- **Dedicated spec schema or validation.** We are not parsing spec structure; we're
  feeding it as markdown to Codex. If spec structure validation is useful later, it's a
  separate feature.
- **Tight integration with the `product-manager` skill.** The skill can *mention* that
  `/codex-review-spec` exists as a next step, but we're not auto-invoking it at the end of
  product-manager. A manual handoff keeps concerns separate.
- **Multi-spec batch review.** One spec per invocation. Batch is speculative and would
  burn the round budget unpredictably.
- **Spec file templates.** The `product-manager` skill already owns the template
  (`references/spec-template.md`). We review whatever markdown the user points at,
  template-conformant or not.

## Implementation Plan

### Task breakdown

1. **Author `codex-review-spec.md` command file**  (parallelizable: no — sequential, one file)
   - Location: `.claude/commands/codex-review-spec.md`
   - Base it on `.claude/commands/codex-review-plan.md` (closest structural analog).
   - Change: the Phase-0 auto-detection search paths (spec locations, not plan locations).
   - Change: the Phase-1 `problem_description` content (spec-flavored prompt, new
     finding taxonomy, spec review dimensions).
   - Change: the completion banner label from `CODEX PLAN REVIEW` to `CODEX SPEC REVIEW`.
   - Keep: Monitor mechanics, round-budget language, escalation-to-user pattern,
     APPROVE/NEEDS_DISCUSSION/MAJOR_CONCERNS verdict keywords.

2. **Update `install.sh`** (parallelizable: yes, with task 3)
   - Add a `cp` line for `codex-review-spec.md` to `$COMMANDS_DIR`.
   - Add `/codex-review-spec` to the post-install usage echo.

3. **Update `uninstall.sh`** (parallelizable: yes, with task 2)
   - Add a block that removes `$COMMANDS_DIR/codex-review-spec.md` if present.

4. **Update `README.md`** (parallelizable: yes, with tasks 2–3)
   - Add `/codex-review-spec` to the install blurb ("installs the
     `/codex-review-code`, `/codex-review-plan`, `/codex-review-spec`, and `/codex-audit`
     slash commands globally").
   - Add a usage block with 2–3 examples mirroring the plan block:
     ```
     /codex-review-spec                         Review an auto-detected spec file
     /codex-review-spec docs/specs/foo.md       Review a specific spec file
     /codex-review-spec rounds:3                Review with a tighter 3-round budget
     ```
   - Add a bullet to the Features list: *Spec Review — Codex adversarially reviews a
     product/feature specification for gaps, ambiguity, scope creep, and untestable
     acceptance criteria before a plan or code gets written*.

5. **Manual smoke test** (sequential, final)
   - Run `./install.sh` and confirm `/codex-review-spec` shows up in Claude Code.
   - Run `/codex-review-spec docs/specs/codex-review-spec.md` against this spec itself as
     a dog-food test.
   - Confirm Codex returns findings, round-budget works, completion banner prints.

### Key files to modify

| File | Change |
|---|---|
| `.claude/commands/codex-review-spec.md` | New file. Forked from `codex-review-plan.md`. |
| `install.sh` | Add `cp` + usage echo line. |
| `uninstall.sh` | Add `rm` block. |
| `README.md` | Features bullet, install blurb, usage examples. |

### Migrations / infrastructure

None. No server code changes, no schema changes, no new dependencies. The server already
exposes everything the command needs.

### Testing strategy

- **Unit tests:** N/A — the command is a markdown prompt file, not executable code. The
  MCP server that backs it already has whatever coverage it has.
- **Integration test:** dog-food by running the command against this spec file itself,
  which doubles as an acceptance-criteria check (see task 5).
- **Regression check:** confirm `/codex-review-plan`, `/codex-review-code`, `/codex-audit`
  still work unchanged after install — the new command should be purely additive.

## Handoff Notes

### Suggested order of operations

1. Write `codex-review-spec.md` (forked from `codex-review-plan.md`).
2. Update install/uninstall in parallel.
3. Update README.
4. Reinstall + smoke test.

### What can be parallelized

Steps 2–4 can all run concurrently once step 1 is done — they touch different files. A
single agent can do the whole thing in one session comfortably; C3 would be overkill for
this scope (small feature, shared context).

### Gotchas to watch for

- **Prompt drift between the three review commands.** The adversarial-stance, feedback-
  framing, and round-budget paragraphs are near-identical across plan/code/audit. Keep
  `/codex-review-spec`'s versions consistent with `codex-review-plan.md` so a future
  refactor can extract a shared block.
- **Finding taxonomy must not silently overlap with plan-review.** `[GAP]` and
  `[AMBIGUITY]` replace `[CRITICAL]` as the dominant category here — spec problems are
  rarely "critical" in the code sense; they're underspecification. Do not copy the plan
  taxonomy verbatim.
- **`APPROVE` keyword check.** The loop exits on a literal `"APPROVE"` substring match
  (same as plan review). Do not use `APPROVED` or any variant in the prompt, or the loop
  will miss the exit signal.
- **Auto-detection order matters.** Search `docs/specs/*.md` and `.claude/specs/*.md`
  before `spec*.md` / `SPEC.md` at the repo root — the former are the canonical locations
  used by the `product-manager` skill; the latter are fallbacks.
- **Don't inject `max_rounds`.** Only pass `max_rounds` when the user explicitly supplied
  `rounds:N`. This matches the existing commands' tuned default (5) and the comment in
  each command about *never* inventing this value.

---

## Changelog

| Date | Change | Author |
|------|--------|--------|
| 2026-04-19 | Initial draft | PM (AI-assisted) |
