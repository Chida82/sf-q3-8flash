# Design

## Context

The facts are in proposal.md, "What is known". In short:
- one Q2 case diverges under MTP, deterministically, from `59c6488` on;
- ds4 at the merge-base and the child before priming give the plain output;
- three causes are possible: H1, the batch size changes the numbers; H2, the
  priming changes the target; H3, the rollback is not exact.

The existing checks cannot see the problem:
- the A/B harness's token gate compares build against build on the same kind,
  so a divergence present in both builds passes;
- the parity oracle has one short `--mtp` prompt;
- `30` checked MTP against plain on Q4 only.

Model runs are expensive. One CLI run costs about 35-40 s here, most of it the
model load, so every step below counts its runs.

## Goals / Non-Goals

**Goals:**
- a lasting check of MTP against plain over a prompt set, on both packs;
- the first diverging token, and which of H1, H2 or H3 causes it;
- a fix that restores byte-identical output, with no precision loss and no
  unmeasured speed loss, or a decision put to the owner with figures.

**Non-Goals:**
- sampled MTP and `--mtp-exact-sampling`;
- the vision second-turn difference (recorded in `30` as pre-existing);
- MTP speed work beyond keeping the current speed.

## Decisions

### D1. The check is a CLI-level script

`tests/test_qwen4_mtp_identity.py --model M [--depths auto,2,3] [--prompts FILE]`,
Python stdlib only, in the style of `tests/test_qwen4_mtp_limits.py`.
- For each prompt it runs the CLI once without `--mtp`, then once with `--mtp`
  per depth. Each run uses `--ctx 8192 --temp 0 --nothink -n <limit>`, and a
  pinned depth sets `DS4_QWEN4_MTP_DEPTH=<d>` inline.
- It compares stdout bytes and prints `SAME` or `DIFF` per pair, with the word
  index where the texts first differ.
- It exits 1 on any `DIFF`.

The default prompt set is 12 prompts, each with its own token limit:
- upstream's three Qwen cases;
- the nine text prompts of the parity set, whose steering line is skipped.

At 4 runs per prompt, that is 48 runs, about 30 minutes per pack. `--depths
auto` cuts it to 24 runs, as a quick check.

The alternatives were:
- the A/B harness: it measures speed and compares builds, not modes, so adding
  a cross-mode gate there would couple two purposes;
- the server: batched sessions would make every run cheaper, but a batched
  session is a second code path, not the one the CLI runs.

### D2. Localization by a probe

A probe (env-gated `fprintf`, not landed) logs, for every committed token:
- its position and token id;
- in the MTP cycle: the verify batch's size, the number of drafts accepted, and
  each verify row's argmax and top-2 margin;
- in plain decode: the argmax and the top-2 margin at the same position.

Diffing the two logs gives the first position `p` where the committed tokens
differ, the batch shape that produced it, and how close the tie was. A margin
of a few ulps points to H1. A large margin points to H2 or H3.

### D3. Telling H1, H2 and H3 apart, cheapest first

1. **H2.** The probe also dumps the target's last-row logits after prefill in
   both modes. If they differ, priming moves the target, and D3 stops there.
2. **H1.** The plain run's token ids up to `p` feed `DS4_QWEN4_FT_LIST` as a
   `prefix|continuation` line with 1-3 continuation tokens, at
   `DS4_QWEN4_GPU_CHUNK` 1, 2 and 3; the dumps are compared with `cmp`.
   - First, the verify call site is read to confirm that the MTP cycle scores
     its batch through the same graph entry as this test. If it does not, the
     probe dumps the verify rows directly.
   - If the dumps differ, a section is found by forcing its T = 1 path in
     turn, using the existing variant knobs where they exist.
3. **H3.** If H1 and H2 both read identical, the probe dumps the target logits
   at `p` in the MTP run and in the plain run. A difference means that the
   state before `p` differs: rollback, the priming tail, or restore. Pinning
   the depth, and dropping the priming tail by a probe knob, narrows it down.

### D4. What may land

- **A state bug (H2, H3):** the fix is kept if S0 passes on both packs, plain
  stays bit-identical (`--bitwise` against `main`), and no MTP metric's pooled
  CI lies wholly below zero.
- **Batch-size dependence (H1):** a fix that makes the section give the same
  numbers at every batch size is kept under the same rule.
- **If H1 has no fix at zero cost:** the change stops and reports three options
  to the owner, each with its figures:
  - (a) the fix and its measured MTP speed cost;
  - (b) re-scoring alone every verify row whose top-2 margin is below a bound,
    with its cost;
  - (c) narrowing the requirement to "identical up to near ties", with the rate
    measured by S0. Option (c) is a precision decision, so it needs the owner's
    explicit approval.

No probe code lands.

### D5. Checks and review

- **Step checks:** `make -j8` with no warnings; `make test -j8`, whose output
  names the suites; `make test-qwen4-kernels`; `python3 tests/test_ab_bench.py`.
- **Model runs:** strictly one after another, each started at the Nominal
  thermal state.
- **Review:** a review after S0 and after the fix. The final pass covers the
  touched region and checks with `rg` that no probe remains.

### D6. Depth data for a project rule

The owner wants to decide whether MTP should run at one draft by project rule,
and when two drafts are worth their risk. In the code:
- `DS4_QWEN4_MTP_DEPTH=2` verifies one draft in a 2-row pass;
- `=3` verifies two drafts in a 3-row pass;
- the automatic default runs depth 2 and switches to 3 only after eight
  first-draft acceptances in a row (`qwen4_spec_depth`);
- exact sampling always runs at depth 2.

For each pack and each of depth 2, depth 3 and auto, the change reports:

| Column | Source |
|---|---|
| diverging prompts out of 12 | S0 at that depth |
| MTP-code and MTP-prose decode (t/s), tokens per cycle | one A/A harness run, `ab_bench.py --a . --b . --kinds mtp-code,mtp-prose --env DS4_QWEN4_MTP_DEPTH=<d> --budget 600` (auto: no env) |
| plain decode (t/s) | one A/A harness run with `--kinds plain`, the same session |
| MTP speedup over plain | the two rows above |

The rows come from separate runs, so their absolute values carry the
between-run noise (about ±3%). The report says so, and gives each run's GPU
clock median.

The data is taken on the tree before any fix, and again after a fix if one
lands. With the data, the owner can choose among:
- keep auto;
- pin depth 2 by rule;
- allow depth 3 only when it gains more than X% over depth 2.

The rule itself is not written by this change unless the owner asks.

## Risks / Trade-offs

- **S0 is slow** (about 30 minutes per pack) → `--depths auto` for quick use.
  The full run is required only before a change that touches MTP, prefill or
  decode lands.
- **H1 can be true and costly to remove** → D4 puts the trade to the owner
  instead of taking it.
- **The probe itself could change timing but not numbers** → it only reads
  logits already on the host, so it adds no GPU work.
- **Q4 may diverge on prompts outside the set** → S0's set is a floor, not a
  proof. D1 runs it on `91f225a` too, so a prompt that already diverged before
  priming is recognized as a separate case.
