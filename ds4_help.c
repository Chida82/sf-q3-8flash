#include "ds4_help.h"

static const char *tool_name(ds4_help_tool tool) {
    switch (tool) {
    case DS4_HELP_SERVER: return "sf-q3-8flash-server";
    case DS4_HELP_BENCH: return "sf-q3-8flash-bench";
    case DS4_HELP_EVAL: return "sf-q3-8flash-eval";
    default: return "sf-q3-8flash";
    }
}

void ds4_help_print(FILE *fp, ds4_help_tool tool, const char *topic) {
    (void)topic;
    const char *name = tool_name(tool);
    fprintf(fp, "%s — Qwen3.8 Flash Next on Apple Metal\n\n", name);
    fprintf(fp, "Usage: %s [options]\n\n", name);
    fprintf(fp, "Model and runtime:\n");
    fprintf(fp, "  -m, --model FILE              Main GGUF (default: qwen3.8-flash-next.gguf)\n");
    fprintf(fp, "  --vision FILE                 Qwen3-VL vision projector GGUF\n");
    fprintf(fp, "  --metal | --cpu               Metal runtime or CPU reference path\n");
    fprintf(fp, "  -c, --ctx N                   Context size\n");
    fprintf(fp, "  -t, --threads N               CPU helper threads\n");
    fprintf(fp, "  --prefill-chunk N             Prefill chunk size\n");
    fprintf(fp, "  --mtp                          Enable built-in Qwen MTP\n");
    fprintf(fp, "  --mtp-exact-sampling          Preserve the ordinary sampling distribution\n");
    fprintf(fp, "  --dir-steering-file FILE      Qwen steering vectors\n");
    fprintf(fp, "  --dir-steering-ffn F          FFN steering scale\n");
    fprintf(fp, "  --dir-steering-attn F         Attention steering scale\n");
    fprintf(fp, "  --quality                     Prefer numerical quality over speed\n");
    fprintf(fp, "  --warm-weights                Touch model pages before inference\n");
    fprintf(fp, "\nSampling:\n");
    fprintf(fp, "  -n, --tokens N                Maximum generated tokens\n");
    fprintf(fp, "  --temp F --top-p F --min-p F  Sampling controls\n");
    fprintf(fp, "  --seed N                      Sampling seed\n");
    fprintf(fp, "  --think | --nothink           Enable or disable reasoning\n");

    if (tool == DS4_HELP_DS4) {
        fprintf(fp, "\nCLI:\n");
        fprintf(fp, "  -p, --prompt TEXT             Run one prompt and exit\n");
        fprintf(fp, "  --prompt-file FILE            Read a prompt from a file\n");
        fprintf(fp, "  --prefix-file FILE            Preload complete conversation turns\n");
        fprintf(fp, "  --inspect                     Print model metadata and exit\n");
        fprintf(fp, "  --dump-tokens                 Print the rendered token stream\n");
    } else if (tool == DS4_HELP_SERVER) {
        fprintf(fp, "\nServer:\n");
        fprintf(fp, "  --host HOST                   Bind address (default: 127.0.0.1)\n");
        fprintf(fp, "  --port N                      Bind port (default: 8004)\n");
        fprintf(fp, "  --batched-session N           Keep and batch N resident sessions\n");
        fprintf(fp, "  --kv-disk-dir DIR             Enable disk KV checkpoints\n");
        fprintf(fp, "  --kv-disk-space-mb N          Disk-cache budget\n");
        fprintf(fp, "  --cors                        Enable browser CORS headers\n");
        fprintf(fp, "  --trace FILE                  Log prompts, cache decisions, and output\n");
    } else if (tool == DS4_HELP_BENCH) {
        fprintf(fp, "\nBenchmark:\n");
        fprintf(fp, "  --ctx-start N --ctx-max N     Context range\n");
        fprintf(fp, "  --step-incr N | --step-mul F  Context progression\n");
        fprintf(fp, "  --gen-tokens N                Decode tokens per measurement\n");
        fprintf(fp, "  --prompt-file FILE            Benchmark input\n");
        fprintf(fp, "  --csv FILE                    Write measurements\n");
    } else if (tool == DS4_HELP_EVAL) {
        fprintf(fp, "\nEvaluation:\n");
        fprintf(fp, "  --suite core|hard|all         Evaluation suite\n");
        fprintf(fp, "  --case-id ID                  Run one case\n");
        fprintf(fp, "  --list-cases                  List available cases\n");
        fprintf(fp, "  --validate-cases              Validate fixtures without a model\n");
        fprintf(fp, "  --self-test-extractors        Test answer extraction without a model\n");
    }

    fprintf(fp, "\nDistributed and advanced options remain available; see README.md and docs/.\n");
}
