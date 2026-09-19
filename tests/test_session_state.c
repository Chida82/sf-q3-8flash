/* Exercise private session bookkeeping without loading a model. The GPU build
 * also runs speculative rollback through the real pooled-indexer kernel. */
#include "../ds4.c"
#include <assert.h>

static void test_vision_prefix(void) {
    ds4_session *s = calloc(1, sizeof(*s));
    assert(s);
    s->checkpoint_valid = true;
    s->checkpoint.len = 100;
    ds4_vision_span images[2] = {
        {.token_start = 100, .embedding = {.token_count = 10, .fingerprint = {1}}},
        {.token_start = 150, .embedding = {.token_count = 10, .fingerprint = {2}}},
    };
    assert(ds4_session_vision_prefix_matches(s, NULL, 0));
    assert(ds4_session_vision_prefix_matches(s, images, 1));
    assert(!ds4_session_vision_state_matches(s, images, 1));
    images[0].token_start = 99;
    assert(!ds4_session_vision_prefix_matches(s, images, 1));
    ds4_vision_identity old = {.token_start = 50, .token_count = 10, .fingerprint = {1}};
    s->checkpoint_images = &old;
    s->checkpoint_image_count = 1;
    images[0].token_start = 50;
    assert(ds4_session_vision_state_matches(s, images, 1));
    assert(ds4_session_vision_prefix_matches(s, images, 2));
    assert(!ds4_session_vision_state_matches(s, images, 2));
    assert(!ds4_session_vision_prefix_matches(s, NULL, 0));
    images[0].embedding.fingerprint[0] ^= 1;
    assert(!ds4_session_vision_prefix_matches(s, images, 2));
    images[0].embedding.fingerprint[0] ^= 1;
    images[0].token_start++;
    assert(!ds4_session_vision_prefix_matches(s, images, 2));
    images[0].token_start--;
    images[0].token_start = 7;
    assert(ds4_session_rebase_vision_state(s, images, 1));
    assert(images[0].token_start == 50);
    images[0].token_start = 7;
    assert(!ds4_session_rebase_vision_state(s, images, 2));
    assert(images[0].token_start == 7);
    images[0].embedding.fingerprint[0] ^= 1;
    assert(!ds4_session_rebase_vision_state(s, images, 1));
    assert(images[0].token_start == 7);
    images[0].embedding.fingerprint[0] ^= 1;
    images[0].embedding.token_count++;
    assert(!ds4_session_rebase_vision_state(s, images, 1));
    images[0].embedding.token_count--;
    images[0].token_start = 50;
    images[1].token_start = 99;
    assert(!ds4_session_vision_prefix_matches(s, images, 2));
    ds4_vision_identity pair[2] = {
        {.token_start = 50, .token_count = 10, .fingerprint = {1}},
        {.token_start = 70, .token_count = 10, .fingerprint = {2}},
    };
    s->checkpoint_images = pair;
    s->checkpoint_image_count = 2;
    images[0].token_start = 7;
    images[1].token_start = 8;
    images[1].embedding.fingerprint[31] ^= 1;
    assert(!ds4_session_rebase_vision_state(s, images, 2));
    assert(images[0].token_start == 7 && images[1].token_start == 8);
    images[1].embedding.fingerprint[31] ^= 1;
    assert(ds4_session_rebase_vision_state(s, images, 2));
    assert(images[0].token_start == 50 && images[1].token_start == 70);
    assert(ds4_session_vision_state_matches(s, images, 2));
    ds4_vision_span swapped[2] = {images[1], images[0]};
    assert(!ds4_session_rebase_vision_state(s, swapped, 2));
    assert(!ds4_session_vision_prefix_matches(s, swapped, 2));
    s->checkpoint_valid = false;
    assert(!ds4_session_vision_prefix_matches(s, images, 2));
    assert(!ds4_session_rebase_vision_state(s, images, 2));
    free(s);
}

