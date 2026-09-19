#!/bin/sh
set -eu

MODEL_REPO=antirez/qwen3.8-flash-next-gguf
VISION_REPO=ggml-org/Qwen3.8-Flash-Next-GGUF
Q2_FILE=Qwen3.8-Flash-Next-Q2.gguf
Q4_FILE=Qwen3.8-Flash-Next-Q4.gguf
VISION_FILE=mmproj-Qwen3.8-Flash-Next-Q8_0.gguf
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT_DIR=${DS4_GGUF_DIR:-"$ROOT/gguf"}
case "$OUT_DIR" in /*) ;; *) OUT_DIR="$ROOT/$OUT_DIR" ;; esac
TOKEN=${HF_TOKEN:-}

usage() {
    cat <<'EOF'
Qwen3.8 Flash Next GGUF downloader

Usage: ./download.sh <q2|q4|vision> [--token TOKEN]

  q2      137.10 GiB; 41.73 GiB resident weights; best for 64 GB Macs
  q4      165.11 GiB; 69.74 GiB resident weights; best for 128 GB Macs
  vision  0.6 GiB Qwen3-VL encoder (does not change the default model link)

Q2 and Q4 include the BF16 n-gram table and built-in MTP weights. Downloads
resume through the Hugging Face CLI. DS4_GGUF_DIR defaults to ./gguf.
EOF
}

[ $# -gt 0 ] || { usage; exit 1; }
case "$1" in
    q2) FILE=$Q2_FILE; EXPECTED_BYTES=147207127040; EXPECTED_SHA=b1b93fa69aca5f187b0fb813aca8f3ec1beb5cf8cf0bd38cf041b93e0b6ccac9; LINK=1; REPO=$MODEL_REPO ;;
    q4) FILE=$Q4_FILE; EXPECTED_BYTES=177280286720; EXPECTED_SHA=680944460a8cbe93ba8b6d7b6107213ffb7e22320bd913000e563ca0a0f25a8a; LINK=1; REPO=$MODEL_REPO ;;
    vision) FILE=$VISION_FILE; EXPECTED_BYTES=; EXPECTED_SHA=; LINK=0; REPO=$VISION_REPO ;;
    -h|--help|help) usage; exit 0 ;;
    *) echo "Unknown component: $1" >&2; usage >&2; exit 1 ;;
esac
shift
while [ $# -gt 0 ]; do
    case "$1" in
        --token) shift; [ $# -gt 0 ] || { echo "Missing value after --token" >&2; exit 1; }; TOKEN=$1 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done
[ -n "$TOKEN" ] || [ ! -s "$HOME/.cache/huggingface/token" ] || TOKEN=$(cat "$HOME/.cache/huggingface/token")

find_hf() {
    command -v hf 2>/dev/null && return
    for dir in "$HOME"/Library/Python/*/bin "$HOME"/.local/bin; do
        [ -x "$dir/hf" ] && { printf '%s\n' "$dir/hf"; return; }
    done
    return 1
}

verify() {
    [ -n "$EXPECTED_BYTES" ] || return 0
    [ "$(wc -c < "$1")" -eq "$EXPECTED_BYTES" ] || {
        echo "Incorrect file size: $1. Move it aside and retry." >&2; exit 1;
    }
    echo "Verifying SHA-256: $1"
    if command -v sha256sum >/dev/null 2>&1; then
        ACTUAL=$(sha256sum < "$1")
    else
        ACTUAL=$(shasum -a 256 < "$1")
    fi
    ACTUAL=${ACTUAL%% *}
    [ "$ACTUAL" = "$EXPECTED_SHA" ] || {
        echo "Checksum mismatch: $1. The file was not accepted." >&2; exit 1;
    }
}

mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/$FILE"
if [ -s "$OUT" ]; then
    verify "$OUT"
    echo "Already downloaded: $OUT"
else
    HF=$(find_hf || true)
    [ -n "$HF" ] || {
        echo "Install the Hugging Face CLI: python3 -m pip install -U huggingface_hub hf_xet" >&2
        exit 1
    }
    echo "Downloading $FILE from https://huggingface.co/$REPO"
    echo "Run this command again to resume an interrupted download."
    if [ -n "$TOKEN" ]; then
        "$HF" download "$REPO" "$FILE" --repo-type model --local-dir "$OUT_DIR" --token "$TOKEN"
    else
        "$HF" download "$REPO" "$FILE" --repo-type model --local-dir "$OUT_DIR"
    fi
    [ -s "$OUT" ] || { echo "Download finished but $OUT is missing" >&2; exit 1; }
    verify "$OUT"
fi

if [ "$LINK" -eq 1 ]; then
    ln -sfn "$OUT" "$ROOT/qwen3.8-flash-next.gguf"
    echo "Linked ./qwen3.8-flash-next.gguf -> $OUT"
    echo "Run ./sf-q3-8flash; add --mtp for speculative decoding."
else
    echo "Use --vision $OUT"
fi
