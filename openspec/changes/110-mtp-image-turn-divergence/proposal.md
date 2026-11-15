# Proposal

## Why

With `--mtp`, greedy output must be exactly the plain greedy output
(`mtp-speculation`, "Greedy output is unchanged by MTP"). An image
conversation breaks that rule, and no check catches it. `30-mtp-cycle`
recorded the difference as pre-existing. `82-mtp-greedy-divergence` left it
out of scope: it made text verify rows exact, and its identity check runs
single-turn text prompts only. This change finds the cause, fixes it if a
bit-identical fix exists, and adds the missing check.

## What is known

**The case** (measured 2026-11-14 on `main` `765e9a5`, Q4 pack):

```sh
python3 tests/test_qwen4_cli_vision.py --model <Q4> --vision <MMPROJ> \
  --image <airdrop.png> --image <alertstop.png>
```

The two PNGs are the AirDrop and AlertStop macOS system icons, converted with
`sips`. The script drives the REPL, once without and once with `--mtp`, with
`--ctx 8192 --temp 0 --nothink -n 180`. For each image it sends `/read <path>`
and then "Describe only the most recent image, including any text and
colors.". It expects four prefills: two image turns and two text follow-ups.

- Both modes PASS: both images encoded, all four prefills completed, no error
  line.
- `ordinary.stdout` and `mtp.stdout` differ from the second image turn on. The
  first differing line reads "has a subtle vertical gradient" in one output
  and "has a vertical gradient" in the other.
- The script checks completion only, so it reports neither the difference nor
  where it starts.

Not measured yet:
- whether the outputs repeat over runs;
- which turn's state first differs;
- whether a text-only multi-turn conversation also diverges;
- whether Q2 behaves the same (the Q2 pack is not on this machine).

**What the code says** (read on 2026-11-14 at `765e9a5`):
- `qwen4_graph_mtp_priming` primes only chunks without image spans
  (`vis_span_count == 0`). An image chunk leaves the predictor unprimed.
- `ds4_session_sync_internal` sets the image spans for the prefill and clears
  them afterwards. Verify batches therefore never hold image rows.
- After an image, text positions carry a non-zero MRoPE delta. A verify pass
  snapshots it (`snap_mrope_delta`, `snap2_mrope_delta`) and restores it when a
  draft is rejected.
- At the end of a REPL turn, plain mode breaks on the stop token without
  evaluating it, then appends EOS to the transcript. MTP mode evaluates the
  parent token and its drafts in a verify pass. So the last rows of a turn can
  be computed by a verify row in one mode and by the next turn's prefill chunk
  in the other.
- The next turn reuses the session only when its prompt extends the
  checkpoint. Otherwise it resets the recurrent state and replays the kept
  tokens with new chunk boundaries. Prefill arithmetic depends on the chunk
  shape; chunk-invariant prefill was dropped.

**Hypotheses** (none is established):
- **H1, turn boundary.** It is not specific to images. The rows at a turn's end
  get different arithmetic in the two modes, or the MTP session's checkpoint
  does not prefix the next transcript and the turn is replayed. H1 predicts
  that a text-only multi-turn REPL conversation diverges too. `82`'s check
  could not see that.
- **H2, unprimed image chunk.** After the image chunk, the predictor's
  `mtp_pos` and `mtp_tail` still describe the previous text chunk. A tail
  flush or a draft then writes into trunk-shared state: priming stages its
  inputs in the MoE transients and writes the predictor residual over the
  trunk streams in place.
- **H3, rollback across MRoPE state.** A rejected draft restores position,
  MRoPE delta or PLE history incorrectly. The delta is zero in text-only
  runs, so such an error shows only after an image.
- **H4, verify rows after an image.** In the form first suggested, image rows
  inside a verify batch, H4 is ruled out by reading. What remains: the exact
  verify rows (`qwen4_verify_attention_rows`) and single-token decode might
  read positions differently once the delta is non-zero. By reading, both use
  the same `pos3` table.

**Tools that exist:**
- `DS4_QWEN4_FAKE_IMAGE=start:count:rows:cols` gives deterministic image spans
  without the vision encoder;
- `DS4_QWEN4_FT_LIST` produces teacher-forced logit dumps;
- `DS4_QWEN4_GPU_CHUNK` sets the batch size;
- `DS4_QWEN4_MTP_DEPTH=2|3` pins the depth;
- `tests/test_qwen4_mtp_identity.py` compares modes on single-turn text.

## What Changes

1. **S0, a regression check.** `tests/test_qwen4_cli_vision.py` gains
   `--compare`: it fails when `ordinary.stdout` and `mtp.stdout` differ, and
   names the first differing turn and line. A text-only REPL variant of the
   same comparison serves H1 (design D1).
2. **Extent.** Run S0 twice on the case to see whether it is deterministic.
   Run the text-only variant too. Run S0 at pinned depths 2 and 3, and on
   `91f225a` (before priming).
3. **Localization.** A probe (not landed) logs, per committed token, the
   position, the token, the batch shape (prefill chunk, verify rows or single
   decode), and the session's `pos`, checkpoint length and MRoPE delta at each
   turn boundary. Diffing the two modes' logs gives the first position where
   state or tokens part.
4. **Cause.** Cheapest test first (design D3).
5. **Fix or decision**, as in `82` (design D4).
6. **Closing:**
   - S0 passes on Q4, and on Q2 if the owner approves its download;
   - the parity oracle and the MTP identity and limits checks pass;
   - an A/B against `main` and a record row, if code outside `tests/`
     changed;
   - `docs/TESTING.md` lists the new check.

Not in scope: sampled MTP; image-turn KV reuse in the server (`#1343`,
`#1322`).

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `mtp-speculation`: a new requirement that MTP greedy output equals plain
  greedy output across REPL turns and in image conversations, checked by S0.

## Impact

- `tests/test_qwen4_cli_vision.py` and, for H1, a text-only REPL case; lines in
  `AGENTS.md` and `docs/TESTING.md`.
- Depending on the cause:
  - `ds4.c`: the turn boundary in `ds4_session_eval_speculative` and the
    REPL, priming state across image chunks, or snapshot restore;
  - `ds4_cli.c`: the REPL turn end.
- `speed-bench/perf-record.md` if engine code changed.
- Runs after `90-upstream-sync-b3f5018`, whose MTP merge rewrites the code
  under study. The case is re-measured on the synced `main` first.
