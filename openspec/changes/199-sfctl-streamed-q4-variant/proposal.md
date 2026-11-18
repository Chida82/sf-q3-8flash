# Proposal

## Why

The owner's second use of SSD streaming is a service: Q4 on this Mac held
to 48-60 GiB so other work can run beside it (`190`). The service today has
two variants, `q3-8flash-q4` (resident, about 70 GiB) and `q3-8flash-q2`
(about 42 GiB), sharing one `SF_ARGS`. There is no way to start Q4
streamed with a fixed cache: `sfctl` passes the same arguments to every
variant, and a variant only picks the weights.

Q2 does not need streaming for this use: resident it already fits under
48 GiB. A streamed Q4 is the variant the owner's use needs, and it has to
be measured as the service runs it, `--ctx 262144 --mtp` with vision, not
only in the bench.

## What Changes

- **sfctl: per-variant arguments.** A config may set `SF_ARGS_<variant>`,
  appended to `SF_ARGS` for that variant, with the same validation as
  `SF_ARGS`. `sfctl/sfctl` and `tests/test_sfctl.sh` are shared by every
  child: the change is made identically in each child that has them, as
  their README requires, and a child that sets no `SF_ARGS_<variant>`
  behaves as today.
- **The variant**: `q4s` in `sfctl/sf-q3-8flash.conf`, the Q4 weights, with
  `--ssd-streaming --ssd-streaming-cache-experts <slots>` for 54 GiB (9,701
  slots by `190`'s measurement, or the footprint option of `196` if it has
  landed), its own disk KV directory (`kv-q4s`).
- **A service-level check**: start the variant from a serve worktree of the
  branch (not the owner's), send the requests of an agent session (a long
  system prompt, tool results, short answers), record time to first token,
  decode rate and the process footprint against `q4` resident.
- `install`, `update` and the serve sync stay the owner's: this change
  prepares and tests them, it does not run them on the owner's service.

## Impact

- `sfctl/sfctl`, `sfctl/README.md`, `tests/test_sfctl.sh` (shared, mirrored
  to the other children with `sfctl`), `sfctl/sf-q3-8flash.conf`,
  `AGENTS.md` (the serving section).
- Starts after `190`; the slot count follows `193` and `196` if they land
  first.
