#!/usr/bin/env python3
"""A/B throughput and correctness harness for two sf-q3-8flash build trees.

Runs the benchmark of build A (baseline) and build B (candidate) on one GGUF,
one process at a time, in A B B A quads, and reports the median B/A ratio per
metric. The verdict is gated on identical tokens and, with --bitwise, on
identical logit bits. With --sections it runs the same schedule under the GPU
section profiler and judges GPU time per prefill chunk instead of throughput.
See "A/B harness" in speed-bench/README.md.
"""

import argparse
import csv
import fcntl
import hashlib
import importlib.util
import io
import json
import os
import random
import re
import statistics
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BENCH = 'sf-q3-8flash-bench'
LOCK = '/tmp/sf-q3-8flash.lock'
MAX_BUDGET = 600
BIG_RSS_KIB = 8 << 20
ACTIVE_PERCENT = 50.0

KINDS = {
    'plain': {'prompt': 'speed-bench/promessi_sposi.txt', 'frontiers': (8192, 8704, 10752), 'gen': 64, 'mtp': False},
    'mtp-code': {'prompt': 'rax.c', 'frontiers': (2048,), 'gen': 128, 'mtp': True},
    'mtp-prose': {'prompt': 'speed-bench/promessi_sposi.txt', 'frontiers': (2048,), 'gen': 128, 'mtp': True},
}
# Headline metrics: they carry the verdict, decide "inconclusive" and fill the record row.
# The per-cycle times (k1..k3 ms) are reported as detail only.
RECORD = [('plain', 'decode'), ('plain', 'prefill 8192'), ('plain', 'prefill +512'),
          ('plain', 'prefill +2048'), ('mtp-code', 'decode'), ('mtp-code', 'tokens/cycle'),
          ('mtp-code', 'prefill 2048'), ('mtp-prose', 'decode'), ('mtp-prose', 'tokens/cycle'),
          ('mtp-prose', 'prefill 2048')]
RECORD_LEAD = ['step', 'date', 'B commit', 'model', 'valid pairs', 'correctness']
MACTOP = {'time': ('timestamp',), 'freq': ('soc_metrics', 'gpu_freq_mhz'),
          'active': ('soc_metrics', 'gpu_active'), 'power': ('soc_metrics', 'gpu_power'),
          'temp': ('soc_metrics', 'gpu_temp'), 'thermal': ('thermal_state',)}
IDS = re.compile(r'^ds4-bench: gen\[ctx=(\d+)\] token ids:(.*)$', re.M)
MTP = re.compile(r'^ds4-bench: mtp\[ctx=(\d+)\] cycles=(\d+) tokens=(\d+)'
                 + ''.join(rf' k{k}=(\d+)/([0-9.]+)ms' for k in (1, 2, 3)) + '$', re.M)
# DS4_QWEN4_TIMING=2 stage groups (ds4.c qwen4_prof_names) and their per-chunk prefill line
GROUPS = ('ple', 'hc_attn', 'gdn', 'attn', 'hc_ffn', 'moe', 'moe_mid', 'moe_down', 'head')
CHUNK = re.compile(r'^ds4: Qwen3\.8 prefill stage GPU ms/chunk \(pos=(\d+) T=(\d+) ok=(\d)\):(.*)$', re.M)


class Stop(Exception):
    """Ends the harness with an exit status: 1 correctness or run failure, 2 refused or aborted."""

    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


# --- inputs -----------------------------------------------------------------

def child_env(pairs, environ=None):
    env = {k: v for k, v in (os.environ if environ is None else environ).items()
           if not k.startswith('DS4_')}
    for pair in pairs:
        key, sep, value = pair.partition('=')
        if not sep or not key:
            raise Stop(2, f'--env {pair}: expected KEY=VALUE')
        env[key] = value
    return env


def model_label(path):
    """The file name, or one symlink hop for the default link (qwen3.8-flash-next.gguf -> gguf/<component>)."""
    if path.is_symlink() and os.readlink(path).endswith('.gguf'):
        return Path(os.readlink(path)).name
    return path.name