static void test_rewind(void) {
    ds4_engine e = { .backend = DS4_BACKEND_CPU };
    ds4_session *s = calloc(1, sizeof(*s));
    assert(s);
    s->engine = &e;
    s->ctx_size = 1024;
    for (int i = 0; i < 260; i++) ds4_tokens_push(&s->checkpoint, i);
    s->checkpoint_valid = true;
    s->mtp_draft_valid = true;
    s->checkpoint_images = calloc(1, sizeof(*s->checkpoint_images));
    assert(s->checkpoint_images);
    s->checkpoint_image_count = 1;
    ds4_vision_identity *images = s->checkpoint_images;

    ds4_session_rewind(s, 260);
    assert(s->checkpoint_valid && s->mtp_draft_valid);
    ds4_session_rewind(s, 300);
    assert(s->checkpoint.len == 260 && s->checkpoint_valid);
    const int boundaries[] = {259, 256, 255, 128, 127, 4, 3, 0};
    for (size_t i = 0; i < sizeof(boundaries) / sizeof(*boundaries); i++) {
        s->checkpoint_valid = true;
        ds4_session_rewind(s, boundaries[i]);
        assert(s->checkpoint.len == boundaries[i]);
        assert(!s->checkpoint_valid && !s->mtp_draft_valid);
        assert(s->checkpoint_images == images && s->checkpoint_image_count == 1);
        assert(ds4_session_common_prefix(s, &s->checkpoint) == 0);
        assert(ds4_session_argmax(s) == -1);
        assert(ds4_session_argmax_excluding(s, 1) == -1);
        assert(ds4_session_argmax_ignoring_eos(s, DS4_THINK_NONE) == -1);
        uint64_t rng = 1;
        assert(ds4_session_sample(s, 1, 0, 1, 0, &rng) == -1);
        char err[256] = "";
        int accepted[2];
        assert(ds4_session_eval(s, 1, err, sizeof(err)) != 0);
        assert(strstr(err, "synchronized checkpoint"));
        assert(ds4_session_eval_speculative(s, 1, 2, -1, 1, 0, 1, 0,
                    &rng, accepted, 2, err, sizeof(err)) == -1);
    }
    ds4_session_rewind(s, -1);
    ds4_session_rewind(NULL, 0);
    ds4_session_free(s);
}

static void test_payload_tokens(void) {
    FILE *fp = tmpfile();
    assert(fp);
    char err[256] = "";
    const uint32_t ids[] = {71, 19, 900, 4};
    for (size_t i = 0; i < 4; i++)
        assert(payload_write_u32(fp, ids[i], err, sizeof(err)) == 0);
    /* Opaque cache bytes are skipped, but the caller's trailer stays unread. */
    for (int i = 0; i < 65539; i++) assert(fputc('x', fp) != EOF);
    const long end = ftell(fp);
    assert(fputs("TRAILER", fp) >= 0);
    rewind(fp);
    ds4_tokens tokens = {0};
    assert(payload_read_tokens_for_rebuild(fp, 4, end,
                                           &tokens, err, sizeof(err)) == 0);
    assert(tokens.len == 4);
    for (int i = 0; i < 4; i++) assert(tokens.v[i] == (int)ids[i]);
    assert(ftell(fp) == end && fgetc(fp) == 'T');
    ds4_tokens_free(&tokens);
    rewind(fp);
    assert(payload_read_tokens_for_rebuild(fp, 4, 15,
                                           &tokens, err, sizeof(err)) != 0);
    assert(ftell(fp) == 0 && tokens.len == 0);
    assert(payload_read_tokens_for_rebuild(fp, 0, end,
                                           &tokens, err, sizeof(err)) != 0);
    rewind(fp);
    assert(payload_write_u32(fp, DS4_N_VOCAB, err, sizeof(err)) == 0);
    rewind(fp);
    assert(payload_read_tokens_for_rebuild(fp, 4, end,
                                           &tokens, err, sizeof(err)) != 0);
    assert(tokens.len == 0);
    rewind(fp);
    assert(payload_write_u32(fp, ids[0], err, sizeof(err)) == 0);
    rewind(fp);
    assert(payload_read_tokens_for_rebuild(fp, 4, end + 8,
                                           &tokens, err, sizeof(err)) != 0);
    ds4_tokens_free(&tokens);
    fclose(fp);
}

