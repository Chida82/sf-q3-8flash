# Design

## Context

The facts are in proposal.md, "What is known". They reduce to three points:
- the Q2 remainder tails are bit-identical and save 140-200 ms of prefill per
  turn;
- no tail kernel runs during decode, yet decode wall-clock with the tails on
  reads about -0.3% on average (range +0.2..-1.1%);
- every true null reads 0: the tails off in both builds, and two same-binary
  runs with only the prefill speed changed.

The source of the decode cost is still unknown. The owner decided on
2026-09-27 that it does not need to be known before landing: a loss of up to 2%
is accepted for a prefill gain of ten percent or more.

## Goals / Non-Goals

**Goals:**
- land the Q2 tails on M5 by default;
- write the owner's trade-off into the keep rule, with the loss kept visible.

**Non-Goals:**
- the tails for other types or devices;
- new tile widths;
- any change to decode kernels;
- finding the decode cost's source (left open, see Open Questions).

## Decisions

### D1. The gate

It is the line `70` measured: the M5 clause gains `type == 16u || type == 10u`,
next to Q4_K (12) and MXFP4 (39). Its comment says the low-bit tails trade a
small decode loss for prefill, as the owner accepted. The variant below 4096
tokens is not revisited: it gave up the 8192 gain and lost the same on decode.
The streamed path goes through the same function, so streamed Q2 prefill gets
the tails too; its token gate covers that.

### D2. The trade-off clause

Added to `openspec/config.yaml` after the keep rule:

> A kernel step with bitwise identical output that gains a prefill metric by
> ten percent or more (pooled median, CI wholly above zero) may be kept
> although a decode metric's pooled CI lies wholly below zero, if no decode
> metric's pooled median is below -2%. The owner approved this on 2026-09-27
> for the low-bit remainder tails of `81`. The performance record keeps the
> loss visible.

The bounds are the owner's words: "a 2% decode loss" against "a two-digit
prefill gain". The clause is narrow on purpose: bitwise output, one shape
at ten percent or more, and a loss bound. Every other case keeps the strict
rule.

### D3. The guard

One harness run against `main` on Q2 with `--bitwise`. `70`'s campaigns already
measured the same code at n = 5..48 per metric, so one run confirms that the
figures still hold on the tree with `80`. If a decode metric reads below -2%,
one repeat is pooled in before the step is dropped.

### D4. Checks

- **The gate:** `make test-qwen4-kernels` with the three
  `byte-exact mid/down nax=2` Q2 lines.
- **Model runs:** one after another, nothing beside them, and each started only
  at the Nominal thermal state.
- **Situation 0:** `main` is the tree on which `80`'s closing parity passed
  with both packs, so it is not run again.

### D6. Comparison with ds4

The owner asked for a table of ds4 against this child, both packs, with and
without MTP. It uses upstream's methods, so the numbers mean what upstream's
published ones mean:
- **Plain prefill and generation:** upstream's `ds4-bench` sweep
  (`docs/PERFORMANCE.md`: *I Promessi Sposi*, 2048-token intervals up to
  65536, 128 generation tokens per frontier), with the same command for both
  binaries.
- **MTP:** upstream's `ds4-bench` has no built-in Qwen MTP (only `--dspark`),
  so generation with and without `--mtp` is measured with the CLI on
  upstream's three Qwen cases (`speed-bench/qwen38-checkpoints`).
- **ds4** is the upstream tree at the child's merge-base, the same the parity
  oracle builds, so the difference is this child's work alone.
- A case ds4 cannot run leaves its ds4 cell empty and gets no percentage;
  nothing is estimated in its place.
- Order ds4, sf, sf, ds4, two runs per build and case, as upstream's
  checkpoint comparison did. This is a published comparison, not a keep
  decision: the keep rule stays with `ab_bench.py`.

### D7. Review

The step is one line and a comment. The final pass reads
`qwen4_moe_mm_tails` against AGENT.md and the surrounding idiom.

## Risks / Trade-offs

- **The decode loss is per token and grows on long answers** → it is bounded
  by the guard at 2%, and the proposal's break-even table shows the tails still
  win for turns that generate fewer than 600-2400 tokens.
  `DS4_QWEN4_MOE_TAILS=0` turns the tails off for long-generation workloads.
- **A trade-off clause invites more trades** → it is bounded (bitwise output,
  a ten percent gain, a 2% loss bound) and names the approval.

## Open Questions

- The source of the decode cost. The fixed-or-per-token test is ready to run
  with `--bench-arg=-n --bench-arg=512` if a later change wants the loss back.
