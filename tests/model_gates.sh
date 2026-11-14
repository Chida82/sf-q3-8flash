#!/bin/bash
# Model-backed gates for a sync or a PR, one model process at a time.
# Stops at the first failing gate and exits non-zero. See AGENTS.md "Before a PR".
set -u

usage() {
    cat <<'EOF'
Usage: tests/model_gates.sh MODEL.gguf [--mmproj FILE --image A --image B] [--out DIR]

Gates, in order (each one PASS or FAIL, stop at the first FAIL):
  mtp-identity  tests/test_qwen4_mtp_identity.py --fail-fast (all depths; DIFF or SLOW fails)
  mtp-limits    tests/test_qwen4_mtp_limits.py
  ds4_test      DS4_TEST_MODEL=MODEL DS4_TEST_GLM_MTP=1 ./ds4_test; only the failures
                docs/TESTING.md lists are allowed
  vision        tests/test_qwen4_cli_vision.py (only with --mmproj and two --image)
  host-paths    make test-qwen4-host-paths QWEN4_GGUF=MODEL

Builds `all` and `ds4_test` first. The StarForge parity oracle is separate.
EOF
}

MODEL= MMPROJ= OUT= IMAGES=()
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --mmproj) MMPROJ=${2:?--mmproj needs a file}; shift ;;
        --image) IMAGES+=("${2:?--image needs a file}"); shift ;;
        --out) OUT=${2:?--out needs a directory}; shift ;;
        -*) echo "model_gates: unknown option $1" >&2; usage >&2; exit 2 ;;
        *) [ -z "$MODEL" ] || { echo "model_gates: one model only" >&2; exit 2; }; MODEL=$1 ;;
    esac
    shift
done
[ -n "$MODEL" ] || { usage >&2; exit 2; }
[ -f "$MODEL" ] || { echo "model_gates: model not found: $MODEL" >&2; exit 2; }
if [ -n "$MMPROJ" ] && [ ${#IMAGES[@]} -ne 2 ]; then
    echo "model_gates: --mmproj needs exactly two --image" >&2; exit 2
fi
MODEL=$(cd "$(dirname "$MODEL")" && pwd)/$(basename "$MODEL")
cd "$(dirname "$0")/.." || exit 2
# `make` alone does not rebuild ds4_test: a stale one ran a whole gate on old code
# at the sync to b3f5018. Build what the gates run, every time.
make -j8 all ds4_test > /dev/null || { echo "model_gates: build failed (make -j8 all ds4_test)" >&2; exit 2; }
OUT=${OUT:-$(mktemp -d "${TMPDIR:-/tmp}/sf-q3-8flash-gates.XXXXXX")}
mkdir -p "$OUT"
echo "model gates: $MODEL, logs in $OUT"

# docs/TESTING.md "ds4_test with a model: known failures"; keep the two lists equal.
KNOWN_DS4_TEST_FAILURES="long-context metal-short-prefill logprob-vectors local-golden-vectors metal-ssd-streaming-cache-pressure"

lock_free() {
    python3 -c 'import fcntl,sys
f = open("/tmp/sf-q3-8flash.lock", "a")
try: fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
except OSError: sys.exit(1)'
}

failed=0
gate() {
    local name=$1; shift
    if ! lock_free; then
        echo "FAIL  $name: /tmp/sf-q3-8flash.lock is held, another model process is running"; failed=1; return
    fi
    local t0=$SECONDS
    "$@" > "$OUT/$name.log" 2>&1
    local rc=$?
    if [ $rc -eq 0 ]; then
        echo "PASS  $name ($((SECONDS - t0)) s)"
    else
        echo "FAIL  $name ($((SECONDS - t0)) s, exit $rc), last lines of $OUT/$name.log:"
        tail -n 15 "$OUT/$name.log" | sed 's/^/      /'
        failed=1
    fi
}

# Per-test summary lines are "<name>: OK" or "<name>: ERR", possibly colored.
run_ds4_test() {
    DS4_TEST_MODEL="$MODEL" DS4_TEST_GLM_MTP=1 ./ds4_test > "$OUT/ds4_test.raw" 2>&1
    local errs unknown=
    errs=$(sed -E 's/\x1b\[[0-9;]*m//g' "$OUT/ds4_test.raw" | sed -nE 's/^([a-z0-9-]+): ERR$/\1/p')
    for t in $errs; do
        case " $KNOWN_DS4_TEST_FAILURES " in *" $t "*) ;; *) unknown="$unknown $t" ;; esac
    done
    cat "$OUT/ds4_test.raw"
    echo "ds4_test failures:${errs:+ $(echo $errs)}"
    [ -z "$unknown" ] || { echo "not in docs/TESTING.md:$unknown"; return 1; }
    grep -q 'ds4 tests: ' "$OUT/ds4_test.raw" || { echo "ds4_test did not finish"; return 1; }
}

for step in identity limits ds4_test vision host; do
    [ $failed -eq 0 ] || break
    case $step in
        identity) gate mtp-identity python3 tests/test_qwen4_mtp_identity.py --model "$MODEL" --fail-fast --output "$OUT/identity" ;;
        limits)   gate mtp-limits python3 tests/test_qwen4_mtp_limits.py --model "$MODEL" ;;
        ds4_test) gate ds4_test run_ds4_test ;;
        vision)   [ -n "$MMPROJ" ] && gate vision python3 tests/test_qwen4_cli_vision.py --model "$MODEL" \
                      --vision "$MMPROJ" --image "${IMAGES[0]}" --image "${IMAGES[1]}" --out-dir "$OUT/vision" ;;
        host)     gate host-paths make test-qwen4-host-paths QWEN4_GGUF="$MODEL" ;;
    esac
done
[ $failed -eq 0 ] && echo "model gates: all PASS" || echo "model gates: FAIL"
exit $failed
