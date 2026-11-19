# Tasks

GPU: section 1. Model runs strictly sequential; a Splash run is a model
run. `$SCR/c204/` holds this change's files.

## 1. Step 0: Splash on this Mac (design D1-D3)

- [ ] 1.1 Ask the owner: install route (desktop app or Homebrew) and the model download (which GGUF, size, where). Nothing installed or downloaded before the answer.
- [ ] 1.2 Install as approved; record versions, the GGUF and the draft revision used.
- [ ] 1.3 Splash: code and prose prompts, 512 tokens, 3 runs each, with the draft and, if possible, without; record decode tokens/s and tokens accepted per cycle.
- [ ] 1.4 This engine on Q4: the same prompts, plain and `--mtp`, 3 runs each; record decode and tokens per cycle.
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
