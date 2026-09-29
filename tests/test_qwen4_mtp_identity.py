"""Qwen MTP greedy output must equal plain greedy output, prompt by prompt and depth by depth."""

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

# (token limit, prompt): upstream's three Qwen cases (speed-bench/qwen38-checkpoints
# in ds4), then the text prompts of the StarForge parity set at its 128 tokens.
PROMPTS = [
    (120, "Write a three-sentence summary of the plot of Hamlet."),
    (400, "List the first 30 Fibonacci numbers with indices."),
    (256, "Explain how a computer sends a web request over TCP and receives the response. "
          "Write four clear paragraphs for a programmer learning networking."),
    (128, "Explain what a Redis stream is in one paragraph."),
    (128, "Write a C function that reverses a singly linked list. Only code."),
    (128, "List the prime numbers below 50, comma separated."),
    (128, 'Translate to Italian: "The quick brown fox jumps over the lazy dog."'),
    (128, 'Given the JSON {"a":1,"b":[1,2,3]} return the sum of all numbers. Answer with the number only.'),
    (128, "Scrivi tre righe su Palermo."),
    (128, "What is the capital of Australia? One word."),
    (128, "Summarize the plot of Hamlet in exactly two sentences."),
    (128, "Write a haiku about compilers."),
]


def first_difference(a, b):
    wa, wb = a.decode(errors="replace").split(), b.decode(errors="replace").split()
    for i, (x, y) in enumerate(zip(wa, wb)):
        if x != y:
            return f"word {i}: {x!r} vs {y!r}"
    return f"word {min(len(wa), len(wb))}: one output ends first"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--depths", default="auto,2,3",
                        help="comma-separated MTP depths: auto, 2 (one draft), 3 (two drafts)")
    parser.add_argument("--prompts", type=Path,
                        help="file of '<tokens>\\t<prompt>' lines in place of the default set")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    depths = args.depths.split(",")
    if any(d not in ("auto", "2", "3") for d in depths):
        parser.error("--depths takes auto, 2 and 3")
    if not args.model.is_file():
        parser.error(f"model not found: {args.model}")
    prompts = PROMPTS
    if args.prompts:
        prompts = [(int(n), p) for n, p in (l.split("\t", 1) for l in args.prompts.read_text().splitlines() if l.strip())]
    root = Path(__file__).resolve().parents[1]
    out = args.output or Path(tempfile.mkdtemp(prefix="qwen-mtp-identity-"))
    out.mkdir(parents=True, exist_ok=True)
    print(f"MTP identity: {len(prompts)} prompts, depths {args.depths}, outputs in {out}", flush=True)

    def run(i, name, n, prompt, extra, depth):
        env = os.environ.copy()
        env.pop("DS4_QWEN4_MTP_DEPTH", None)
        if depth != "auto":
            env["DS4_QWEN4_MTP_DEPTH"] = depth
        cmd = [str(root / "sf-q3-8flash"), "-m", str(args.model.resolve()), "--ctx", "8192",
               "--temp", "0", "--nothink", "-n", str(n), *extra, "-p", prompt]
        result = subprocess.run(cmd, cwd=root, env=env, capture_output=True, timeout=600)
        (out / f"{i}-{name}.stdout").write_bytes(result.stdout)
        (out / f"{i}-{name}.stderr").write_bytes(result.stderr)
        if result.returncode != 0 or not result.stdout:
            sys.exit(f"{i} {name}: run failed; see {out / f'{i}-{name}.stderr'}")
        speed = re.search(rb"generation: ([\d.]+) t/s", result.stderr)
        return result.stdout, speed.group(1).decode() if speed else "?"

    diffs = 0
    for i, (n, prompt) in enumerate(prompts, 1):
        plain, speed = run(i, "plain", n, prompt, [], "auto")
        print(f"  {i:2}  plain       {speed:>6} t/s  {prompt[:60]}", flush=True)
        for depth in depths:
            mtp, speed = run(i, f"mtp-{depth}", n, prompt, ["--mtp"], depth)
            same = mtp == plain
            diffs += not same
            note = "" if same else "  " + first_difference(plain, mtp)
            print(f"  {i:2}  mtp {depth:<4}    {speed:>6} t/s  {'SAME' if same else 'DIFF'}{note}", flush=True)
    print(f"{'PASS' if not diffs else 'FAIL'}: {diffs} of {len(prompts) * len(depths)} MTP runs differ from plain")
    sys.exit(1 if diffs else 0)


if __name__ == "__main__":
    main()
