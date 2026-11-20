# Tasks

GPU: section 3. Model runs strictly sequential, each under the one-second
memory guard. `$SCR/c199/` holds this change's files. No `sfctl install`,
`update`, `start` of the owner's service, or serve sync: those are the
owner's.

## 1. sfctl (design D1; no GPU)

- [x] 1.1 Branch `feature/199-sfctl-streamed-q4-variant`; `SF_ARGS_<variant>` in `load_conf` and the agent's argument list; `sfctl/README.md`. *(`variant_args`, unset and checked per variant in `load_conf`, appended after `SF_ARGS` in the agent, read by `boost_check`. No streaming name in the shared files.)*
- [x] 1.2 `tests/test_sfctl.sh` cases; `make test -j8` names `sfctl tests passed`. *(Three cases: the options follow `SF_ARGS` with `@HOME@`/`@VARIANT@`, reach only their variant, and a forbidden character is refused. The pre-variant golden agent is unchanged. `make test -j8` green.)*

## 2. The variant (design D2; no GPU)

- [x] 2.1 `q4s` in `sfctl/sf-q3-8flash.conf`; `sfctl plist q3-8flash-q4s` prints the expected arguments (read-only). *(With a scratch HOME, since an installed service reads serve's config: `-m gguf/Qwen3.8-Flash-Next-Q4.gguf`, `SF_ARGS`, `kv-q4s`, then `--ssd-streaming --ssd-streaming-cache-experts 11831`; `plutil -lint` OK; the `q4` agent has no streaming option. First written at 10,725, `193`'s 54 GiB count; after rebasing on `205`, which plans the graph that is allocated, the count is the 54 GiB row of `docs/SSD_STREAMING.md` ("Capped RAM"), the service's shape `--ctx 262144 --mtp` with the 0.57 GiB projector: (54 - 23.53 - 0.57) GiB / 2,713,600 bytes per expert = 11,831 slots, the count `205`/3.1 measured at or under its plan. 3.1 confirms it at service level.)*

## 3. Service-level check (design D3)

- [x] 3.1 The scripted agent session against `q4s` and against resident `q4`, from a scratch serve worktree on a free port. *(2026-11-20, the branch rebased on `main` 7abdb53. `speed-bench/agent_reuse.py` (16 requests: two tool-loop conversations of 18-45K tokens through chat and responses, a side request, a server restart) with the service's arguments (`--ctx 262144 --tokens 65536 --mtp --mtp-exact-sampling`, the projector), the GGUF evicted before each variant, one at a time under the one-second memory guard; a 32 GiB Parallels VM was running beside, idle. `q4s` uses `SF_ARGS_q4s` as written, buffered reads.*

  *| | q4 resident | q4s (11,831 slots) |*
  *|---|---|---|*
  *| Responses | 16 | identical bytes, all 16 |*
  *| Planned memory | 86.94 GiB | 53.44 GiB (expert cache 29.90) |*
  *| Process footprint (steady) | 17 GB + 69.7 GiB mapped model | 47 GB + 6.3 GiB mapped |*
  *| Decode, mean of per-request averages (MTP) | 72.6 t/s | 44.0 t/s (-39%) |*
  *| Cold prefill 41-45K tokens (a.tool1, a.resp1) | 23.5 s, 28.5 s | 29.8 s, 30.5 s |*
  *| Whole session, wall | 155.2 s | 207.9 s (+34%) |*
  *| Guard max: compressor / file-backed | 2.5 / 16.7 GiB | 3.4 / 59.5 GiB |*

  *The 54 GiB plan holds at service level. With buffered reads the file cache filled the free RAM (file-backed up to 59.5 GiB); beside the idle VM nothing was compressed, but beside a neighbour that needs that RAM `195` measured the compressor taking it. `--ssd-streaming-uncached` (207) would keep the file cache out at about -30% decode; the owner keeps sfctl without it for now, so `SF_ARGS_q4s` does not set it.)*

## 4. Closing (design D4)

- [x] 4.1 Mirror `sfctl/sfctl`, `sfctl/README.md`, `tests/test_sfctl.sh` to the other children with `sfctl`, each on its own branch with its tests. *(2026-11-20: `sf-ds4-1flash` `feature/sfctl-variant-args` dfccbf1, `sf-ds4-1flash` `sys1` line `feature/sys1-sfctl-variant-args` 6b9b39e (from `sys1`, which had sfctl from before variants); configs unchanged. `make test -j8` names `sfctl tests passed` in each; with a scratch HOME `sfctl plist` is byte-identical before and after for `q3-8flash`, `-q4`, `-q2`, `ds4-1flash` and the `sys1` agent; the three files `cmp` equal.)*
- [x] 4.2 `AGENTS.md` serving section; `openspec validate 199-sfctl-streamed-q4-variant --strict`.
- [x] 4.3 Report to the owner with the session table and the exact commands for `sfctl update` and `sfctl start q3-8flash-q4s`, for the owner to run. Land as one signed commit; archive.
