# Design

## Context

Step 0 measured Splash with its DFlash 2 draft on this Mac: 1.85 to 4.06
times its own plain decode, against 1.09 to 1.50 for built-in MTP here
(tasks 1.3-1.5). The feasibility pass (tasks 2.1-2.4) found:

- This engine's verify is exact per row: each row computes as a single
  decoded token would, so greedy `--mtp` output is byte-identical to plain.
  Splash's rows share expert tiles, a row's result depends on the rows beside
  it, and its text varies from run to run unless every cycle verifies the
  whole block (`--verify-rows all`).
- The verify is capped at 3 rows by two named recurrent-state snapshots and a
  few row limits. Upstream commit `7e6ab2f` (not in `upstream/main`) lifts it
  to 16 rows with n consecutive snapshot slots in three kernels, and adds
  grouped expert kernels that read an expert once for the rows that route it
  while keeping each row's arithmetic.
- The draft is 80 BF16 tensors, 1.15 GiB, in one safetensors file: 5 layers
  of plain attention (32/8 heads of 128, RoPE base 10000, 2048 window) and
  SwiGLU with two 2-tap grouped dynamic convolutions each, and a selector
  over the top 16 candidates per position.
- An exact row costs about 3.5 ms here (from MTP cycles) against about
  1.5 ms in Splash. What a row costs from the fourth on is not known.

The owner accepts an external draft model for DFlash 2, wants as much of the
existing engine reused as possible, and asked whether the verify may be
relaxed, for the draft mode only, to come nearer Splash's cost per row.

## Goals / Non-Goals

**Goals:**
- A draft mode whose greedy output is byte-identical to plain by default.
- New code kept small: upstream's long verify, existing kernels for the
  draft's projections, norms, MLP and head.
- A measured answer on a relaxed verify before it is built (D7: none).

**Non-Goals:**
- Replacing MTP, or changing its cycle's output or speed.
- Tree verification (Splash verifies up to 16 rows of a candidate tree).
- The draft under SSD streaming, in batched server sessions, or with vision
  prompts' image rows.
- Training or converting drafts for other models.

## Decisions

**D1-D4, step 0.** Done as written in the first version of this design:
ratios against each engine's own plain decode, an isolated install, the
bench prompts, feasibility before any build. Results are in tasks 1 and 2.

**D5, two stages and one gate.** Stage A ports upstream's long exact verify
and stops for a measurement. Stage B adds the draft. Stage A has a user of
its own, upstream's lookup blocks of up to 7 drafts, so it is measured
without a draft and is worth keeping if stage B never starts.

**D6, exact by default.** The draft changes which tokens are proposed, never
which are kept. With exact rows, greedy output is byte-identical to plain
whatever rows a cycle verifies, and `tests/test_qwen4_mtp_identity.py` stays
the reference with the draft mode added. Sampling follows the existing
rules: opportunistic acceptance by argmax, and under `--mtp-exact-sampling`
each draft is a point proposal accepted with its target probability.

**D7, no relaxed verify.** The owner asked whether the verify could be
relaxed, for the draft mode only, to come nearer Splash's cost per row. The
candidate was the block computed by the prefill kernels this engine already
has. Measured (task 3.6): on Q4 a block of 8 rows takes 55.2 ms on them
against 55.8 ms exact, and they are slower than the exact rows up to 7 rows.
There is nothing to buy with the output's identity, so the exact verify is
the only one. Splash's cost per row comes from kernels this engine does not
have (expert tiles shared by a few rows, int8 activations, a taped recurrent
scan); writing them is a second kernel family and out of scope.

**D8, the gate after stage A.** Measured on Q4 and Q2, resident: time of a
verify block of 1 to 8 rows, exact and relaxed. Projected with Splash's
tokens per cycle (task 1.3, whole block). Stage B starts if the projection
is at least +10% over MTP on the chat code prompts in the mode the owner
then chooses. Otherwise the change closes with stage A, if stage A pays on
its own (`mtp-copy`), or with nothing.

**D9, the draft on existing kernels.** Projections, `fc`, the MLP and the
head use the multi-row matvec; norms the RMS norm kernels; the selector runs
on the CPU from two mapped codebooks. New: one kernel for the mean of the
four hyper-connection streams at layers 5, 15, 25, 35 and 45, one for the
grouped dynamic convolution. The draft's attention uses the trunk's rows
kernels if they take 32/8 heads of 128 and a one-axis RoPE; if not, one
small dense kernel (8 queries, at most 2056 keys). Each new kernel has a CPU
reference. The draft only proposes, so its weights load as F16.

**D10, the draft file.** Read `model.safetensors` in place from the shared
Hugging Face cache: `download.sh` fetches the repository and links it under
`gguf/`, and a small reader validates the header (sizes, offsets, dtypes,
the 80 expected tensors and shapes) before any tensor is mapped. No GGUF
conversion and no second copy on disk.

**D11, rows per cycle.** A block is at most 4 rows, the anchor and three
drafts: a fifth row starts a second walk of the dense weights and costs
9 ms on Q4 (task 3.6). A cycle verifies the anchor and the first rows of
the selector's path. The count comes from the selector's own scores along
the path (a floor on the running product), fixed constants, no clock. With
exact rows the count changes speed only.

**D12, modes.** `--dflash2 FILE` selects the draft cycle and excludes
`--mtp`'s predictor (one drafter per engine). Engine open refuses it with
`--ssd-streaming`: each verified row routes its own experts and rejected
rows would cost reads (`197`); `q4s` keeps MTP. Batched server sessions and
image rows decode plain in this mode.

**D13, nothing on main until complete.** All of S1 lives on
`feature/204-dflash2`. It lands as one signed commit when the owner says the
change is complete.

**D14, closed at the gate.** Stage A reached exact verify rows up to 8,
bit-identical to one-token decoding, and their cost: 28.0 ms for a block of
4 on Q4, 55.8 ms for 8, resident (task 3.6). The projection is +11% to +25%
over MTP on chat code, about +49% on a prose continuation, nothing on a
story, and nothing for the streamed variant. The owner closed the change
there: the draft would serve few cases. No code lands. The branch
`feature/204-dflash2` keeps the exact rows and the block probe at `5dd4be0`.

## Risks / Trade-offs

- The gain may be far below Splash's: exact rows cost more than twice
  Splash's. The gate (D8) stops the change before the draft is built.
- Upstream's snapshot slots write the whole recurrent state per row, about
  760 MiB a cycle for 8 rows. If that shows, tape each row's GDN inputs and
  fold the accepted path instead (Splash's way); decided by stage A's
  profile, not built ahead.
- Upstream's grouped exact kernels are for Q8_0 experts. This child's packs
  use IQ2/Q2_K and Q4_K/MXFP4, whose exact grouped kernels exist for two
  rows; widening them is this child's code.
- `7e6ab2f` is not merged upstream: if upstream changes it, the next sync
  conflicts there.
- Acceptance was measured on ISTA's Q2_0 file, not on this child's packs.
- Permanent code with no upstream counterpart (the draft), about 2 GiB more
  memory in draft mode, and a product contract that now names an external
  model for one optional mode.
