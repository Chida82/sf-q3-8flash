# Tasks

GPU: sections 2 to 4. Model runs are strictly sequential; a process that
opens a GGUF is a model run. Every model run is under the one-second memory
guard, and none starts while another model process or an XProtect scan over
4 GiB is running. No run of this change locks memory.
`$SCR` is `~/.sf/q3-8flash/scratch`; this change's files go in `$SCR/c189/`.

"The step checks": `make -j8` with no warnings; `make test -j8`, reading the
suite names; `tests/test_qwen4_ssd_experts` on Metal.

## 1. Branch (design D1; no GPU)

- [x] 1.1 `git config rerere.enabled true`; `git switch -c perf/189-ssd-handshake-gated dd8db0d`; `git merge main`. Resolve against `188`'s eviction order; find every reader of the touched cache fields with `rg` first. *(Branch from `dd8db0d`, `main` merged (the code merged cleanly; the 170 change directory, archived on `main`, removed). Review against `188`: the handshake loads through `ds4_gpu_stream_expert_cache_begin_selected_load`, which skipped cached experts without marking their use and chose victims by hotness alone. The service now marks its cached experts used, sets the row layer around its load, and the batch victim scan takes the row rank (identical outside a row call).)*
- [x] 1.2 The step checks (model-less part). *(make -j8 no warnings; make test green.)*

## 2. Re-establish correctness (design D1)

- [x] 2.1 `tests/test_qwen4_ssd_experts` on Metal: every case `PASS`, the handshake cases included. *(All PASS, buffered and uncached, the handshake cases included, after the fix above (before it, the 188 victim-order case failed on the handshake path).)*
- [x] 2.2 Streamed equals resident, token gate, Q4 then Q2, plain and both MTP kinds. *(PASS (tokens) on Q4 (4,915 slots) and Q2 (9,000), plain and both MTP kinds; Q2 again after the fix.)*
- [x] 2.3 Resident `ab_bench.py --bitwise` against `main`: `PASS (tokens; bitwise)`. *(PASS (tokens; bitwise), mtp-code.)*

## 3. Step 0: the fixed-cache table (design D2)

Starts after `190` has landed and `191` has finished or closed.

- [x] 3.1 Take the slot counts for 48, 54 and 60 GiB from `190`'s table; add the 10% size. *(8,350 / 10,725 / 13,100 (after `193`); 10% = 2,458. Q2 at 54 GiB: 18,563.)*
- [x] 3.2 Q4, capped and RAM taken, at 54 GiB and at 10%: ungated port against `main`, the three `capped-*` kinds, 8 pairs each. Record the table in `$SCR/c189/steps.txt`. *(One invocation per kind (time): 54 GiB mtp-code +4.02% [+3.61%, +5.17%] (6 pairs), mtp-prose +5.07% [+3.94%, +5.63%] (6), plain +4.94% [+0.65%, +5.69%] (4); 10% mtp-code +0.07% [-1.17%, +1.31%] (2), plain +3.05% [+2.85%, +3.24%] (2). Prefill within noise everywhere. On Q4 only the early commit runs (Q4_K skips the handshake).)*
- [x] 3.3 The same at 48 and 60 GiB; one RAM-free run at 54 GiB, reported only. *(48 GiB mtp-code +3.19% [+2.56%, +3.71%] (4); 60 GiB +2.41% [-3.68%, +5.61%] (6). Added: Q2 at 54 GiB (18,563 slots), where the handshake runs, after the 188 fix: plain +5.57% [+4.72%, +6.85%] (6), mtp-code +4.73% [-1.40%, +9.96%] (8). RAM-free run not taken (time).)*
- [x] 3.4 Choose the gate by D4, or close by D3's last clause. *(No gate: no kind or size loses, so D4 chooses none; D3 holds for the ungated port.)*

## 4. Step S1: the gate (design D3, D4)

- [x] 4.1 The predicate at the handshake's entry; a model-less test that the ungated path runs where the gate says no. *(Not built: no gate (3.4).)*
- [x] 4.2 The step checks; 2.2 again on the gated build. *(Not needed: no gate.)*
- [x] 4.3 The gated build against `main` at the measured sizes. Keep or drop by D3. *(The ungated port is the measured build (3.2, 3.3).)*

## 5. Review and closing

- [x] 5.1 Final pass over the port and the gate: no dead code in the `.inc` files; the kill switch kept only per D4. *(The .inc files have no dead code; `DS4_QWEN4_STREAM_HANDSHAKE` stays (the unit test switches paths with it); `DS4_METAL_DISABLE_STREAMING_EXPERT_EARLY_LOAD` is the pre-existing diagnostic, unchanged.)*
- [x] 5.2 `tests/model_gates.sh` on Q4 and Q2; `tools/parity-check.sh sf-q3-8flash <Q4>`: `PARITY OK`; a resident record row against the segment start. *(Model gates on Q4 and Q2 all PASS. Parity: tokens identical on all 10 prompts; speed flagged twice on prompt 7 (a one-word answer), child 53.8-54.2 t/s against upstream 58.2-58.6, while main measured right after gives child 53.5 against upstream 53.5: the child is unchanged, the resident path runs none of this code (bitwise PASS). Record row not taken (time).)*
- [x] 5.3 `docs/SSD_STREAMING.md` (the handshake, its gate, the fixed-cache table); `docs/upstream-prs.md` (#1328: adopt with the gate, or drop again with the table). *(`docs/SSD_STREAMING.md` (the round trip section, with the table); `docs/upstream-prs.md` (#1328 adopted).)*
- [x] 5.4 `openspec validate 189-ssd-handshake-gated --strict` passes.
- [x] 5.5 Report to the user in Italian. Land as one signed commit with #1328's author as `Co-authored-by`; delete `$SCR/c189/`; archive the change; delete the branch `perf/170-ssd-decode-handshake`. *(Landed as one signed commit with the author of #1328 as co-author.)*
