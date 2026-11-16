# Proposal

## Why

When the disk KV cache is over budget, `ds4_kvstore_evict` deletes the
checkpoints with the lowest `ds4_kvstore_entry_eviction_score`
(`ds4_kvstore.c:564`). The score decays an entry's hits with a six-hour half
life, but then adds a constant: `(effective_hits + 1.0) * tokens / file_size`
(`ds4_kvstore.c:580`). A checkpoint that was never hit keeps its full
tokens-per-byte score forever. An old, slightly denser dump that nobody has
loaded for days therefore outranks a conversation saved a minute ago, and the
next store can evict the new one before its first lookup.

#986 (`ba4b40e`, one commit) reports exactly that: a graceful shutdown saved a
105662-token conversation and the next save evicted it, while older unused
dumps survived. Losing the checkpoint the client returns to means a full
re-prefill, which is a performance loss (cache reuse) under the intake
criteria.

## What Changes

- The constant `1` ages with the same half life as the hits:
  `(effective_hits + freshness) * density`, where `freshness` is
  `exp2(-elapsed / half_life)` from the entry's last use (or creation), and 0
  for an entry with no timestamp. The hit clamp, the anchor factor, the
  superseded-continued-prefix factor and the byte budget are unchanged.
  Freshness is a preference, not a pin: a fresh entry is still evicted when the
  budget cannot hold the working set.
- Port the PR's two unit tests into the child's `--server` suite
  (`test_kv_cache_eviction_decays_unused_value`,
  `test_kv_cache_eviction_preserves_sequential_shutdown_saves`), adapted to the
  child's test helpers.
- The child's fixture helper `test_kv_text_stub_file_model` stamps entries at
  time 100 (1970). Under aging those entries score 0, so tests about identity
  and prefix policy would start to depend on the age tie-break. Stamp them at
  `now`, as the PR does.

No file format, lookup key, payload, model math or sampling changes. Existing
cache files need no migration.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
(none: eviction ranking only)

## Impact

- `ds4_kvstore.c` (`ds4_kvstore_entry_eviction_score`, about 5 lines).
- `ds4_server.c` unit tests (two new tests, the fixture timestamp).
- `docs/SERVER.md` if it describes the eviction score; `docs/upstream-prs.md`
  (`ba4b40e`).
