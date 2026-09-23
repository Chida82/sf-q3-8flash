ifneq ($(shell uname -s),Darwin)
$(error sf-q3-8flash builds on macOS only)
endif

# sf: child identity (SPEC.md §E). Everything else below is upstream's.
BIN ?= sf-q3-8flash
SF_DEFS := -DSF_DEFAULT_MODEL='"qwen3.8-flash-next.gguf"' -DSF_DEFAULT_PORT=8004 \
           -DSF_HOME='".sf/q3-8flash"' -DSF_LOCK_FILE='"/tmp/sf-q3-8flash.lock"'

CC ?= cc
NATIVE_CPU_FLAG ?= -mcpu=native
DEBUG_FLAGS ?= -g
CFLAGS ?= -O3 -ffast-math $(DEBUG_FLAGS) $(NATIVE_CPU_FLAG) -Wall -Wextra -std=c99
OBJCFLAGS ?= -O3 -ffast-math $(DEBUG_FLAGS) $(NATIVE_CPU_FLAG) -Wall -Wextra -fobjc-arc
QUALITY_CFLAGS ?= -O3 $(DEBUG_FLAGS) $(NATIVE_CPU_FLAG) -Wall -Wextra -std=c11
CFLAGS += $(SF_DEFS)
OBJCFLAGS += $(SF_DEFS)
LDLIBS ?= -lm -pthread
METAL_LDLIBS := $(LDLIBS) -framework Foundation -framework Metal
METAL_SRCS := $(wildcard metal/*.metal)
CORE_OBJS := ds4.o ds4_image.o ds4_distributed.o ds4_tp.o ds4_ssd.o ds4_metal.o ds4_layer_pack.o
CPU_CORE_OBJS := ds4_cpu.o ds4_image.o ds4_distributed.o ds4_tp.o ds4_ssd.o ds4_layer_pack.o
DS4_TEST_MODEL ?= qwen3.8-flash-next.gguf
QWEN4_KERNEL_TEST := tests/test_qwen4_kernels

.PHONY: all help clean cpu test test-frontends test-session-state \
        check-mxfp4-half-lut test-mxfp4-metal test-qwen4-kernels test-qwen4-q2 \
        test-qwen4-vision test-qwen4-moe-mm-specialize test-qwen4-prefill-reuse \
        test-q8-prefill-variants test-qwen4-ngrams test-ssd-cache \
        test-metal-session-batch test-metal-moe-prefill test-metal-dense-mpp \
        test-metal-ssd-experts test-metal-command-memory \
        metal-decode-schedule-bench metal-prefill-variant-bench session-concurrency-bench \
        test-download-model test-quality-api

all: $(BIN) $(BIN)-server $(BIN)-bench $(BIN)-eval

help:
	@echo "sf-q3-8flash build targets:"
	@echo "  make                       Build the four Metal binaries"
	@echo "  make cpu                   Build the four CPU-reference binaries ($(BIN)-cpu*)"
	@echo "  make test                  Run model-less tests"
	@echo "  make test-qwen4-kernels    Run Qwen3.8 Metal kernel tests"
	@echo "  make test-qwen4-q2         Run exact low-bit decode and prefill parity"
	@echo "  make test-qwen4-vision     Compare vision with HF (requires snapshot, mmproj, image)"
	@echo "  make clean                 Remove build outputs"

$(BIN): ds4_cli.o ds4_help.o ds4_prompt_prefix.o linenoise.o $(CORE_OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(METAL_LDLIBS)

$(BIN)-server: ds4_server.o ds4_help.o ds4_kvstore.o rax.o $(CORE_OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(METAL_LDLIBS)

$(BIN)-bench: ds4_bench.o ds4_help.o $(CORE_OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(METAL_LDLIBS)

$(BIN)-eval: ds4_eval.o ds4_eval_cases.o ds4_help.o $(CORE_OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(METAL_LDLIBS)

# The CPU-reference build gets its own four names. Linking it over the default
# names, as upstream does, leaves make unable to tell the flavours apart: a
# plain `make` afterwards finds the binaries newer than every object, relinks
# nothing, and the next model run dies with "Qwen3.8 requires Metal". Separate
# names make that state unreachable instead of documented.
cpu: ds4_cli_cpu.o ds4_server_cpu.o ds4_bench_cpu.o ds4_eval_cpu.o ds4_eval_cases.o \
     ds4_help.o ds4_prompt_prefix.o ds4_kvstore.o linenoise.o rax.o $(CPU_CORE_OBJS)
	$(CC) $(CFLAGS) -o $(BIN)-cpu ds4_cli_cpu.o ds4_help.o ds4_prompt_prefix.o linenoise.o $(CPU_CORE_OBJS) $(LDLIBS)
	$(CC) $(CFLAGS) -o $(BIN)-cpu-server ds4_server_cpu.o ds4_help.o ds4_kvstore.o rax.o $(CPU_CORE_OBJS) $(LDLIBS)
	$(CC) $(CFLAGS) -o $(BIN)-cpu-bench ds4_bench_cpu.o ds4_help.o $(CPU_CORE_OBJS) $(LDLIBS)
	$(CC) $(CFLAGS) -o $(BIN)-cpu-eval ds4_eval_cpu.o ds4_eval_cases.o ds4_help.o $(CPU_CORE_OBJS) $(LDLIBS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

ds4_metal.o: ds4_metal.m ds4_gpu.h ds4_gpu_tp.h $(METAL_SRCS)
	$(CC) $(OBJCFLAGS) -c -o $@ $<

ds4_cpu.o: ds4.c
	$(CC) $(CFLAGS) -Wno-unused-function -DDS4_NO_GPU -c -o $@ $<

ds4_cli_cpu.o: ds4_cli.c
	$(CC) $(CFLAGS) -DDS4_NO_GPU -c -o $@ $<



ds4_server_cpu.o: ds4_server.c
	$(CC) $(CFLAGS) -DDS4_NO_GPU -c -o $@ $<

ds4_bench_cpu.o: ds4_bench.c
	$(CC) $(CFLAGS) -DDS4_NO_GPU -c -o $@ $<

ds4_eval_cpu.o: ds4_eval.c
	$(CC) $(CFLAGS) -DDS4_NO_GPU -c -o $@ $<

rax.o: rax.c rax.h rax_malloc.h
linenoise.o: linenoise.c linenoise.h

# sf: header dependencies. Upstream's generic %.o rule tracks only the .c, so a
# change to ds4.h left objects built against the old struct layout; the server
# unit tests then read TP fields at the wrong offset until `make clean`. Each
# object lists the headers it includes directly plus those pulled in by ds4.h.
DS4_CORE_HDRS := ds4.h ds4_tool_text.h ds4_distributed.h ds4_image.h ds4_tp.h \
                 ds4_layer_pack.h ds4_gpu_mgpu.h ds4_gpu.h ds4_gpu_tp.h ds4_qwen4_vision.h \
                 ds4_qwen4_unicode.inc
ds4.o ds4_cpu.o ds4_cpu_test_hooks.o: $(DS4_CORE_HDRS)
ds4_metal.o: $(DS4_CORE_HDRS)
ds4_cli.o ds4_cli_cpu.o: ds4.h ds4_distributed.h ds4_tp.h ds4_help.h ds4_prompt_prefix.h linenoise.h
ds4_server.o ds4_server_cpu.o: ds4.h ds4_tool_text.h ds4_distributed.h ds4_help.h ds4_kvstore.h ds4_tp.h rax.h
ds4_bench.o ds4_bench_cpu.o: ds4.h ds4_distributed.h ds4_help.h ds4_tp.h
ds4_eval.o ds4_eval_cpu.o: ds4.h ds4_distributed.h ds4_eval_cases.h ds4_help.h ds4_tp.h
ds4_eval_cases.o: ds4_eval_cases.h
ds4_help.o: ds4_help.h ds4.h
ds4_kvstore.o: ds4_kvstore.h ds4.h
ds4_prompt_prefix.o: ds4_prompt_prefix.h
ds4_tp.o: ds4_tp.h ds4_gpu.h ds4.h
ds4_distributed.o: ds4_distributed.h ds4.h
ds4_ssd.o: ds4_ssd.h
ds4_image.o: ds4_image.h
ds4_layer_pack.o: ds4_layer_pack.h
ds4_test.o: tests/ds4_test.c ds4_server.c ds4.c ds4.h ds4_help.h ds4_kvstore.h
	$(CC) $(CFLAGS) -Wno-unused-function -c -o $@ $<

ds4_test: ds4_test.o ds4_help.o ds4_kvstore.o rax.o $(CORE_OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(METAL_LDLIBS)

tests/test_prompt_prefix: tests/test_prompt_prefix.c ds4_prompt_prefix.o
	$(CC) $(CFLAGS) -I. -o $@ $^

tests/test_layer_pack: tests/test_layer_pack.c ds4_layer_pack.o
	$(CC) $(CFLAGS) -I. -o $@ $^ $(LDLIBS)

ds4_cpu_test_hooks.o: ds4.c
	$(CC) $(CFLAGS) -Wno-unused-function -DDS4_NO_GPU -DDS4_TEST_HOOKS -c -o $@ $<

tests/test_sampling: tests/test_sampling.c ds4_cpu_test_hooks.o ds4_image.o ds4_distributed.o ds4_tp.o ds4_ssd.o ds4_layer_pack.o
	$(CC) $(CFLAGS) -fno-finite-math-only -DDS4_TEST_HOOKS -I. -o $@ $^ $(LDLIBS)

tests/test_image_decode.o: tests/test_image_decode.c ds4_image.h
	$(CC) $(CFLAGS) -I. -c -o $@ $<

tests/test_image_decode: tests/test_image_decode.o ds4_image.o
	$(CC) $(CFLAGS) -o $@ $^ -lm

tests/test_session_state.o: tests/test_session_state.c
	$(CC) $(CFLAGS) -Wno-unused-function -DDS4_NO_GPU -I. -c -o $@ $<

tests/test_session_state: tests/test_session_state.o $(filter-out ds4_cpu.o,$(CPU_CORE_OBJS))
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)

tests/test_tp_commands: tests/test_tp_commands.c $(filter-out ds4_tp.o,$(CPU_CORE_OBJS))
	$(CC) $(CFLAGS) -I. -o $@ $^ $(LDLIBS)

tests/test_tp_rdma: tests/test_tp_rdma.c $(filter-out ds4_tp.o,$(CPU_CORE_OBJS))
	$(CC) $(CFLAGS) -I. -o $@ $^ $(LDLIBS)

tests/test_tp_tcp: tests/test_tp_tcp.c $(filter-out ds4_tp.o,$(CPU_CORE_OBJS))
	$(CC) $(CFLAGS) -I. -o $@ $^ $(LDLIBS)

tests/test_tp_link: tests/test_tp_link.c ds4_tp.h ds4.h $(CPU_CORE_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ $< $(CPU_CORE_OBJS) $(LDLIBS)

test-session-state: tests/test_session_state tests/test_tp_commands tests/test_tp_rdma tests/test_tp_tcp
	./tests/test_session_state
	./tests/test_tp_commands
	./tests/test_tp_rdma
	./tests/test_tp_tcp

tests/test_qwen4_ngrams.o: tests/test_qwen4_ngrams.c
	$(CC) $(filter-out -ffast-math,$(CFLAGS)) -Wno-unused-function -I. -c -o $@ $<

tests/test_qwen4_ngrams: tests/test_qwen4_ngrams.o $(filter-out ds4_cpu.o,$(CPU_CORE_OBJS))
	$(CC) $(filter-out -ffast-math,$(CFLAGS)) -o $@ $^ $(LDLIBS)

test-qwen4-ngrams: tests/test_qwen4_ngrams
	./tests/test_qwen4_ngrams

tests/test_qwen4_ngram_state.o: tests/test_qwen4_ngram_state.c
	$(CC) $(filter-out -ffast-math,$(CFLAGS)) -Wno-unused-function -I. -c -o $@ $<

tests/test_qwen4_ngram_state: tests/test_qwen4_ngram_state.o $(filter-out ds4.o,$(CORE_OBJS))
	$(CC) $(filter-out -ffast-math,$(CFLAGS)) -o $@ $^ $(METAL_LDLIBS)

tests/test_qwen4_kernels.o: tests/test_qwen4_kernels.c
	$(CC) $(CFLAGS) -I. -c -o $@ $<

$(QWEN4_KERNEL_TEST): tests/test_qwen4_kernels.o ds4_metal.o ds4_image.o
	$(CC) $(CFLAGS) -o $@ $^ $(METAL_LDLIBS)

test-qwen4-kernels: $(QWEN4_KERNEL_TEST)
	./$(QWEN4_KERNEL_TEST)

tests/test_qwen4_moe_mm_specialize: tests/test_qwen4_moe_mm_specialize.c $(CORE_OBJS)
	$(CC) $(CFLAGS) -fno-fast-math -I. -o $@ $^ $(METAL_LDLIBS)

test-qwen4-moe-mm-specialize: tests/test_qwen4_moe_mm_specialize
	./tests/test_qwen4_moe_mm_specialize

tests/test_qwen4_conv_parallel: tests/test_qwen4_conv_parallel.c $(CORE_OBJS)
	$(CC) $(CFLAGS) -fno-fast-math -I. -o $@ $^ $(METAL_LDLIBS)

test-qwen4-prefill-reuse: tests/test_qwen4_conv_parallel tests/test_qwen4_moe_mm_specialize
	./tests/test_qwen4_conv_parallel
	./tests/test_qwen4_moe_mm_specialize

test-qwen4-q2: $(QWEN4_KERNEL_TEST) tests/test_qwen4_moe_mm_specialize
	DS4_TEST_QWEN4_MV_EXACT=1 ./$(QWEN4_KERNEL_TEST)
	./tests/test_qwen4_moe_mm_specialize

tests/test_q8_prefill_variants: tests/test_q8_prefill_variants.c $(CORE_OBJS)
	$(CC) $(CFLAGS) -fno-fast-math -I. -o $@ $^ $(METAL_LDLIBS)

test-q8-prefill-variants: tests/test_q8_prefill_variants
	./tests/test_q8_prefill_variants

tests/test_qwen4_vision: tests/test_qwen4_vision.c $(CORE_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ $^ $(METAL_LDLIBS)

test-qwen4-vision: tests/test_qwen4_vision
	@test -n "$(DS4_QWEN4_SNAPSHOT)" -a -n "$(DS4_QWEN4_MMPROJ)" -a -n "$(DS4_QWEN4_IMAGE)" || \
	  { echo "set DS4_QWEN4_SNAPSHOT, DS4_QWEN4_MMPROJ and DS4_QWEN4_IMAGE"; exit 1; }
	python3 tests/qwen4_vision_ref.py --snapshot "$(DS4_QWEN4_SNAPSHOT)" --mmproj "$(DS4_QWEN4_MMPROJ)" --image "$(DS4_QWEN4_IMAGE)"

tests/test_mxfp4_metal: tests/test_mxfp4_metal.c ds4_metal.o ds4_image.o
	$(CC) $(CFLAGS) -I. -o $@ $^ $(METAL_LDLIBS)

check-mxfp4-half-lut:
	python3 metal/generate_mxfp4_half_lut.py --check

test-mxfp4-metal: check-mxfp4-half-lut tests/test_mxfp4_metal
	./tests/test_mxfp4_metal

tests/test_metal_session_batch: tests/test_metal_session_batch.c $(CORE_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ $^ $(METAL_LDLIBS)

tests/test_metal_tp_cancel: tests/test_metal_tp_cancel.c ds4.h ds4_tp.h $(CORE_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ $< $(CORE_OBJS) $(METAL_LDLIBS)

tests/test_metal_tp_bulk: tests/test_metal_tp_bulk.c ds4_gpu.h ds4_tp.h $(CORE_OBJS)
	$(CC) $(filter-out -ffast-math,$(CFLAGS)) -I. -o $@ $< $(CORE_OBJS) $(METAL_LDLIBS)

tests/test_qwen4_prefill: tests/test_qwen4_prefill.c ds4.h $(CORE_OBJS)
	$(CC) $(QUALITY_CFLAGS) -I. -o $@ $< $(CORE_OBJS) $(METAL_LDLIBS)

test-metal-session-batch: tests/test_metal_session_batch
	DS4_TEST_MODEL="$(DS4_TEST_MODEL)" ./tests/test_metal_session_batch

tests/test_metal_moe_prefill: tests/test_metal_moe_prefill.c $(CORE_OBJS)
	$(CC) $(CFLAGS) -fno-fast-math -I. -o $@ $^ $(METAL_LDLIBS)

test-metal-moe-prefill: tests/test_metal_moe_prefill
	./tests/test_metal_moe_prefill

tests/test_metal_dense_mpp: tests/test_metal_dense_mpp.c $(CORE_OBJS)
	$(CC) $(CFLAGS) -fno-fast-math -I. -o $@ $^ $(METAL_LDLIBS)

test-metal-dense-mpp: tests/test_metal_dense_mpp
	./tests/test_metal_dense_mpp

tests/test_metal_ssd_experts: tests/test_metal_ssd_experts.c $(CORE_OBJS)
	$(CC) $(CFLAGS) -fno-fast-math -I. -o $@ $^ $(METAL_LDLIBS)

test-metal-ssd-experts: tests/test_metal_ssd_experts
	./tests/test_metal_ssd_experts
	./tests/test_metal_ssd_experts --q4
	./tests/test_metal_ssd_experts --mxfp4

tests/test_metal_command_memory: tests/test_metal_command_memory.c $(CORE_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ $^ $(METAL_LDLIBS)

test-metal-command-memory: tests/test_metal_command_memory
	MTL_DEBUG_LAYER=1 ./tests/test_metal_command_memory
	MTL_DEBUG_LAYER=1 ./tests/test_metal_command_memory row
	MTL_DEBUG_LAYER=1 ./tests/test_metal_command_memory session
	MTL_DEBUG_LAYER=1 ./tests/test_metal_command_memory batch
	MTL_DEBUG_LAYER=1 ./tests/test_metal_command_memory big

tests/test_ssd_cache: tests/test_ssd_cache.c ds4_ssd.c ds4_ssd.h
	$(CC) $(CFLAGS) -I. -o $@ tests/test_ssd_cache.c ds4_ssd.c

test-ssd-cache: tests/test_ssd_cache
	./tests/test_ssd_cache

test-frontends: ds4_test
	./ds4_test --server

q4k-dot-test: tests/test_q4k_dot.c
	$(CC) -O2 -Wall -Wextra -std=c99 -o tests/test_q4k_dot $< -lm -pthread
	./tests/test_q4k_dot

mxfp4-dot-test: tests/test_mxfp4_dot.c
	$(CC) -O2 -Wall -Wextra -std=c99 -o tests/test_mxfp4_dot $< -lm
	./tests/test_mxfp4_dot

test: all ds4_test q4k-dot-test mxfp4-dot-test test-session-state tests/test_layer_pack \
      tests/test_prompt_prefix tests/test_sampling tests/test_image_decode test-qwen4-ngrams
	./$(BIN)-eval --validate-cases
	./$(BIN)-eval --self-test-extractors
	./ds4_test --server
	./tests/test_layer_pack
	./tests/test_prompt_prefix
	./tests/test_sampling
	./tests/test_image_decode
	python3 tests/test_model_download.py


gguf-tools/quality-testing/score_official: gguf-tools/quality-testing/score_official.c $(CORE_OBJS) rax.o
	$(CC) $(QUALITY_CFLAGS) -I. -o $@ $^ $(METAL_LDLIBS)

test-quality-api: tests/test_quality_api.c gguf-tools/quality-testing/score_official.c
	$(CC) $(QUALITY_CFLAGS) -I. -ffunction-sections -fdata-sections -o tests/test_quality_api tests/test_quality_api.c -Wl,-dead_strip -lm
	./tests/test_quality_api
	python3 tests/test_collect_official.py

test-download-model:
	python3 tests/test_model_download.py

speed-bench/metal_decode_schedule_bench: speed-bench/metal_decode_schedule_bench.c $(CORE_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ $^ $(METAL_LDLIBS)
metal-decode-schedule-bench: speed-bench/metal_decode_schedule_bench

speed-bench/metal_prefill_variant_bench: speed-bench/metal_prefill_variant_bench.c $(CORE_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ $^ $(METAL_LDLIBS)
metal-prefill-variant-bench: speed-bench/metal_prefill_variant_bench

speed-bench/session_concurrency_bench: speed-bench/session_concurrency_bench.c $(CORE_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ $^ $(METAL_LDLIBS)
session-concurrency-bench: speed-bench/session_concurrency_bench

clean:
	rm -f $(BIN) $(BIN)-server $(BIN)-bench $(BIN)-eval ds4_test *.o tests/*.o speed-bench/*.o
	rm -f $(BIN)-cpu $(BIN)-cpu-server $(BIN)-cpu-bench $(BIN)-cpu-eval
	rm -f tests/test_q4k_dot tests/test_mxfp4_dot tests/test_session_state tests/test_tp_commands tests/test_tp_rdma tests/test_tp_tcp
	rm -f tests/test_layer_pack tests/test_prompt_prefix tests/test_sampling tests/test_qwen4_ngrams tests/test_qwen4_ngram_state
	rm -f tests/test_image_decode
	rm -f tests/test_qwen4_kernels tests/test_qwen4_moe_mm_specialize tests/test_qwen4_conv_parallel tests/test_q8_prefill_variants tests/test_qwen4_vision
	rm -f tests/test_metal_tp_bulk tests/test_metal_tp_cancel tests/test_tp_link tests/test_qwen4_prefill
	rm -f tests/test_mxfp4_metal tests/test_metal_session_batch tests/test_metal_moe_prefill tests/test_metal_dense_mpp tests/test_metal_ssd_experts tests/test_metal_command_memory tests/test_ssd_cache tests/test_quality_api
	rm -f speed-bench/metal_decode_schedule_bench speed-bench/metal_prefill_variant_bench speed-bench/session_concurrency_bench
