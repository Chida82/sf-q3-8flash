# Tasks

## 1. Registry skeleton

- [x] 1.1 Create `docs/upstream-prs.md` with: a one-paragraph purpose (a record of which upstream PRs were reviewed, up to which head, and the verdict per commit); a sentence stating that the head SHAs record what was reviewed and are not a sync base (the base stays in git: `sync-*` tags and `git merge-base HEAD upstream/main`); the `Last review:` date; and the two commands from proposal.md, using `updated:>=`. Verify the file exists and `grep -c 'gh api repos/antirez/ds4/compare' docs/upstream-prs.md` prints 1.
- [x] 1.2 Under the commands, add the fallback for a force-pushed PR: when `compare` fails because the recorded head is gone, list `gh pr view <N> -R antirez/ds4 --json commits -q '.commits[] | .oid[0:7] + " " + .messageHeadline'` and diff it against the recorded commit lines by subject. Verify by running the fallback on #1056 and checking that it prints 30 lines.
- [x] 1.3 Add the verdict legend (`adopt -> <change>`, `idea -> <change>`, `drop`, `next sync`, `superseded by <sha>`, `already in main`, `in main, modified`, `not reachable from Qwen`, `docs`). Also add the rule that a change that adopts or rejects a commit updates that commit's line in the same branch. Verify that the legend lists every verdict used in section 2.

## 2. Populate the 2026-09-24 review

- [x] 2.1 Add the PR summary table from proposal.md: number, title, state, head analyzed, commit count, last update, analysis date. Verify each head against `gh pr view <N> -R antirez/ds4 --json headRefOid,commits` (as of writing: #1062 `1ab00b5`/33, #1056 `b1af94b`/30, #864 `482e246`/1, #959 `b4605a0`/3).
- [x] 2.2 Add one line per commit of #1062 (sha7, subject, verdict, reason). After `git fetch upstream` and `git fetch upstream pull/1062/head`, classify with `git cherry -v upstream/main FETCH_HEAD`: a `-` line is `already in main` (same patch). A `+` line whose subject is in `git log upstream/main --format=%s` is `in main, modified` (as of writing 15 and 8: `68cd651` `5947b48` `b63d48d` `832f4e4` `13cccce` `b6c5936` `aaba688` `80e5eef`). For a modified commit that an adopted commit builds on (`13cccce` for `0a89a04`), add what the landed version changed. Verify that the number of #1062 commit lines equals 33 and that the five adopted SHAs point to `30-mtp-cycle`.
- [x] 2.3 Add one line per commit of #1056 with the verdicts in proposal.md. The SSD commits go to `80-qwen-ssd-streaming` and the IQ2/Q2_K commits to `70-q2-kernels-m5`. Mark `2d6a207` `89986c3` `0024ca0` as `drop` (chunk-invariant prefill changes logits) and `92f57fc` as superseded by `acce8da`. Verify that the number of #1056 commit lines equals 30 and that every target change named exists in `openspec list --sort name`.
- [x] 2.4 Add the short rows for #1047, #864, #959, #1014 and #947, then the list of excluded PRs, with the note that Qwen support landed in #991 (2026-09-06). Verify that every PR number in proposal.md appears in the file (a grep loop over the numbers prints nothing missing).

## 3. Triage the PRs that arrived on review day

- [x] 3.1 Record #1115 (head `c544020`, 3 commits). Mark `485902a` (TurboQuant 2..8-bit KV for the Qwen attention caches) `drop`, because it quantizes the KV cache and loses precision, which is not accepted. Mark `f5e419d` (Qwen prompt rendering fix) `next sync`: a correctness fix, taken at the next project sync, not in a perf branch. `c544020` is test plumbing. Verify that #1115 has a row and 3 commit lines.
- [x] 3.2 Review #1118 (head `25def38`, 1 commit, server idle prefill quantum) and record a verdict. Verify that #1118 has a row and 1 commit line.
- [x] 3.3 Re-run the `updated:>=2026-09-24` search. Record any other PR it shows that reaches the Qwen or Metal path, or add it to the excluded list. Verify that every number the search prints appears in the file.

## 4. OpenSpec context

- [x] 4.1 Add a `context:` block to `openspec/config.yaml` that says:
  - analyzed upstream PRs and per-commit verdicts live in `docs/upstream-prs.md`;
  - proposals, designs and tasks consult it, and adopting or rejecting a commit updates its line;
  - provenance goes in the registry and in commit messages, never in source comments;
  - change names use `<NN>-<kebab-name>` in execution order.
  - performance changes must not lose precision: no KV-cache or activation quantization, and no route that changes greedy output.

  Verify with `openspec instructions design --change 20-perf-bench-harness --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["context"])'`, which should print the block.

## 5. Close

- [x] 5.1 Check that no source, build or test file changed: `git status --short` lists only `docs/upstream-prs.md`, `openspec/`, and nothing under `*.c`, `*.m`, `*.metal`, `Makefile` or `tests/`.
- [x] 5.2 Run `openspec validate 10-upstream-pr-intake` and confirm it passes.