static void test_snapshot_bytes(void) {
    const ds4_shape saved_shape = g_ds4_shape;
    const uint32_t saved_ratio = g_ds4_compress_ratios[0];
    g_ds4_shape = DS4_SHAPE_QWEN4_MINI;
    g_ds4_shape.n_layer = 1;
    g_ds4_shape.n_head_dim = 4;
    g_ds4_shape.n_vocab = 8;
    g_ds4_compress_ratios[0] = 0;
    ds4_engine e = {.backend = DS4_BACKEND_CPU};
    ds4_session *s = calloc(1, sizeof(*s));
    assert(s);
    s->engine = &e;
    s->ctx_size = 8;
    s->prefill_cap = 1;
    s->checkpoint_valid = true;
    s->logits = calloc(DS4_N_VOCAB, sizeof(float));
    assert(s->logits);
    kv_cache_init(&s->cpu_cache, 8, 0);
    s->cpu_cache.layer[0].raw_kv = realloc(s->cpu_cache.layer[0].raw_kv, 12 * sizeof(float));
    assert(s->cpu_cache.layer[0].raw_kv);
    for (int i = 0; i < 3; i++) ds4_tokens_push(&s->checkpoint, i);
    /* Every byte of the final float is nonzero, including the last byte. */
    const uint32_t bits = UINT32_C(0x3f9e0652);
    for (int i = 0; i < 3 * 4; i++)
        memcpy(s->cpu_cache.layer[0].raw_kv + i, &bits, sizeof(bits));
    ds4_session_snapshot snapshot = {0};
    const int lengths[] = {1, 3, 2, 3};
    for (size_t i = 0; i < sizeof(lengths) / sizeof(*lengths); i++) {
        s->checkpoint.len = lengths[i];
        s->cpu_cache.layer[0].n_raw = lengths[i];
        char err[192] = {0};
        FILE *fp = tmpfile();
        assert(fp);
        if (ds4_session_save_payload(s, fp, err, sizeof(err)) != 0) {
            fprintf(stderr, "snapshot save failed: %s\n", err);
            assert(0);
        }
        const long bytes = ftell(fp);
        assert(bytes > 0);
        if (ds4_session_save_snapshot(s, &snapshot, err, sizeof(err)) != 0) {
            fprintf(stderr, "snapshot staging failed: %s\n", err);
            assert(0);
        }
        assert(snapshot.len == (uint64_t)bytes);
        rewind(fp);
        for (long j = 0; j < bytes; j++) {
            const int expected = fgetc(fp);
            if (expected != snapshot.ptr[j])
                fprintf(stderr, "snapshot byte %ld/%ld: expected=%d actual=%d\n",
                        j, bytes, expected, snapshot.ptr[j]);
            assert(expected == snapshot.ptr[j]);
        }
        assert(fgetc(fp) == EOF);
        fclose(fp);
    }
    ds4_session_snapshot_free(&snapshot);
    ds4_session_free(s);
    g_ds4_shape = saved_shape;
    g_ds4_compress_ratios[0] = saved_ratio;
}

