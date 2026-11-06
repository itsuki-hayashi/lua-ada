/* Keep the upstream debug allocator and its identity checks unchanged. The
 * only interposition is its two backing malloc/free calls. This independent
 * backing-byte ceiling cannot be removed by T.totalmem's fault-injection API.
 * No reference code is linked into the production Ada library. */
#define LUA_CORE
#include "../../../references/lua/lprefix.h"
#include "../../../references/lua/lua.h"
#include "allocator_limit.h"

typedef union BackingHeader {
  LUAI_MAXALIGN;
  size_t size;
} BackingHeader;

static size_t backing_bytes;

static void *bounded_malloc(size_t size) {
  BackingHeader *block;
  size_t limit = conformance_limit();
  if (backing_bytes > limit || size > limit - backing_bytes ||
      size > SIZE_MAX - sizeof(BackingHeader)) return NULL;
  block = (BackingHeader *)malloc(sizeof(BackingHeader) + size);
  if (block == NULL) return NULL;
  block->size = size;
  backing_bytes += size;
  return block + 1;
}

static void bounded_free(void *pointer) {
  if (pointer != NULL) {
    BackingHeader *block = (BackingHeader *)pointer - 1;
    backing_bytes -= block->size;
    free(block);
  }
}

#define malloc bounded_malloc
#define free bounded_free
#include "../../../references/lua/ltests.c"
