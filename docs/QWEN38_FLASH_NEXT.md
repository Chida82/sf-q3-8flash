# Qwen3.8 Flash Next

Qwen3.8 Flash Next uses the `qwen4exp` GGUF architecture and a dedicated Metal
graph with gated delta-net, gated GQA, block-sparse attention,
hyper-connections, n-gram embeddings, MoE, and built-in MTP.

## Download and run

```sh
make -j8
./download.sh q2                 # or q4
./sf-q3-8flash --ctx 8192 --prefill-chunk 1024
```

The Q2 GGUF is about 137.10 GiB with 41.73 GiB of resident weights. Q4 is about
165.11 GiB with 69.74 GiB resident. Both include MTP weights and the 95.37 GiB
BF16 n-gram table. The n-grams remain on disk and selected rows are read from
the GGUF, so use a fast local SSD.

Enable built-in speculation with `--mtp`. `--nothink` disables reasoning. The
server advertises `qwen3.8-flash-next`, `qwen3.8-flash-next-chat`, and
`qwen3.8-flash-next-reasoner`; tool calls use Qwen's native format.

Batched server sessions share the prefill workspace while recurrent and
attention state stays per session. Images and steering use the ordered fallback.
`--mtp-exact-sampling` keeps the ordinary sampling distribution.

The native context is 262144 tokens. `DS4_QWEN4_YARN_FACTOR=2` or `=4` enables
static YaRN beyond it, with a possible quality cost on shorter prompts.

## Vision

```sh
./download.sh vision
./sf-q3-8flash --vision gguf/mmproj-Qwen3.8-Flash-Next-Q8_0.gguf
```

Images use the Qwen3-VL tower. The CLI accepts `/read image.png`; server APIs
accept image content. Images are resized to multiples of 32 pixels within 64 to
1024 tokens; `DS4_QWEN4_IMAGE_MAX_TOKENS` can raise the cap.

For implementation parity with the original checkpoint:

```sh
DS4_QWEN4_SNAPSHOT=/path/to/checkpoint \
DS4_QWEN4_MMPROJ=/path/to/mmproj.gguf \
DS4_QWEN4_IMAGE=/path/to/image.png \
make test-qwen4-vision
```

## Validation

```sh
make test-qwen4-kernels test-qwen4-q2 test-qwen4-prefill-reuse
make test-q8-prefill-variants test-qwen4-ngrams
DS4_TEST_MODEL=/path/to/main-with-mtp.gguf DS4_TEST_GLM_MTP=1 ./ds4_test
python3 tests/test_qwen4_checkpoint_replay.py --model /path/to/main-with-mtp.gguf
python3 tests/test_qwen4_mtp_limits.py --model /path/to/main-with-mtp.gguf
python3 tests/test_qwen4_logit_dump.py --model /path/to/main-with-mtp.gguf
python3 tests/test_qwen4_steering.py --model /path/to/main-with-mtp.gguf
```

The checkpoint tests cover chunk boundaries, rollback, repeated restores, and
truncated payloads. The logit test compares all-row prefill with teacher-forced
decode. The steering test covers all 48 trunk layers.

Qwen tensor-parallel, pipeline, and full model-weight SSD streaming execution
remain unavailable until their recurrent-state contracts are implemented and
verified; their shared infrastructure stays in this child.
