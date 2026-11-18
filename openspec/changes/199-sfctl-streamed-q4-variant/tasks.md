# Tasks

GPU: section 3. Model runs strictly sequential, each under the one-second
memory guard. `$SCR/c199/` holds this change's files. No `sfctl install`,
`update`, `start` of the owner's service, or serve sync: those are the
owner's.

## 1. sfctl (design D1; no GPU)

- [ ] 1.1 Branch `feature/199-sfctl-streamed-q4-variant`; `SF_ARGS_<variant>` in `load_conf` and the agent's argument list; `sfctl/README.md`.
- [ ] 1.2 `tests/test_sfctl.sh` cases; `make test -j8` names `sfctl tests passed`.

## 2. The variant (design D2; no GPU)

- [ ] 2.1 `q4s` in `sfctl/sf-q3-8flash.conf`; `sfctl plist q3-8flash-q4s` prints the expected arguments (read-only).

## 3. Service-level check (design D3)

- [ ] 3.1 The scripted agent session against `q4s` and against resident `q4`, from a scratch serve worktree on a free port.

## 4. Closing (design D4)

- [ ] 4.1 Mirror `sfctl/sfctl`, `sfctl/README.md`, `tests/test_sfctl.sh` to the other children with `sfctl`, each on its own branch with its tests.
- [ ] 4.2 `AGENTS.md` serving section; `openspec validate 199-sfctl-streamed-q4-variant --strict`.
- [ ] 4.3 Report to the owner with the session table and the exact commands for `sfctl update` and `sfctl start q3-8flash-q4s`, for the owner to run. Land as one signed commit; archive.
