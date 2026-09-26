# Design

## Context

The facts are in proposal.md, "What is known". They reduce to three points:
- the Q2 remainder tails are bit-identical and save 140-200 ms of prefill per
  turn;
- no tail kernel runs during decode, yet decode wall-clock with the tails on
  reads about −0.3% on average (range +0.2..−1.1%);
- every true null reads 0: the tails off in both builds, and two same-binary
  runs with only the prefill speed changed.

The unknown is the shape of the decode cost. A fixed cost per decode phase
of about 10-15 ms explains every reading. A cost per token explains them as
well, if it sits at 0.3-1%. The decision depends on which one it is.

Files and figures from `70` live in that session's scratch dir
(`c70/steps.txt`, `q1*`, `x1-coupling`, `x2-coupling`, `q1b-*`, `q1c-*`).
Everything this change needs from them is restated in proposal.md, so none
has to exist.

## Goals / Non-Goals

**Goals:**
- measure whether the decode cost is fixed per decode phase or per token;
- find its source if a probe can, and remove it if the fix is bit-identical;
- land the tails if the cost is removable or fixed and small, or put the trade
  to the owner with numbers.

**Non-Goals:**
- the tails for other types or devices;
- new tile widths;
- any change to decode kernels.

## Decisions

### D1. A generation-length override, not a new metric

`ab_bench.py --gen N` passes `-n N` to every bench run. A fixed cost C per
phase at decode rate r and length G reads as a loss of `C·r/G`. At G = 512
the 10 ms of the plain reading becomes −0.1%, while a per-token cost stays
−0.77%. The two predictions differ by more than the CI half-widths the
default runs reached (about ±0.4% at n = 20).

The alternative was a per-token timing column in the bench CSV. It would
show where the time goes, but it changes `ds4_bench.c`, which the parity
oracle and the record rows depend on. The length override needs no bench
change, because `-n` already exists.

With an override, the record row is suppressed (spec delta). A row made with
512-token phases would sit in the performance record as if it were comparable
with the rest.

The limits are 16..4096. Below 16, the first-cycle cut leaves too few steady
tokens. Above 4096, one run exceeds what the 600 s budget can pair.

### D2. The diagnosis runs on the MTP-code kind first

At `--gen 512`, one plain run decodes 3 × 512 tokens after about 10 s of
prefill, so the 600 s budget holds only about 5 pairs. One MTP-code run
prefills 2048 tokens and decodes 512 at about 64 t/s, about 10 s in all, so
the budget holds about 25 pairs. The plan:
1. MTP-code at the default length, then at `--gen 512`, with the tails on in B
   and off in A (the Q1 gate in B's tree, `main` in A's);
2. plain at `--gen 256` with a 600 s budget, one repeat pooled in, so that the
   kind that tripped on the final tree is also covered.

The verdict per kind:
- **fixed**, if the pooled loss at the long length lies wholly above −0.4%
  and the default length still reads below zero;
- **per token**, if the pooled loss at the long length lies wholly below
  −0.4%;
- **inconclusive** otherwise: one repeat pooled in, then the decision is
  taken as per token, the conservative reading.

### D3. Probes for the source, cheapest first, none landing

Each probe answers one question and is thrown away:
1. **Lazy pipelines.** The tail pipelines (`kernel_qwen4_moe_mm_{mid,down}_nax`
   32-token, `_nax16`, `_nax8` for 16/10) are created on first use, inside the
   first prefill of each process. A probe creates them at engine open. If the
   decode loss disappears, the fix is to create them at open, which is
   bit-identical.
2. **Mid or down.** A probe knob enables the tails on the mid side only, then
   on the down side only, run with MTP-code at the default length. It shows
   which half carries the cost.
3. **Command-buffer timing.** `DS4_METAL_CB_TIMES=1` on one A run and one B run
   of MTP-code, single runs outside the harness, one after another. It shows
   whether the extra time sits in the first command buffers of decode or is
   spread out.

A probe that removes the loss becomes a candidate fix. It lands only if it is
bit-identical (`--bitwise`) and its own A/B shows no metric wholly below zero.

### D4. The gate itself

It is the line `70` measured:
`(type == 12u || type == 39u || type == 16u || type == 10u) &&
ds4_gpu_device_is_m5_apple_silicon()`. Its comment becomes "on M5 for both
packs". The variant below 4096 tokens is not revisited: it gave up the 8192
gain and lost the same on decode.

### D5. The trade-off clause, only if D2 says "fixed" or the owner chooses it

The clause is added to `openspec/config.yaml` after the keep rule:

> A kernel step that saves prefill time may be kept although one decode
> metric's pooled CI lies wholly below zero, if all of these hold:
> - its output is bitwise identical;
> - the loss, re-measured with 512-token decode phases, shrinks as a fixed
>   per-phase cost would, or its per-request size (loss times phase time) is
>   below a tenth of the prefill time the step saves on a 512-token turn;
> - the proposal names the trade and the owner approved it.
>
> The record row keeps the loss visible.

This keeps the rule strict for every other case. The per-request bound comes
from the measured figures: 140 ms saved against 10-15 ms is about 10×. Under
outcome (c) the clause is the owner's call and is written only with that
approval, recorded in tasks.md.

### D6. Checks

- **Tools:** `python3 tests/test_ab_bench.py`, plus one A/A MTP-code run at
  `--gen 512` (noise floor at that length).
- **The gate:** `make test-qwen4-kernels` with every `Q2 tiles` hash equal to
  `70`'s pin, which the test prints, and the three byte-exact lines.
- **Model runs:** one after another, nothing beside them, and each started only
  at the Nominal thermal state.

### D7. Review

A step review after S0 and after the fix or gate. A final pass over the region
touched: the harness option, `qwen4_moe_mm_tails` and any fix. No probe code
may remain (`rg` for the probe knob names).

## Risks / Trade-offs

- **Longer phases can hide a per-token cost behind noise** → D2's thresholds
  are set from the default runs' CI half-widths, and an inconclusive result is
  taken as per token.
- **The fixed-cost reading could be a coincidence of three campaigns** → D2
  measures it directly, and the proposal does not rely on it.
- **A trade-off clause invites more trades** → it is bounded (bitwise output,
  a 10× bound, the owner's approval) and names the evidence it needs.
- **The cost could be real per token and unremovable** → outcome (c) keeps
  `DS4_QWEN4_MOE_TAILS=1` as the documented prefill-first setting, which needs
  no code.

## Open Questions

- Outcome (c), if it comes: the owner chooses between the clause with the tails
  on and the tails off with the env documented. The proposal's break-even table
  is the input.
