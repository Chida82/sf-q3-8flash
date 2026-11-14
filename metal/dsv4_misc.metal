struct ds4_metal_args_dsv4_topk_mask {
    int64_t  ne00;
    int64_t  ne01;
    uint64_t nb00;
    uint64_t nb01;
    int64_t  ne0;
    int64_t  ne1;
    uint64_t nb0;
    uint64_t nb1;
};

struct ds4_metal_args_dsv4_indexer_weighted_sum {
    int64_t  ne00;
    int64_t  ne01;
    int64_t  ne02;
    uint64_t nb00;
    uint64_t nb01;
    uint64_t nb02;
    int64_t  ne10;
    int64_t  ne11;
    uint64_t nb10;
    uint64_t nb11;
    int64_t  ne0;
    int64_t  ne1;
    uint64_t nb0;
    uint64_t nb1;
    float    scale;
};

struct ds4_metal_args_dsv4_softmax_pool {
    int64_t  ne00;
    int64_t  ne01;
    int64_t  ne02;
    uint64_t nb00;
    uint64_t nb01;
    uint64_t nb02;
    uint64_t nb10;
    uint64_t nb11;
    uint64_t nb12;
    int64_t  ne0;
    int64_t  ne1;
    uint64_t nb0;
    uint64_t nb1;
};

struct ds4_metal_args_dsv4_softmax_pool_ratio4_direct {
    int64_t  n_rows;
    uint32_t head_dim;
    uint32_t n_comp;
    uint32_t replay;
    uint32_t pad;
};

struct ds4_metal_args_dsv4_compressor_score_ape {
    uint32_t width;
    uint32_t ratio;
    uint32_t pos0;
    uint32_t n_tokens;
};

struct ds4_metal_args_dsv4_indexed_attention {
    uint32_t n_tokens;
    uint32_t n_head;
    uint32_t n_raw;
    uint32_t raw_cap;
    uint32_t raw_start;
    uint32_t n_comp;
    uint32_t top_k;
    uint32_t pos0;
    uint32_t window;
    uint32_t ratio;
    uint32_t comp_kv_f16;
    uint32_t n_splits;
    uint64_t q_token_stride;
    uint64_t q_head_stride;
    uint64_t raw_row_stride;
    uint64_t comp_row_stride;
    uint64_t topk_token_stride;
    uint64_t dst_token_stride;
    uint64_t dst_head_stride;
    float    scale;
};

struct ds4_metal_args_dsv4_indexer_scores_fused {
    uint32_t n_comp;
    uint32_t n_tokens;
    uint32_t n_head;
    uint32_t head_dim;
    uint32_t pos0;
    uint32_t ratio;
    uint64_t q_token_stride;
    uint64_t q_head_stride;
    uint64_t weights_token_stride;
    uint64_t index_row_stride;
    uint64_t score_token_stride;
    float    scale;
};

struct ds4_metal_args_dsv4_router_select_one {
    uint32_t has_bias;
    uint32_t hash_mode;
    uint32_t use_token_buffer;
    uint32_t token;
    uint32_t hash_rows;
};

struct ds4_metal_args_dsv4_router_select_visual {
    uint32_t hash_rows;
    uint32_t vocab_size;
    uint32_t n_tokens;
    uint32_t has_bias;
    uint32_t hash_mode;
};

struct ds4_metal_args_dsv4_directional_steering_project {
    uint32_t width;
    uint32_t rows;
    uint32_t layer;
    uint32_t n_threads;
    float    scale;
};

