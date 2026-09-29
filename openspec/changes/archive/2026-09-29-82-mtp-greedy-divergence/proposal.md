# Proposal

## Why

With `--mtp`, greedy output must be exactly the plain greedy output
(`mtp-speculation`, "Greedy output is unchanged by MTP"). On 2026-09-27, while
`81` compared this child with ds4, one of six cases broke that rule. Nothing
in the child's checks caught it, because none of them compares MTP output with
plain output on the Q2 pack. This change finds out why the outputs diverge,
fixes the cause if a bit-identical fix exists, and adds the missing check.

## What is known

**The case.** The Q2 pack (`Qwen3.8-Flash-Next-Q2.gguf`), upstream's networking
prompt from `speed-bench/qwen38-checkpoints`:

```sh
./sf-q3-8flash -m <Q2> --ctx 8192 --temp 0 --nothink -n 256 --mtp \
  -p "Explain how a computer sends a web request over TCP and receives the response. Write four clear paragraphs for a programmer learning networking."
```

- Without `--mtp` the output has md5 `4512c50b…`, the same on ds4 and on the
  child.
- With `--mtp`, ds4 at the merge-base `0aaea5a` gives the same `4512c50b…`.
- With `--mtp`, the child gives `0cdc9f3b…`. The text matches until the third
  paragraph, then takes a different wording ("and manages flow control…"
  against "and transmits these segments…"), and stays different.
- Both outputs repeat exactly over two runs each, so this is deterministic and
  not noise.

**Where it is not.**

| Case | Result |
|---|---|
| Q2, Hamlet (120 tokens), MTP | same as plain |
| Q2, Fibonacci (400 tokens), MTP | same as plain |
| Q4, all three prompts, MTP | same as plain, and the same as ds4 |
| Plain decode, all six cases | same on ds4 and the child |
| Parity oracle, both packs | token-identical, including its one `--mtp` prompt (a haiku) |

**Bisect.** The same command was run on each landed commit, one run each on Q2:

