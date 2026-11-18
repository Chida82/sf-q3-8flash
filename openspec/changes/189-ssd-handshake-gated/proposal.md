# Proposal

## Why

`170-ssd-decode-handshake` ported upstream #1328: a streamed layer commits
its GPU work early and waits for its missing experts inside the command,
instead of draining the GPU first. It was dropped by its own rule on
2026-11-18, but its figures say the idea pays in part of the space:

| Kind and cache (Q2, emulated 48 GB) | Decode, `main` -> port |
|---|---|
| plain, 10.8K context, 3.35 GiB of experts | -2.7% [-2.9%, -2.1%] |
| mtp-code, 2K context | +4.0% [+3.5%, +4.3%] |
| mtp-prose, 2K context | +3.5% [-2.8%, +5.0%] |
| plain, 2K context, 9.5 GiB (by hand, 8 pairs) | +3.9% [+3.3%, +5.3%] |

Two variables moved together in that table: the kind (plain or MTP) and the
expert cache size (the plan sizes the cache from the context and from the
memory free at launch, and it varied across the night from 2064 to 2608
slots on Q2 and from 772 to 931 on Q4). The plain run at 2K suggests the cache
size, not MTP, decides the sign; the MTP runs alone cannot say. The likely
mechanism, from reading: a handshake layer cannot compute its cached experts
while the missing ones load, and the ordinary path does; with a small cache
most layers miss, and that overlap is worth more than the drain the handshake
saves.

The owner's service runs with `--mtp`, so a gain on MTP decode is the one
that reaches real use. This change measures the two variables apart, at a
fixed cache size, and enables the handshake only where it wins. It is
measured in the capped-RAM bench of `190-ssd-capped-ram-bench`, after
`191-ssd-decode-layer-round-trip`.

Performance under the intake criteria, on the streaming path the owner named
as a next focus.

## What Changes

- **Step 0, measurement only.** The port (`dd8db0d`) brought onto current
  `main`, then measured on Q4 at a fixed expert cache, the same slot count on
  both sides, at the 48, 54 and 60 GiB footprints and at one small cache,
  plain and MTP kinds (design D2). No gating code yet.
- **S1, the gate.** From step 0's table, one predicate decides per layer or
  per call whether the handshake runs: by kind (MTP verify rows only), by
  cache coverage (the share of the layer's selected experts already cached),
  or both. Elsewhere the ordinary path runs as on `main`.
- The keep rule weighs MTP decode and plain decode together (design D3).

Output must not change: token ids of a streamed run stay identical to the
resident run; the resident path stays bitwise unchanged.

## Impact

- `ds4_metal.m`, the port's `ds4_metal_stream_handshake.inc` and
  `ds4_metal_stream_overlap.inc`, `metal/qwen4.metal`,
  `tests/test_qwen4_ssd_experts.c`, `docs/SSD_STREAMING.md`,
  `docs/upstream-prs.md` (#1328's verdict).
- Builds on `188`'s eviction order: the port is rebased onto it, and the
  measurement is against `main` with `188`.
- Co-author when landed: the author of upstream #1328.
