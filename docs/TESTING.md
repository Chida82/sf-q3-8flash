# Testing

Run the model-less suite after every change:

```sh
make -j8
make test -j8
python3 tests/test_model_download.py
```

Focused checks:

```sh
make test-qwen4-kernels
make test-qwen4-q2
make test-qwen4-prefill-reuse
make test-q8-prefill-variants
make test-qwen4-ngrams
```

Model-backed checks require a Qwen3.8 GGUF:

```sh
DS4_TEST_MODEL=/absolute/path/model.gguf DS4_TEST_GLM_MTP=1 ./ds4_test
python3 tests/test_qwen4_mtp_limits.py --model /absolute/path/model.gguf
python3 tests/test_qwen4_mtp_identity.py --model /absolute/path/model.gguf
./sf-q3-8flash-eval -m /absolute/path/model.gguf --suite core
./sf-q3-8flash-bench -m /absolute/path/model.gguf
```

`test_qwen4_mtp_identity.py` compares MTP with plain greedy output on 12
prompts at the automatic depth and at depths 2 and 3. Run it on both packs
before landing MTP, prefill or decode work; it takes about 30 minutes per pack,
or half with `--depths auto`.

Vision parity additionally requires the original checkpoint, projector GGUF,
and an image; see `make help` for the three environment variables.

Before a PR, run StarForge's parity oracle against the upstream merge-base.
Greedy tokens must match exactly and median throughput must remain within 2%.

## `ds4_test` with a model: known failures

`./ds4_test` with a Qwen GGUF is not green, in this child or in upstream ds4.
Measured on 2026-09-29 on an M5 Max, one run each, with
`DS4_TEST_MODEL=<gguf> DS4_TEST_GLM_MTP=1 ./ds4_test`, on ds4 at the merge-base
`0aaea5a`, on this child before `82-mtp-greedy-divergence`, and after it. The
last two give the same failures, assertion for assertion.

| Test | What fails | Q2 | Q4 | Also in ds4 |
|---|---|---|---|---|
| `long-context` | 5 (Q2) or 1 (Q4) of the planted facts are not recalled at about 31k tokens; on Q4 "wrong assignment for Priya: got 9 expected 97" | 5 | 1 | yes |
| `metal-short-prefill` | `tokens[i] >= 0` at `tests/ds4_test.c` (cause not investigated) | 1 | 1 | yes |
| `logprob-vectors`, `local-golden-vectors`, `metal-ssd-streaming-cache-pressure` | `tests/test-vectors/flash-0731/*.vec` (DeepSeek vectors) is not in this child, so `fopen` fails | 3 | 3 | ds4 has the files, and fails on them too: its vectors are DeepSeek's, not Qwen's |
| Failure count | | 9 | 5 | 23 (Q2), 19 (Q4) |

ds4 has 14 more failures than the child on each pack: `ds4_engine_open` in the
cache-pressure test and every logprob-vector step, none of which reaches the
child's kept tests.

A change passes this suite when its failure list equals the child's list above:
same tests, same assertion lines, same counts. A new failing test, or a higher
count, is a regression until shown otherwise; a change in `long-context` is the
one to look at first, since it depends on attention.

To compare quickly, run the same command on a worktree of the commit before the
change (`git worktree add --detach <dir outside /tmp> <sha>`; `make ds4_test`),
one model process at a time, and diff the `tests/ds4_test.c:NNN: assertion
failed` lines. Line numbers move when `tests/ds4_test.c` changes, so before
trusting this table after a sync, check what upstream did to the test:

```sh
git diff --stat <merge-base-then> $(git merge-base HEAD upstream/main) -- tests/ds4_test.c
```

If the diff is large, or tests were added, renamed or removed, rebuild the
table by running ds4 at the new merge-base (`$SF/upstream/.worktrees/<sha7>`,
`ds4_test` already built there) and this child, on Q2 and Q4.
