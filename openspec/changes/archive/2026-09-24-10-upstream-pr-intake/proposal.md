# Proposal

## Why

Performance work in this child now borrows from upstream ds4 pull requests that
are not merged. Neither git nor OpenSpec records which PRs were analyzed, up to
which head commit, or what was decided per commit, so a later review cannot tell
new PRs and new commits on old PRs from work already judged.

## What Changes

- Add `docs/upstream-prs.md`, a living registry of analyzed upstream PRs:
  - At the top, the two commands that find what changed since the last review:
    ```sh
    # new commits on a PR already analyzed (recorded head .. current head)
    gh api repos/antirez/ds4/compare/<recorded-sha>...$(gh pr view <N> -R antirez/ds4 --json headRefOid -q .headRefOid) -q '.commits[] | .sha[0:7] + " " + (.commit.message | split("\n")[0])'
    # PRs created or updated after the last review date
    gh pr list -R antirez/ds4 --state all --search "updated:>=<YYYY-MM-DD>" --json number,title,headRefOid,updatedAt
    ```
  - One row per PR: number, title, state at analysis, **head SHA analyzed**,
    commit count, analysis date.
  - One line per relevant commit: verdict (`adopt -> <change>`, `idea -> <change>`,
    `drop`, `already in main`, `not reachable from Qwen`) and a one-line reason.
- Populate it with the 2026-09-24 review:

  | PR | State | Head analyzed | Commits | Updated | Summary |
  |---|---|---|---|---|---|
  | #1062 | open | `1ab00b5` | 33 | 2026-09-16 | 23 already in main by subject; adopt `acce8da` `be4cec8` `926ee12` `0a89a04` `1cd83e3` -> `30-mtp-cycle`; drop `822de06` `4d8b5dd` `1ab00b5` (already in child); `c3fb60c` `472c869` docs |
  | #1056 | open | `b1af94b` | 30 | 2026-09-23 | adopt `a50fecc` `04c0867` `9bff1ca`, idea `cdfc0d5` (HC) -> `40-dense-decode-kernels`; idea `b86c8ae` -> `30-mtp-cycle`; SSD commits -> `80-qwen-ssd-streaming`; IQ2/Q2_K commits -> `70-q2-kernels-m5`; `2d6a207` `89986c3` `0024ca0` drop (chunk-invariant prefill changes logits); `92f57fc` superseded by `acce8da` |
  | #1047 | closed | `d6cbc77` | 3 | 2026-09-19 | folded into #1056 |
  | #864 | open | `482e246` | 1 | 2026-08-27 | code targets DeepSeek `mul_mm_id`; ideas -> `60-q4-expert-prefill` (double-buffered staging only; split M=16 tiles and tail cull dropped: they change accumulation), `50-q4-expert-decode` (FP4 decode), `70-q2-kernels-m5` (half LUT) |
  | #959 | open | `b4605a0` | 3 | 2026-09-14 | not reachable from Qwen (argsort merge; Qwen uses radix select) |
  | #1014 | closed | `fe545fa` | 3 | 2026-09-10 | not reachable from Qwen (DeepSeek HC compressors) |
  | #947 | closed | `a11bf74` | 1 | 2026-09-02 | M5 Metal-4 tensor route: already in the baseline |

  Excluded as not reachable from the Qwen graph or not Metal (no rows needed
  beyond a list): #1090 #1073 #1041 #1042 #1060 #1061 #954 #953 #952 #794 #830
  #831 #758 #206 #371 #381 #385 #797 #1000 #396 #261 #846 #850 #1063 #1070 #1100
  #990 #1068. Qwen support itself is #991 (2026-09-06); older PRs cannot touch
  the Qwen path.
- Triage the PRs updated on the review day after the table was drawn:
  #1115 (Qwen TurboQuant KV cache: drop, lossy; Qwen template fix) and #1118 (server idle
  prefill quantum).
- Add a `context` entry to `openspec/config.yaml` naming the registry, so every
  proposal, design and task list consults it and a change that adopts a commit
  updates that commit's line.
  The same entry states the change-name convention (`<NN>-<kebab-name>`,
  numbered in execution order) so new changes keep the order visible in
  `openspec list --sort name`.
- Provenance of borrowed code lives in the registry and in commit messages, not
  in source comments. `sf-ablate` markers for cuts are unchanged.

## Capabilities

### New Capabilities
None. This is a development record, not product behavior (`skip_specs: true`).

### Modified Capabilities
None.

## Impact

- New file `docs/upstream-prs.md`; one entry in `openspec/config.yaml`.
- No source, build or test change.
- Every other change in this set refers to the registry for its commit list.
