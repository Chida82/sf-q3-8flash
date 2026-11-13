# Design

## Context

`sfctl` already exists in `sf-ds4-1flash` (its `675-sfctl` design). It runs
each model from a serve worktree at local `main`, never starts on its own,
allows one engine at a time, and reads everything model-specific from
`sfctl/sf-<model>.conf`. This change brings it here and removes what kept the
copies from being identical.

## Decisions

### D1. Three shared files, one per-model file
`sfctl/sfctl`, `sfctl/README.md` and `tests/test_sfctl.sh` are byte-identical in
every child; only `sfctl/sf-<model>.conf` differs. A fix to sfctl is then a
copy, not a port.
- The README uses `<model>` and `<port>` and points to the config's comments
  for what the service runs.
- The test sources the checkout's only `sf-*.conf` for `SF_SERVER` and
  `SF_PORT`, and uses `no-such-model` for the not-installed case.

Alternative rejected: keep model-specific READMEs and tests. They drift, and
the next fix has to be adapted by hand in each child.

### D2. The service options
- **Q4 resident, no SSD streaming.** Q4 is about 70 GiB resident; with a 256K
  context the server plans 89.3 GiB (KV 8.33, buffers 11.24, model 69.73) on a
  128 GiB Mac. Streaming would only cost speed here.
- **256K context, 64K output tokens.** The native context; coding agents need
  long contexts, and Qwen's reasoning can spend hundreds of tokens before the
  answer.
- **`--mtp --mtp-exact-sampling`.** Built-in MTP is free speed for greedy
  requests and, with exact sampling, keeps the ordinary distribution for
  sampled ones. Nothing in the service may change output.
- **Vision on.** The projector is 0.6 GiB.
- **Disk KV 32 GiB in `~/.sf/q3-8flash/kv`**, the child's home, as in
  `sf-ds4-1flash`.
- **No boost option:** this child has no fanboost; sfctl only runs
  `fanboost check` when an option starts with `--boost`.

### D3. `download.sh` and `hf` agent mode
`hf` 2.4 prints hints and then `path=<file>` when it detects an AI agent, and
the bare path otherwise. `download.sh` keeps the last line and strips `path=`,
which handles both forms; the existing `[ -s "$CACHED" ]` check still rejects
anything that is not a file. The fake `hf` in `tests/test_model_download.py`
gains a `FAKE_HF_AGENT` mode that prints the agent form.

## Risks / Trade-offs

- **The `~/.local/bin/sfctl` link points to the last installed serve.** Since
  the script is identical everywhere, which serve it points to does not matter
  until two children carry different versions; `sfctl update` on each child
  brings them back in line.
- **Exact sampling runs MTP at depth two at nonzero temperature**, so sampled
  requests gain less from MTP than greedy ones. Accepted: no precision loss.