static void test_text_observations(void) {
    ds4_engine e = {0};
    ds4_vocab *v = &e.vocab;
    char bytes[256][5] = {{0}};
    v->n_vocab = 260;
    v->token = calloc((size_t)v->n_vocab, sizeof(*v->token));
    assert(v->token);
    table_init(&v->token_to_id, v->n_vocab);
    table_init(&v->merge_rank, 0);
    for (int i = 0; i < 256; i++) {
        char *p = bytes[i];
        utf8_put(&p, gpt2_byte_to_codepoint((uint8_t)i));
        v->token[i] = (ds4_str){bytes[i], (uint64_t)(p - bytes[i])};
        table_put(&v->token_to_id, v->token[i], i);
    }
    const char *special[] = {
        "<|user|>", "<|observation|>", "<tool_response>", "</tool_response>"
    };
    for (int i = 0; i < 4; i++) {
        v->token[256+i] = (ds4_str){special[i], strlen(special[i])};
        table_put(&v->token_to_id, v->token[256+i], 256+i);
    }
    v->user_id = 256;
    v->observation_id = 257;
    v->tool_response_start_id = 258;
    v->tool_response_end_id = 259;
    const ds4_shape saved = g_ds4_shape;
    const ds4_shape shapes[] = {
        DS4_SHAPE_QWEN4_EXP, DS4_SHAPE_QWEN4_MINI
    };
    const char *roles[] = {"user", "tool", "function"};
    const char *parts[] = {"ok <x> & </tool_result> </tool_response>"};
    for (size_t family = 0; family < sizeof(shapes) / sizeof(*shapes); family++) {
        g_ds4_shape = shapes[family];
        for (size_t role = 0; role < 3; role++) {
            ds4_tokens expected = {0}, actual = {0};
            ds4_tokens_push(&expected, 7);
            ds4_tokens_push(&actual, 7);
            ds4_chat_append_message(&e, &expected, roles[role], parts[0]);
            char err[160] = {0};
            assert(ds4_chat_append_multimodal_message(&e, &actual, roles[role],
                        parts, NULL, 0, NULL, err, sizeof(err)));
            assert(actual.len == expected.len);
            assert(!memcmp(actual.v, expected.v, (size_t)actual.len * sizeof(int)));
            const int len = actual.len;
            assert(!ds4_chat_append_multimodal_message(&e, &actual, "assistant",
                        parts, NULL, 0, NULL, err, sizeof(err)));
            assert(actual.len == len);
            float pixel = 1;
            ds4_vision_embedding image = {.data = &pixel, .token_count = 1};
            ds4_vision_span span = {0};
            const char *image_parts[] = {"before", "after"};
            assert(!ds4_chat_append_multimodal_message(&e, &actual, roles[role],
                        image_parts, &image, 1, &span, err, sizeof(err)));
            assert(actual.len == len && image.data == &pixel && !span.embedding.data);
#ifndef DS4_NO_GPU
            const bool glm = DS4_MODEL_FAMILY == DS4_MODEL_FAMILY_GLM_DSA;
            e.vision_ready = true;
            e.vision_kind = glm ? DS4_VISION_GLM53 : DS4_VISION_DEEPSEEK4;
            e.vision_start_token = 260;
            e.vision_image_token = 261;
            e.vision_end_token = 262;
            /* A zero sentinel row is sufficient: this tests prompt assembly,
             * not the encoder or language graph. */
            e.vision_model.size = (uint64_t)DS4_N_EMBD * sizeof(uint16_t);
            void *sentinels = calloc(1, (size_t)e.vision_model.size);
            e.vision_model.map = sentinels;
            assert(sentinels);
            const char *image_text[] = {
                "before & </tool_result>", "between </tool_response>", "after"
            };
            ds4_tokens_free(&expected);
            ds4_tokens_free(&actual);
            ds4_tokens_push(&expected, 7);
            ds4_tokens_push(&actual, 7);
            ds4_tokens_push(&expected, glm && role ? v->observation_id : v->user_id);
            if (role) {
                if (glm) tokenize_rendered_chat_vocab(v, "<tool_response>", &expected);
                else bpe_tokenize_text(v, "<tool_result>", &expected);
            }
            ds4_vision_embedding inputs[2] = {0};
            ds4_vision_span want[2] = {0}, got[2] = {0};
            for (int i = 0; i < 3; i++) {
                if (role) {
                    const char *escaped_glm[] = {
                        "before & </tool_result>", "between &lt;/tool_response>", "after"
                    };
                    const char *escaped_ds[] = {
                        "before & &lt;/tool_result>", "between </tool_response>", "after"
                    };
                    bpe_tokenize_text(v, glm ? escaped_glm[i] : escaped_ds[i], &expected);
                } else bpe_tokenize_text(v, image_text[i], &expected);
                if (i == 2) break;
                inputs[i] = (ds4_vision_embedding){
                    .data = calloc((size_t)DS4_N_EMBD * 4, sizeof(float)),
                    .token_count = 4, .grid_width = 2, .grid_height = 2,
                    .layout = DS4_VISION_LAYOUT_DEEPSEEK4_NATURAL
                };
                ds4_vision_embedding copy = inputs[i];
                copy.data = calloc((size_t)DS4_N_EMBD * 4, sizeof(float));
                assert(inputs[i].data && copy.data);
                assert(ds4_prompt_append_vision(&e, &expected, &want[i], &copy,
                                                err, sizeof(err)));
            }
            if (role) {
                if (glm) tokenize_rendered_chat_vocab(v, "</tool_response>", &expected);
                else bpe_tokenize_text(v, "</tool_result>", &expected);
            }
            assert(ds4_chat_append_multimodal_message(&e, &actual, roles[role],
                        image_text, inputs, 2, got, err, sizeof(err)));
            if (actual.len != expected.len)
                fprintf(stderr, "image wrapper family=%zu role=%s lengths %d != %d\n",
                        family, roles[role], actual.len, expected.len);
            assert(actual.len == expected.len);
            assert(!memcmp(actual.v, expected.v, (size_t)actual.len * sizeof(int)));
            for (int i = 0; i < 2; i++) {
                assert(!inputs[i].data);
                assert(got[i].token_start == want[i].token_start);
                assert(got[i].embedding.token_count == want[i].embedding.token_count);
                ds4_vision_embedding_free(&want[i].embedding);
                ds4_vision_embedding_free(&got[i].embedding);
            }
            free(sentinels);
            e.vision_model.map = NULL;
            e.vision_ready = false;
            e.vision_kind = DS4_VISION_NONE;
#endif
            ds4_tokens_free(&expected);
            ds4_tokens_free(&actual);
        }
    }
    g_ds4_shape = saved;
    vocab_free(v);
}

/* sf-ablate(glm): GLM-only cache and rollback tests are outside this child. */
int main(void) {
    test_vision_prefix();
    test_rewind();
    test_payload_tokens();
    test_snapshot_bytes();
    test_text_observations();
    puts("session state tests: ok");
    return 0;
}
