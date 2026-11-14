# Proposal

## Why

`download.sh` passes the Hugging Face token to `hf download` as `--token
<value>`. Any local user can read it in `ps` while a 165 GiB download runs, and
`hf` 2.4 warns about it on every call (seen during `sfctl install` in `83`).
The script also reads `~/.cache/huggingface/token` itself and puts it on the
command line, although `hf` reads its own login.

## What Changes

- The token, from `--token` or `HF_TOKEN`, reaches `hf` through the `HF_TOKEN`
  environment variable of that one command, never through argv.
- With no token, `download.sh` no longer reads `~/.cache/huggingface/token`:
  `hf` uses its own login.
- `tests/test_model_download.py`: the fake `hf` asserts that `--token` never
  appears in argv, and a new case checks that `--token` arrives as `HF_TOKEN`.

Non-goals: no change to verification, links or components.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `service-control`: install and update keep the token out of argv.

## Impact

- `download.sh`, `tests/test_model_download.py`.
- No model, engine or server change; no A/B run.
