#!/usr/bin/env python3
"""Model-backed regression test for Qwen CLI image turns and follow-up text.

Run with uv run tests/test_qwen4_cli_vision.py --model MAIN
--vision MMPROJ --image FIRST.png --image SECOND.png. Tests ordinary and MTP
decode. Use two different images to exercise image changes in one conversation.

--compare also requires every turn of the MTP output to equal the ordinary
output (greedy MTP must not change tokens), printing SAME or DIFF per turn.
--text-turns runs four text-only turns instead of the image conversation; it
needs neither --vision nor --image.
"""

import argparse
import pathlib
import re
import subprocess
import tempfile

TEXT_TURNS = [
    "List the three primary colors of light, one per line.",
    "For each of them, name a fruit of that color.",
    "Which of those fruits has the most vitamin C? Answer in one sentence.",
    "Write a haiku about that fruit.",
]
# `/power` with no argument only prints the current value: sent before the
# first turn and after each one, it marks turn bounds on stdout, which the
# REPL does not otherwise do.
SEPARATOR = "/power\n"
SEPARATOR_RE = re.compile(r"^Power: \d+%\.\n", re.MULTILINE)


def split_turns(stdout):
    """Turns of a REPL stdout written with SEPARATOR after each turn."""
    parts = SEPARATOR_RE.split(stdout)
    return parts[1:-1]  # drop the help banner and what follows the last turn


def compare_turns(ordinary, mtp):
    """Return (lines, failed): one SAME/DIFF line per turn."""
    a, b = split_turns(ordinary), split_turns(mtp)
    lines, failed = [], len(a) != len(b)
    if failed:
        lines.append(f"DIFF turn count: ordinary {len(a)}, mtp {len(b)}")
    for i, (ta, tb) in enumerate(zip(a, b), 1):
        if ta == tb:
            lines.append(f"SAME turn {i}")
            continue
        failed = True
        la, lb = ta.splitlines(), tb.splitlines()
        k = next((k for k, (x, y) in enumerate(zip(la, lb)) if x != y),
                 min(len(la), len(lb)))
        lines.append(f"DIFF turn {i}, line {k + 1}:\n"
                     f"  ordinary: {la[k] if k < len(la) else '<end of turn>'}\n"
                     f"  mtp:      {lb[k] if k < len(lb) else '<end of turn>'}")
    return lines, failed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", default="./sf-q3-8flash")
    parser.add_argument("--model", required=True)
    parser.add_argument("--vision")
    parser.add_argument("--image", action="append", default=[])
    parser.add_argument("--text-turns", action="store_true")
    parser.add_argument("--compare", action="store_true")
    parser.add_argument("--out-dir")
    args = parser.parse_args()
    if args.text_turns:
        if args.image or args.vision:
            parser.error("--text-turns takes neither --vision nor --image")
        commands = "".join(f"{t}\n{SEPARATOR}" for t in TEXT_TURNS)
        expect_images, vision = 0, []
    else:
        if not args.vision or len(args.image) != 2:
            parser.error("provide --vision and two --image arguments")
        images = [pathlib.Path(path).resolve(strict=True) for path in args.image]
        if any("\n" in str(path) or "\r" in str(path) for path in images):
            parser.error("image paths must not contain line breaks")
        commands = "".join(
            f"/read {path}\n{SEPARATOR}"
            f"Describe only the most recent image, including any text and colors.\n{SEPARATOR}"
            for path in images
        )
        expect_images, vision = 2, ["--vision", args.vision]
    commands = SEPARATOR + commands + "/quit\n"
    out = pathlib.Path(args.out_dir or tempfile.mkdtemp(prefix="qwen-cli-vision-"))
    out.mkdir(parents=True, exist_ok=True)
    base = [str(pathlib.Path(args.binary).resolve()), "-m", args.model, *vision,
            "--ctx", "8192", "--temp", "0", "--nothink", "-n", "180"]
    print(f"Logs: {out}", flush=True)
    stdouts = {}
    for mode, extra in [("ordinary", []), ("mtp", ["--mtp"])]:
        result = subprocess.run(base + extra, input=commands, text=True,
                                capture_output=True, timeout=600)
        (out / f"{mode}.stdout").write_text(result.stdout)
        (out / f"{mode}.stderr").write_text(result.stderr)
        stdouts[mode] = result.stdout
        # The REPL can return zero after an image turn fails if a later text
        # turn succeeds. Check diagnostics as well as the process exit code.
        errors = re.findall(r"^.*(?:failed|outside the vocabulary).*$",
                            result.stderr, re.MULTILINE | re.IGNORECASE)
        encoded = len(re.findall(r"ds4: image \d+x\d+, \d+ image tokens",
                                 result.stderr))
        completed = result.stderr.count("ds4: prefill:")
        if result.returncode or errors or encoded != expect_images or completed != 4:
            raise SystemExit(
                f"FAIL {mode}: exit={result.returncode}, "
                f"encoded={encoded}/{expect_images}, "
                f"completed={completed}/4, errors={errors}; see {out}")
        print(f"PASS {mode}: all four turns completed", flush=True)
    if args.compare:
        lines, failed = compare_turns(stdouts["ordinary"], stdouts["mtp"])
        print("\n".join(lines), flush=True)
        if failed:
            raise SystemExit(f"FAIL compare: MTP output differs; see {out}")
        print("PASS compare: MTP output equals ordinary output", flush=True)


if __name__ == "__main__":
    main()