// Optional directional steering projection.
//
// Each threadgroup owns one 4096-wide token row, computes
// dot(row, direction[layer]), then subtracts scale * direction * dot in-place.
// Positive scales remove a concept direction; negative scales amplify it.  The
// kernel is not used unless a steering file and nonzero scale are provided.
kernel void kernel_dsv4_directional_steering_project_f32(
        constant ds4_metal_args_dsv4_directional_steering_project & args,
        device float *x,
        device const float *directions,
        threadgroup float *scratch [[threadgroup(0)]],
        uint row [[threadgroup_position_in_grid]],
        uint tid [[thread_position_in_threadgroup]]) {
    if (row >= args.rows || args.width == 0) return;

    device float *xr = x + (uint64_t)row * args.width;
    device const float *dir = directions + (uint64_t)args.layer * args.width;
    const uint nth = args.n_threads;

    float sum = 0.0f;
    for (uint i = tid; i < args.width; i += nth) {
        sum += xr[i] * dir[i];
    }
    scratch[tid] = sum;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (uint step = nth >> 1; step > 0; step >>= 1) {
        if (tid < step) scratch[tid] += scratch[tid + step];
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    const float coeff = args.scale * scratch[0];
    for (uint i = tid; i < args.width; i += nth) {
        xr[i] -= coeff * dir[i];
    }
}

// Decode-only DS4 ratio-4 indexer score builder.  One threadgroup owns one
// compressed row for the current token, stages that 128-wide row once, then
// walks the 64 indexer heads in four-head groups.  This avoids materializing the
// intermediate [compressed rows x heads] score matrix used by the generic
// matvec + weighted-sum path.
kernel void kernel_dsv4_indexer_score_one_direct(
        constant ds4_metal_args_dsv4_indexer_scores_fused & args,
        device const char *q,
        device const char *weights,
        device const char *index_comp,
        device       char *scores,
        threadgroup float *shared [[threadgroup(0)]],
        uint row [[threadgroup_position_in_grid]],
        ushort tid [[thread_index_in_threadgroup]],
        ushort lane [[thread_index_in_simdgroup]],
        ushort sg [[simdgroup_index_in_threadgroup]]) {
    if (row >= args.n_comp || args.n_head != 64u || args.head_dim != 128u) {
        return;
    }

    threadgroup float *ktg = shared;        // [128]
    threadgroup float *psum = ktg + 128u;   // [4]

    if (tid < 128u) {
        device const float *krow = (device const float *)(index_comp +
            (uint64_t)row * args.index_row_stride);
        ktg[tid] = krow[tid];
    }

    float acc = 0.0f;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (uint head0 = 0; head0 < 64u; head0 += 4u) {
        const uint head = head0 + (uint)sg;
        device const float4 *q4 = (device const float4 *)(q +
            (uint64_t)head * args.q_head_stride);
        threadgroup const float4 *k4 = (threadgroup const float4 *)ktg;

        float s = dot(q4[lane], k4[lane]);
        s = simd_sum(s);
        if (lane == 0) {
            device const float *w = (device const float *)weights;
            psum[sg] = max(s, 0.0f) * (w[head] * args.scale);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        if (tid == 0) {
            acc += psum[0];
            acc += psum[1];
            acc += psum[2];
            acc += psum[3];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    if (tid == 0) {
        device float *dst = (device float *)scores;
        dst[row] = acc;
    }
}

// The four SIMD groups finish their own heads independently. Publish all 64
// contributions before summing them in head order, with one block barrier.
kernel void kernel_dsv4_indexer_score_one_heads(
        constant ds4_metal_args_dsv4_indexer_scores_fused & args,
        device const char *q,
        device const char *weights,
        device const char *index_comp,
        device       char *scores,
        threadgroup float *shared [[threadgroup(0)]],
        uint row [[threadgroup_position_in_grid]],
        ushort tid [[thread_index_in_threadgroup]],
        ushort lane [[thread_index_in_simdgroup]],
        ushort sg [[simdgroup_index_in_threadgroup]]) {
    if (row >= args.n_comp || args.n_head != 64u || args.head_dim != 128u) {
        return;
    }

    device const float4 *krow = (device const float4 *)(index_comp +
        (uint64_t)row * args.index_row_stride);
    const float4 key = krow[lane];
    device const float *w = (device const float *)weights;
    for (uint head = sg; head < 64u; head += 4u) {
        device const float4 *q4 = (device const float4 *)(q + (uint64_t)head * args.q_head_stride);
        const float score = simd_sum(dot(q4[lane], key));
        if (lane == 0) shared[head] = max(score, 0.0f) * (w[head] * args.scale);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (tid == 0) {
        float acc = 0.0f;
        for (uint head = 0; head < 64u; head++) acc += shared[head];
        ((device float *)scores)[row] = acc;
    }
}

// Decode router post-processing for one token. The selected expert ids are
// already known; this gathers their probabilities, normalizes by the selected
// sum, clamps the denominator like the reference path, and applies DS4's 1.5
// expert-weight scale in one tiny dispatch.
kernel void kernel_dsv4_router_weights_one(
        device const char *probs,
        device const char *selected,
        device       char *weights,
        uint tid [[thread_position_in_grid]]) {
    if (tid >= 6) return;

    device const float *p = (device const float *)probs;
    device const int   *s = (device const int *)selected;

    float sum = 0.0f;
    for (uint i = 0; i < 6; i++) {
        sum += p[s[i]];
    }
    sum = max(sum, 6.103515625e-5f);

    device float *w = (device float *)weights;
    w[tid] = p[s[tid]] / sum * 1.5f;
}

// Batched Flash-router weight finalization after selection is already known.
// Six active lanes deliberately match kernel_sum_rows_f32_f32's reduction
// topology. The denominator and divided weights cross threadgroup storage
// boundaries so division cannot be reassociated with the final scale.
kernel void kernel_dsv4_router_weights_batch(
        constant float &scale,
        device const float *probs,
        device const int32_t *selected,
        device float *weights,
        threadgroup volatile float *scratch [[threadgroup(0)]],
        uint row [[threadgroup_position_in_grid]],
        ushort tid [[thread_position_in_threadgroup]],
        ushort sgitg [[simdgroup_index_in_threadgroup]],
        ushort tiisg [[thread_index_in_simdgroup]]) {
    if (tid >= 6) return;

    threadgroup volatile float *sum_scratch = scratch;
    threadgroup volatile float *denom_scratch = scratch + 32;
    threadgroup volatile float *div_scratch = scratch + 33;
    const uint out_index = row * 6u + (uint)tid;
    const int32_t expert = selected[out_index];
    const float p = probs[row * 256u + (uint)expert];

    // Keep this sequence identical to kernel_sum_rows_f32_f32 for width 6.
    if (sgitg == 0) {
        sum_scratch[tiisg] = 0.0f;
    }
    float sumf = 0.0f;
    sumf += p;
    sumf = simd_sum(sumf);
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (tiisg == 0) {
        sum_scratch[sgitg] = sumf;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    sumf = sum_scratch[tiisg];
    sumf = simd_sum(sumf);

    if (tid == 0) {
        denom_scratch[0] = clamp(sumf, 6.103515625e-5f, INFINITY);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    div_scratch[tid] = p / denom_scratch[0];
    threadgroup_barrier(mem_flags::mem_threadgroup);
    weights[out_index] = div_scratch[tid] * scale;
}

// Decode router selection for one token after the existing
// sqrt(softplus(logit)) probability kernel has run. Bias affects only top-k
// selection. Route-weight normalization deliberately stays in the old one-token
// kernel: even tiny denominator-order changes here are amplified by 43 MoE
// layers, so this kernel only replaces the selection work.
kernel void kernel_dsv4_router_finalize_one(
        constant ds4_metal_args_dsv4_router_select_one & args,
        device const float *probs,
        device const float *bias,
        device const int32_t *hash,
        device const int32_t *tokens,
        device int32_t *selected,
        threadgroup float *scratch [[threadgroup(0)]],
        uint tid [[thread_position_in_threadgroup]]) {
    if (tid >= 256) return;

    threadgroup float *sel_scores = scratch;
    threadgroup int32_t *idx = (threadgroup int32_t *)(scratch + 256);
    const float p = probs[tid];
    sel_scores[tid] = args.has_bias ? p + bias[tid] : p;
    idx[tid] = (int32_t)tid;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (args.hash_mode) {
        if (tid == 0) {
            const uint token = args.use_token_buffer ? (uint)tokens[0] : args.token;
            const uint row = min(token, args.hash_rows - 1u);
            device const int32_t *src = hash + row * 6u;
            for (uint i = 0; i < 6; i++) {
                selected[i] = src[i];
            }
        }
    } else {
        for (uint k = 2; k <= 256; k <<= 1) {
            for (uint j = k >> 1; j > 0; j >>= 1) {
                const uint other = tid ^ j;
                if (other > tid) {
                    if ((tid & k) == 0) {
                        if (sel_scores[(uint)idx[tid]] < sel_scores[(uint)idx[other]]) {
                            const int32_t tmp = idx[tid];
                            idx[tid] = idx[other];
                            idx[other] = tmp;
                        }
                    } else {
                        if (sel_scores[(uint)idx[tid]] > sel_scores[(uint)idx[other]]) {
                            const int32_t tmp = idx[tid];
                            idx[tid] = idx[other];
                            idx[other] = tmp;
                        }
                    }
                }
                threadgroup_barrier(mem_flags::mem_threadgroup);
            }
        }
        if (tid < 6) {
            selected[tid] = idx[tid];
        }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
}

/* Vision-Exp uses score-based visual routing even in the first three layers,
 * where ordinary text rows use a token-id hash table. One threadgroup owns a
 * row so the image/text decision is uniform across all barriers. */
kernel void kernel_dsv4_router_select_visual_batch(
        constant ds4_metal_args_dsv4_router_select_visual & args,
        device const float *probs,
        device const float *bias,
        device const float *visual_bias,
        device const int32_t *hash,
        device const int32_t *tokens,
        device int32_t *selected,
        threadgroup float *scratch [[threadgroup(0)]],
        uint tid [[thread_position_in_threadgroup]],
        uint row [[threadgroup_position_in_grid]]) {
    if (tid >= 256u || row >= args.n_tokens) return;

    const int32_t token = tokens[row];
    const bool image = token >= 0 && (uint32_t)token >= args.vocab_size;
    device int32_t *out = selected + (uint64_t)row * 6u;
    if (args.hash_mode && !image) {
        const uint hash_row = token >= 0 && (uint32_t)token < args.hash_rows
            ? (uint32_t)token : 0u;
        if (tid < 6u) out[tid] = hash[(uint64_t)hash_row * 6u + tid];
        return;
    }

    threadgroup float *scores = scratch;
    threadgroup int32_t *indices = (threadgroup int32_t *)(scratch + 256u);
    const float p = probs[(uint64_t)row * 256u + tid];
    scores[tid] = p + (image ? visual_bias[tid]
                             : (args.has_bias ? bias[tid] : 0.0f));
    indices[tid] = (int32_t)tid;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (uint k = 2u; k <= 256u; k <<= 1u) {
        for (uint j = k >> 1u; j > 0u; j >>= 1u) {
            const uint other = tid ^ j;
            if (other > tid) {
                const bool descending = (tid & k) == 0u;
                const int32_t a = indices[tid];
                const int32_t b = indices[other];
                const float sa = scores[(uint)a];
                const float sb = scores[(uint)b];
                if ((descending && sa < sb) || (!descending && sa > sb)) {
                    indices[tid] = b;
                    indices[other] = a;
                }
            }
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
    }
    if (tid < 6u) out[tid] = indices[tid];
}

// M3 decode specialization for the non-hash one-token router. Scores and ids
// stay in registers. Intra-SIMD bitonic stages use shuffle-xor; the six stages
// that cross 32-lane SIMD groups exchange through alternating threadgroup
// banks. The next bank's publish barrier proves every prior-bank read finished;
// by the time a bank is reused two cross stages later, no reader can remain.
kernel void kernel_dsv4_router_finalize_one_simd(
        constant ds4_metal_args_dsv4_router_select_one & args,
        device const float *probs,
        device const float *bias,
        device const int32_t *hash,
        device const int32_t *tokens,
        device int32_t *selected,
        threadgroup float *scratch [[threadgroup(0)]],
        uint tid [[thread_position_in_threadgroup]]) {
    if (tid >= 256 || args.hash_mode) return;

    (void)hash;
    (void)tokens;
    threadgroup float *score0_tg = scratch;
    threadgroup int32_t *idx0_tg =
        (threadgroup int32_t *)(scratch + 256);
    threadgroup float *score1_tg = scratch + 512;
    threadgroup int32_t *idx1_tg =
        (threadgroup int32_t *)(scratch + 768);
    const float p = probs[tid];
    float score = args.has_bias ? p + bias[tid] : p;
    int32_t idx = (int32_t)tid;
    uint cross_stage = 0;

    for (uint k = 2; k <= 256; k <<= 1) {
        for (uint j = k >> 1; j > 0; j >>= 1) {
            float peer_score;
            int32_t peer_idx;
            bool take_peer;
            const bool lower = (tid & j) == 0;
            const bool descending = (tid & k) == 0;

            if (j < 32) {
                peer_score = simd_shuffle_xor(score, (ushort)j);
                peer_idx = simd_shuffle_xor(idx, (ushort)j);
                take_peer = descending
                    ? (lower ? score < peer_score : score > peer_score)
                    : (lower ? score > peer_score : score < peer_score);
                if (take_peer) {
                    score = peer_score;
                    idx = peer_idx;
                }
            } else {
                threadgroup float *score_tg =
                    (cross_stage & 1u) != 0u ? score1_tg : score0_tg;
                threadgroup int32_t *idx_tg =
                    (cross_stage & 1u) != 0u ? idx1_tg : idx0_tg;
                score_tg[tid] = score;
                idx_tg[tid] = idx;
                threadgroup_barrier(mem_flags::mem_threadgroup);

                const uint other = tid ^ j;
                peer_score = score_tg[other];
                peer_idx = idx_tg[other];
                take_peer = descending
                    ? (lower ? score < peer_score : score > peer_score)
                    : (lower ? score > peer_score : score < peer_score);
                if (take_peer) {
                    score = peer_score;
                    idx = peer_idx;
                }
                cross_stage++;
            }
        }
    }

    if (tid < 6) {
        selected[tid] = idx;
    }
}

// M3 decode specialization that extends the register/TG SIMD selection above
// through the existing six-value serial weight normalization. The selected ids
// cross the same device-memory boundary as the standalone weight kernel;
// volatile TG stores pin its left-fold and scaled-reciprocal rounding points.
kernel void kernel_dsv4_router_finalize_weights_one_simd(
        constant ds4_metal_args_dsv4_router_select_one & args,
        device const float *probs,
        device const float *bias,
        device const int32_t *hash,
        device const int32_t *tokens,
        device int32_t *selected,
        device float *weights,
        threadgroup float *scratch [[threadgroup(0)]],
        uint tid [[thread_position_in_threadgroup]]) {
    if (tid >= 256 || args.hash_mode) return;

    (void)hash;
    (void)tokens;
    threadgroup float *score0_tg = scratch;
    threadgroup int32_t *idx0_tg =
        (threadgroup int32_t *)(scratch + 256);
    threadgroup float *score1_tg = scratch + 512;
    threadgroup int32_t *idx1_tg =
        (threadgroup int32_t *)(scratch + 768);
    const float p = probs[tid];
    float score = args.has_bias ? p + bias[tid] : p;
    int32_t idx = (int32_t)tid;
    uint cross_stage = 0;

    for (uint k = 2; k <= 256; k <<= 1) {
        for (uint j = k >> 1; j > 0; j >>= 1) {
            float peer_score;
            int32_t peer_idx;
            bool take_peer;
            const bool lower = (tid & j) == 0;
            const bool descending = (tid & k) == 0;

            if (j < 32) {
                peer_score = simd_shuffle_xor(score, (ushort)j);
                peer_idx = simd_shuffle_xor(idx, (ushort)j);
                take_peer = descending
                    ? (lower ? score < peer_score : score > peer_score)
                    : (lower ? score > peer_score : score < peer_score);
                if (take_peer) {
                    score = peer_score;
                    idx = peer_idx;
                }
            } else {
                threadgroup float *score_tg =
                    (cross_stage & 1u) != 0u ? score1_tg : score0_tg;
                threadgroup int32_t *idx_tg =
                    (cross_stage & 1u) != 0u ? idx1_tg : idx0_tg;
                score_tg[tid] = score;
                idx_tg[tid] = idx;
                threadgroup_barrier(mem_flags::mem_threadgroup);

                const uint other = tid ^ j;
                peer_score = score_tg[other];
                peer_idx = idx_tg[other];
                take_peer = descending
                    ? (lower ? score < peer_score : score > peer_score)
                    : (lower ? score > peer_score : score < peer_score);
                if (take_peer) {
                    score = peer_score;
                    idx = peer_idx;
                }
                cross_stage++;
            }
        }
    }

    if (tid < 6) {
        selected[tid] = idx;
    }
    threadgroup_barrier(mem_flags::mem_device);

    threadgroup volatile float *norm_scratch =
        (threadgroup volatile float *)scratch;
    if (tid == 0) {
        device const int32_t *s = selected;
        norm_scratch[0] = 0.0f;
        for (uint i = 0; i < 6; i++) {
            norm_scratch[0] = norm_scratch[0] + probs[s[i]];
        }
        norm_scratch[0] = max(norm_scratch[0], 6.103515625e-5f);
        norm_scratch[1] = 1.5f / norm_scratch[0];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (tid < 6) {
        device const int32_t *s = selected;
        weights[tid] = probs[s[tid]] * norm_scratch[1];
    }
}

// M3 decode specialization that materializes the probability
// transform in device memory before running the exact SIMD selection and
// weight normalization above. The volatile reload after the device barrier
// pins the same float store/load boundary as the standalone transform dispatch.
kernel void kernel_dsv4_router_transform_finalize_weights_one_simd(
        constant ds4_metal_args_dsv4_router_select_one & args,
        device const float *logits,
        device float *probs,
        device const float *bias,
        device const int32_t *hash,
        device const int32_t *tokens,
        device int32_t *selected,
        device float *weights,
        threadgroup float *scratch [[threadgroup(0)]],
        uint tid [[thread_position_in_threadgroup]]) {
    if (tid >= 256 || args.hash_mode) return;

    if (tid < 64) {
        device const float4 *s = (device const float4 *)logits;
        device float4 *d = (device float4 *)probs;
        const float4 x = s[tid];
        const float4 ex = exp(x);
        const float4 em = min(ex, 0.03125f);
        const float4 poly = em*(1.0f - em*(0.5f - em*(1.0f/3.0f - 0.25f*em)));
        const float4 sp = select(select(log(1.0f + ex), poly, ex < 0.03125f), x, x > 20.0f);
        d[tid] = sqrt(sp);
    }
    threadgroup_barrier(mem_flags::mem_device);
    device volatile const float *reloaded_probs =
        (device volatile const float *)probs;

    (void)hash;
    (void)tokens;
    threadgroup float *score0_tg = scratch;
    threadgroup int32_t *idx0_tg =
        (threadgroup int32_t *)(scratch + 256);
    threadgroup float *score1_tg = scratch + 512;
    threadgroup int32_t *idx1_tg =
        (threadgroup int32_t *)(scratch + 768);
    const float p = reloaded_probs[tid];
    float score = args.has_bias ? p + bias[tid] : p;
    int32_t idx = (int32_t)tid;
    uint cross_stage = 0;

    for (uint k = 2; k <= 256; k <<= 1) {
        for (uint j = k >> 1; j > 0; j >>= 1) {
            float peer_score;
            int32_t peer_idx;
            bool take_peer;
            const bool lower = (tid & j) == 0;
            const bool descending = (tid & k) == 0;

            if (j < 32) {
                peer_score = simd_shuffle_xor(score, (ushort)j);
                peer_idx = simd_shuffle_xor(idx, (ushort)j);
                take_peer = descending
                    ? (lower ? score < peer_score : score > peer_score)
                    : (lower ? score > peer_score : score < peer_score);
                if (take_peer) {
                    score = peer_score;
                    idx = peer_idx;
                }
            } else {
                threadgroup float *score_tg =
                    (cross_stage & 1u) != 0u ? score1_tg : score0_tg;
                threadgroup int32_t *idx_tg =
                    (cross_stage & 1u) != 0u ? idx1_tg : idx0_tg;
                score_tg[tid] = score;
                idx_tg[tid] = idx;
                threadgroup_barrier(mem_flags::mem_threadgroup);

                const uint other = tid ^ j;
                peer_score = score_tg[other];
                peer_idx = idx_tg[other];
                take_peer = descending
                    ? (lower ? score < peer_score : score > peer_score)
                    : (lower ? score > peer_score : score < peer_score);
                if (take_peer) {
                    score = peer_score;
                    idx = peer_idx;
                }
                cross_stage++;
            }
        }
    }

    if (tid < 6) {
        selected[tid] = idx;
    }
    threadgroup_barrier(mem_flags::mem_device);

    threadgroup volatile float *norm_scratch =
        (threadgroup volatile float *)scratch;
    if (tid == 0) {
        device const int32_t *s = selected;
        norm_scratch[0] = 0.0f;
        for (uint i = 0; i < 6; i++) {
            norm_scratch[0] =
                norm_scratch[0] + reloaded_probs[s[i]];
        }
        norm_scratch[0] = max(norm_scratch[0], 6.103515625e-5f);
        norm_scratch[1] = 1.5f / norm_scratch[0];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (tid < 6) {
        device const int32_t *s = selected;
        weights[tid] = reloaded_probs[s[tid]] * norm_scratch[1];
    }
}

kernel void kernel_dsv4_router_project_select_fused(
        constant ds4_metal_args_mul_mv & args,
        constant ds4_metal_args_dsv4_router_select_one & select_args,
        device const char * src0_router,
        device const char * src1,
        device float * logits,
        device float * probs,
        device const float * bias,
        device int32_t * selected,
        device float * weights,
        device atomic_uint * completion,
        threadgroup char * shmem_raw [[threadgroup(0)]],
        uint3 tgpig [[threadgroup_position_in_grid]],
        uint3 tpitg [[thread_position_in_threadgroup]],
        ushort tiisg [[thread_index_in_simdgroup]],
        ushort sgitg [[simdgroup_index_in_threadgroup]]) {
    constexpr short NSG = 8;
    constexpr short NR0 = 2;
    constexpr short NB  = 32;
    constexpr short NF  = 16;
    constexpr short NF4 = NF/4;
    constexpr short NW  = N_SIMDWIDTH;
    const uint tid = tpitg.x;
    const int nb = args.ne00/NB;
    const int r0 = tgpig.x*NR0;
    device const float4 *y4 = (device const float4 *)src1;
    device const half4 *ax4[NR0];
    FOR_UNROLL (short row = 0; row < NR0; ++row) {
        ax4[row] = (device const half4 *)
            (src0_router + (uint64_t)(r0 + row)*args.nb01);
    }
    float sumf[NR0] = {0.f};
    const short ix = tiisg/(NW/NF);
    const short il = tiisg%(NW/NF);
    const int ib0 = sgitg*NF + ix;
    device const float4 *yb4 = y4 + (ib0*NB + il*NF)/4;
    for (int ib = ib0; ib < nb; ib += NSG*NF) {
        float4 yl4[NF4];
        FOR_UNROLL (short i = 0; i < NF4; ++i) {
            yl4[i] = yb4[i];
        }
        FOR_UNROLL (short row = 0; row < NR0; ++row) {
            device const half4 *xb4 = ax4[row] + (ib*NB + il*NF)/4;
            float sumq = 0.f;
            FOR_UNROLL (short i = 0; i < NF4; ++i) {
                sumq += dot(float4(xb4[i]), yl4[i]);
            }
            sumf[row] += sumq;
        }
        yb4 += NSG*NF*NW/4;
    }
    helper_mv_reduce_and_write<NR0>(logits, sumf, r0, args.ne01,
                                    tiisg, sgitg, shmem_raw);

    threadgroup float *scratch = (threadgroup float *)shmem_raw;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    atomic_thread_fence(mem_flags::mem_device,
                        memory_order_seq_cst,
                        thread_scope_device);
    if (tid == 0) {
        const uint old = atomic_fetch_add_explicit(
            completion, 1u, memory_order_relaxed);
        scratch[0] = old == 127u ? 1.0f : 0.0f;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (scratch[0] == 0.0f) return;
    atomic_thread_fence(mem_flags::mem_device,
                        memory_order_seq_cst,
                        thread_scope_device);

    if (tid < 64) {
        device volatile const float4 *s =
            (device volatile const float4 *)logits;
        device float4 *d = (device float4 *)probs;
        const float4 xv = s[tid];
        const float4 ex = exp(xv);
        const float4 em = min(ex, 0.03125f);
        const float4 poly = em*(1.0f - em*(0.5f - em*(1.0f/3.0f - 0.25f*em)));
        const float4 sp = select(select(log(1.0f + ex), poly, ex < 0.03125f), xv, xv > 20.0f);
        d[tid] = sqrt(sp);
    }
    threadgroup_barrier(mem_flags::mem_device);
    device volatile const float *reloaded_probs =
        (device volatile const float *)probs;

    threadgroup float *score0_tg = scratch;
    threadgroup int32_t *idx0_tg =
        (threadgroup int32_t *)(scratch + 256);
    threadgroup float *score1_tg = scratch + 512;
    threadgroup int32_t *idx1_tg =
        (threadgroup int32_t *)(scratch + 768);
    const float p = reloaded_probs[tid];
    float score = select_args.has_bias ? p + bias[tid] : p;
    int32_t idx = (int32_t)tid;
    uint cross_stage = 0;
    for (uint k = 2; k <= 256; k <<= 1) {
        for (uint j = k >> 1; j > 0; j >>= 1) {
            float peer_score;
            int32_t peer_idx;
            bool take_peer;
            const bool lower = (tid & j) == 0;
            const bool descending = (tid & k) == 0;
            if (j < 32) {
                peer_score = simd_shuffle_xor(score, (ushort)j);
                peer_idx = simd_shuffle_xor(idx, (ushort)j);
                take_peer = descending
                    ? (lower ? score < peer_score : score > peer_score)
                    : (lower ? score > peer_score : score < peer_score);
                if (take_peer) {
                    score = peer_score;
                    idx = peer_idx;
                }
            } else {
                threadgroup float *score_tg =
                    (cross_stage & 1u) != 0u ? score1_tg : score0_tg;
                threadgroup int32_t *idx_tg =
                    (cross_stage & 1u) != 0u ? idx1_tg : idx0_tg;
                score_tg[tid] = score;
                idx_tg[tid] = idx;
                threadgroup_barrier(mem_flags::mem_threadgroup);
                const uint other = tid ^ j;
                peer_score = score_tg[other];
                peer_idx = idx_tg[other];
                take_peer = descending
                    ? (lower ? score < peer_score : score > peer_score)
                    : (lower ? score > peer_score : score < peer_score);
                if (take_peer) {
                    score = peer_score;
                    idx = peer_idx;
                }
                cross_stage++;
            }
        }
    }
    if (tid < 6) selected[tid] = idx;
    threadgroup_barrier(mem_flags::mem_device);
    threadgroup volatile float *norm_scratch =
        (threadgroup volatile float *)scratch;
    if (tid == 0) {
        norm_scratch[0] = 0.0f;
        for (uint i = 0; i < 6; ++i) {
            norm_scratch[0] = norm_scratch[0] + reloaded_probs[selected[i]];
        }
        norm_scratch[0] = max(norm_scratch[0], 6.103515625e-5f);
        norm_scratch[1] = 1.5f / norm_scratch[0];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (tid < 6) {
        weights[tid] = reloaded_probs[selected[tid]] * norm_scratch[1];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    atomic_thread_fence(mem_flags::mem_device,
                        memory_order_seq_cst,
                        thread_scope_device);
    if (tid == 0) {
        atomic_store_explicit(completion, 0u, memory_order_relaxed);
    }
}


// Fills the dense compressed-attention mask with -inf. The selected top-k rows
// are enabled by kernel_dsv4_topk_mask_scatter in a second ordered dispatch.
kernel void kernel_dsv4_topk_mask(
        constant ds4_metal_args_dsv4_topk_mask & args,
        device const char * topk,
        device       char * dst,
        uint gid [[thread_position_in_grid]]) {
    const int64_t n = args.ne0 * args.ne1;
    if ((int64_t) gid >= n) {
        return;
    }

    const int64_t ic = gid % args.ne0;
    const int64_t it = gid / args.ne0;

    (void)topk;
    *((device float *) (dst + ic*args.nb0 + it*args.nb1)) = -INFINITY;
}

// Enables the selected compressed rows in the dense mask. This replaces the
// old O(n_comp * n_tokens * top_k) membership test with O(top_k * n_tokens)
// writes while preserving exactly the same 0/-inf mask consumed by attention.
kernel void kernel_dsv4_topk_mask_scatter(
        constant ds4_metal_args_dsv4_topk_mask & args,
        device const char * topk,
        device       char * dst,
        uint gid [[thread_position_in_grid]]) {
    const int64_t n = args.ne00 * args.ne01;
    if ((int64_t) gid >= n) {
        return;
    }

    const int64_t ik = gid % args.ne00;
    const int64_t it = gid / args.ne00;
    const int32_t idx = *((device const int32_t *) (topk + ik*args.nb00 + it*args.nb01));
    if (idx >= 0 && (int64_t)idx < args.ne0) {
        *((device float *) (dst + (int64_t)idx*args.nb0 + it*args.nb1)) = 0.0f;
    }
}

// Copy the selected compressed-key mask while retaining causal visibility.
// Image bidirectionality applies to raw keys only, never compressed keys.
struct ds4_metal_args_causal_comp_mask {
    uint n_comp, n_tokens, pos0, ratio, n_keys;
};

kernel void kernel_dsv4_causal_comp_mask(
        constant ds4_metal_args_causal_comp_mask &args,
        device const float *selected_mask,
        device half *dst,
        uint2 gid [[thread_position_in_grid]]) {
    const uint col = gid.x, row = gid.y;
    if (col >= args.n_comp || row >= args.n_tokens) return;
    const ulong visible = (ulong(args.pos0) + ulong(row) + 1ul) / args.ratio;
    dst[ulong(row) * args.n_keys + col] = ulong(col) < visible
        ? half(selected_mask[ulong(row) * args.n_comp + col]) : half(-INFINITY);
}

// Sorts each token's selected compressed rows by row id. The indexer selects by
// score, but attention scans compressed K/V in cache order in the dense graph.
// Sorting preserves that order while still letting the indexed attention kernel
// touch only the selected rows.
kernel void kernel_dsv4_sort_i32_rows_asc(
        constant ds4_metal_args_dsv4_topk_mask & args,
        device const char * src,
        device       char * dst,
        threadgroup int32_t * row_tmp [[threadgroup(0)]],
        uint row [[threadgroup_position_in_grid]],
        uint tid [[thread_position_in_threadgroup]],
        uint n_threads [[threads_per_threadgroup]]) {
    const uint top_k = (uint)args.ne00;
    if (row >= (uint)args.ne01 || tid >= n_threads) {
        return;
    }

    for (uint i = tid; i < top_k; i += n_threads) {
        row_tmp[i] = *((device const int32_t *) (src + (uint64_t)i*args.nb00 + (uint64_t)row*args.nb01));
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (uint k = 2; k <= top_k; k <<= 1) {
        for (uint j = k >> 1; j > 0; j >>= 1) {
            for (uint i = tid; i < top_k; i += n_threads) {
                const uint other = i ^ j;
                if (other > i && other < top_k) {
                    const int32_t a = row_tmp[i];
                    const int32_t b = row_tmp[other];
                    const bool up = (i & k) == 0;
                    if ((up && a > b) || (!up && a < b)) {
                        row_tmp[i] = b;
                        row_tmp[other] = a;
                    }
                }
            }
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
    }

    for (uint i = tid; i < top_k; i += n_threads) {
        *((device int32_t *) (dst + (uint64_t)i*args.nb00 + (uint64_t)row*args.nb01)) = row_tmp[i];
    }
}

static inline void dsv4_attend_f32_row_as_f16(
        device const char *kv,
        uint64_t row_stride,
        uint row,
        half4 q0,
        half4 q1,
        half4 q2,
        half4 q3,
        float scale,
        ushort lane,
        thread float &M,
        thread float &S,
        thread float4 &o0,
        thread float4 &o1,
        thread float4 &o2,
        thread float4 &o3) {
    device const float4 *kv4 = (device const float4 *)(kv + (uint64_t)row * row_stride);
    const half4 k0 = (half4)kv4[lane +  0];
    const half4 k1 = (half4)kv4[lane + 32];
    const half4 k2 = (half4)kv4[lane + 64];
    const half4 k3 = (half4)kv4[lane + 96];

    float score = dot((float4)q0, (float4)k0) +
                  dot((float4)q1, (float4)k1) +
                  dot((float4)q2, (float4)k2) +
                  dot((float4)q3, (float4)k3);
    score = simd_sum(score) * scale;

    const float old_m = M;
    const float new_m = max(M, score);
    const float old_scale = exp(old_m - new_m);
    const float row_scale = exp(score - new_m);

    S = S * old_scale + row_scale;
    o0 *= old_scale;
    o1 *= old_scale;
    o2 *= old_scale;
    o3 *= old_scale;

    o0 += (float4)k0 * row_scale;
    o1 += (float4)k1 * row_scale;
    o2 += (float4)k2 * row_scale;
    o3 += (float4)k3 * row_scale;
    M = new_m;
}

static inline void dsv4_attend_shared_f32_row_as_f16(
        threadgroup const float4 *kv4,
        half4 q0,
        half4 q1,
        half4 q2,
        half4 q3,
        float scale,
        ushort lane,
        thread float &M,
        thread float &S,
        thread float4 &o0,
        thread float4 &o1,
        thread float4 &o2,
        thread float4 &o3) {
    const half4 k0 = (half4)kv4[lane +  0];
    const half4 k1 = (half4)kv4[lane + 32];
    const half4 k2 = (half4)kv4[lane + 64];
    const half4 k3 = (half4)kv4[lane + 96];

    float score = dot((float4)q0, (float4)k0) +
                  dot((float4)q1, (float4)k1) +
                  dot((float4)q2, (float4)k2) +
                  dot((float4)q3, (float4)k3);
    score = simd_sum(score) * scale;

    const float old_m = M;
    const float new_m = max(M, score);
    const float old_scale = exp(old_m - new_m);
    const float row_scale = exp(score - new_m);

    S = S * old_scale + row_scale;
    o0 *= old_scale;
    o1 *= old_scale;
    o2 *= old_scale;
    o3 *= old_scale;

    o0 += (float4)k0 * row_scale;
    o1 += (float4)k1 * row_scale;
    o2 += (float4)k2 * row_scale;
    o3 += (float4)k3 * row_scale;
    M = new_m;
}

static inline void dsv4_attend_shared_f32_row_as_f16_at(
        threadgroup const float4 *kv4,
        uint row_in_tg,
        half4 q0,
        half4 q1,
        half4 q2,
        half4 q3,
        float scale,
        ushort lane,
        thread float &M,
        thread float &S,
        thread float4 &o0,
        thread float4 &o1,
        thread float4 &o2,
        thread float4 &o3) {
    dsv4_attend_shared_f32_row_as_f16(kv4 + row_in_tg * 128u,
                                      q0, q1, q2, q3,
                                      scale,
                                      lane,
                                      M, S,
                                      o0, o1, o2, o3);
}

static inline void dsv4_attend_shared_h4_row(
        threadgroup const half4 *kv4,
        half4 q0,
        half4 q1,
        half4 q2,
        half4 q3,
        float scale,
        ushort lane,
        thread float &M,
        thread float &S,
        thread float4 &o0,
        thread float4 &o1,
        thread float4 &o2,
        thread float4 &o3) {
    const half4 k0 = kv4[lane +  0];
    const half4 k1 = kv4[lane + 32];
    const half4 k2 = kv4[lane + 64];
    const half4 k3 = kv4[lane + 96];

    float score = dot((float4)q0, (float4)k0) +
                  dot((float4)q1, (float4)k1) +
                  dot((float4)q2, (float4)k2) +
                  dot((float4)q3, (float4)k3);
    score = simd_sum(score) * scale;

    const float old_m = M;
    const float new_m = max(M, score);
    const float old_scale = exp(old_m - new_m);
    const float row_scale = exp(score - new_m);

    S = S * old_scale + row_scale;
    o0 *= old_scale;
    o1 *= old_scale;
    o2 *= old_scale;
    o3 *= old_scale;

    o0 += (float4)k0 * row_scale;
    o1 += (float4)k1 * row_scale;
    o2 += (float4)k2 * row_scale;
    o3 += (float4)k3 * row_scale;
    M = new_m;
}

static inline void dsv4_attend_shared_h4_row_at(
        threadgroup const half4 *kv4,
        uint row_in_tg,
        half4 q0,
        half4 q1,
        half4 q2,
        half4 q3,
        float scale,
        ushort lane,
        thread float &M,
        thread float &S,
        thread float4 &o0,
        thread float4 &o1,
        thread float4 &o2,
        thread float4 &o3) {
    dsv4_attend_shared_h4_row(kv4 + row_in_tg * 128u,
                              q0, q1, q2, q3,
                              scale,
                              lane,
                              M, S,
                              o0, o1, o2, o3);
}

static inline half4 dsv4_load_cache_h4(
        device const char *kv,
        uint64_t row_stride,
        uint row,
        uint col,
        bool f16_rows) {
    device const char *base = kv + (uint64_t)row * row_stride;
    if (f16_rows) {
        return ((device const half4 *)base)[col];
    }
    return (half4)((device const float4 *)base)[col];
}

static inline void dsv4_attend_sink(
        float score,
        thread float &M,
        thread float &S,
        thread float4 &o0,
        thread float4 &o1,
        thread float4 &o2,
        thread float4 &o3) {
    const float old_m = M;
    const float new_m = max(M, score);
    const float old_scale = exp(old_m - new_m);
    const float row_scale = exp(score - new_m);

    S = S * old_scale + row_scale;
    o0 *= old_scale;
    o1 *= old_scale;
    o2 *= old_scale;
    o3 *= old_scale;
    M = new_m;
}

// DS4 ratio-4 indexed mixed attention. It replaces the dense top-k mask path:
// the threadgroup covers one token and eight heads. Top-k rows and local raw
// rows are the same for all heads of a token, so K/V is staged once in
// threadgroup memory and reused by the eight simdgroups. It keeps the DS4 F16
// attention rounding by casting Q/K/V to half before the dot/value update.
kernel void kernel_dsv4_indexed_mixed_attention_heads8(
        constant ds4_metal_args_dsv4_indexed_attention & args,
        device const char *q,
        device const char *raw_kv,
        device const char *comp_kv,
        device const char *topk,
        device const char *sinks,
        device       char *dst,
        threadgroup half4 *kv_shared [[threadgroup(0)]],
        uint2  tgpig [[threadgroup_position_in_grid]],
        ushort tid   [[thread_index_in_threadgroup]],
        ushort lane  [[thread_index_in_simdgroup]],
        ushort sg    [[simdgroup_index_in_threadgroup]]) {
    const uint token = tgpig.x;
    const uint head = tgpig.y * 8u + (uint)sg;
    if (token >= args.n_tokens || head >= args.n_head) {
        return;
    }

    device const float4 *q4 = (device const float4 *)(q +
        (uint64_t)token * args.q_token_stride +
        (uint64_t)head  * args.q_head_stride);
    const half4 q0 = (half4)q4[lane +  0];
    const half4 q1 = (half4)q4[lane + 32];
    const half4 q2 = (half4)q4[lane + 64];
    const half4 q3 = (half4)q4[lane + 96];

    float M = -FLT_MAX/2.0f;
    float S = 0.0f;
    float4 o0 = 0.0f;
    float4 o1 = 0.0f;
    float4 o2 = 0.0f;
    float4 o3 = 0.0f;

    const uint qpos = args.pos0 + token;
    const uint last_pos = args.pos0 + args.n_tokens - 1u;
    const uint first_raw_pos = last_pos + 1u - args.n_raw;
    const uint raw_last_pos = first_raw_pos + args.n_raw - 1u;
    const uint window_first = (args.window != 0u && qpos + 1u > args.window) ?
        qpos + 1u - args.window : 0u;
    uint first = max(first_raw_pos, window_first);
    uint last = min(qpos, raw_last_pos);

    if (first <= last) {
        for (uint pos = first; pos <= last; pos++) {
            const uint logical = pos - first_raw_pos;
            const uint row = (args.raw_start + logical) % args.raw_cap;
            device const float4 *src = (device const float4 *)(raw_kv +
                (uint64_t)row * args.raw_row_stride);
            if (tid < 128) kv_shared[tid] = (half4)src[tid];
            threadgroup_barrier(mem_flags::mem_threadgroup);
            dsv4_attend_shared_h4_row(kv_shared,
                                      q0, q1, q2, q3,
                                      args.scale,
                                      lane,
                                      M, S,
                                      o0, o1, o2, o3);
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
    }

    uint visible = (qpos + 1u) / args.ratio;
    visible = min(visible, args.n_comp);
    device const int32_t *row_topk = (device const int32_t *)(topk +
        (uint64_t)token * args.topk_token_stride);
    for (uint i = 0; i < args.top_k; i++) {
        const int32_t idx = row_topk[i];
        if (idx < 0) {
            continue;
        }
        if ((uint)idx >= visible) {
            break;
        }
        if (tid < 128) {
            kv_shared[tid] = dsv4_load_cache_h4(comp_kv,
                                                args.comp_row_stride,
                                                (uint)idx,
                                                tid,
                                                args.comp_kv_f16 != 0u);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        dsv4_attend_shared_h4_row(kv_shared,
                                  q0, q1, q2, q3,
                                  args.scale,
                                  lane,
                                  M, S,
                                  o0, o1, o2, o3);
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    dsv4_attend_sink(((device const float *)sinks)[head], M, S, o0, o1, o2, o3);

    const float inv_s = S == 0.0f ? 0.0f : 1.0f/S;
    device float4 *dst4 = (device float4 *)(dst +
        (uint64_t)token * args.dst_token_stride +
        (uint64_t)head  * args.dst_head_stride);
    dst4[lane +  0] = o0 * inv_s;
    dst4[lane + 32] = o1 * inv_s;
    dst4[lane + 64] = o2 * inv_s;
    dst4[lane + 96] = o3 * inv_s;
}

// Each simdgroup owns two heads and updates both from one staged K/V row.
// This doubles row reuse without increasing the 256-thread workgroup.
kernel void kernel_dsv4_indexed_mixed_attention_heads16_dual(
        constant ds4_metal_args_dsv4_indexed_attention &args,
        device const char *q,
        device const char *raw_kv,
        device const char *comp_kv,
        device const char *topk,
        device const char *sinks,
        device char *dst,
        threadgroup half4 *kv_shared [[threadgroup(0)]],
        uint2 tgpig [[threadgroup_position_in_grid]],
        ushort tid [[thread_index_in_threadgroup]],
        ushort lane [[thread_index_in_simdgroup]],
        ushort sg [[simdgroup_index_in_threadgroup]]) {
    const uint token = tgpig.x;
    const uint head0 = tgpig.y*16u + (uint)sg;
    const uint head1 = head0 + 8u;
    if (token >= args.n_tokens || head0 >= args.n_head) return;

    device const float4 *qa = (device const float4 *)(q +
        (uint64_t)token*args.q_token_stride +
        (uint64_t)head0*args.q_head_stride);
    half4 qa0 = (half4)qa[lane + 0];
    half4 qa1 = (half4)qa[lane + 32];
    half4 qa2 = (half4)qa[lane + 64];
    half4 qa3 = (half4)qa[lane + 96];
    half4 qb0 = half4(0.0h), qb1 = half4(0.0h);
    half4 qb2 = half4(0.0h), qb3 = half4(0.0h);
    if (head1 < args.n_head) {
        device const float4 *qb = (device const float4 *)(q +
            (uint64_t)token*args.q_token_stride +
            (uint64_t)head1*args.q_head_stride);
        qb0 = (half4)qb[lane + 0];
        qb1 = (half4)qb[lane + 32];
        qb2 = (half4)qb[lane + 64];
        qb3 = (half4)qb[lane + 96];
    }

    float Ma = -FLT_MAX/2.0f, Sa = 0.0f;
    float Mb = -FLT_MAX/2.0f, Sb = 0.0f;
    float4 ao0 = 0.0f, ao1 = 0.0f, ao2 = 0.0f, ao3 = 0.0f;
    float4 bo0 = 0.0f, bo1 = 0.0f, bo2 = 0.0f, bo3 = 0.0f;

    const uint qpos = args.pos0 + token;
    const uint last_pos = args.pos0 + args.n_tokens - 1u;
    const uint first_raw_pos = last_pos + 1u - args.n_raw;
    const uint raw_last_pos = first_raw_pos + args.n_raw - 1u;
    const uint window_first = (args.window != 0u && qpos + 1u > args.window) ?
        qpos + 1u - args.window : 0u;
    const uint first = max(first_raw_pos, window_first);
    const uint last = min(qpos, raw_last_pos);
    if (first <= last) {
        for (uint pos = first; pos <= last; pos++) {
            const uint logical = pos - first_raw_pos;
            const uint row = (args.raw_start + logical)%args.raw_cap;
            device const float4 *src = (device const float4 *)(raw_kv +
                (uint64_t)row*args.raw_row_stride);
            if (tid < 128) kv_shared[tid] = (half4)src[tid];
            threadgroup_barrier(mem_flags::mem_threadgroup);
            dsv4_attend_shared_h4_row(kv_shared, qa0, qa1, qa2, qa3,
                args.scale, lane, Ma, Sa, ao0, ao1, ao2, ao3);
            if (head1 < args.n_head) {
                dsv4_attend_shared_h4_row(kv_shared, qb0, qb1, qb2, qb3,
                    args.scale, lane, Mb, Sb, bo0, bo1, bo2, bo3);
            }
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
    }

    const uint visible = min((qpos + 1u)/args.ratio, args.n_comp);
    device const int32_t *row_topk = (device const int32_t *)(topk +
        (uint64_t)token*args.topk_token_stride);
    for (uint i = 0; i < args.top_k; i++) {
        const int32_t idx = row_topk[i];
        if (idx < 0) continue;
        if ((uint)idx >= visible) break;
        if (tid < 128) {
            kv_shared[tid] = dsv4_load_cache_h4(comp_kv,
                args.comp_row_stride, (uint)idx, tid, args.comp_kv_f16 != 0u);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        dsv4_attend_shared_h4_row(kv_shared, qa0, qa1, qa2, qa3,
            args.scale, lane, Ma, Sa, ao0, ao1, ao2, ao3);
        if (head1 < args.n_head) {
            dsv4_attend_shared_h4_row(kv_shared, qb0, qb1, qb2, qb3,
                args.scale, lane, Mb, Sb, bo0, bo1, bo2, bo3);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    dsv4_attend_sink(((device const float *)sinks)[head0],
        Ma, Sa, ao0, ao1, ao2, ao3);
    const float ia = Sa == 0.0f ? 0.0f : 1.0f/Sa;
    device float4 *da = (device float4 *)(dst +
        (uint64_t)token*args.dst_token_stride +
        (uint64_t)head0*args.dst_head_stride);
    da[lane + 0] = ao0*ia; da[lane + 32] = ao1*ia;
    da[lane + 64] = ao2*ia; da[lane + 96] = ao3*ia;
    if (head1 < args.n_head) {
        dsv4_attend_sink(((device const float *)sinks)[head1],
            Mb, Sb, bo0, bo1, bo2, bo3);
        const float ib = Sb == 0.0f ? 0.0f : 1.0f/Sb;
        device float4 *db = (device float4 *)(dst +
            (uint64_t)token*args.dst_token_stride +
            (uint64_t)head1*args.dst_head_stride);
        db[lane + 0] = bo0*ib; db[lane + 32] = bo1*ib;
        db[lane + 64] = bo2*ib; db[lane + 96] = bo3*ib;
    }
}

// Decode specialization of kernel_dsv4_indexed_mixed_attention_heads8.
// Generation attends one token at a time, so the ratio-4 indexed path spends a
// visible amount of time repeatedly staging the same K/V row for the eight
// heads in a group. This variant stages sixteen selected rows at once and then
// consumes them sequentially, preserving the row order and online softmax math
// while cutting threadgroup barriers in the long top-k scan.
kernel void kernel_dsv4_indexed_mixed_attention_heads8_rb16(
        constant ds4_metal_args_dsv4_indexed_attention & args,
        device const char *q,
        device const char *raw_kv,
        device const char *comp_kv,
        device const char *topk,
        device const char *sinks,
        device       char *dst,
        threadgroup half4 *kv_shared [[threadgroup(0)]],
        uint2  tgpig [[threadgroup_position_in_grid]],
        ushort tid   [[thread_index_in_threadgroup]],
        ushort lane  [[thread_index_in_simdgroup]],
        ushort sg    [[simdgroup_index_in_threadgroup]]) {
    const uint token = tgpig.x;
    const uint head = tgpig.y * 8u + (uint)sg;
    if (token >= args.n_tokens || head >= args.n_head) {
        return;
    }

    device const float4 *q4 = (device const float4 *)(q +
        (uint64_t)token * args.q_token_stride +
        (uint64_t)head  * args.q_head_stride);
    const half4 q0 = (half4)q4[lane +  0];
    const half4 q1 = (half4)q4[lane + 32];
    const half4 q2 = (half4)q4[lane + 64];
    const half4 q3 = (half4)q4[lane + 96];

    float M = -FLT_MAX/2.0f;
    float S = 0.0f;
    float4 o0 = 0.0f;
    float4 o1 = 0.0f;
    float4 o2 = 0.0f;
    float4 o3 = 0.0f;

    const uint qpos = args.pos0 + token;
    const uint last_pos = args.pos0 + args.n_tokens - 1u;
    const uint first_raw_pos = last_pos + 1u - args.n_raw;
    const uint raw_last_pos = first_raw_pos + args.n_raw - 1u;
    const uint window_first = (args.window != 0u && qpos + 1u > args.window) ?
        qpos + 1u - args.window : 0u;
    uint first = max(first_raw_pos, window_first);
    uint last = min(qpos, raw_last_pos);

    if (first <= last) {
        for (uint pos0 = first; pos0 <= last; pos0 += 16u) {
            const uint n_rows = min(16u, last - pos0 + 1u);
            for (uint off = (uint)tid; off < n_rows * 128u; off += 256u) {
                const uint r = off >> 7;
                const uint c = off & 127u;
                const uint logical = pos0 + r - first_raw_pos;
                const uint row = (args.raw_start + logical) % args.raw_cap;
                device const float4 *src = (device const float4 *)(raw_kv +
                    (uint64_t)row * args.raw_row_stride);
                kv_shared[off] = (half4)src[c];
            }
            threadgroup_barrier(mem_flags::mem_threadgroup);
            for (uint r = 0; r < n_rows; r++) {
                dsv4_attend_shared_h4_row_at(kv_shared,
                                             r,
                                             q0, q1, q2, q3,
                                             args.scale,
                                             lane,
                                             M, S,
                                             o0, o1, o2, o3);
            }
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
    }

    uint visible = (qpos + 1u) / args.ratio;
    visible = min(visible, args.n_comp);
    device const int32_t *row_topk = (device const int32_t *)(topk +
        (uint64_t)token * args.topk_token_stride);
    bool stop = false;
    for (uint i = 0; i < args.top_k && !stop; i += 16u) {
        uint rows[16];
        uint n_rows = 0;
        for (uint j = 0; j < 16u && i + j < args.top_k; j++) {
            const int32_t idx = row_topk[i + j];
            if (idx < 0) {
                continue;
            }
            if ((uint)idx >= visible) {
                stop = true;
                break;
            }
            rows[n_rows++] = (uint)idx;
        }
        if (n_rows == 0) {
            continue;
        }
        for (uint off = (uint)tid; off < n_rows * 128u; off += 256u) {
            const uint r = off >> 7;
            const uint c = off & 127u;
            kv_shared[off] = dsv4_load_cache_h4(comp_kv,
                                                args.comp_row_stride,
                                                rows[r],
                                                c,
                                                args.comp_kv_f16 != 0u);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        for (uint r = 0; r < n_rows; r++) {
            dsv4_attend_shared_h4_row_at(kv_shared,
                                         r,
                                         q0, q1, q2, q3,
                                         args.scale,
                                         lane,
                                         M, S,
                                         o0, o1, o2, o3);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    dsv4_attend_sink(((device const float *)sinks)[head], M, S, o0, o1, o2, o3);

    const float inv_s = S == 0.0f ? 0.0f : 1.0f/S;
    device float4 *dst4 = (device float4 *)(dst +
        (uint64_t)token * args.dst_token_stride +
        (uint64_t)head  * args.dst_head_stride);
    dst4[lane +  0] = o0 * inv_s;
    dst4[lane + 32] = o1 * inv_s;
    dst4[lane + 64] = o2 * inv_s;
    dst4[lane + 96] = o3 * inv_s;
}

// Long-context decode specialization of the indexed mixed-attention path.
//
// The ordinary heads8 kernel reuses each K/V row across eight heads, but only
// launches one threadgroup per head group. Long-context decode therefore has
// too little parallel work while each group scans its raw and selected rows.
// This kernel retains the same eight-head reuse while splitting that row
// sequence across args.n_splits workgroups. A second kernel merges the online
// softmax partials and applies the attention sink.
kernel void kernel_dsv4_indexed_mixed_attention_heads8_split(
        constant ds4_metal_args_dsv4_indexed_attention & args,
        device const char *q,
        device const char *raw_kv,
        device const char *comp_kv,
        device const char *topk,
        device       char *tmp,
        threadgroup half4 *kv_shared [[threadgroup(0)]],
        uint3  tgpig [[threadgroup_position_in_grid]],
        ushort tid   [[thread_index_in_threadgroup]],
        ushort lane  [[thread_index_in_simdgroup]],
        ushort sg    [[simdgroup_index_in_threadgroup]]) {
    constexpr uint rows_per_block = 16u;
    constexpr uint vecs_per_row = 128u;

    const uint token = tgpig.x;
    const uint head = tgpig.y * 8u + (uint)sg;
    const uint split = tgpig.z;
    const uint n_splits = args.n_splits;
    if (token >= args.n_tokens || head >= args.n_head ||
        n_splits < 2u || n_splits > 31u || split >= n_splits) {
        return;
    }

    device const float4 *q4 = (device const float4 *)(q +
        (uint64_t)token * args.q_token_stride +
        (uint64_t)head  * args.q_head_stride);
    const half4 q0 = (half4)q4[lane +  0];
    const half4 q1 = (half4)q4[lane + 32];
    const half4 q2 = (half4)q4[lane + 64];
    const half4 q3 = (half4)q4[lane + 96];

    float M = -FLT_MAX/2.0f;
    float S = 0.0f;
    float4 o0 = 0.0f;
    float4 o1 = 0.0f;
    float4 o2 = 0.0f;
    float4 o3 = 0.0f;

    const uint qpos = args.pos0 + token;
    const uint last_pos = args.pos0 + args.n_tokens - 1u;
    const uint first_raw_pos = last_pos + 1u - args.n_raw;
    const uint raw_last_pos = first_raw_pos + args.n_raw - 1u;
    const uint window_first = (args.window != 0u && qpos + 1u > args.window) ?
        qpos + 1u - args.window : 0u;
    const uint raw_first = max(first_raw_pos, window_first);
    const uint raw_last = min(qpos, raw_last_pos);
    const uint raw_count = raw_first <= raw_last ?
        raw_last - raw_first + 1u : 0u;
    const uint total_rows = raw_count + args.top_k;
    const uint rows_per_split =
        (total_rows + n_splits - 1u) / n_splits;
    const uint split_first = min(split * rows_per_split, total_rows);
    const uint split_last = min(split_first + rows_per_split, total_rows);
    const uint visible = min((qpos + 1u) / args.ratio, args.n_comp);
    device const int32_t *row_topk = (device const int32_t *)(topk +
        (uint64_t)token * args.topk_token_stride);

    for (uint seq0 = split_first; seq0 < split_last;
         seq0 += rows_per_block) {
        const uint n_rows = min(rows_per_block, split_last - seq0);
        for (uint off = (uint)tid;
             off < n_rows * vecs_per_row;
             off += 256u) {
            const uint r = off / vecs_per_row;
            const uint c = off - r * vecs_per_row;
            const uint seq = seq0 + r;
            half4 value = half4(0.0h);
            if (seq < raw_count) {
                const uint pos = raw_first + seq;
                const uint logical = pos - first_raw_pos;
                const uint row = (args.raw_start + logical) % args.raw_cap;
                device const float4 *src = (device const float4 *)(raw_kv +
                    (uint64_t)row * args.raw_row_stride);
                value = (half4)src[c];
            } else {
                const int32_t idx = row_topk[seq - raw_count];
                if (idx >= 0 && (uint)idx < visible) {
                    value = dsv4_load_cache_h4(comp_kv,
                                               args.comp_row_stride,
                                               (uint)idx,
                                               c,
                                               args.comp_kv_f16 != 0u);
                }
            }
            kv_shared[off] = value;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        for (uint r = 0; r < n_rows; r++) {
            const uint seq = seq0 + r;
            bool valid = true;
            if (seq >= raw_count) {
                const int32_t idx = row_topk[seq - raw_count];
                valid = idx >= 0 && (uint)idx < visible;
            }
            if (valid) {
                dsv4_attend_shared_h4_row_at(kv_shared,
                                             r,
                                             q0, q1, q2, q3,
                                             args.scale,
                                             lane,
                                             M, S,
                                             o0, o1, o2, o3);
            }
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    const uint64_t n_rows = (uint64_t)args.n_tokens * args.n_head;
    const uint64_t row = (uint64_t)token * args.n_head + head;
    device float4 *partials = (device float4 *)tmp;
    partials[(row * vecs_per_row + lane +  0u) * n_splits + split] = o0;
    partials[(row * vecs_per_row + lane + 32u) * n_splits + split] = o1;
    partials[(row * vecs_per_row + lane + 64u) * n_splits + split] = o2;
    partials[(row * vecs_per_row + lane + 96u) * n_splits + split] = o3;

    if (lane == 0u) {
        device float *stats = (device float *)(partials +
            n_rows * vecs_per_row * n_splits);
        const uint64_t stat = (row * n_splits + split) * 2u;
        stats[stat + 0u] = S;
        stats[stat + 1u] = M;
    }
}

kernel void kernel_dsv4_indexed_mixed_attention_heads8_split_reduce(
        constant ds4_metal_args_dsv4_indexed_attention & args,
        device const char *tmp,
        device const char *sinks,
        device       char *dst,
        uint tgpig [[threadgroup_position_in_grid]],
        ushort lane [[thread_index_in_simdgroup]],
        ushort sg   [[simdgroup_index_in_threadgroup]]) {
    constexpr uint vecs_per_row = 128u;
    const uint n_splits = args.n_splits;
    const uint64_t n_rows = (uint64_t)args.n_tokens * args.n_head;
    const uint64_t row = tgpig;
    if (row >= n_rows || n_splits < 2u || n_splits > 31u) {
        return;
    }

    device const float4 *partials = (device const float4 *)tmp;
    device const float *stats = (device const float *)(partials +
        n_rows * vecs_per_row * n_splits);
    float part_sum = 0.0f;
    float part_max = -FLT_MAX/2.0f;
    if ((uint)lane < n_splits) {
        const uint64_t stat = (row * n_splits + (uint)lane) * 2u;
        part_sum = stats[stat + 0u];
        part_max = stats[stat + 1u];
    } else if ((uint)lane == n_splits) {
        const uint head = (uint)(row % args.n_head);
        part_sum = 1.0f;
        part_max = ((device const float *)sinks)[head];
    }

    const float global_max = simd_max(part_max);
    const float part_scale = part_sum > 0.0f ?
        exp(part_max - global_max) : 0.0f;
    const float total_sum = simd_sum(part_sum * part_scale);
    const float inv_sum = total_sum > 0.0f ? 1.0f / total_sum : 0.0f;

    device float4 *out = (device float4 *)dst + row * vecs_per_row;
    for (uint i = (uint)sg; i < vecs_per_row; i += 4u) {
        float4 value = float4(0.0f);
        if ((uint)lane < n_splits) {
            value = partials[(row * vecs_per_row + i) * n_splits +
                             (uint)lane] * part_scale;
        }
        value = simd_sum(value);
        if (lane == 0u) {
            out[i] = value * inv_sum;
        }
    }
}

static inline float dsv4_indexer_dot128_shared_q(
        float4 c0,
        float4 c1,
        float4 c2,
        float4 c3,
        threadgroup const float4 *q4,
        ushort lane) {
    float sum = 0.0f;
    if (lane < 8) {
        const ushort ib = lane >> 1;
        const ushort il = lane & 1;
        const ushort base = ib*8 + il*4;
        sum += dot(c0, q4[base + 0]);
        sum += dot(c1, q4[base + 1]);
        sum += dot(c2, q4[base + 2]);
        sum += dot(c3, q4[base + 3]);
    }
    return simd_sum(sum);
}

// Tiled prefill score builder for the sparse-compressed attention indexer.
//
// The kernel covers an 8-token by 32-compressed-row rectangle: K is copied into
// threadgroup memory once, then reused for all 64 indexer heads, while simdgroup
// matrix multiply computes each 8x8 score subtile.
//
// It still writes the exact score matrix consumed by top-k:
//
//     score[t,c] = sum_h relu(dot(Q[t,h], K[c])) * W[t,h] * scale
//
// Causal masking is applied on store so invisible compressed rows become -inf.
kernel void kernel_dsv4_indexer_scores_tiled_f32(
        constant ds4_metal_args_dsv4_indexer_scores_fused & args,
        device const char *q,
        device const char *weights,
        device const char *index_comp,
        device       char *scores,
        threadgroup float *shared [[threadgroup(0)]],
        uint2  tgpig [[threadgroup_position_in_grid]],
        ushort tid   [[thread_index_in_threadgroup]],
        ushort lane  [[thread_index_in_simdgroup]],
        ushort sg    [[simdgroup_index_in_threadgroup]]) {
    constexpr uint TM = 8;
    constexpr uint TN = 32;
    constexpr uint TS = 8;
    constexpr uint D  = 128;

    const uint c0 = tgpig.x * TN;
    const uint t0 = tgpig.y * TM;

    threadgroup float *qtg = shared;             // [8][128]
    threadgroup float *ktg = qtg + TM*D;         // [32][128]
    threadgroup float *dot = ktg + TN*D;         // [8][32]

    const uint last_token = min(t0 + TM, args.n_tokens);
    const uint max_visible = last_token > t0 ?
        min((args.pos0 + last_token) / args.ratio, args.n_comp) : 0u;

    if (c0 >= max_visible) {
        for (uint i = tid; i < TM*TN; i += 128) {
            const uint r = i / TN;
            const uint cc = i - r*TN;
            const uint token = t0 + r;
            const uint comp = c0 + cc;
            if (token < args.n_tokens && comp < args.n_comp) {
                device float *dst = (device float *)(scores +
                    (uint64_t)token * args.score_token_stride) + comp;
                *dst = -INFINITY;
            }
        }
        return;
    }

    for (uint i = tid; i < TN*D; i += 128) {
        const uint cc = i / D;
        const uint d = i - cc*D;
        const uint comp = c0 + cc;
        float v = 0.0f;
        if (comp < args.n_comp) {
            device const float *row = (device const float *)(index_comp +
                (uint64_t)comp * args.index_row_stride);
            v = row[d];
        }
        ktg[i] = v;
    }

    const uint cell0 = lane;
    const uint cell1 = lane + 32u;
    const uint row0 = cell0 >> 3;
    const uint row1 = cell1 >> 3;
    const uint sub0 = cell0 & 7u;
    const uint sub1 = cell1 & 7u;
    const uint col0 = (uint)sg * TS + sub0;
    const uint col1 = (uint)sg * TS + sub1;
    const uint token0 = t0 + row0;
    const uint token1 = t0 + row1;
    const uint comp0 = c0 + col0;
    const uint comp1 = c0 + col1;

    float acc0 = 0.0f;
    float acc1 = 0.0f;

    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (uint head = 0; head < args.n_head; head++) {
        for (uint i = tid; i < TM*D; i += 128) {
            const uint r = i / D;
            const uint d = i - r*D;
            const uint token = t0 + r;
            float v = 0.0f;
            if (token < args.n_tokens) {
                device const float *qrow = (device const float *)(q +
                    (uint64_t)token * args.q_token_stride +
                    (uint64_t)head  * args.q_head_stride);
                v = qrow[d];
            }
            qtg[i] = v;
        }

        threadgroup_barrier(mem_flags::mem_threadgroup);

        simdgroup_float8x8 mdot = make_filled_simdgroup_matrix<float, 8>(0.0f);
        for (uint db = 0; db < D/TS; db++) {
            simdgroup_float8x8 mq;
            simdgroup_float8x8 mk;
            simdgroup_load(mq, qtg + db*TS, D, 0, false);
            simdgroup_load(mk, ktg + ((uint)sg * TS) * D + db*TS, D, 0, true);
            simdgroup_multiply_accumulate(mdot, mq, mk, mdot);
        }

        simdgroup_store(mdot, dot + (uint)sg * TS, TN, 0, false);

        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (token0 < args.n_tokens && comp0 < args.n_comp) {
            device const float *w = (device const float *)(weights +
                (uint64_t)token0 * args.weights_token_stride);
            const float s = dot[row0*TN + col0];
            acc0 += max(s, 0.0f) * (w[head] * args.scale);
        }
        if (token1 < args.n_tokens && comp1 < args.n_comp) {
            device const float *w = (device const float *)(weights +
                (uint64_t)token1 * args.weights_token_stride);
            const float s = dot[row1*TN + col1];
            acc1 += max(s, 0.0f) * (w[head] * args.scale);
        }

        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    if (token0 < args.n_tokens && comp0 < args.n_comp) {
        const uint visible = min((args.pos0 + token0 + 1u) / args.ratio, args.n_comp);
        device float *dst = (device float *)(scores +
            (uint64_t)token0 * args.score_token_stride) + comp0;
        *dst = comp0 < visible ? acc0 : -INFINITY;
    }
    if (token1 < args.n_tokens && comp1 < args.n_comp) {
        const uint visible = min((args.pos0 + token1 + 1u) / args.ratio, args.n_comp);
        device float *dst = (device float *)(scores +
            (uint64_t)token1 * args.score_token_stride) + comp1;
        *dst = comp1 < visible ? acc1 : -INFINITY;
    }
}

kernel void kernel_dsv4_indexer_scores_tiled(
        constant ds4_metal_args_dsv4_indexer_scores_fused & args,
        device const char *q,
        device const char *weights,
        device const char *index_comp,
        device       char *scores,
        threadgroup float *shared [[threadgroup(0)]],
        uint2  tgpig [[threadgroup_position_in_grid]],
        ushort tid   [[thread_index_in_threadgroup]],
        ushort lane  [[thread_index_in_simdgroup]],
        ushort sg    [[simdgroup_index_in_threadgroup]]) {
    constexpr uint TM = 8;
    constexpr uint TN = 32;
    constexpr uint TS = 8;
    constexpr uint D  = 128;

    const uint c0 = tgpig.x * TN;
    const uint t0 = tgpig.y * TM;

    // Q/K are staged as half but the dot accumulator and final score remain
    // float. This is the one intentional precision tradeoff in the indexer:
    // the indexer only ranks compressed rows for top-k selection, and long
    // context profiling shows this score matrix dominates the prefill slope.
    threadgroup half *qtg = (threadgroup half *)shared; // [8][128]
    threadgroup half *ktg = qtg + TM*D;                 // [32][128]
    threadgroup float *dot = (threadgroup float *)(ktg + TN*D); // [8][32]

    const uint last_token = min(t0 + TM, args.n_tokens);
    const uint max_visible = last_token > t0 ?
        min((args.pos0 + last_token) / args.ratio, args.n_comp) : 0u;

    if (c0 >= max_visible) {
        for (uint i = tid; i < TM*TN; i += 128) {
            const uint r = i / TN;
            const uint cc = i - r*TN;
            const uint token = t0 + r;
            const uint comp = c0 + cc;
            if (token < args.n_tokens && comp < args.n_comp) {
                device float *dst = (device float *)(scores +
                    (uint64_t)token * args.score_token_stride) + comp;
                *dst = -INFINITY;
            }
        }
        return;
    }

    // Stage compressed index rows once. Edge columns are zeroed so the matrix
    // loads below can stay regular; guarded stores discard them.
    for (uint i = tid; i < TN*D; i += 128) {
        const uint cc = i / D;
        const uint d = i - cc*D;
        const uint comp = c0 + cc;
        half v = half(0.0f);
        if (comp < args.n_comp) {
            device const float *row = (device const float *)(index_comp +
                (uint64_t)comp * args.index_row_stride);
            v = half(row[d]);
        }
        ktg[i] = v;
    }

    const uint cell0 = lane;
    const uint cell1 = lane + 32u;
    const uint row0 = cell0 >> 3;
    const uint row1 = cell1 >> 3;
    const uint sub0 = cell0 & 7u;
    const uint sub1 = cell1 & 7u;
    const uint col0 = (uint)sg * TS + sub0;
    const uint col1 = (uint)sg * TS + sub1;
    const uint token0 = t0 + row0;
    const uint token1 = t0 + row1;
    const uint comp0 = c0 + col0;
    const uint comp1 = c0 + col1;

    float acc0 = 0.0f;
    float acc1 = 0.0f;

    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (uint head = 0; head < args.n_head; head++) {
        // Stage Q for the eight-token tile. Each 8x8 matrix load below reads a
        // contiguous depth block from this layout.
        for (uint i = tid; i < TM*D; i += 128) {
            const uint r = i / D;
            const uint d = i - r*D;
            const uint token = t0 + r;
            half v = half(0.0f);
            if (token < args.n_tokens) {
                device const float *qrow = (device const float *)(q +
                    (uint64_t)token * args.q_token_stride +
                    (uint64_t)head  * args.q_head_stride);
                v = half(qrow[d]);
            }
            qtg[i] = v;
        }

        threadgroup_barrier(mem_flags::mem_threadgroup);

        simdgroup_float8x8 mdot = make_filled_simdgroup_matrix<float, 8>(0.0f);
        for (uint db = 0; db < D/TS; db++) {
            simdgroup_half8x8 mq;
            simdgroup_half8x8 mk;
            simdgroup_load(mq, qtg + db*TS, D, 0, false);
            simdgroup_load(mk, ktg + ((uint)sg * TS) * D + db*TS, D, 0, true);
            simdgroup_multiply_accumulate(mdot, mq, mk, mdot);
        }

        simdgroup_store(mdot, dot + (uint)sg * TS, TN, 0, false);

        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (token0 < args.n_tokens && comp0 < args.n_comp) {
            device const float *w = (device const float *)(weights +
                (uint64_t)token0 * args.weights_token_stride);
            const float s = dot[row0*TN + col0];
            acc0 += max(s, 0.0f) * (w[head] * args.scale);
        }
        if (token1 < args.n_tokens && comp1 < args.n_comp) {
            device const float *w = (device const float *)(weights +
                (uint64_t)token1 * args.weights_token_stride);
            const float s = dot[row1*TN + col1];
            acc1 += max(s, 0.0f) * (w[head] * args.scale);
        }

        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    if (token0 < args.n_tokens && comp0 < args.n_comp) {
        const uint visible = min((args.pos0 + token0 + 1u) / args.ratio, args.n_comp);
        device float *dst = (device float *)(scores +
            (uint64_t)token0 * args.score_token_stride) + comp0;
        *dst = comp0 < visible ? acc0 : -INFINITY;
    }
    if (token1 < args.n_tokens && comp1 < args.n_comp) {
        const uint visible = min((args.pos0 + token1 + 1u) / args.ratio, args.n_comp);
        device float *dst = (device float *)(scores +
            (uint64_t)token1 * args.score_token_stride) + comp1;
        *dst = comp1 < visible ? acc1 : -INFINITY;
    }
}

#ifdef DS4_METAL_HAS_TENSOR
// Retained full-512 prefill indexer score path.  This is the part of sparse
// compressed attention that maps cleanly to TensorOps: a regular token by
// compressed-row dot tile.  The kernel intentionally leaves top-k selection and
// indexed attention semantics unchanged; all 512 selected rows remain available
// to the later attention kernel.
//
// Each matmul processes a pair of heads (TQ = 2 x TM q rows): the per-element
// dot is still a 128-deep reduction in 32-wide k-steps, so scores are
// bit-identical to single-head tiles while the run count halves.  The q tile
// is double-buffered, so the next k-step's stage overlaps the current
// cooperative matmul and each pair needs 5 barriers instead of 10.  q and k
// staging use one float4/half4 per lane (each thread covers one row of 8/32
// consecutive elements), which is the same half(float) conversion per element
// as the scalar form.
kernel void kernel_dsv4_indexer_scores_nax(
        constant ds4_metal_args_dsv4_indexer_scores_fused & args,
        device const char *q,
        device const char *weights,
        device const char *index_comp,
        device       char *scores,
        threadgroup half *shared [[threadgroup(0)]],
        uint2  tgpig [[threadgroup_position_in_grid]],
        ushort tid   [[thread_index_in_threadgroup]]) {
    constexpr int TM = 16;
    constexpr int TQ = 32;
    constexpr int TN = 32;
    constexpr int NK = 32;
    constexpr int D  = 128;
    constexpr int NUM_THREADS = 128;

    // The 16-token x 32-row tile was the winning NAX shape in local sweeps.  A
    // wider 64-row compressed tile increased setup/cache pressure and was
    // slower despite doing more work per dispatch.
    const uint c0 = tgpig.x * TN;
    const uint t0 = tgpig.y * TM;

    threadgroup half  *qtg = shared;               // 2 x [TQ][NK]
    threadgroup half  *ktg = qtg + 2*TQ*NK;        // [32][128]
    threadgroup float *dot = (threadgroup float *)(ktg + TN*D); // [TQ][TN], column-major

    const uint last_token = min(t0 + (uint)TM, args.n_tokens);
    const uint max_visible = last_token > t0 ?
        min((args.pos0 + last_token) / args.ratio, args.n_comp) : 0u;

    if (c0 >= max_visible) {
        for (uint i = tid; i < TM*TN; i += NUM_THREADS) {
            const uint r = i / TN;
            const uint cc = i - r*TN;
            const uint token = t0 + r;
            const uint comp = c0 + cc;
            if (token < args.n_tokens && comp < args.n_comp) {
                device float *dst = (device float *)(scores +
                    (uint64_t)token * args.score_token_stride) + comp;
                *dst = -INFINITY;
            }
        }
        return;
    }

    {
        // One compressed row per 4 threads, 32 consecutive floats per thread.
        const uint cc = tid / 4;
        const uint comp = c0 + cc;
        device const float *krow = nullptr;
        if (comp < args.n_comp) {
            krow = (device const float *)(index_comp +
                (uint64_t)comp * args.index_row_stride);
        }
        const uint d0 = (tid % 4) * 32;
        FOR_UNROLL (uint j = 0; j < 8; j++) {
            const float4 kv = krow ? *(device const float4 *)(krow + d0 + 4*j)
                                   : float4(0.0f);
            *(threadgroup half4 *)(ktg + cc*D + d0 + 4*j) = half4(kv);
        }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    float acc[4];
    #pragma unroll
    for (uint j = 0; j < 4; j++) {
        acc[j] = 0.0f;
    }

    auto tq0 = tensor(qtg,          dextents<int32_t, 2>(NK, TQ));
    auto tq1 = tensor(qtg + TQ*NK,  dextents<int32_t, 2>(NK, TQ));
    auto tk = tensor(ktg, dextents<int32_t, 2>(D, TN));
    auto td = tensor(dot, dextents<int32_t, 2>(TQ, TN), array<int, 2>({1, TQ}));

    matmul2d<
        matmul2d_descriptor(TN, TQ, NK, false, true, false,
            matmul2d_descriptor::mode::multiply_accumulate),
        execution_simdgroups<4>> mm;

    // One q row per 4 threads, 8 consecutive floats per thread.  Row r covers
    // head (r / TM) of the pair and token row (r % TM).
    const uint q_r = tid / 4;
    const uint q_k4 = (tid % 4) * 8;
    const uint q_hl = q_r / TM;
    const uint q_tr = q_r % TM;
    const uint q_token = t0 + q_tr;
    device const char *q_row_base = nullptr;
    if (q_token < args.n_tokens) {
        q_row_base = q + (uint64_t)q_token * args.q_token_stride;
    }

    auto stage_q = [&](const uint head0, const uint loop_k, threadgroup half *buf) {
        const uint head = head0 + q_hl;
        half4 v0 = half4(0.0f);
        half4 v1 = half4(0.0f);
        if (q_row_base && head < args.n_head) {
            device const float4 *src4 = (device const float4 *)
                (q_row_base + (uint64_t)head * args.q_head_stride +
                 (uint64_t)(loop_k + q_k4) * sizeof(float));
            v0 = half4(src4[0]);
            v1 = half4(src4[1]);
        }
        *(threadgroup half4 *)(buf + q_r*NK + q_k4)     = v0;
        *(threadgroup half4 *)(buf + q_r*NK + q_k4 + 4) = v1;
    };

    for (uint head0 = 0; head0 < args.n_head; head0 += 2) {
        auto ct = mm.template get_destination_cooperative_tensor<decltype(tk), decltype(tq0), float>();
        #pragma unroll
        for (uint16_t i = 0; i < ct.get_capacity(); i++) {
            if (ct.is_valid_element(i)) {
                ct[i] = 0.0f;
            }
        }

        stage_q(head0, 0, qtg);
        threadgroup_barrier(mem_flags::mem_threadgroup);

        uint qsel = 0;
        FOR_UNROLL (uint i = 0; i < 4; i++) {
            auto mk = tk.slice(i*NK, 0);
            auto mq = (qsel ? tq1 : tq0).slice(0, 0);
            mm.run(mk, mq, ct);
            if (i < 3) {
                qsel ^= 1u;
                stage_q(head0, (i + 1)*NK, qsel ? qtg + TQ*NK : qtg);
                threadgroup_barrier(mem_flags::mem_threadgroup);
            }
        }

        ct.store(td);
        threadgroup_barrier(mem_flags::mem_threadgroup);

        #pragma unroll
        for (uint j = 0; j < 4; j++) {
            const uint linear = (uint)tid + j*NUM_THREADS;
            if (linear < TM*TN) {
                const uint r = linear / TN;
                const uint cc = linear - r*TN;
                const uint token = t0 + r;
                if (token < args.n_tokens) {
                    device const float *w = (device const float *)(weights +
                        (uint64_t)token * args.weights_token_stride);
                    acc[j] += max(dot[cc*TQ + r], 0.0f) * (w[head0] * args.scale);
                    if (head0 + 1 < args.n_head) {
                        acc[j] += max(dot[cc*TQ + TM + r], 0.0f) * (w[head0 + 1] * args.scale);
                    }
                }
            }
        }
        // No barrier here: the next pair's q stage and these dot reads touch
        // different buffers, and the next q-stage barrier separates the next
        // ct.store from these reads.
    }

    #pragma unroll
    for (uint j = 0; j < 4; j++) {
        const uint linear = (uint)tid + j*NUM_THREADS;
        if (linear >= TM*TN) {
            continue;
        }
        const uint r = linear / TN;
        const uint cc = linear - r*TN;
        const uint token = t0 + r;
        const uint comp = c0 + cc;
        if (token < args.n_tokens && comp < args.n_comp) {
            const uint visible = min((args.pos0 + token + 1u) / args.ratio, args.n_comp);
            device float *dst = (device float *)(scores +
                (uint64_t)token * args.score_token_stride) + comp;
            *dst = comp < visible ? acc[j] : -INFINITY;
        }
    }
}
#endif

// Collapses per-head indexer scores into one score per compressed row using the
// learned head weights. Negative head scores are clipped exactly as DS4 expects.
kernel void kernel_dsv4_indexer_weighted_sum(
        constant ds4_metal_args_dsv4_indexer_weighted_sum & args,
        device const char * scores,
        device const char * weights,
        device       char * dst,
        uint gid [[thread_position_in_grid]]) {
    const int64_t n = args.ne0 * args.ne1;
    if ((int64_t) gid >= n) {
        return;
    }

    const int64_t ic = gid % args.ne0;
    const int64_t it = gid / args.ne0;

    float acc = 0.0f;
    for (int64_t ih = 0; ih < args.ne02; ++ih) {
        const float s = *((device const float *) (scores  + ic*args.nb00 + it*args.nb01 + ih*args.nb02));
        const float w = *((device const float *) (weights + ih*args.nb10 + it*args.nb11));
        acc += max(s, 0.0f) * (w * args.scale);
    }

    *((device float *) (dst + ic*args.nb0 + it*args.nb1)) = acc;
}

// Adds the periodic compressor APE directly to projected scores. The legacy
// path materializes one repeated APE segment per period and then performs this
// same single F32 add; these kernels remove only that intermediate copy graph.
kernel void kernel_dsv4_compressor_score_ape_f32(
        constant ds4_metal_args_dsv4_compressor_score_ape & args,
        device const float *score,
        device const float *ape,
        device       float *dst,
        uint gid [[thread_position_in_grid]]) {
    const uint64_t total = (uint64_t)args.n_tokens * args.width;
    if ((uint64_t)gid >= total) return;

    const uint token = gid / args.width;
    const uint col = gid - token*args.width;
    const uint ape_row = (uint)(((uint64_t)args.pos0 + token) % args.ratio);
    dst[gid] = score[gid] + ape[(uint64_t)ape_row*args.width + col];
}

kernel void kernel_dsv4_compressor_score_ape_f16(
        constant ds4_metal_args_dsv4_compressor_score_ape & args,
        device const float *score,
        device const half  *ape,
        device       float *dst,
        uint gid [[thread_position_in_grid]]) {
    const uint64_t total = (uint64_t)args.n_tokens * args.width;
    if ((uint64_t)gid >= total) return;

    const uint token = gid / args.width;
    const uint col = gid - token*args.width;
    const uint ape_row = (uint)(((uint64_t)args.pos0 + token) % args.ratio);
    dst[gid] = score[gid] + float(ape[(uint64_t)ape_row*args.width + col]);
}

// Fused softmax-weighted pooling of compressed KV rows. It is used when several
// compressor rows are present; the one-row case deliberately follows the
// unfused softmax/mul/sum graph in Objective-C to keep identical reductions.
kernel void kernel_dsv4_softmax_pool(
        constant ds4_metal_args_dsv4_softmax_pool & args,
        device const char * kv,
        device const char * score,
        device       char * dst,
        uint gid [[thread_position_in_grid]]) {
    const int64_t n = args.ne0 * args.ne1;
    if ((int64_t) gid >= n) {
        return;
    }

    const int64_t id = gid % args.ne0;
    const int64_t ic = gid / args.ne0;

    float max_s = -INFINITY;
    for (int64_t ir = 0; ir < args.ne00; ++ir) {
        const float s = *((device const float *) (score + ir*args.nb10 + id*args.nb11 + ic*args.nb12));
        max_s = max(max_s, s);
    }

    float sum = 0.0f;
    float acc = 0.0f;
    for (int64_t ir = 0; ir < args.ne00; ++ir) {
        const float s = *((device const float *) (score + ir*args.nb10 + id*args.nb11 + ic*args.nb12));
        const float w = exp(s - max_s);
        const float v = *((device const float *) (kv + ir*args.nb00 + id*args.nb01 + ic*args.nb02));
        sum += w;
        acc += v*w;
    }

    *((device float *) (dst + id*args.nb0 + ic*args.nb1)) = acc/sum;
}



// Tensor-parallel keep-alive: a few threadgroups of FMAs dispatched
// back-to-back on a side queue while TP decode runs.  The per-layer gate
// stalls make the real workload look idle to the GPU power manager, which
// otherwise halves the clocks within a second (~2x decode regression);
// this holds them up for negligible bandwidth and a few watts.
kernel void kernel_dsv4_tp_keepalive(
        device float * out,
        constant uint & iters,
        uint tid [[thread_position_in_grid]]) {
    float a = out[tid];
    const float b = 1.000001f;
    for (uint i = 0; i < iters; i++) {
        a = fma(a, b, 0.000001f);
        a = fma(a, b, -0.000001f);
    }
    out[tid] = a;
}

// Tensor-parallel gate flag: publishes a sequence number to a slab slot the
// CPU service thread spin-reads, replacing the much slower shared-event
// signal for the GPU->CPU direction.  Ordering against the partial-output
// kernels comes from the buffer hazard on the shared slab.
kernel void kernel_dsv4_tp_flag_set(
        device atomic_uint & flag,
        constant uint & value,
        uint tid [[thread_position_in_grid]]) {
    if (tid == 0) {
        atomic_store_explicit(&flag, value, memory_order_relaxed);
    }
}

// Poll-gate flag with a payload checksum: the CPU sees the flag word as soon
// as its cache line is written back at command-buffer completion, which can
// precede the rest of the partial's lines. Publishing an integer checksum of
// the partial lets the service thread verify the payload in memory before it
// posts the RDMA send, instead of waiting for the (much later) completion
// status. Integer sums are order-independent, so the value is exact.
kernel void kernel_dsv4_tp_flag_set_checked(
        device atomic_uint & flag,
        device atomic_uint & check,
        constant uint & value,
        device const uint * payload,
        constant uint & words,
        threadgroup uint * shmem [[threadgroup(0)]],
        uint tid [[thread_index_in_threadgroup]],
        ushort tiisg [[thread_index_in_simdgroup]],
        ushort sgitg [[simdgroup_index_in_threadgroup]]) {
    uint sum = 0u;
    for (uint i = tid; i < words; i += 256u) sum += payload[i];
    sum = simd_sum(sum);
    if (tiisg == 0) shmem[sgitg] = sum;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (tid == 0) {
        uint total = 0u;
        for (uint s = 0; s < 8u; s++) total += shmem[s];
        atomic_store_explicit(&check, total ^ (value * 0x9E3779B9u), memory_order_relaxed);
        atomic_store_explicit(&flag, value, memory_order_relaxed);
    }
}

// Fused local FFN sum + checked poll-gate flag.  out = a + b for n words
// (the rank's FFN partial in its slab slot); every threadgroup adds the
// integer sum of the words it stored to a device accumulator and the
// last-arriving threadgroup publishes the checksum and the flag.  Integer
// sums are order independent, so the checksum equals the one
// kernel_dsv4_tp_flag_set_checked would compute over the same payload, and
// the gate loses one kernel.  ctl[0] counts arrivals, ctl[1] accumulates;
// the last arriver resets both for the next use of the slot.
kernel void kernel_dsv4_add2_f32_tp_flag_checked(
        constant uint & n,
        device const float * a,
        device const float * b,
        device float * out,
        device atomic_uint & flag,
        device atomic_uint & check,
        constant uint & value,
        device atomic_uint * ctl,
        constant uint & ntg,
        threadgroup uint * shmem [[threadgroup(0)]],
        uint tid [[thread_index_in_threadgroup]],
        uint tgid [[threadgroup_position_in_grid]],
        ushort tiisg [[thread_index_in_simdgroup]],
        ushort sgitg [[simdgroup_index_in_threadgroup]]) {
    const uint i = tgid * 256u + tid;
    uint w = 0u;
    if (i < n) {
        const float v = a[i] + b[i];
        out[i] = v;
        w = as_type<uint>(v);
    }
    w = simd_sum(w);
    if (tiisg == 0) shmem[sgitg] = w;
    threadgroup_barrier(mem_flags::mem_device | mem_flags::mem_threadgroup);
    if (tid == 0) {
        uint s = 0u;
        for (uint k = 0; k < 8u; k++) s += shmem[k];
        atomic_fetch_add_explicit(&ctl[1], s, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_device);
    if (tid == 0) {
        const uint old = atomic_fetch_add_explicit(&ctl[0], 1u, memory_order_relaxed);
        if (old + 1u == ntg) {
            const uint total = atomic_exchange_explicit(&ctl[1], 0u, memory_order_relaxed);
            atomic_store_explicit(&ctl[0], 0u, memory_order_relaxed);
            atomic_store_explicit(&check, total ^ (value * 0x9E3779B9u), memory_order_relaxed);
            atomic_store_explicit(&flag, value, memory_order_relaxed);
        }
    }
}

// Inline decode gates: the CPU releases the GPU by a store to a system-coherent
// word that a one-thread kernel spin-reads inside the open command buffer, so
// the stream neither parks on a shared event nor ends a command buffer per
// gate. Without that buffer boundary the partial and the flag have to be pushed
// to system visibility explicitly: both are re-stored through coherent(system)
// views followed by a system-scope fence.
#pragma METAL internals : enable
#ifndef __METAL_MEMORY_SCOPE_SYSTEM__
#define __METAL_MEMORY_SCOPE_SYSTEM__ 3
#endif
namespace metal {
constexpr constant metal::thread_scope thread_scope_system =
    static_cast<thread_scope>(__METAL_MEMORY_SCOPE_SYSTEM__);
}

kernel void kernel_dsv4_tp_payload_publish(
        volatile coherent(system) device uint * payload,
        constant uint & n_words,
        uint tid [[thread_position_in_grid]]) {
    if (tid < n_words) payload[tid] = payload[tid];
    metal::atomic_thread_fence(metal::mem_flags::mem_device,
                               metal::memory_order_seq_cst,
                               metal::thread_scope_system);
}

kernel void kernel_dsv4_tp_flag_publish(
        volatile coherent(system) device uint * flag,
        constant uint & value) {
    flag[0] = value;
    metal::atomic_thread_fence(metal::mem_flags::mem_device,
                               metal::memory_order_seq_cst,
                               metal::thread_scope_system);
}

// Bounded: a process killed mid-gate never stores the release word, and an
// unbounded loop strands the kernel in GPU firmware until a reboot (observed).
// The release seq is compared monotonically so a store is never missed.
// [1] keeps the spin count of the last wait, [2] counts timeouts.
kernel void kernel_dsv4_tp_release_wait(
        volatile coherent(system) device uint * release_word,
        constant uint & value,
        constant uint & max_iters) {
    uint i = 0;
    for (; i < max_iters; i++) {
        metal::atomic_thread_fence(metal::mem_flags::mem_device,
                               metal::memory_order_seq_cst,
                               metal::thread_scope_system);
        if ((int)(release_word[0] - value) >= 0) break;
    }
    release_word[1] = i;
    if (i >= max_iters) release_word[2] = release_word[2] + 1u;
    metal::atomic_thread_fence(metal::mem_flags::mem_device,
                               metal::memory_order_seq_cst,
                               metal::thread_scope_system);
}

// Tensor-parallel poll gate: waits for the service thread's release of gate
// `value` without parking the command buffer on a shared event, which costs
// tens of microseconds of GPU idle per gate on Apple silicon. A running
// kernel never observes an external write to a cache line it already read
// (the L2 copy stays stale until the command buffer ends), so every probe
// reads a line this command buffer has not touched: the region is consumed
// front to back, 32 lines per simdgroup probe, with growing pauses between
// rounds. The gate is always the first work of its command buffer, so the
// whole region is fresh. 8192 lines cover roughly 600 ms before `status`
// reports a timeout, which the service thread reports at the next gate.
kernel void kernel_dsv4_tp_poll_release(
        device const uint * region,
        constant uint & value,
        constant uint & nlines,
        device uint * status,
        uint tid [[thread_index_in_threadgroup]]) {
    const uint rounds = nlines / 32u;
    float spin = 1.0f;
    for (uint r = 0; r < rounds; r++) {
        const uint line = r * 32u + tid;
        const uint x = region[line * 32u];
        const uint hit = (x == value) ? line : 0xffffffffu;
        const uint first = simd_min(hit);
        if (first != 0xffffffffu) {
            if (tid == 0) status[0] = first;
            return;
        }
        uint pause = 0u;
        if (r >= 160u) pause = 375000u;      /* ~5 ms   x 96 rounds */
        else if (r >= 96u) pause = 150000u;  /* ~2 ms   x 64 rounds */
        else if (r >= 64u) pause = 20000u;   /* ~270 us x 32 rounds */
        else if (r >= 32u) pause = 1200u;    /* ~16 us  x 32 rounds */
        else if (r >= 16u) pause = 150u;     /* ~2 us   x 16 rounds */
        for (uint i = 0; i < pause; i++) {
            spin = fma(spin, 1.000001f, 0.000001f);
            spin = fma(spin, 1.000001f, -0.000001f);
        }
    }
    if (tid == 0) status[0] = 0xffffffffu;
    if (spin == 0.0f) status[1] = 0u; /* keeps the pause loop alive */
}

// Ratio-4 compressor pooling without materializing the [n_comp, 8, head_dim]
// KV and score packs. The row mapping and both reduction loops deliberately
// match kernel_dsv4_softmax_pool so the arithmetic order is unchanged.
kernel void kernel_dsv4_softmax_pool_ratio4_direct(
        constant ds4_metal_args_dsv4_softmax_pool_ratio4_direct & args,
        device const float * kv,
        device const float * score,
        device const float * state_kv,
        device const float * state_score,
        device       float * dst,
        uint gid [[thread_position_in_grid]]) {
    const uint64_t n = (uint64_t)args.head_dim * args.n_comp;
    if ((uint64_t)gid >= n || args.head_dim == 0u) {
        return;
    }

    const uint64_t id = gid % args.head_dim;
    const uint64_t ic = gid / args.head_dim;
    const uint64_t input_row_stride = 2ull * args.head_dim;

    float max_s = -INFINITY;
    float sum = 0.0f;
    float acc = 0.0f;
    if (ic != 0u) {
        const int64_t token_base = (int64_t)ic * 4 - 4;
        for (int64_t ir = 0; ir < args.n_rows; ++ir) {
            const uint64_t token = (uint64_t)(token_base + ir);
            const uint64_t src = token * input_row_stride +
                                 ((uint64_t)ir >> 2u) * args.head_dim + id;
            const float s = score[src];
            max_s = max(max_s, s);
        }

        for (int64_t ir = 0; ir < args.n_rows; ++ir) {
            const uint64_t token = (uint64_t)(token_base + ir);
            const uint64_t src = token * input_row_stride +
                                 ((uint64_t)ir >> 2u) * args.head_dim + id;
            const float s = score[src];
            const float w = exp(s - max_s);
            const float v = kv[src];
            sum += w;
            acc += v*w;
        }
    } else {
        for (int64_t ir = 0; ir < args.n_rows; ++ir) {
            float s;
            if (ir >= 4) {
                const uint64_t src = (uint64_t)(ir - 4) * input_row_stride +
                                     args.head_dim + id;
                s = score[src];
            } else if (args.replay != 0u) {
                s = state_score[(uint64_t)ir * input_row_stride + id];
            } else {
                s = -INFINITY;
            }
            max_s = max(max_s, s);
        }

        for (int64_t ir = 0; ir < args.n_rows; ++ir) {
            float s;
            float v;
            if (ir >= 4) {
                const uint64_t src = (uint64_t)(ir - 4) * input_row_stride +
                                     args.head_dim + id;
                s = score[src];
                v = kv[src];
            } else if (args.replay != 0u) {
                const uint64_t src = (uint64_t)ir * input_row_stride + id;
                s = state_score[src];
                v = state_kv[src];
            } else {
                s = -INFINITY;
                v = 0.0f;
            }
            const float w = exp(s - max_s);
            sum += w;
            acc += v*w;
        }
    }

    dst[ic * args.head_dim + id] = acc/sum;
}
