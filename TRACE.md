# Upstream sync trace

This file records **reasoning from upstream syncs**, not general development
history and not the child's current upstream position. Current position comes
only from Git (`sync-*` tags and `git merge-base upstream/main main`).

Why it exists:

- make non-obvious conflict and ablation decisions understandable later;
- preserve techniques that worked and may help with a similar future conflict;
- record assumptions, risks, and evidence when parity alone is not explanatory.

Entries are evidence, **not permanent law**. A later failure may prove a choice
wrong; challenge and revise it. Reusing a technique from an older entry still
requires checking that the code and model assumptions match.

Do not record routine child-local development here (`fix`, `perf`, new features):
Git history, PRs, and issues cover those. Add one entry per upstream sync. For
a fully automatic/routine sync, a short entry saying so is enough.

---

<!-- Copy this block for each sync, newest first. Keep it factual and short. -->

## sync-<upstream-sha7> — <YYYY-MM-DD>

- **Upstream range:** `<previous-upstream-sha>..<target-upstream-sha>`
- **Scope:** <what the upstream commits changed and whether this child uses it>
- **PR:** <URL or `not opened yet`>

### Decisions

- `<file:line or symbol>`
  - Upstream intent: <what upstream was trying to change>
  - Child decision: <kept / adapted / dropped>
  - Reason: <model/backend/feature invariant or test evidence>
  - Revisit if: <condition that would make this decision questionable>

Use `None — clean/rerere-only sync` when there was no manual decision.

### Reusable techniques

- <technique that worked, why it worked, and the assumptions required>

Use `None` when there is no reusable lesson. Do not present a technique as a
universal rule.

### Verification

- `make test`: <pass/fail>
- Model-backed tests: <commands and result>
- Parity oracle: <token result; speed delta>
- Known gaps: <anything not exercised>
