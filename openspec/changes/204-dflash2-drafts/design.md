# Design

## Context

Built-in MTP (`--mtp`) drafts 1-2 tokens per cycle from the model's own
head and verifies up to 3 rows; rollback of the GDN recurrent state is
bounded by that depth. Splash runs Qwen3.8-Flash-Next with a DFlash 2 draft
on Metal, on GGUFs other than this child's (`ISTA-DASLab/...-GSQ-RCO-GGUF:Q2_0`
in its README; unsloth's GGUFs load too). It chooses verify rows per cycle
from measured step costs, and records speculation counts in its API
responses. Splash is installed with Homebrew or a desktop app; both change
the machine.

## Goals / Non-Goals

**Goals:**
- Know, on this Mac, what DFlash 2 gains over MTP before writing code.
- Keep the measurement fair across two engines with different weights.

**Non-Goals:**
- Training a draft (none exists for DeepSeek V4.1; out of scope).
- Replacing MTP.
- Copying Splash code: if S1 proceeds, the draft runs on this child's own
  kernels, with Splash and the DFlash 2 release as references only.

## Decisions

**D1, step 0 measures ratios, not absolute speed.** The two engines differ
in weights, kernels and scheduling, so absolute decode decides nothing. For
each engine: speculative decode / plain decode on the same prompts, greedy,
one request at a time, resident, nothing else running (no VM or container).
Splash's plain decode is taken with its draft disabled if it allows it; if
it does not, its tokens accepted per cycle against this engine's MTP decide
instead, priced with this engine's own cost per verified row (`197`'s depth
2 and 3 figures). Projected gain = (Splash ratio / this engine's MTP ratio)
- 1. Pass: at least +10% on code or prose, neither below -2%. Below that,
close with the table.

**D2, the install is isolated and removed.** The owner chooses the route:
the desktop app (dragged to Applications, removed after) or Homebrew
(`brew install incoai/tap/splash`, `brew uninstall` and `brew untap` after).
Its downloads go to the shared Hugging Face cache; whatever step 0 adds is
listed and deleted at the end unless the owner keeps it. No Splash process
runs beside a model process of this engine.

**D3, workloads.** The bench's code and prose prompts (`speed-bench/`),
512 generated tokens, 3 runs per engine and mode, medians. Splash serves
over HTTP: its figures are taken from the server's own decode timing or
speculation counts, not from end-to-end wall time including HTTP.

**D4, S1 stays separate from step 0.** If step 0 passes, the feasibility
findings (rollback depth, draft GGUF, memory, kernels) rewrite this design
and the tasks before any build, and the owner decides the contract change.

## Risks / Trade-offs

- Splash may not load this child's GGUFs and the two engines then run
  different quantizations; the ratio method absorbs most of that, not all
  (acceptance depends on how close the target is to the weights the draft
  was trained on).
- Splash's adaptive verify rows may hide a cost this engine would pay with
  a fixed depth.
- An app or brew install is a change to the machine: approval first, and
  removal is part of the step.
- If S1 proceeds, the draft adds code with no upstream counterpart, about
  1.2 GB of memory, and a deeper rollback that the SSD path also pays.
