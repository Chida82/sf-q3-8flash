# Proposal

## Why

Splash (incoai/splash, Apache-2.0) serves this model with a DFlash 2 draft
instead of the model's MTP head. DFlash 2 is a small separate model
(`incoai/Qwen3.8-Flash-Next-DFlash2`, Apache-2.0, 1.2 GB BF16, 5 layers)
that reads the outputs of target layers 5, 15, 25, 35 and 45 (the mean of
the four hyper-connection streams) and proposes a whole block of 8
positions in one pass: an anchor and 7 proposals, with 16 candidates per
position and a learned selector that walks one path through them. The
target verifies the block, so greedy output stays the target's and sampling
keeps its distribution. It is lossless, within the no-precision-loss rule.

The draft's model card reports, on one NVIDIA GB300 with 3 proposed tokens
per step (limited there by the sparse-attention kernels), tokens accepted
per step of 2.83-3.26 against MTP's 2.50-3.08, and decode 1.63-1.82x over
autoregressive against MTP's 1.35-1.59x: about 13-24% over MTP. Here,
resident Q4 MTP decodes about 90 tokens/s on code at 2.46 tokens per cycle
and about 66 on prose at 1.49 (`speed-bench/perf-record.md`).

Nothing says the gain carries to this Mac: every verified row of this MoE
routes its own experts (Splash counts about 43 experts a layer for 8 rows
against 17 for 2), so rejected rows cost real bandwidth, and under SSD
streaming they also cost reads (`197`: depth 3 gained 1.4% on code and lost
8.2% on prose). The owner asked to keep this in view, starting from a
measurement of Splash itself on this machine, before any engine work.

## What Changes

- **Step 0, no engine change.** Splash and its draft run on this Mac
  (M5 Max, 128 GB), resident, on the bench's code and prose prompts, beside
  this engine's `--mtp` on the same prompts. Compared: each engine's
  speculative decode over its own plain decode (the ratio cancels the
  different weights and kernels), tokens accepted per cycle, and absolute
  decode. Installing Splash and downloading its model need the owner's
  approval first (global instructions). Close the change unless DFlash 2's
  ratio projects at least +10% decode over this engine's MTP on code or
  prose, with neither below -2%.
- **Feasibility, only if step 0 passes, no GPU.** Draft verification of up
  to 8 rows needs a recurrent-state rollback deeper than today's 3 rows
  (`187`: Splash keeps a per-row GDN tape); the draft's weights need a GGUF
  component from the shared Hugging Face cache; the draft's memory
  (about 1.2 GB plus its 2,048-position window) must fit the plans. The
  design is rewritten with what is found, and the change is updated before
  any build.
- **S1, only after that.** The draft as an additional speculative mode
  beside built-in MTP, off by default. MTP stays: it costs no memory and
  remains the mode for SSD streaming unless a measurement there says
  otherwise.

## Capabilities

### New Capabilities

None at step 0. If S1 proceeds, `mtp-speculation` gains the draft mode in
an update of this change.

### Modified Capabilities

None at step 0.

## Impact

- Step 0: scratch files only (`$SCR/c204/`), a temporary Splash install and
  a model download, both approved by the owner and removed afterwards.
- If S1 proceeds: `ds4.c` (capture, draft forward, verify, rollback),
  `ds4_metal.m` and `metal/qwen4.metal` (draft kernels), `ds4_cli.c`,
  `ds4_server.c`, `ds4_bench.c` (option), `download.sh` (draft component),
  tests, `docs/SPECULATIVE_DECODING.md`.
- **Product contract.** `AGENTS.md` states "no external support model" and
  the StarForge registry lists MTP alone for this child. S1 changes both;
  the owner decides that before S1, not by landing it.
- Upstream ds4 has no DFlash path: no parity reference for the draft mode
  itself (greedy output must still equal plain), and permanent code with no
  sync counterpart.
