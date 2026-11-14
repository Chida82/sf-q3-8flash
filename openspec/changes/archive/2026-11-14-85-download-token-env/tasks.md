# Tasks

## 1. Token through the environment

- [x] 1.1 `download.sh`: pass `HF_TOKEN=$TOKEN` to the `hf download` command instead of `--token`; drop the read of `~/.cache/huggingface/token`.
- [x] 1.2 `tests/test_model_download.py`: the fake `hf` rejects `--token` in argv; add `test_token_goes_through_the_environment`.
- [x] 1.3 Run `python3 tests/test_model_download.py` (every case passes) and check that the new case fails against the old `download.sh`.
- [x] 1.4 Land as one signed commit on `main` when the owner asks, then `sfctl update q3-8flash`. (Landed 2026-11-14: 7 tests pass, the new case fails against the old script. `sfctl update` waits for the owner's "sync serve", with `90`, `91`, `88`.)
