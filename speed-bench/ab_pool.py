#!/usr/bin/env python3
"""Pooled B/A pair ratios of several ab_bench invocations, with a bootstrap 95% CI.

usage: ab_pool.py <kind> [--prefill <frontier> | --sections <shape> <groups>] <out dir>...

Without an option the metric is decode (tokens/s over all frontiers, from samples.csv);
--prefill takes the prefill tokens/s of that frontier row; --sections takes a section-time
shape as the summary names it (for example "prefill +2048") and the target groups, and pools
the (target / untouched) ratios of sections.csv. Pairs the harness dropped as disturbed are
left out, as in its own verdict. See "Pooling" in speed-bench/README.md.
"""

import csv
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ab_bench as ab  # noqa: E402


def run_values(out, kind, prefill=None, shape=None, targets=()):
    """(build, value, dropped) per timed run of the kind, in run order."""
    runs = {}
    name = 'sections.csv' if shape else 'samples.csv'
    if not shape and (Path(out) / 'sections.csv').exists():
        raise ab.Stop(2, f'{out}: section-time runs include the profiler\'s waits; pool their --sections shapes')
    with open(Path(out) / name, newline='') as f:
        for r in csv.DictReader(f):
            if r['kind'] == kind and (not shape or r['shape'] == shape):
                runs.setdefault(int(r['run']), []).append(r)
    values = []
    for n in sorted(runs):
        rs = runs[n]
        if shape:
            target, rest = ab.section_split({g: float(rs[0][g]) for g in ab.GROUPS}, targets)
            v = target / rest
        elif prefill:
            row = next((r for r in rs if r['frontier'] == str(prefill)), None)
            if row is None:
                raise ab.Stop(2, f'{out}: {kind} run {n} has no frontier {prefill}')
            v = float(row['prefill_tps'])
        else:
            tokens = sum(int(r['gen_tokens']) for r in rs)
            v = tokens / sum(int(r['gen_tokens']) / float(r['gen_steady_tps']) for r in rs)
        values.append((rs[0]['build'], v, rs[0]['note'].startswith('pair dropped')))
    return values


def pooled(kind, dirs, **metric):
    """The valid pair ratios of every invocation: B1/A1 and B2/A2 of each A B B A quad."""
    ratios = []
    for out in dirs:
        q = run_values(out, kind, **metric)
        if [b for b, _, _ in q] != list('ABBA') * (len(q) // 4):
            raise ab.Stop(2, f'{out}: {kind} runs are not in A B B A order')
        for i in range(0, len(q), 4):
            a1, b1, b2, a2 = q[i:i + 4]
            ratios += [b[1] / a[1] for a, b in ((a1, b1), (a2, b2)) if not (a[2] or b[2])]
    return ratios


def main(argv):
    try:
        if len(argv) < 2:
            raise ab.Stop(2, __doc__.split('\n\n')[1])
        kind, rest = argv[0], argv[1:]
        metric, name = {}, 'decode'
        if rest[:1] == ['--prefill']:
            metric, name, rest = {'prefill': int(rest[1])}, f'prefill {rest[1]}', rest[2:]
        elif rest[:1] == ['--sections']:
            targets = [g for g in rest[2].split(',') if g]
            if not targets or any(g not in ab.GROUPS for g in targets):
                raise ab.Stop(2, f'--sections {rest[2]}: choose groups from {", ".join(ab.GROUPS)}')
            metric, name, rest = {'shape': rest[1], 'targets': targets}, f'sections {rest[1]}', rest[3:]
        ratios = pooled(kind, rest, **metric)
    except (ab.Stop, IndexError, OSError, ValueError) as exc:
        print(f'ab_pool: {exc}', file=sys.stderr)
        return exc.code if isinstance(exc, ab.Stop) else 2
    if not ratios:
        print(f'ab_pool: {kind} {name}: no valid pairs', file=sys.stderr)
        return 1
    lo, hi = ab.bootstrap_ci(ratios)
    ci = f'{(lo - 1) * 100:+.2f}..{(hi - 1) * 100:+.2f}' if lo is not None else '-'
    print(f'{kind} {name} pooled n={len(ratios)} median {(statistics.median(ratios) - 1) * 100:+.2f}% '
          f'95% CI {ci}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
