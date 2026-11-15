# Design

## Context

proposal.md, "What is known", gives the case, the code facts and H1-H4. In
short: two images, four REPL turns, and the outputs part from the second image
turn on. Image spans exist only during prefill, priming skips image chunks,
and a REPL turn ends differently in the two modes.

One CLI run of the case costs two model loads plus four turns, about two
minutes on Q4. Every step below counts its runs.

## Goals / Non-Goals

**Goals:**
- a lasting check that compares MTP with plain output over a REPL
  conversation, with and without images;
- the first diverging state, and which hypothesis causes it;
- a fix that restores byte-identical output with no precision loss and no
  unmeasured speed loss, or a decision put to the owner with figures.

**Non-Goals:**
- sampled MTP, `--mtp-exact-sampling` (`150`);
- server image-turn reuse;
- MTP speed work beyond keeping the current speed.

## Decisions

### D1. The check stays at the REPL

The divergence needs several turns, and only the REPL (or the server) keeps a
session across turns. S0:
- `tests/test_qwen4_cli_vision.py --compare` splits both stdouts into turns,
  compares them turn by turn, prints
  `SAME` or `DIFF` per turn with the first differing line, and exits 1 on any
  `DIFF`. Without `--compare` the script behaves as today.
- For H1, the same comparison runs on a text-only command file: four user
  turns, no `/read`. This starts as a scratch script. If H1 is confirmed, it
  lands as a `--text-turns` case of the same script, so one tool covers both
  conversation kinds.

The server was considered and not used. It adds batching and KV-cache tiers
that are not part of this case.

### D2. Localization by a probe

The probe is env-gated and marked `PROBE-110`. It logs:
- per committed token: the position, the token id, and the path that computed
  its row (prefill chunk of size T, verify row r of R, single decode);
- at each turn boundary: the session's `pos`, `checkpoint.len`, the transcript
  length, whether sync reused or replayed, `mrope_delta`, `mtp_pos` and
  `mtp_tail_valid`;
- for verify passes after an image: the snapshot and restore of
  `mrope_delta`.

Diffing the two modes' logs gives the first position where the paths or the
state differ, which is earlier than the first differing word.

### D3. Telling H1-H4 apart, cheapest first

1. **H1.** Run the text-only REPL comparison (2 runs).
   - If it diverges, images are irrelevant. Read the turn-boundary lines of
     the probe: either a row computed by different paths, or a replay.
   - If it does not diverge, H1 is unlikely and steps 2-4 follow.
2. **H4.** Use `DS4_QWEN4_FAKE_IMAGE` to place a synthetic image early in a
   text prompt. Run a `DS4_QWEN4_FT_LIST` teacher-forced dump of the tokens
   that follow it at `DS4_QWEN4_GPU_CHUNK` 1, 2 and 3, and compare with `cmp`.
   Equal dumps rule out H4. Before that, confirm that the verify call reaches
   this graph entry; if it does not, the probe dumps verify rows directly, as
   in `82`.
3. **H2.** Dump the target's last-row logits after the second image chunk's
   prefill in both modes. If they differ while the session states before that
   prefill are equal, the unprimed-chunk path changes the target. Narrow it
   with a probe knob that skips the tail flush.
4. **H3.** Pin the depth to 2 and to 3, and compare the restored
   `mrope_delta`, `pos` and `ple_prev` after each rejected draft with the
   values plain decode reaches at the same position.

### D4. What may land

Same rule as `82`:
- **A state bug (H2, H3), or a turn-boundary bug that is a real difference in
  the evaluated tokens (H1, replay):** fix it. Keep the fix if:
  - S0 passes in both conversation kinds;
  - the plain path stays bit-identical (`--bitwise` against `main`);
  - no MTP metric's pooled CI lies wholly below zero.
- **An arithmetic difference that cannot be removed for free** (H1: verify row
  against prefill-chunk row for the same token): stop and put the options to
  the owner with figures:
  - (a) make the turn end compute the same rows in both modes, with its cost;
  - (b) re-evaluate the closing rows at the next turn's start in MTP mode, so
    both modes enter the turn with prefill-computed rows, with its cost;
  - (c) narrow the requirement to single-turn identity. That is a precision
    decision, so it needs the owner's explicit approval.

No probe code lands.

### D5. Checks and review

- **Step checks:** `make -j8` with no warnings; `make test -j8`, whose output
  names the suites; `make test-qwen4-kernels`; `python3 tests/test_ab_bench.py`.
- **Model runs:** strictly one after another, each started at the Nominal
  thermal state.
- **Review:** one review after S0 and one after the fix. The final pass
  covers the touched region and checks with `rg PROBE-110` that no probe
  remains.

## Risks / Trade-offs

- **The case may not be deterministic.** Two repeats come first. If the
  outputs vary from run to run in one mode, the problem is nondeterminism, not
  MTP, and the change reports that before going on.
- **H1 widens the scope to every multi-turn conversation**, including the
  server. If confirmed, the server's live session path is checked the same
  way before closing (one two-turn request pair through
  `sf-q3-8flash-server`).
- **Q2 is not on this machine** → the change closes on Q4 and lists the Q2
  run as pending the owner's approval of the 137 GiB download.
- **`90` may change the result** → task 1.2 re-measures the case on the synced
  `main` before anything else.
