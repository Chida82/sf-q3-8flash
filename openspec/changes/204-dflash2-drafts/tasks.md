# Tasks

GPU: section 1. Model runs strictly sequential; a Splash run is a model
run. `$SCR/c204/` holds this change's files.

## 1. Step 0: Splash on this Mac (design D1-D3)

- [ ] 1.1 Ask the owner: install route (desktop app or Homebrew) and the model download (which GGUF, size, where). Nothing installed or downloaded before the answer. *(Open, 2026-11-20: the owner's answer reached the night executor relayed by the main session at about 00:05: Homebrew (`brew tap incoai/tap`, `brew install incoai/tap/splash`, nothing else), and the download of `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF:Q2_0` (2 shards, 61.86 GiB) only if Splash refuses this child's GGUFs; Splash's run rules: never beside a model run of this engine or a measurement, `splash serve` in the foreground under the memory guard, stopped by its own pid, `--max-cache-disk 0`, versions recorded; no Splash run after 07:15. The executor does not install on an approval it did not receive itself, so the main session was to run the two brew commands in windows the executor kept free of model runs (01:28-02:00, 03:09-03:20, 04:41-05:45); nothing was installed in them. Nothing is installed and nothing was downloaded.)*
- [x] 1.2 Install as approved; record versions, the GGUF and the draft revision used. *(2026-11-20: the owner ran `brew tap incoai/tap` and `brew install incoai/tap/splash`: Splash 1.7.0. Splash refused this child's Q4 GGUF ("GGUF tensors this build cannot load: hc_attn_inject.weight (F16) in 48 layers, hc_ffn_inject.weight (F16) in 48 layers, indexer.q_proj.weight (Q8_0) in 12 layers, indexer.k_proj.weight (Q8_0) in 12 layers"), so it downloaded `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF:Q2_0` at revision ed59f92082b1 (62 GiB) and the draft `incoai/Qwen3.8-Flash-Next-DFlash2` (1.1 GiB) into the shared Hugging Face cache. Splash keeps 9.7 MB of its own in `~/Library/Application Support/Splash`. The VM was off and the sfctl service stopped for every run.)*
- [x] 1.3 Splash: code and prose prompts, 512 tokens, 3 runs each, with the draft and, if possible, without; record decode tokens/s and tokens accepted per cycle. *(2026-11-20, `splash serve --max-cache-disk 0 --language-only --idle-release off`, under the one-second memory guard. Two workloads: the bench's prompts as raw completions (2024 / 2049 tokens, 512 generated, 3 runs), and three chat prompts whose answer the model cannot recall (a Python module, a C function, an original story; thinking off, 512 tokens, 2 runs), timed on the client from the first to the last streamed chunk, the same method for both engines. Splash has no option that disables the draft: its plain decode is taken from its own start-up measurement of a one-row step, 15.26 ms, about 65.5 t/s.*

  *| Splash, ISTA Q2_0 | raw code | raw prose | chat Python | chat C | chat story |*
  *|---|---|---|---|---|---|*
  *| `--verify-rows auto` (default), t/s | 208.3 | 265.8 | 230.3 | 258.7 | 121.5 |*
  *| tokens per cycle | 5.4 | 6.9 | 5.5 | 6.3 | 2.7 |*
  *| `--verify-rows all`, t/s | 157.9 | 216.7 | 232.9 | 264.3 | 120.9 |*
  *| tokens per cycle | 3.7 | 5.2 | 5.3 | 6.1 | 2.7 |*

  *Greedy output is not repeatable with the default: the three raw runs of each prompt gave three different texts, as Splash's own log warns. `--verify-rows all` makes the raw runs repeat; in chat the second run still differs from the first, because a request restored from Splash's int8 cached state (`--cached-states int8`, the default) can differ at near ties. This engine gave identical text for every run, plain and MTP alike.)*
- [x] 1.4 This engine on Q4: the same prompts, plain and `--mtp`, 3 runs each; record decode and tokens per cycle. *(Done 2026-11-20 on `main` bb1f9e8, resident, the bench's code (`rax.c`) and prose (`speed-bench/promessi_sposi.txt`) prompts at 2048 tokens, 512 generated, greedy, 3 runs each, medians; Q2 too, for a comparison with Splash's Q2_0 file if Splash refuses this child's GGUFs:*

  *| Pack | Prompt | Plain decode | MTP decode | MTP / plain | Tokens per cycle |*
  *|---|---|---|---|---|---|*
  *| Q4 | code | 54.90 t/s | 80.61 | 1.468 | 2.09 |*
  *| Q4 | prose | 54.26 | 65.23 | 1.202 | 1.57 |*
  *| Q2 | code | 54.15 | 78.47 | 1.449 | 2.06 |*
  *| Q2 | prose | 54.57 | 59.44 | 1.089 | 1.49 |*)*
- [x] 1.5 Table and projected gain by D1. Close, or continue to section 2. *(2026-11-20. This engine on the same chat prompts (server, `--ctx 32768`, 2 runs):*

  *| This engine | chat Python | chat C | chat story |*
  *|---|---|---|---|*
  *| Q2 plain, t/s | 60.2 | 60.4 | 60.5 |*
  *| Q2 `--mtp` | 90.5 | 88.3 | 73.7 |*
  *| Q4 plain | 58.9 | 58.8 | 58.9 |*
  *| Q4 `--mtp` | 88.6 | 84.9 | 72.0 |*

  *D1, speculative over plain on Q2-class weights (Splash's plain from its one-row step):*

  *| | raw code | raw prose | chat Python | chat C | chat story |*
  *|---|---|---|---|---|---|*
  *| Splash (default) | 3.18 | 4.06 | 3.52 | 3.95 | 1.85 |*
  *| This engine, MTP | 1.45 | 1.09 | 1.50 | 1.46 | 1.22 |*
  *| Projected gain | +119% | +273% | +134% | +170% | +52% |*

  *Step 0 passes D1 by a wide margin on every prompt, also with `--verify-rows all` (chat Python +137%, C +176%, story +52%). The plain decode of the two engines is close (65.5 against 60.2 t/s), so the gap is the draft. Limits: different weights (ISTA's Q2_0 against this child's pack, whose hyper-connection and indexer tensors Splash does not load); Splash's plain figure is its start-up measurement, not a run; one Mac, 512 tokens. Section 2 waits for the owner's decision.)*
- [ ] 1.6 Remove the install and the downloads as agreed in 1.1.

## 2. Feasibility (design D4; no GPU; only if 1.5 passes)

- [ ] 2.1 Rollback: what verifying up to 8 rows needs for GDN and the KV caches, against the current 3-row path.
- [ ] 2.2 Draft weights: a GGUF component through the shared Hugging Face cache (SPEC.md §C), the tensors and their formats.
- [ ] 2.3 Memory: the draft and its window in the resident and streamed plans.
- [ ] 2.4 Owner decision on the product contract (external draft model).
- [ ] 2.5 Rewrite design and tasks for S1 (`openspec-update-change`).

## 3. Closing

- [ ] 3.1 `openspec validate 204-dflash2-drafts --strict`; report in Italian; land as one signed commit (docs only if closed at step 0); archive.
