/* ds4_gpu_mgpu.h — tier-aware tensor helpers of the DeepSeek graph.
 *
 * sf-ablate(cuda): the CUDA multi-GPU types (ds4_gpu_config, ds4_gpu_ctx,
 * g_gpu[]), its multi-device init, per-device caches and cross-device copy
 * variants were removed with the CUDA backend. What is left is the tensor
 * struct and the three helpers the DeepSeek graph's multi-tier plumbing still
 * names; on Metal every graph is single-tier (tier 0).
 */
#ifndef DS4_GPU_MGPU_H
#define DS4_GPU_MGPU_H

#include <stddef.h>
#include <stdint.h>

/* sf-ablate(build): C++ linkage guard removed; this child has no C++ translation unit. */

#define DS4_MAX_GPUS 16

/* Complete definition of the previously-opaque ds4_gpu_tensor, plus a
 * typedef so callers can stack-allocate or struct-embed tensors without
 * including ds4_gpu.h first. */
struct ds4_gpu_tensor {
    void    *ptr;
    uint64_t bytes;
    int      owner;
    int      device_id;   /* -1 means legacy/untagged → treat as device 0 */
};
#ifndef DS4_GPU_TENSOR_DEFINED
#define DS4_GPU_TENSOR_DEFINED
typedef struct ds4_gpu_tensor ds4_gpu_tensor;
#endif

#ifndef DS4_GPU_ATTENTION_DECODE_ROW_DEFINED
#define DS4_GPU_ATTENTION_DECODE_ROW_DEFINED
#define DS4_GPU_ATTENTION_DECODE_BATCH_MAX 32u
typedef struct {
    uint64_t raw_kv;
    uint64_t comp_kv;
    uint64_t topk;
    uint32_t pos;
    uint32_t n_raw;
    uint32_t raw_cap;
    uint32_t raw_start;
    uint32_t n_comp;
    uint32_t top_k;
    uint32_t window;
    uint32_t ratio;
    uint32_t indexed;
} ds4_gpu_attention_decode_row;
#endif

/* Heap-allocated tensor on a logical tier; tier 0 is ds4_gpu_tensor_alloc. */
ds4_gpu_tensor *ds4_gpu_tensor_alloc_ptr_on(int tier, uint64_t bytes);

/* Cross-tier copy; only multi-tier placements reach it. */
int ds4_gpu_tensor_copy_xdev(ds4_gpu_tensor *dst,
                              const ds4_gpu_tensor *src,
                              uint64_t bytes);

/* Select the device of a logical tier; only multi-tier placements reach it. */
int ds4_gpu_set_current_device(int logical_tier);

#endif /* DS4_GPU_MGPU_H */
