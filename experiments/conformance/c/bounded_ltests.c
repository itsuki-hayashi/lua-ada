/* Keep the upstream debug allocator and its identity checks unchanged. The
 * only interposition is its two backing malloc/free calls. This independent
 * backing-byte ceiling cannot be removed by T.totalmem's fault-injection API.
 * No reference code is linked into the production Ada library. */
#define LUA_CORE
#include "../../../references/lua/lprefix.h"
#include "../../../references/lua/lua.h"
#include "allocator_limit.h"
#include <limits.h>

typedef union BackingHeader {
  LUAI_MAXALIGN;
  size_t size;
} BackingHeader;

static size_t backing_bytes;
static size_t backing_blocks;
static unsigned long long refused_allocations;

/* These observations describe the independent backing cap, not T.totalmem's
 * replaceable fault-injection controls. The launcher reads them only after
 * Lua has closed its states; they never stand in for a Lua GC count. */
LUA_API size_t conformance_live_bytes(void) { return backing_bytes; }
LUA_API size_t conformance_live_blocks(void) { return backing_blocks; }
LUA_API unsigned long long conformance_refusals(void) {
  return refused_allocations;
}

static void *bounded_malloc(size_t size) {
  BackingHeader *block;
  size_t limit = conformance_limit();
  if (backing_bytes > limit || size > limit - backing_bytes ||
      size > SIZE_MAX - sizeof(BackingHeader)) {
    refused_allocations++;
    return NULL;
  }
  block = (BackingHeader *)malloc(sizeof(BackingHeader) + size);
  if (block == NULL) {
    refused_allocations++;
    return NULL;
  }
  block->size = size;
  backing_bytes += size;
  backing_blocks++;
  return block + 1;
}

static void bounded_free(void *pointer) {
  if (pointer != NULL) {
    BackingHeader *block = (BackingHeader *)pointer - 1;
    backing_bytes -= block->size;
    backing_blocks--;
    free(block);
  }
}

static void observed_setwarnf(lua_State *, lua_WarnFunction, void *);
#define lua_setwarnf observed_setwarnf
#define malloc bounded_malloc
#define free bounded_free
#include "../../../references/lua/ltests.c"
#undef lua_setwarnf

/* Observe delivery without changing the pinned handler's controls, errors or
 * _WARN storage. The distinct gc.lua close errors are assembled across native
 * fragments and counted only after the original callback accepts the message. */
static lua_WarnFunction original_warning;
static char observed_warning[200];
static size_t observed_warning_length;
static unsigned long long expected_finalizer_warnings;

LUA_API unsigned long long conformance_expected_finalizer_warnings(void) {
  return expected_finalizer_warnings;
}

static void observed_warning_callback(void *data, const char *message,
                                      int continued) {
  size_t length = strlen(message);
  original_warning(data, message, continued);
  /* ltests.c has already rejected messages that overflow this same capacity. */
  if (length >= sizeof(observed_warning) - observed_warning_length) abort();
  memcpy(observed_warning + observed_warning_length, message, length + 1);
  observed_warning_length += length;
  if (!continued) {
    if (strstr(observed_warning, "@expected warning") != NULL) {
      if (expected_finalizer_warnings == ULLONG_MAX) abort();
      expected_finalizer_warnings++;
    }
    observed_warning_length = 0;
    observed_warning[0] = '\0';
  }
}

static void observed_setwarnf(lua_State *L, lua_WarnFunction function,
                              void *data) {
  original_warning = function;
  observed_warning_length = 0;
  expected_finalizer_warnings = 0;
  lua_setwarnf(L, observed_warning_callback, data);
}
