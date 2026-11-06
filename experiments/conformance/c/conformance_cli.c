/* Compile the pinned CLI itself so option parsing, argv layout, signals and
 * subprocess behavior remain reference evidence. Only its initial allocator
 * provider is wrapped in default mode; instrumented mode retains ltests.h's
 * allocator and installs its independent backing cap in bounded_ltests.c. */
#include "../../../references/lua/lprefix.h"
#include "../../../references/lua/lua.h"
#include "../../../references/lua/lauxlib.h"
#include "../../../references/lua/llimits.h"
#include "allocator_limit.h"
#include <string.h>

LUA_API unsigned conformance_stack_limit(void);
LUA_API unsigned conformance_c_call_limit(void);
LUA_API unsigned conformance_extra_space(void);
LUA_API unsigned conformance_aux_buffer(void);

#if !defined(CONFORMANCE_UPSTREAM_TEST)
typedef struct Allocator {
  lua_Alloc original;
  void *userdata;
  size_t bytes;
} Allocator;
static Allocator allocator;

static void *bounded_alloc(void *ud, void *pointer, size_t oldsize,
                           size_t size) {
  Allocator *state = (Allocator *)ud;
  size_t old = pointer != NULL ? oldsize : 0;
  size_t limit = conformance_limit();
  void *result;
  if (size > old && (state->bytes > limit ||
                    size - old > limit - state->bytes)) return NULL;
  result = state->original(state->userdata, pointer, oldsize, size);
  /* A failed growth leaves the old allocation live. A zero-size request is
   * a successful free even though realloc's conventional result is NULL. */
  if (result != NULL || size == 0) state->bytes = state->bytes - old + size;
  return result;
}

static lua_State *conformance_newstate(void) {
  lua_State *L = (luaL_newstate)();
  if (L != NULL) {
    /* Retain the original panic/warning setup. Initial state bytes are part
     * of the ceiling even though original creation precedes interposition. */
    allocator.original = lua_getallocf(L, &allocator.userdata);
    allocator.bytes = (size_t)lua_gc(L, LUA_GCCOUNT) * 1024u +
                      (size_t)lua_gc(L, LUA_GCCOUNTB);
    lua_setallocf(L, bounded_alloc, &allocator);
  }
  return L;
}
#define luaL_newstate() conformance_newstate()
#endif

#define main conformance_cli_main
#include "../../../references/lua/lua.c"
#undef main

static void print_configuration(void) {
#if defined(CONFORMANCE_UPSTREAM_TEST)
  const char *profile = "upstream-test";
  const char *accounting = "debug-allocator-backing-bytes";
  unsigned expected_extra = (unsigned)sizeof(struct L_EXTRA);
#else
  const char *profile = "default";
  const char *accounting = "lua-managed-payload-bytes";
  unsigned expected_extra = (unsigned)sizeof(void *);
#endif
  printf("{\"schema_version\":1,\"configuration\":\"%s\","
         "\"lua_version\":\"%s\",\"lua_release\":\"%s\",\"integer_bytes\":%u,"
         "\"number_bytes\":%u,\"compat_global\":%d,"
         "\"extra_space_bytes\":%u,\"expected_extra_space_bytes\":%u,"
         "\"pointer_bytes\":%u,\"max_stack\":%u,"
         "\"max_c_calls\":%u,\"aux_buffer_bytes\":%d,"
         "\"rand32\":%s,\"compat_math\":%s,"
         "\"allocator_limit_bytes\":%llu,\"allocator_accounting\":\"%s\"}\n",
         profile, LUA_VERSION, LUA_RELEASE, (unsigned)sizeof(lua_Integer),
         (unsigned)sizeof(lua_Number), LUA_COMPAT_GLOBAL,
         conformance_extra_space(), expected_extra,
         (unsigned)sizeof(void *), conformance_stack_limit(),
         conformance_c_call_limit(),
         (int)conformance_aux_buffer(),
#if defined(LUA_RAND32)
         "true",
#else
         "false",
#endif
#if defined(LUA_COMPAT_MATHLIB)
         "true",
#else
         "false",
#endif
         (unsigned long long)conformance_limit(), accounting);
}

int main(int argc, char **argv) {
  int result;
  (void)conformance_limit();  /* validate before entering the reference CLI */
  if (argc == 2 && strcmp(argv[1], "--conformance-config") == 0) {
    print_configuration();
    return EXIT_SUCCESS;
  }
  result = conformance_cli_main(argc, argv);
#if !defined(CONFORMANCE_UPSTREAM_TEST)
  if (allocator.bytes != 0) {
    fputs("reference allocator balance failure\n", stderr);
    return EXIT_FAILURE;
  }
#endif
  return result;
}
