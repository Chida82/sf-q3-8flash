# Tasks

Work happens on a branch, never on main. The model run in 3.2 is the only one
on the machine while it runs.

## 1. sfctl in this child

- [x] 1.1 `git switch -c feature/sfctl`; copy `sfctl/sfctl`, `sfctl/README.md` and `tests/test_sfctl.sh` from `sf-ds4-1flash`.
- [x] 1.2 `sfctl/sf-q3-8flash.conf` as in design D2, with its comment block. Verify `sfctl/sfctl plist q3-8flash` prints a plist that `plutil -lint` accepts.
- [x] 1.3 Make the README and the script's usage line model-agnostic (design D1). Verify `grep -n ds4-1flash sfctl/*` finds only the port list in "Adding a model".
- [x] 1.4 Make `tests/test_sfctl.sh` read model, server and port from the config; add it to `make test` and as `make test-sfctl`. Verify `make test` prints `sfctl tests passed` and `grep -c '^test:' Makefile` is 1.
- [x] 1.5 `README.md`: the service paragraph. `AGENTS.md`: the Service row and "Serving (sfctl)".

## 2. sf-ds4-1flash

- [x] 2.1 On `feature/sfctl-shared`, copy the three shared files from this child and move the service description into the comments of `sfctl/sf-ds4-1flash.conf`. Verify `cmp` finds the three files identical and `sh tests/test_sfctl.sh` passes there.

## 3. Verification and install

- [x] 3.1 `make test -j8` passes.
- [x] 3.2 Run `sf-q3-8flash-server` by hand with the arguments of the generated plist: listening in 15 s, 89.3 GiB planned, a chat request answers. Stop it.
- [x] 3.3 Land both branches on local `main` (signed commits).
- [x] 3.4 `sfctl/sfctl install` stops at `./download.sh q4`: `hf` 2.4 printed `path=<file>`. Fix `download.sh` on `fix/download-hf-path-output` (design D3) with a test case that fails without the fix; land it; remove the half-made serve worktree and install again. Verify `sfctl status` shows `q3-8flash stopped port 8912, serve <sha> = main`.
- [x] 3.5 `sfctl update ds4-1flash`, so its serve carries the shared files.
- [x] 3.6 Through launchd, one model at a time: `sfctl start q3-8flash`, a chat request, `sfctl start ds4-1flash` refused while Qwen runs, `sfctl stop q3-8flash`; then `sfctl start ds4-1flash`, a chat request, `sfctl stop ds4-1flash`. Both answer; `sfctl status` shows both stopped and `serve = main`.
