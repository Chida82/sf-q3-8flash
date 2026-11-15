
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

#ifdef DS4_METAL_HAS_TENSOR
#endif

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
