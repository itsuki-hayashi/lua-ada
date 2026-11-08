/* Keep the upstream debug allocator body and identity checks unchanged.
 * Interpose its backing malloc/free calls and observe its final return only.
 * The independent backing-byte ceiling cannot be removed by T.totalmem's
 * fault-injection API. No reference code enters the production Ada library. */
#define LUA_CORE
#include "../../../references/lua/lprefix.h"
#include "../../../references/lua/lua.h"
#include "../../../references/lua/ltests.h"
#include "allocator_limit.h"
#include <limits.h>

typedef union BackingHeader {
  LUAI_MAXALIGN;
  size_t size;
} BackingHeader;

static size_t backing_bytes;
static size_t backing_blocks;
static unsigned long long refused_allocations;
static unsigned long long debug_refusals;

/* Live ownership describes the independent backing cap, not T.totalmem's
 * replaceable fault-injection controls. Aggregate refusals observe all real
 * debug allocator NULL returns; backing refusals identify the narrower cap.
 * The launcher reads these after closure, never as a substitute Lua GC count. */
LUA_API size_t conformance_live_bytes(void) { return backing_bytes; }
LUA_API size_t conformance_live_blocks(void) { return backing_blocks; }
LUA_API unsigned long long conformance_refusals(void) {
  return debug_refusals;
}
LUA_API unsigned long long conformance_backing_refusals(void) {
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
static void *original_debug_realloc(void *, void *, size_t, size_t);
#define lua_setwarnf observed_setwarnf
#define malloc bounded_malloc
#define free bounded_free
/* Rename only function-like occurrences, including the original definition.
 * Bare function-pointer uses remain debug_realloc, so ltests.c's exact
 * allocator identity assertion still sees the public wrapper installed by
 * luaL_newstate. The original body, limits, old blocks and return value are
 * unchanged. Watching backing malloc alone misses its earlier MEMLIMIT/count
 * refusals and falsely reports zero real allocator refusals in heavy.lua. */
#define debug_realloc(...) original_debug_realloc(__VA_ARGS__)
#include "../../../references/lua/ltests.c"
#undef debug_realloc
#undef lua_setwarnf

LUA_API void *debug_realloc(void *data, void *block,
                            size_t old_size, size_t new_size) {
  void *result = original_debug_realloc(data, block, old_size, new_size);
  if (new_size != 0 && result == NULL) {
    if (debug_refusals == ULLONG_MAX) abort();
    debug_refusals++;
  }
  return result;
}

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
