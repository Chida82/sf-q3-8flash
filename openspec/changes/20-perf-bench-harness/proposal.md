# Proposal

## Why

Every performance change in this set needs a before/after verdict, and on the
target machine (MacBook Pro Mac17,6, M5 Max 40-core GPU, 128 GB) GPU heat lowers
throughput during a run. The existing tools do not fit:

- StarForge's `tools/speed-compare.sh` compares against upstream, not two builds
  of the child. It defaults to `--ssd-streaming` (which Qwen rejects), waits 180 s
  between runs and takes about 4 minutes per run.
- `sf-q3-8flash-bench` measures prefill and plain decode but not built-in MTP:
  `speculative = false` is hard-coded (`sf-ablate(specdec)` in `ds4_bench.c`).

The biggest candidate gains (`30-mtp-cycle`) are MTP-only, so without MTP coverage
the best candidate cannot be judged.

## What Changes

- A script under `speed-bench/` that A/B-compares two child builds (A = baseline,
  B = candidate) on the same GGUF, in **at most 10 minutes**, shorter by default.
- **Preflight**, refusing to start unless:
  - the charger is connected;
  - `thermal_state` is Nominal;
  - GPU temperature is below a threshold;
  - no other large model process is running.

  `mactop --headless` provides these readings without sudo.
- **Untimed warm-up**, so the 69.7 GiB of resident weights are paged in first.
  The BF16 n-gram table is read with `F_NOCACHE` and cannot be warmed.
- **Interleaved order** (A B B A …), so thermal drift affects both builds
  equally. The verdict is the median B/A ratio per metric.
- **GPU log**: frequency, temperature and power are logged at 1 Hz beside every
  sample. A sample whose GPU frequency falls below a set fraction of the run's
  peak is flagged and excluded.
- **Metrics:**
  - plain decode tok/s;
  - prefill tok/s at 512, 2048 and 8192 new tokens. The short points match
    suffixes resumed from the disk KV cache;
  - MTP decode tok/s, tokens per cycle and cycle-time breakdown
    (`--mtp --mtp-timing`) on one code prompt and one prose prompt;
  - prefill with `--mtp` on.
- **Correctness gate**: greedy output of A and B must be token-identical (hash of
  the generated tokens). For changes that claim bitwise identity, frontier
  logits are dumped (`--dump-frontier-logits-dir`) and compared bit-exact.
- Output: raw CSV per sample, GPU log and a one-screen summary.
- Works on the Q4 default model and on the Q2 model via `-m`.

## Capabilities

### New Capabilities
- `perf-harness`: A/B throughput and correctness measurement between two child
  builds, including the thermal preflight, interleaving, frequency-based sample
  rejection, the metric set and the 10-minute budget.

### Modified Capabilities
None.

## Impact

- New script and short README section in `speed-bench/`.
- Uses the installed `mactop`. Its absence must be reported, not silently ignored.
- The design decides where MTP is measured: through the CLI, or by giving
  `sf-q3-8flash-bench` an MTP mode. The second touches `ds4_bench.c` and its
  `sf-ablate(specdec)` site.
- Never runs two model processes at once. It is not a CI gate; it produces the
  verdict every other change in this set cites.