def git(tree, *args):
    r = subprocess.run(['git', '-C', str(tree), *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ''


def prepare_tree(path):
    tree = Path(path).resolve()
    if not (tree / 'Makefile').is_file() or not (tree / 'metal').is_dir():
        raise Stop(2, f'{path}: not a build tree (needs a Makefile and metal/)')
    r = subprocess.run(['make', '-C', str(tree), '-j8', BENCH], capture_output=True, text=True)
    if r.returncode != 0:
        raise Stop(2, f'{path}: make {BENCH} failed:\n{r.stdout[-2000:]}{r.stderr[-2000:]}')
    return {'path': tree, 'commit': git(tree, 'rev-parse', '--short', 'HEAD') or '?',
            'branch': git(tree, 'rev-parse', '--abbrev-ref', 'HEAD') or '?',
            'dirty': bool(git(tree, 'status', '--porcelain'))}


# --- mactop -----------------------------------------------------------------

def parse_mactop(text):
    """mactop --headless streams one JSON object per line, prefixed by '[' or ','."""
    lines = [line.strip().lstrip('[,').rstrip(']').strip() for line in text.splitlines()]
    lines = [line for line in lines if line]
    samples = []
    for i, line in enumerate(lines):
        try:
            samples.append(json.loads(line))
        except ValueError:
            if i != len(lines) - 1:  # only the line being written at termination may be partial
                raise Stop(2, f'mactop log line {i + 1} is not JSON')
    return samples


def reading(sample, version='?'):
    r = {}
    for name, keys in MACTOP.items():
        value = sample
        for key in keys:
            if not isinstance(value, dict) or key not in value:
                raise Stop(2, f'mactop {version} output has no {".".join(keys)}')
            value = value[key]
        r[name] = value
    r['time'] = datetime.fromisoformat(r['time']).timestamp()
    return r


def mactop_version():
    try:
        return subprocess.run(['mactop', '--version'], capture_output=True, text=True).stdout.split()[-1]
    except (FileNotFoundError, IndexError):
        return '?'


def preflight(max_temp):
    try:
        out = subprocess.run(['mactop', '--headless', '--count', '1', '--interval', '1000'],
                             capture_output=True, text=True, timeout=30).stdout
    except FileNotFoundError:
        raise Stop(2, 'preflight refused: mactop is required (brew install mactop); '
                      'the harness does not run without the GPU log')
    samples = parse_mactop(out)
    if not samples:
        raise Stop(2, 'preflight refused: mactop returned no reading')
    sample = samples[0]
    r = reading(sample, mactop_version())
    problems = []
    battery = sample.get('battery', {})
    if battery.get('present', False) and not battery.get('on_ac_power', False):
        problems.append('not on AC power: connect the charger')
    if r['thermal'] != 'Nominal':
        problems.append(f'thermal state is {r["thermal"]}, not Nominal')
    if r['temp'] >= max_temp:
        problems.append(f'GPU temperature {r["temp"]:.1f} C is not below {max_temp:g} C')
    try:
        with open(LOCK, 'a') as f:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.flock(f, fcntl.LOCK_UN)
    except BlockingIOError:
        problems.append(f'{LOCK} is held: another sf-q3-8flash process is running')
    ps = subprocess.run(['ps', '-axo', 'pid=,rss=,comm='], capture_output=True, text=True).stdout
    for line in ps.splitlines():
        pid, rss, comm = line.split(None, 2)
        if int(pid) != os.getpid() and int(rss) >= BIG_RSS_KIB:
            problems.append(f'pid {pid} ({comm}) has {int(rss) / 1048576:.1f} GiB resident')
    if problems:
        raise Stop(2, 'preflight refused:\n  ' + '\n  '.join(problems))
    return sample


class Monitor:
    def __init__(self, path):
        self.path = path
        self.file = open(path, 'w')
        self.proc = subprocess.Popen(['mactop', '--headless', '--count', '0', '--interval', '1000'],
                                     stdout=self.file, stderr=subprocess.DEVNULL)

    def check(self):
        if self.proc.poll() is not None:
            raise Stop(2, f'mactop exited during the run (status {self.proc.returncode}); the GPU log is incomplete')

    def stop(self):
        if self.proc.poll() is None:
            self.proc.terminate()
            self.proc.wait(timeout=10)
        self.file.close()

    def readings(self, version):
        return [reading(s, version) for s in parse_mactop(Path(self.path).read_text())]


# --- one run ----------------------------------------------------------------

def bench_cmd(tree, kind, model, csv_path, logits_dir=None):
    k = KINDS[kind]
    cmd = [str(tree / BENCH), '-m', str(model), '--prompt-file', str(ROOT / k['prompt']),
           '--frontiers', ','.join(map(str, k['frontiers'])), '-n', str(k['gen']),
           '--show-output', '--csv', str(csv_path)]
    if k['mtp']:
        cmd.append('--mtp')
    if logits_dir:
        cmd += ['--dump-frontier-logits-dir', str(logits_dir)]
    return cmd


def shapes(kind):
    """(metric name, chunk position, chunk tokens) of each prefill a kind times: every frontier
    is prefilled on top of the previous one."""
    out, previous = [], 0
    for f in KINDS[kind]['frontiers']:
        out.append((f'prefill {f}' if previous == 0 else f'prefill +{f - previous}', previous, f - previous))
        previous = f
    return out


def metrics(rows, mtp, kind):
    frontiers = KINDS[kind]['frontiers']
    m = {}
    for (name, _, _), f in zip(shapes(kind), frontiers):
        m[name] = float(rows[f]['prefill_tps'])
    steady = [(int(rows[f]['gen_steady_tokens']), float(rows[f]['gen_steady_tps'])) for f in frontiers]
    seconds = sum(n / tps for n, tps in steady if tps > 0)
    m['decode'] = sum(n for n, _ in steady) / seconds if seconds else None
    if KINDS[kind]['mtp']:
        cycles = sum(mtp[f]['cycles'] for f in frontiers)
        m['tokens/cycle'] = sum(mtp[f]['tokens'] for f in frontiers) / cycles if cycles else None
        for k in (1, 2, 3):
            calls = sum(mtp[f]['k'][k][0] for f in frontiers)
            m[f'k{k} ms'] = (sum(mtp[f]['k'][k][0] * mtp[f]['k'][k][1] for f in frontiers) / calls
                             if calls else None)
    return m


def parse_run(csv_text, err_text, kind):
    frontiers = list(KINDS[kind]['frontiers'])
    rows = {int(r['ctx_tokens']): r for r in csv.DictReader(io.StringIO(csv_text))}
    tokens = {int(m[1]): [int(t) for t in m[2].split()] for m in IDS.finditer(err_text)}
    mtp = {}
    for m in MTP.finditer(err_text):
        g = [float(x) for x in m.groups()]
        mtp[int(g[0])] = {'cycles': g[1], 'tokens': g[2],
                          'k': {k: (g[1 + 2 * k], g[2 + 2 * k]) for k in (1, 2, 3)}}
    parts = [('CSV rows', rows), ('token ids', tokens)] + ([('MTP lines', mtp)] if KINDS[kind]['mtp'] else [])
    missing = [what for what, got in parts if sorted(got) != frontiers]
    if missing:
        raise Stop(1, f'{kind}: bench output lacks {", ".join(missing)} for frontiers {frontiers}')
    return {'rows': rows, 'tokens': tokens, 'mtp': mtp, 'metrics': metrics(rows, mtp, kind)}


def parse_sections(err_text, kind):
    """GPU ms per stage group of each prefill chunk the kind times, from the profiler's lines."""
    chunks = {}
    for m in CHUNK.finditer(err_text):
        if m[3] != '1':
            raise Stop(1, f'{kind}: profiled chunk pos={m[1]} T={m[2]} reported ok=0')
        words = m[4].split()
        times = dict(zip(words[::2], words[1::2]))
        if any(g not in times for g in GROUPS):
            raise Stop(1, f'{kind}: section-time line for pos={m[1]} T={m[2]} lacks a stage group')
        chunks.setdefault((int(m[1]), int(m[2])), {g: float(times[g]) for g in GROUPS})
    out = {}
    for name, pos, tokens in shapes(kind):
        if (pos, tokens) not in chunks:
            raise Stop(1, f'{kind}: no section-time line for {name} (pos={pos} T={tokens})')
        out[name] = chunks[pos, tokens]
    return out


def run_bench(n, build, tree, kind, model, env, out, phase, bitwise, sections=False):
    stem = out / 'logs' / f'{n:02d}-{build}-{kind}'
    logits_dir = out / 'logits' / f'{build}-{kind}' if phase == 'warm-up' and bitwise else None
    if logits_dir:
        logits_dir.mkdir(parents=True)
    cmd = bench_cmd(tree, kind, model, f'{stem}.csv', logits_dir)
    start = time.time()
    with open(f'{stem}.err', 'wb') as err:
        rc = subprocess.run(cmd, cwd=tree, env=env, stdout=subprocess.DEVNULL, stderr=err).returncode
    end = time.time()
    if rc != 0:
        raise Stop(1, f'{build} {kind} run failed (exit {rc}); see {stem}.err')
    err_text = Path(f'{stem}.err').read_text(errors='replace')
    run = parse_run(Path(f'{stem}.csv').read_text(), err_text, kind)
    if sections:
        run['sections'] = parse_sections(err_text, kind)
    run.update(n=n, build=build, kind=kind, phase=phase, warmup=phase != 'timed', start=start, end=end,
               duration=end - start, logits=logits_dir, note='')
    return run


# --- correctness -------------------------------------------------------------

def first_diff(a, b):
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return i
    return None if len(a) == len(b) else min(len(a), len(b))


def check_tokens(run, ref):
    for f, ids in ref['tokens'].items():
        pos = first_diff(ids, run['tokens'].get(f, []))
        if pos is not None:
            what = ('FAIL: baseline is nondeterministic, A runs differ' if run['build'] == 'A'
                    else 'FAIL: B differs from A')
            return f'{what}: {run["kind"]}, frontier {f}, token index {pos}'
    return None


def load_logits_validator():
    path = ROOT / 'gguf-tools/quality-testing/compare_frontier_logits.py'
    spec = importlib.util.spec_from_file_location('compare_frontier_logits', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def check_logits(dir_a, dir_b, frontiers):
    """Bit-exact comparison of every prefill and decode dump, strictly validated."""
    cfl = load_logits_validator()
    # frontier order, prefill before decode, so the first difference says where drift starts
    names = sorted((p.name for p in dir_a.iterdir()), key=lambda n: (n.split('.')[0], '.decode.' in n))
    if not names or sorted(names) != sorted(p.name for p in dir_b.iterdir()):
        return f'FAIL bitwise: A and B dumped different files ({dir_a.name})'
    meta = json.loads((dir_a / names[0]).read_text())
    try:
        expected = cfl.validate_expectations(list(frontiers), meta['ctx'], meta['model'], meta['backend'],
                                             meta['quality'], meta['quant_bits'], meta['vocab'])
        previous = dict(zip(frontiers, (0,) + tuple(frontiers[:-1])))
        for name in names:
            f = int(re.match(r'frontier_(\d+)', name)[1])
            _, a, _ = cfl.validate_dump(dir_a / name, expected, f, previous[f])
            _, b, _ = cfl.validate_dump(dir_b / name, expected, f, previous[f])
            if a != b:
                index = next(i for i in range(0, len(a), 4) if a[i:i + 4] != b[i:i + 4]) // 4
                return f'FAIL bitwise: {name}: frontier {f}, vocabulary index {index}'
    except (cfl.InvalidDump, KeyError, OSError) as exc:
        return f'FAIL bitwise: {dir_a.name}: {exc}'
    return None


# --- schedule ----------------------------------------------------------------

def schedule(kinds, deadline, runner, check, runs, preheat_until=0.0, clock=time.time):
    """Warm-up (A, B per kind), preheat until preheat_until, then A B B A quads while they fit.

    runner(build, kind, phase) returns a run, appended to runs; check(runs) raises Stop on a
    correctness failure. Preheat runs alternate A and B on the first kind, so the timed rounds
    start on the laptop's thermal plateau (design D10). A quad is predicted from the latest
    duration per build and kind, plus 10%.
    """
    for kind in kinds:
        for build in 'AB':
            runs.append(runner(build, kind, 'warm-up'))
            check(runs)
    while clock() < preheat_until:
        runs.append(runner('AB'[len(runs) % 2], kinds[0], 'preheat'))
        check(runs)
    latest = {(r['build'], r['kind']): r['duration'] for r in runs}
    while True:
        for kind in kinds:
            if clock() + 1.1 * 2 * (latest['A', kind] + latest['B', kind]) > deadline:
                return
            for build in 'ABBA':
                run = runner(build, kind, 'timed')
                runs.append(run)
                latest[build, kind] = run['duration']
                check(runs)


# --- analysis ----------------------------------------------------------------

def judge(timed, readings):
    for run in timed:
        window = [x for x in readings if run['start'] - 1 <= x['time'] <= run['end']]
        active = [x['freq'] for x in window if x['active'] >= ACTIVE_PERCENT]
        run['freq'] = statistics.median(active) if len(active) >= 2 else None
        run['temp'] = max((x['temp'] for x in window), default=None)
        run['power'] = statistics.median([x['power'] for x in window]) if window else None
        run['thermal'] = sorted({x['thermal'] for x in window})
        if run['freq'] is None:
            run['note'] = 'unjudged: fewer than two active GPU samples'


def drop_disturbed(timed, kinds, fraction):
    """Drop the pair of any run whose GPU ran below fraction of the timed runs' median frequency.

    mactop's frequency does not predict small pair errors, but an external disturbance (another
    GPU user, a deeper throttle) shows up as a run far below the invocation's plateau.
    """
    freqs = [r['freq'] for r in timed if r.get('freq')]
    if not freqs:
        return
    median = statistics.median(freqs)
    floor = fraction * median
    for kind in kinds:
        for a, b in pairs(timed, kind):
            low = [r for r in (a, b) if r.get('freq') and r['freq'] < floor]
            if low:
                a['flag'] = b['flag'] = (f'pair dropped: run {low[0]["n"]} at {low[0]["freq"]:.0f} MHz, '
                                         f'below {fraction:.0%} of the {median:.0f} MHz median')


def pairs(timed, kind):
    runs = [r for r in timed if r['kind'] == kind]
    out = []
    for q in range(0, len(runs) - 3, 4):
        a1, b1, b2, a2 = runs[q:q + 4]
        out += [(a1, b1), (a2, b2)]
    return out


def verdict(runs, kinds):
    timed = [r for r in runs if not r['warmup']]
    table = []
    for kind in kinds:
        valid = [(a, b) for a, b in pairs(timed, kind) if not a.get('flag')]
        names = next((r['metrics'] for r in runs if r['kind'] == kind), {})
        for name in names:
            both = [(a['metrics'][name], b['metrics'][name]) for a, b in valid
                    if a['metrics'][name] and b['metrics'][name] is not None]
            ratios = [b / a for a, b in both]
            table.append({'kind': kind, 'metric': name, 'headline': (kind, name) in RECORD,
                          'a': statistics.median([a for a, _ in both]) if both else None,
                          'b': statistics.median([b for _, b in both]) if both else None,
                          'ratio': statistics.median(ratios) if ratios else None,
                          'lo': min(ratios, default=None), 'hi': max(ratios, default=None),
                          'n': len(ratios)})
    return table


def bootstrap_ci(values, resamples=10000, seed=1):
    """95% CI of the median by bootstrap (fixed seed); (None, None) below two values."""
    if len(values) < 2:
        return None, None
    rng = random.Random(seed)
    bs = sorted(statistics.median(rng.choices(values, k=len(values))) for _ in range(resamples))
    return bs[resamples // 40], bs[resamples - resamples // 40]


def section_split(groups, targets):
    """(target ms, untouched ms) of one chunk."""
    target = sum(groups[g] for g in targets)
    return target, sum(groups.values()) - target


def med(values):
    return statistics.median(values) if values else None


def section_table(runs, kinds, targets):
    """Per kind and shape: B's (target / untouched) over A's per valid pair, with its CI, and
    the whole-chunk ratio. The untouched groups share the run's clock, so the ratio cancels
    the clock drift between runs."""
    timed = [r for r in runs if not r['warmup']]
    table = []
    for kind in kinds:
        valid = [(a, b) for a, b in pairs(timed, kind) if not a.get('flag')]
        for name, _, _ in shapes(kind):
            split = [(section_split(a['sections'][name], targets), section_split(b['sections'][name], targets))
                     for a, b in valid]
            split = [(x, y) for x, y in split if x[0] > 0 and x[1] > 0 and y[1] > 0]
            ratios = [(bt / bu) / (at / au) for (at, au), (bt, bu) in split]
            lo, hi = bootstrap_ci(ratios)
            table.append({'kind': kind, 'shape': name, 'n': len(ratios),
                          'a_target': med([x[0] for x, _ in split]), 'b_target': med([y[0] for _, y in split]),
                          'a_rest': med([x[1] for x, _ in split]), 'b_rest': med([y[1] for _, y in split]),
                          'ratio': med(ratios), 'lo': lo, 'hi': hi,
                          'whole': med([sum(y) / sum(x) for x, y in split])})
    return table


def pct(ratio):
    return f'{(ratio - 1) * 100:+.1f}%'


def num(value):
    return '-' if value is None else f'{value:.2f}' if value < 10 else f'{value:.1f}'


def record_header():
    names = RECORD_LEAD + [f'{kind} {metric}' for kind, metric in RECORD]
    return '| ' + ' | '.join(names) + ' |\n|' + '---|' * len(names)


def record_row(step, date, commit, model, valid_pairs, correctness, table):
    cells = {(t['kind'], t['metric']): t for t in table}
    row = [step, date, commit, model, str(valid_pairs), correctness]
    for key in RECORD:
        t = cells.get(key)
        row.append(f'{num(t["b"])} ({pct(t["ratio"])})' if t and t['ratio'] is not None else '')
    return '| ' + ' | '.join(row) + ' |'


def section_lines(ctx, sections):
    lines = [f'sections  target {"+".join(ctx["sections"])}; B/A of (target / untouched) GPU ms per '
             'prefill chunk, per valid pair',
             f'{"kind":<10} {"shape":<14} {"A target":>9} {"B target":>9} {"A other":>9} {"B other":>9} '
             f'{"B/A":>7}  {"95% CI":<17} {"whole":>7} n']
    for t in sections:
        ci = f'{pct(t["lo"])} .. {pct(t["hi"])}' if t['lo'] is not None else ''
        lines.append(f'{t["kind"]:<10} {t["shape"]:<14} {num(t["a_target"]):>9} {num(t["b_target"]):>9} '
                     f'{num(t["a_rest"]):>9} {num(t["b_rest"]):>9} '
                     f'{pct(t["ratio"]) if t["ratio"] is not None else "-":>7}  {ci:<17} '
                     f'{pct(t["whole"]) if t["whole"] is not None else "-":>7} {t["n"]}')
    return lines


def summary(ctx, runs, table, status, correctness, sections=None):
    timed = [r for r in runs if not r['warmup']]
    kinds = ctx['kinds']
    all_pairs = [p for kind in kinds for p in pairs(timed, kind)]
    valid = sum(1 for a, _ in all_pairs if not a.get('flag'))
    lines = [f'sf-q3-8flash A/B  {ctx["date"]}  {ctx["device"]}  mactop {ctx["mactop"]}']
    for label in 'AB':
        t = ctx[label]
        lines.append(f'{label}  {t["path"]}  {t["commit"]}{" (uncommitted changes)" if t["dirty"] else ""}')
    lines.append(f'model  {ctx["model_name"]} ({ctx["model"]})   env  {" ".join(ctx["env"]) or "-"}')
    lines.append(f'time  {ctx["elapsed"]:.0f} s of {ctx["budget"]} s   runs {len(runs)} '
                 f'({len(runs) - len(timed)} untimed, preheat {ctx["preheat"]:.0f} s)   '
                 f'pairs {valid} valid, {len(all_pairs) - valid} dropped')
    freqs = [r['freq'] for r in timed if r.get('freq')]
    thermal = sorted(set().union(*(r.get('thermal', []) for r in timed)))
    if freqs:
        lines.append(f'GPU  timed runs at {min(freqs):.0f}-{max(freqs):.0f} MHz (median {statistics.median(freqs):.0f}), '
                     f'thermal {"/".join(thermal) or "?"}')
    lines.append(f'correctness  {correctness}')
    lines.append('')
    if sections is not None:
        # profiled runs include the profiler's waits: no throughput table or record row
        lines += section_lines(ctx, sections)
    else:
        lines.append(f'{"kind":<10} {"metric":<14} {"A":>9} {"B":>9} {"B/A":>7}  {"range":<17} n')
        for t in table:
            span = f'{pct(t["lo"])} .. {pct(t["hi"])}' if t['n'] else ''
            mark = '' if t['headline'] else '  (detail)'
            lines.append(f'{t["kind"]:<10} {t["metric"]:<14} {num(t["a"]):>9} {num(t["b"]):>9} '
                         f'{pct(t["ratio"]) if t["ratio"] is not None else "-":>7}  {span:<17} {t["n"]}{mark}')
    notes = [f'run {r["n"]} {r["build"]} {r["kind"]}: {r.get("flag") or r["note"]}'
             for r in timed if r.get('flag') or r['note']]
    if notes:
        lines += [''] + notes
    if sections is not None:
        thin = [f'{t["kind"]} {t["shape"]}' for t in sections if t['n'] < 2]
    else:
        thin = [f'{t["kind"]} {t["metric"]}' for t in table if t['headline'] and t['n'] < 2]
    if thin and status == 'PASS':
        lines += ['', f'INCONCLUSIVE: fewer than two valid pairs for {", ".join(thin)}']
    if sections is None:
        lines += ['', 'record row:', record_row(ctx['B']['branch'], ctx['date'][:10], ctx['B']['commit'],
                                                 ctx['model_name'], valid, status, table)]
    return '\n'.join(lines), bool(thin)


def write_samples(path, runs):
    fields = ['run', 'build', 'kind', 'frontier', 'prefill_tokens', 'prefill_tps', 'gen_tokens', 'gen_tps',
              'gen_steady_tps', 'mtp_cycles', 'mtp_tokens', 'gpu_freq_mhz', 'gpu_temp_max',
              'gpu_power_median', 'note', 'tokens_sha256']
    with open(path, 'w', newline='') as f:
        w = csv.DictWriter(f, fields)
        w.writeheader()
        for r in runs:
            if r['warmup']:
                continue
            for frontier, row in sorted(r['rows'].items()):
                mtp = r['mtp'].get(frontier, {})
                ids = ' '.join(map(str, r['tokens'][frontier])).encode()
                w.writerow({'run': r['n'], 'build': r['build'], 'kind': r['kind'], 'frontier': frontier,
                            'prefill_tokens': row['prefill_tokens'], 'prefill_tps': row['prefill_tps'],
                            'gen_tokens': row['gen_tokens'], 'gen_tps': row['gen_tps'],
                            'gen_steady_tps': row['gen_steady_tps'], 'mtp_cycles': mtp.get('cycles', ''),
                            'mtp_tokens': mtp.get('tokens', ''), 'gpu_freq_mhz': r.get('freq') or '',
                            'gpu_temp_max': r.get('temp') or '', 'gpu_power_median': r.get('power') or '',
                            'note': r.get('flag') or r['note'], 'tokens_sha256': hashlib.sha256(ids).hexdigest()})


def write_sections(path, runs):
    with open(path, 'w', newline='') as f:
        w = csv.DictWriter(f, ['run', 'build', 'kind', 'shape', *GROUPS, 'note'])
        w.writeheader()
        for r in runs:
            if r['warmup']:
                continue
            for shape, groups in r['sections'].items():
                w.writerow({'run': r['n'], 'build': r['build'], 'kind': r['kind'], 'shape': shape, **groups,
                            'note': r.get('flag') or r['note']})


# --- main --------------------------------------------------------------------

def parse_args(argv):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--a', required=True, help='baseline build tree')
    p.add_argument('--b', required=True, help='candidate build tree (may equal --a for an A/A run)')
    p.add_argument('-m', '--model', default=str(ROOT / 'qwen3.8-flash-next.gguf'))
    p.add_argument('--kinds', help=f'comma list of {", ".join(KINDS)} (default all; plain with --sections)')
    p.add_argument('--budget', type=int, default=480, help=f'wall-clock seconds, at most {MAX_BUDGET}')
    p.add_argument('--bitwise', action='store_true', help='also require bit-identical logits')
    p.add_argument('--env', action='append', default=[], metavar='KEY=VALUE', help='set for both builds')
    p.add_argument('--max-gpu-temp', type=float, default=60.0)
    p.add_argument('--min-freq-of-median', type=float, default=0.90,
                   help="drop a pair when one of its runs ran below this fraction of the timed runs' "
                        'median GPU frequency (an external disturbance)')
    p.add_argument('--preheat', type=float, default=210.0,
                   help='seconds of load before the timed rounds (at most half the budget); '
                        'the M5 Max reaches its thermal plateau about 215-240 s into a run')
    p.add_argument('--sections', metavar='GROUPS',
                   help='judge GPU time per prefill chunk: comma list of the DS4_QWEN4_TIMING=2 groups the '
                        f'step targets ({", ".join(GROUPS)}), normalized by the other groups')
    p.add_argument('--out', help='output directory (default $TMPDIR/sf-q3-8flash-ab/<UTC time>)')
    args = p.parse_args(argv)
    args.sections = [g for g in (args.sections or '').split(',') if g]
    for g in args.sections:
        if g not in GROUPS:
            raise Stop(2, f'--sections {g}: not a profiler group; choose from {", ".join(GROUPS)}')
    if args.sections and set(args.sections) == set(GROUPS):
        raise Stop(2, '--sections: leave at least one group untouched to normalize by')
    kinds = args.kinds or ('plain' if args.sections else ','.join(KINDS))
    args.kinds = [k for k in kinds.split(',') if k]
    if not args.kinds or any(k not in KINDS for k in args.kinds):
        raise Stop(2, f'--kinds {",".join(args.kinds)}: choose from {", ".join(KINDS)}')
    if not 0 < args.budget <= MAX_BUDGET:
        raise Stop(2, f'--budget {args.budget}: must be between 1 and {MAX_BUDGET} seconds')
    return args


def main(argv=None):
    begin = time.time()
    try:
        args = parse_args(argv)
        args.env += ['DS4_QWEN4_TIMING=2'] if args.sections else []
        env = child_env(args.env)
        model = Path(os.path.abspath(args.model))
        if not model.is_file():
            raise Stop(2, f'{args.model}: model not found')
        trees = {'A': prepare_tree(args.a), 'B': prepare_tree(args.b)}
        now = datetime.now(timezone.utc)
        out = Path(args.out) if args.out else (Path(os.environ.get('TMPDIR', '/tmp')) / 'sf-q3-8flash-ab'
                                               / now.strftime('%Y%m%dT%H%M%SZ'))
        (out / 'logs').mkdir(parents=True)
        sample = preflight(args.max_gpu_temp)
    except Stop as stop:
        print(f'ab_bench: {stop}', file=sys.stderr)
        return stop.code

    version = mactop_version()
    ctx = {'date': now.strftime('%Y-%m-%d %H:%M UTC'), 'device': sample.get('system_info', {}).get('name', '?'),
           'mactop': version, 'A': trees['A'], 'B': trees['B'], 'model': str(model),
           'model_name': model_label(model), 'env': args.env,
           'budget': args.budget, 'kinds': args.kinds, 'sections': args.sections}
    counter = iter(range(1, 10_000))
    refs = {}
    runs = []

    def runner(build, kind, phase):
        run = run_bench(next(counter), build, trees[build]['path'], kind, model, env, out, phase, args.bitwise,
                        bool(args.sections))
        monitor.check()
        refs.setdefault(kind, run)  # the first run of a kind is A's warm-up
        print(f'  run {run["n"]:2d} {build} {kind:<9} {phase:<7} {run["duration"]:.1f} s',
              file=sys.stderr, flush=True)
        return run

    def check(done):
        last = done[-1]
        problem = check_tokens(last, refs[last['kind']])
        if not problem and args.bitwise and last['phase'] == 'warm-up' and last['build'] == 'B':
            problem = check_logits(out / 'logits' / f'A-{last["kind"]}', out / 'logits' / f'B-{last["kind"]}',
                                   KINDS[last['kind']]['frontiers'])
        if problem:
            raise Stop(1, problem)

    status, correctness = 'PASS', 'PASS (tokens' + ('; bitwise)' if args.bitwise else ')')
    monitor = Monitor(out / 'gpu.json')
    try:
        load = time.time()
        schedule(args.kinds, begin + args.budget, runner, check, runs,
                 min(load + args.preheat, begin + args.budget / 2))
    except Stop as stop:
        if stop.code != 1 or not runs:
            print(f'ab_bench: {stop}', file=sys.stderr)
            return stop.code
        status, correctness = 'FAIL', str(stop)
    finally:
        monitor.stop()
    ctx['elapsed'] = time.time() - begin
    timed = [r for r in runs if not r['warmup']]
    ctx['preheat'] = (timed[0]['start'] - load) if timed else ctx['elapsed']
    judge(timed, monitor.readings(version))
    drop_disturbed(timed, args.kinds, args.min_freq_of_median)
    table = verdict(runs, args.kinds)
    sections = section_table(runs, args.kinds, args.sections) if args.sections else None
    text, thin = summary(ctx, runs, table, status, correctness, sections)
    write_samples(out / 'samples.csv', runs)
    if args.sections:
        write_sections(out / 'sections.csv', runs)
    (out / 'summary.txt').write_text(text + '\n')
    print(text)
    print(f'\noutput: {out}', file=sys.stderr)
    if status != 'PASS':
        return 1
    return 3 if thin else 0


if __name__ == '__main__':
    raise SystemExit(main())
