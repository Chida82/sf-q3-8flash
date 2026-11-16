# Design

## Context

The child's scorer is upstream's at the sync, plus `160`'s superseded-prefix
factor and its protection of the checkpoint about to load
(`incoming->protect_text`). #986 was written before both. Its hunk touches
only the base term, so it composes with them. The PR's server-test hunks are
against upstream's `ds4_server.c`; the child's helpers differ
(`test_kv_stub_file(dir, sha, reason, tokens, hits, last_used, bytes)`), so
the tests are rewritten, not cherry-picked.

## Decisions

### D1. Take the scorer hunk as is

`freshness` reuses `DS4_KVSTORE_HIT_HALF_LIFE_SECONDS`, with no new option.
Edge cases, each covered by the ported unit test:
- no timestamp: 0;
- a future timestamp: 1, so a clock step cannot amplify the score;
- `now = UINT64_MAX`: 0.

`exp2` underflows to 0 after about 1000 half lives, so very old unused entries
tie at 0. The existing age tie-break
(`test_kv_cache_eviction_decayed_hits_tie_break_by_age`) orders them, oldest
first.

### D2. Fixture timestamps

Change the 1970 stamps in `test_kv_text_stub_file_model` (and the other
helpers that hard-code `100, 100`, seven sites) to `now` only where a test is
about identity or prefix policy. A test that is about age keeps its explicit
timestamps. Each site is read before it changes, and the `--server` output
must name every eviction test as passing.

### D3. Proof

- Model-less: `./ds4_test --server`, reading the names of the two new tests
  and of the existing `test_kv_cache_eviction_*` tests in its output.
- The PR's second test is the reported scenario scaled down: two old evict
  dumps, two shutdown saves in sequence, budget for two. Both new saves must
  survive, also after a reopen. It fails on `main` (checked before the port)
  and passes on the branch.
- No GPU run decides this change. A short live workload cannot show it: every
  entry it writes is minutes old, so freshness is about 1 and the ranking is
  `main`'s. An optional guard on Q4, run only if the GPU is free:
  `speed-bench/agent_reuse.py` against `main` with a fresh cache directory.
  No request may lose cached tokens.

## Risks / Trade-offs

- **Old checkpoints a user keeps on purpose** (a long document loaded once a
  week) now lose to recent saves under pressure. That is the intended
  trade-off: the budget is a cache, and the hit bonus still protects anything
  that is actually reused.
- **Cache directories already over budget** may evict different files at the
  first store after the upgrade, oldest-unused first.
