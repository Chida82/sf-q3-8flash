# Tasks

GPU: section 1. Model runs strictly sequential; a Splash run is a model
run. `$SCR/c204/` holds this change's files.

## 1. Step 0: Splash on this Mac (design D1-D3)

- [ ] 1.1 Ask the owner: install route (desktop app or Homebrew) and the model download (which GGUF, size, where). Nothing installed or downloaded before the answer. *(Open, 2026-11-20: the owner's answer reached the night executor relayed by the main session at about 00:05: Homebrew (`brew tap incoai/tap`, `brew install incoai/tap/splash`, nothing else), and the download of `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF:Q2_0` (2 shards, 61.86 GiB) only if Splash refuses this child's GGUFs; Splash's run rules: never beside a model run of this engine or a measurement, `splash serve` in the foreground under the memory guard, stopped by its own pid, `--max-cache-disk 0`, versions recorded; no Splash run after 07:15. The executor does not install on an approval it did not receive itself, so the main session was to run the two brew commands in windows the executor kept free of model runs (01:28-02:00, 03:09-03:20, 04:41-05:45); nothing was installed in them. Nothing is installed and nothing was downloaded.)*
- [ ] 1.2 Install as approved; record versions, the GGUF and the draft revision used.
- [ ] 1.3 Splash: code and prose prompts, 512 tokens, 3 runs each, with the draft and, if possible, without; record decode tokens/s and tokens accepted per cycle.
- [x] 1.4 This engine on Q4: the same prompts, plain and `--mtp`, 3 runs each; record decode and tokens per cycle. *(Done 2026-11-20 on `main` bb1f9e8, resident, the bench's code (`rax.c`) and prose (`speed-bench/promessi_sposi.txt`) prompts at 2048 tokens, 512 generated, greedy, 3 runs each, medians; Q2 too, for a comparison with Splash's Q2_0 file if Splash refuses this child's GGUFs:*

  *| Pack | Prompt | Plain decode | MTP decode | MTP / plain | Tokens per cycle |*
  *|---|---|---|---|---|---|*
  *| Q4 | code | 54.90 t/s | 80.61 | 1.468 | 2.09 |*
  *| Q4 | prose | 54.26 | 65.23 | 1.202 | 1.57 |*
  *| Q2 | code | 54.15 | 78.47 | 1.449 | 2.06 |*
  *| Q2 | prose | 54.57 | 59.44 | 1.089 | 1.49 |*)*
- [ ] 1.5 Table and projected gain by D1. Close, or continue to section 2.
- [ ] 1.6 Remove the install and the downloads as agreed in 1.1.

## 2. Feasibility (design D4; no GPU; only if 1.5 passes)

- [ ] 2.1 Rollback: what verifying up to 8 rows needs for GDN and the KV caches, against the current 3-row path.
- [ ] 2.2 Draft weights: a GGUF component through the shared Hugging Face cache (SPEC.md §C), the tensors and their formats.
- [ ] 2.3 Memory: the draft and its window in the resident and streamed plans.
- [ ] 2.4 Owner decision on the product contract (external draft model).
- [ ] 2.5 Rewrite design and tasks for S1 (`openspec-update-change`).

## 3. Closing

- [ ] 3.1 `openspec validate 204-dflash2-drafts --strict`; report in Italian; land as one signed commit (docs only if closed at step 0); archive.
