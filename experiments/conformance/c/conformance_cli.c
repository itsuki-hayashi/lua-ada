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
#if defined(_WIN32)
#include <process.h>
#define conformance_getpid _getpid
#else
#include <unistd.h>
#define conformance_getpid getpid
#endif

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
static unsigned long long refused_allocations;

static void *bounded_alloc(void *ud, void *pointer, size_t oldsize,
                           size_t size) {
  Allocator *state = (Allocator *)ud;
  size_t old = pointer != NULL ? oldsize : 0;
  size_t limit = conformance_limit();
  void *result;
  if (size > old && (state->bytes > limit ||
                    size - old > limit - state->bytes)) {
    refused_allocations++;
    return NULL;
  }
  result = state->original(state->userdata, pointer, oldsize, size);
  if (result == NULL && size != 0) refused_allocations++;
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

#if defined(CONFORMANCE_UPSTREAM_TEST)
LUA_API size_t conformance_live_bytes(void);
LUA_API size_t conformance_live_blocks(void);
LUA_API unsigned long long conformance_refusals(void);
LUA_API unsigned long long conformance_expected_finalizer_warnings(void);
#endif

static int write_allocator_telemetry(void) {
  const char *prefix = getenv("LUA_ADA_CONFORMANCE_TELEMETRY");
  const char *run_id = getenv("LUA_ADA_CONFORMANCE_RUN_ID");
  const char *cursor;
  char *path;
  FILE *output;
  int failed;
  unsigned long pid = (unsigned long)conformance_getpid();
  if (prefix == NULL) return 1;  /* Ordinary observations need no sidecar. */
  if (run_id == NULL || *run_id == '\0') return 0;
  /* Run IDs are runner-generated hex GUIDs. Restrict their spelling before
   * JSON emission so the environment cannot inject forged telemetry fields. */
  for (cursor = run_id; *cursor != '\0'; cursor++) {
    if (!((*cursor >= '0' && *cursor <= '9') ||
          (*cursor >= 'a' && *cursor <= 'f') || *cursor == '-')) return 0;
  }
  if (strlen(prefix) > SIZE_MAX - 40) return 0;
  path = (char *)malloc(strlen(prefix) + 40);
  if (path == NULL) return 0;
  snprintf(path, strlen(prefix) + 40, "%s.%lu.json", prefix, pid);
  output = fopen(path, "wb");
  free(path);
  if (output == NULL) return 0;
  fprintf(output, "{\"schema_version\":1,\"run_id\":\"%s\","
          "\"process_id\":%lu,\"allocator_limit_bytes\":%llu,",
          run_id, pid, (unsigned long long)conformance_limit());
#if defined(CONFORMANCE_UPSTREAM_TEST)
  fprintf(output, "\"configuration\":\"upstream-test\","
          "\"expected_finalizer_warnings\":%llu,"
          "\"managed_refusals\":%llu,\"outstanding_bytes\":%llu,"
          "\"outstanding_blocks\":%llu}\n",
          conformance_expected_finalizer_warnings(), conformance_refusals(),
          (unsigned long long)conformance_live_bytes(),
          (unsigned long long)conformance_live_blocks());
#else
  /* Initial blocks predate default allocator interposition. Zero accounted
   * bytes proves zero positive-size live blocks. If any bytes remain, expose
   * the block count as unknown rather than fabricate a nonzero count. */
  fprintf(output, "\"configuration\":\"default\","
          "\"managed_refusals\":%llu,\"outstanding_bytes\":%llu,"
          "\"outstanding_blocks\":%s}\n", refused_allocations,
          (unsigned long long)allocator.bytes,
          allocator.bytes == 0 ? "0" : "null");
#endif
  failed = ferror(output);
  if (fclose(output) != 0) failed = 1;
  return !failed;
}

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
         "\"implementation\":\"C Lua\",\"test_adapter\":%s,"
         "\"lua_version\":\"%s\",\"lua_release\":\"%s\",\"integer_bytes\":%u,"
         "\"number_bytes\":%u,\"compat_global\":%d,"
         "\"extra_space_bytes\":%u,\"expected_extra_space_bytes\":%u,"
         "\"pointer_bytes\":%u,\"max_stack\":%u,"
         "\"max_c_calls\":%u,\"aux_buffer_bytes\":%d,"
         "\"rand32\":%s,\"compat_math\":%s,"
         "\"allocator_limit_bytes\":%llu,\"allocator_accounting\":\"%s\"}\n",
         profile,
#if defined(CONFORMANCE_UPSTREAM_TEST)
         "true",
#else
         "false",
#endif
         LUA_VERSION, LUA_RELEASE, (unsigned)sizeof(lua_Integer),
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
  if (!write_allocator_telemetry()) {
    fputs("conformance allocator telemetry output failed\n", stderr);
    return EXIT_FAILURE;
  }
#if !defined(CONFORMANCE_UPSTREAM_TEST)
  if (allocator.bytes != 0) {
    fputs("reference allocator balance failure\n", stderr);
    return EXIT_FAILURE;
  }
#endif
  return result;
}
