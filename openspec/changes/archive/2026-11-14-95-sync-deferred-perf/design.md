# Design

## D1. The embedding gather is a Qwen kernel, not upstream's GLM pair

Upstream's `1c6d058` stages prompt embeddings on the GPU in two dispatches:

1. `kernel_glm53_embedding_bf16` (`metal/glm53_bf16.metal`): for every token
   row and element, `out[t][d] = bf16_to_f32(table[token[t]][d])`, zero for an
   out-of-range id;
2. `ds4_gpu_repeat_hc_rows_tensor`: copy each row to the `hc` streams of `R`.

The first kernel carries a GLM name only because GLM 5.3 needed a BF16 gather
first. Nothing in it is GLM-specific. Bringing it back means bringing back a
file this child deleted with GLM (`metal/glm53_bf16.metal`) and adding the
kernel to "Names that lie", for twelve lines of code.

The child already has the dequantizer: `qwen4_embd_at(row, type, i)` in
`metal/qwen4.metal`, written for `30`'s MTP input and proved there to equal the
host's `qwen4_ref_row` for F32, F16, BF16, Q8_0 and Q4_0 tables. One kernel
does both of upstream's steps:

```metal
struct ds4_metal_args_qwen4_embd_rows {
    uint32_t n_embd, n_hc, n_tokens, table_type, row_bytes, n_vocab;
};

/* Prompt rows of the residual: the token's embedding, dequantized as the host
 * reference does it, written to every HC stream. */
kernel void kernel_qwen4_embd_rows(
        constant ds4_metal_args_qwen4_embd_rows & args,
        device const int  *ids,     /* [T] */
        device const char *table,   /* token embeddings */
        device float      *R,       /* [T][hc][E] */
        uint2 gid [[thread_position_in_grid]]) {
    const uint d = gid.x, t = gid.y;
    if (d >= args.n_embd || t >= args.n_tokens) return;
    const int id = ids[t];
    const float v = id >= 0 && (uint)id < args.n_vocab
        ? qwen4_embd_at(table + (uint64_t)(uint)id * args.row_bytes, args.table_type, d) : 0.0f;
    device float *o = R + (uint64_t)t * args.n_hc * args.n_embd + d;
    for (uint s = 0; s < args.n_hc; s++) o[(uint64_t)s * args.n_embd] = v;
}
```

The out-of-range branch is never taken: `c97964b` (taken at `90`) validates
token ids before staging. It stays as a bound on a device read.

Host side, in `qwen4_graph_stage_embeddings`: write the ids to `g->selected`
(idle until the first layer's routing, as upstream notes), dispatch, skip the
host loop's embedding copy but keep its M-RoPE positions, and skip the `R`
upload. Image spans keep the host path. Before taking the branch, check every
reader of `g->host_row` after staging; upstream found none, and this child's
priming reads `R`, not `host_row`.

## D2. Threshold

Upstream gathers on the device only for `T >= 128`, with no figure given for
the choice. For a short chunk the host copy is a few rows of memcpy and the
upload is small, so a dispatch may not pay. Measure 1, 32 and 128 and keep the
smallest that never loses (tasks 1.4).

## D3. Exactness

The value is a copy of a dequantized table element, computed by the same
expression the MTP stage already uses and the kernel suite already pins.
`make test-qwen4-kernels` gets a direct pin (tasks 1.2), and the A/B runs with
`--bitwise`.
