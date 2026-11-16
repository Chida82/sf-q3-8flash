# Tasks

GPU: none required. One optional guard run on Q4 (4.1), only if the GPU is free.

Starts from `main`. `<Q4>` is the child's `qwen3.8-flash-next.gguf`; `$SCR` is
`~/.sf/q3-8flash/scratch`, and this change's files go in `$SCR/c181/`. Model
runs are strictly sequential.

"The step checks": `make -j8` with no warnings; `make test -j8`, whose output
names the suites; `./ds4_test --server`, reading the names of the eviction
tests in its output.

## 1. Branch and references (no GPU)

- [ ] 1.1 `git config rerere.enabled true`; `git switch -c fix/181-kvstore-checkpoint-aging`. `git fetch upstream pull/986/head`; check the head is still `ba4b40e`; save the diff to `$SCR/c181/`.
- [ ] 1.2 Write the two unit tests (design D3) on `main` first and record that the sequential-shutdown test fails there.

## 2. Step S1: the scorer (design D1, D2; no GPU)

- [ ] 2.1 Apply the `ds4_kvstore.c` hunk. Change the fixture timestamps per D2, reading each site first.
- [ ] 2.2 Add the two tests to `ds4_server_unit_tests_run`. Run the step checks.
- [ ] 2.3 Step review: the scorer, its callers (`ds4_kvstore_evict`, the startup log at `ds4_kvstore.c:688`), and the interaction with `160`'s protected checkpoint.

## 3. Review (no GPU)

- [ ] 3.1 Final pass over the touched region; no other scorer term changes.

## 4. Optional guard (GPU: one workload run on Q4, if free)

- [ ] 4.1 `speed-bench/agent_reuse.py` on `main` and on the branch, each with a fresh cache directory: no request loses cached tokens. Record in `$SCR/c181/steps.txt`, or record that the run was skipped.

## 5. Closing

- [ ] 5.1 `docs/SERVER.md` (the eviction score, if described); `docs/upstream-prs.md`: `ba4b40e` to `adopt -> 181-kvstore-checkpoint-aging`.
- [ ] 5.2 `openspec validate 181-kvstore-checkpoint-aging --strict` passes.
- [ ] 5.3 Report to the user in Italian. Land as one signed commit, with the PR author as `Co-authored-by`; delete `$SCR/c181/`; archive the change.
