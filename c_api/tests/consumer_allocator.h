/* First-party public C API regressions. MIT license; see ../../LICENSE. */
#ifndef LUA_ADA_CONSUMER_ALLOCATOR_H
#define LUA_ADA_CONSUMER_ALLOCATOR_H

struct allocation_counts {
    size_t bytes;
    size_t blocks;
    size_t calls;
    int refuse;
    size_t growths;
    size_t fail_after;
};

static void *counted_allocator(void *data, void *block, size_t old_size,
                                size_t new_size) {
    struct allocation_counts *counts = (struct allocation_counts *)data;
    void *replacement;
    int fresh = block == NULL;
    counts->calls++;
    if (new_size == 0) {
        if (block != NULL) {
            assert(counts->bytes >= old_size && counts->blocks > 0);
            counts->bytes -= old_size;
            counts->blocks--;
            free(block);
        }
        return NULL;
    }
    if (fresh || new_size > old_size) {
        counts->growths++;
        if (counts->refuse || (counts->fail_after != 0 &&
            counts->growths >= counts->fail_after)) return NULL;
    }
    replacement = realloc(block, new_size);
    if (replacement == NULL) return NULL;
    if (fresh) counts->blocks++;
    counts->bytes = counts->bytes - (fresh ? 0 : old_size) + new_size;
    return replacement;
}

#endif
