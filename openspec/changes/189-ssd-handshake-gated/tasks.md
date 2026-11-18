# Tasks

GPU: sections 2 to 4. Model runs are strictly sequential; a process that
opens a GGUF is a model run. Every model run is under the one-second memory
guard; memory-locked runs only on streamed processes and never while a
container, another model process or an XProtect scan over 4 GiB is running.
`$SCR` is `~/.sf/q3-8flash/scratch`; this change's files go in `$SCR/c189/`.

"The step checks": `make -j8` with no warnings; `make test -j8`, reading the
suite names; `tests/test_qwen4_ssd_experts` on Metal.

## 1. Branch (design D1; no GPU)

- [ ] 1.1 `git config rerere.enabled true`; `git switch -c perf/189-ssd-handshake-gated dd8db0d`; `git merge main`. Resolve against `188`'s eviction order; find every reader of the touched cache fields with `rg` first.
- [ ] 1.2 The step checks (model-less part).

## 2. Re-establish correctness (design D1)

- [ ] 2.1 `tests/test_qwen4_ssd_experts` on Metal: every case `PASS`, the handshake cases included.
- [ ] 2.2 Streamed equals resident, token gate, Q4 then Q2, plain and both MTP kinds.
- [ ] 2.3 Resident `ab_bench.py --bitwise` against `main`: `PASS (tokens; bitwise)`.

## 3. Step 0: the fixed-cache table (design D2)

- [ ] 3.1 Read the plan's slot counts at 48 GB for the plain and MTP contexts on Q4 (one engine open each, logged); choose the three sizes.
- [ ] 3.2 Q4, steady state: ungated port against `main` at the three sizes, plain and both MTP kinds, 8 pairs each. Record the table in `$SCR/c189/steps.txt`.
- [ ] 3.3 Q4, one cold check at the plan's size.
- [ ] 3.4 Q2 the same, if D2's condition holds.
- [ ] 3.5 Choose the gate by D4, or close by D3's last clause.

## 4. Step S1: the gate (design D3, D4)

- [ ] 4.1 The predicate at the handshake's entry; a model-less test that the ungated path runs where the gate says no.
- [ ] 4.2 The step checks; 2.2 again on the gated build.
- [ ] 4.3 The gated build against `main` at the measured sizes, steady state. Keep or drop by D3.

## 5. Review and closing

- [ ] 5.1 Final pass over the port and the gate: no dead code in the `.inc` files; the kill switch kept only per D4.
- [ ] 5.2 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`; a resident record row against the segment start.
- [ ] 5.3 `docs/SSD_STREAMING.md` (the handshake, its gate, the fixed-cache table); `docs/upstream-prs.md` (#1328: adopt with the gate, or drop again with the table).
- [ ] 5.4 `openspec validate 189-ssd-handshake-gated --strict` passes.
- [ ] 5.5 Report to the user in Italian. Land as one signed commit with #1328's author as `Co-authored-by`; delete `$SCR/c189/`; archive the change; delete the branch `perf/170-ssd-decode-handshake`.