| Commit | Content | MTP output |
|---|---|---|
| `91f225a` | segment start, after `20` | same as plain |
| `59c6488` | `30`: prime the MTP predictor during prefill (#1062 `acce8da`) | **differs** |
| `695ad1a`, `334d1ce` | rest of `30` | differs |
| `53dcad6` | `50` | differs |
| `79f6b42` | after `61` | differs |
| `d242114` | `70` | differs |
| `cf74f17` | `80` (current `main`) | differs |

The first bad commit is `59c6488`. The divergence has nothing to do with `81`:
its tails only run in prefill batches above 64 tokens, and this prompt has
about 30.

**What `59c6488` does.** Each prompt chunk now primes the nextn layer's cache
once the trunk has run it. The priming writes the predictor residual over the
trunk streams in place, and the chunk's last row waits in a private tail that
the next forward flushes. Rewinds and payload restores drop the tail. Its
commit says that prefill logits are bit-identical to `main`. `30` checked this
on Q4 only: the parity oracle, the MTP limits, and the plain `--bitwise`
harness. `30` also recorded that MTP and plain outputs already differed on
`91f225a` from the second turn of a vision conversation, and accepted that as
pre-existing.

**How the priming can change committed tokens.** The priming changes the
drafts. A committed token must not depend on the drafts: its logits come from
the verify batch, which scores the parent plus one or two drafts. Three causes
are possible:
- **H1, the batch size changes the numbers.** The target logits of a row in a
  batch of 2 or 3 tokens are not bit-identical to those of the same row decoded
  alone. This was always true, but before `59c6488` other drafts led to other
  batch shapes, which happened to miss a near tie. H1 would not be specific to
  Q2. Q2 would only be where it showed first.
- **H2, the priming changes the target.** It writes over the trunk streams, so
  a path where those streams are read again would move the target's own
  state.
- **H3, the rollback is not exact.** After a rejected draft, the recurrent
  (GDN) state, the attention rows or the priming tail are not restored exactly,
  on a path that the new drafts reach.

The tools to tell these apart exist:
- `DS4_QWEN4_FT_LIST` runs a token sequence through the production Metal graph
  and dumps all-row logits, or teacher-forced logits for a
  `prefix|continuation` line;
- `DS4_QWEN4_GPU_CHUNK` sets its batch size;
- `DS4_QWEN4_MTP_BATCH_CHECK` compares sequential and paired GPU drafts;
- `DS4_QWEN4_MTP_DEPTH=2|3` pins the draft depth.

## What Changes

1. **S0, a regression check.** A new `tests/test_qwen4_mtp_identity.py`
   (design D1) runs a fixed prompt set through the CLI without and with
   `--mtp`, at the automatic depth and at pinned depths 2 and 3. It reports each
   pair as same or different, with the first differing word, and exits 1 on any
   difference.
2. **D1, extent.** S0 runs on both packs, on this tree and on `91f225a`. The
   result shows how often the divergence happens, whether it also reaches Q4,
   and whether it existed before priming on other prompts.
3. **D1b, depth data for a project rule.** The owner may pin MTP to one
   draft by project rule, or allow two drafts only above a speed gain, knowing
   the risk. For each pack, at depth 2 (one draft, a 2-row verify), depth 3 (two
   drafts, a 3-row verify) and the automatic depth, the change measures:
   - how many of S0's prompts diverge;
   - MTP decode speed and tokens per cycle on the harness's code and prose
     kinds, next to plain decode.

   Depth 1 means no draft: that is plain decode, identical by construction. If
   a fix lands, the table is measured again after it.
4. **D2, localization.** For the first diverging case, a probe (not landed)
   logs:
   - the committed token index;
   - the verify batch's shape;
   - the top-2 logit margin, in plain decode and in the MTP cycle.

   This finds the first token where the two runs part.
5. **D3, cause.** Three tests, run in order:
   - **H1:** the teacher-forced logits of the diverging sequence at batch sizes
     1, 2 and 3, compared bitwise;
   - **H2:** the target logits after prefill with and without MTP, compared
     bitwise;
   - **H3:** the target logits at the diverging position after a rejected
     draft, compared with the plain logits.
6. **D4, fix or decision.**
   - **H2 or H3 (a state bug):** fixed so that MTP output equals plain output
     again, while keeping the priming.
   - **H1:** the kernel or section whose result depends on the batch size is
     found. If it can be made bitwise independent of the batch size with no
     speed loss, that fix lands. If not, the options go to the owner with
     figures: the fix and its speed cost; or verification that re-scores
     disagreeing rows one at a time; or the requirement narrowed with the loss
     documented.
7. **Closing.** On both packs:
   - S0 passes;
   - the parity oracle and the MTP limits pass;
   - an A/B against `main` and a record row, if any code changed;
   - the README's note on the exception is updated;
   - the `acce8da` line in `docs/upstream-prs.md` is updated.

Not in scope:
- sampled (non-greedy) MTP, or `--mtp-exact-sampling`;
- the vision second-turn difference that `30` recorded as pre-existing. S0
  runs text prompts only. If D3 finds the same cause, the vision difference is
  noted and left to its own change.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `mtp-speculation`: a new requirement that MTP greedy identity is checked on
  both packs over a prompt set and at every depth, because the existing
  scenarios were checked on Q4 only.

## Impact

- New `tests/test_qwen4_mtp_identity.py`, and a line for it in `AGENTS.md` and
  `docs/TESTING.md`.
- Depending on the cause: `ds4.c` (MTP cycle, priming, rollback) or
  `ds4_metal.m` and `metal/qwen4.metal` (a kernel whose result depends on the
  batch size).
- `README.md` (the "Quality and performance" note), `docs/upstream-prs.md`
  (`acce8da`, #1062), and `speed-bench/perf-record.md` if code changed.
- No model format or API change.
