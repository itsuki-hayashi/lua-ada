/* First-party same-source C/Ada native-module consumer contract.
 * MIT license; see ../../LICENSE.
 *
 * This ordinary C program links the real Lua 5.5 C API and the unchanged
 * upstream native fixtures found in argv[1]. It uses only public headers,
 * public lauxlib/lualib calls and the operating system's module tables. The
 * fixture directory must contain lib1, lib11, lib2, lib21 and lib2-v2
 * images with the platform suffix (.dll on Windows, .so on POSIX). Dependent
 * DLL search paths are the responsibility of the outer runner. */

/* Must precede every system header so RTLD_NOLOAD is visible under -std=c99. */
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#define NATIVE_SUFFIX ".dll"
#elif defined(__unix__) || defined(__APPLE__)
#define _DEFAULT_SOURCE 1
#include <dlfcn.h>
#define NATIVE_SUFFIX ".so"
#ifndef RTLD_NOLOAD
#error "dlopen on this POSIX platform does not expose RTLD_NOLOAD"
#endif
#else
#error "native module contract needs GetModuleHandleA or dlopen RTLD_NOLOAD"
#endif

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "consumer_allocator.h"

/* Fixed seed reused by every fresh state so failures are reproducible. */
#define CASE_SEED 872641U
#define PATH_CAPACITY 1024

/* Provider wrapper around counted_allocator. It is the only allocator a test
 * state ever sees, so the state-close balance check covers every block Lua
 * requested. It also watches one fixture-owned external-string header. */
struct provider {
    struct allocation_counts counts; /* counts for the wrapped allocator */
    void *tracked;                   /* fixture header awaiting its release */
    size_t tracked_size;            /* header plus terminated payload size */
    size_t tracked_frees;           /* exact releases observed for tracked */
    int bad_free;                   /* realloc or short release of tracked */
};

/* Source-linked fixture layout: the fixture places this two-field header
 * immediately before each external-string payload. It is not Lua's private
 * string representation; the test reads it only to find the free callback. */
struct ext_str_header {
    void *ud;
    lua_Alloc alloc;
};

static void *provider_allocator(void *data, void *block, size_t old_size,
                                size_t new_size) {
    struct provider *provider = (struct provider *)data;
    /* A tracked block may only be released once, at its recorded exact
     * size. Any resize means the fixture violated the header contract. */
    if (block != NULL && block == provider->tracked) {
        if (new_size == 0) {
            if (old_size != provider->tracked_size) provider->bad_free = 1;
            provider->tracked = NULL;
            provider->tracked_frees++;
        } else {
            provider->bad_free = 1;
        }
    }
    return counted_allocator(&provider->counts, block, old_size, new_size);
}

static int report(const char *name, const char *message) {
    fprintf(stderr, "native-module-%s: %s\n", name, message);
    return 0;
}

static void report_lua_error(lua_State *L, const char *name) {
    const char *message = lua_tostring(L, -1);
    fprintf(stderr, "native-module-%s: Lua error: %s\n", name,
            message != NULL ? message : "(no message)");
}

/* Fixture image paths are built with snprintf so a long directory name fails
 * cleanly instead of overrunning the buffer. */
static int image_path(char *buffer, size_t size, const char *dir,
                      const char *name) {
    int written = snprintf(buffer, size, "%s/%s%s", dir, name, NATIVE_SUFFIX);
    return written > 0 && (size_t)written < size;
}

/* Returns 1 when the image is present in the process, 0 when it is absent
 * and -1 when the query itself could not be completed. */
static int image_loaded(const char *path) {
#ifdef _WIN32
    char full[PATH_CAPACITY];
    char *cursor;
    DWORD length = GetFullPathNameA(path, sizeof full, full, NULL);
    if (length == 0 || length >= sizeof full) return -1;
    /* Module tables are keyed by the canonical backslash form on Windows. */
    for (cursor = full; *cursor != '\0'; cursor++) {
        if (*cursor == '/') *cursor = '\\';
    }
    return GetModuleHandleA(full) != NULL ? 1 : 0;
#else
    /* RTLD_NOLOAD returns a handle only for an already-resident image. That
     * query adds one reference, so it is balanced before returning. */
    void *handle = dlopen(path, RTLD_NOLOAD | RTLD_NOW);
    if (handle == NULL) return 0;
    return dlclose(handle) == 0 ? 1 : -1;
#endif
}

static int check_images(const char *dir, const char *const *images,
                        int expect_loaded) {
    size_t i;
    for (i = 0; images[i] != NULL; i++) {
        char path[PATH_CAPACITY];
        int state;
        if (!image_path(path, sizeof path, dir, images[i])) {
            fprintf(stderr, "fixture path too long for %s\n", images[i]);
            return 0;
        }
        state = image_loaded(path);
        if (state < 0) {
            fprintf(stderr, "cannot query native image %s\n", path);
            return 0;
        }
        if ((state == 1) != (expect_loaded != 0)) {
            fprintf(stderr, "native image %s was %s\n", path,
                    expect_loaded ? "absent before state close"
                                  : "still resident after state close");
            return 0;
        }
    }
    return 1;
}

/* package.cpath is assigned through the stack. The fixture directory is a
 * pushed string value, never spliced into Lua source text. */
static int set_cpath(lua_State *L, const char *dir) {
    if (lua_getglobal(L, "package") != LUA_TTABLE) {
        lua_pop(L, 1);
        return 0;
    }
    lua_pushfstring(L, "%s/?%s", dir, NATIVE_SUFFIX);
    lua_setfield(L, -2, "cpath");
    lua_pop(L, 1);
    return 1;
}

/* Loads the constant chunk, passes the fixture directory and suffix as its
 * two varargs, then runs it. Assertions live in Lua; any error is printed. */
static int run_script(lua_State *L, const char *name, const char *source,
                      const char *dir) {
    int status = luaL_loadstring(L, source);
    if (status == LUA_OK) {
        lua_pushstring(L, dir);
        lua_pushstring(L, NATIVE_SUFFIX);
        status = lua_pcall(L, 2, 0, 0);
    }
    if (status != LUA_OK) {
        report_lua_error(L, name);
        lua_pop(L, 1);
        return 0;
    }
    return 1;
}

/* Calls require through the global table and leaves the module value on the
 * stack. A failure is printed and returns zero with the error popped. */
static int require_module(lua_State *L, const char *name,
                          const char *case_name) {
    lua_getglobal(L, "require");
    lua_pushstring(L, name);
    if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
        report_lua_error(L, case_name);
        lua_pop(L, 1);
        return 0;
    }
    return 1;
}

/* ---- Script cases ---- */

/* Missing file: package.loadlib returns nil, message and stage "open". The
 * three-result shape is part of the public loader contract. */
static const char script_missing_open[] =
    "local dir, suffix = ...\n"
    "local results = table.pack(package.loadlib(dir .. '/no_such_native_module'"
    " .. suffix, 'onefunction'))\n"
    "assert(results.n == 3, 'loadlib must return three values')\n"
    "assert(results[1] == nil, 'missing library unexpectedly opened')\n"
    "assert(type(results[2]) == 'string', 'missing library message')\n"
    "assert(results[3] == 'open', 'missing library stage was ' .. tostring(results[3]))\n";

/* A missing symbol in an existing image reports stage "init". The library
 * stays cached, so a later real symbol in the same image is still found. */
static const char script_cached_symbol[] =
    "local dir, suffix = ...\n"
    "local path = dir .. '/lib1' .. suffix\n"
    "local f, message, stage = package.loadlib(path, 'no_such_symbol_for_contract')\n"
    "assert(f == nil and type(message) == 'string' and stage == 'init',"
    " 'missing symbol stage was ' .. tostring(stage))\n"
    "local onefunction = assert(package.loadlib(path, 'onefunction'))\n"
    "local a,b=onefunction(15,25); assert(a==25 and b==15)\n";

/* Real lib1 and lib11 exports, via the symbol loader and require. */
static const char script_exports[] =
    "local dir, suffix = ...\n"
    "local path = dir .. '/lib1' .. suffix\n"
    "assert(package.loadlib(path,'*'))\n"
    "local f=assert(package.loadlib(path,'onefunction'))\n"
    "local a,b=f(15,25);assert(a==25 and b==15)\n"
    "f=assert(package.loadlib(path,'anotherfunc'))\n"
    "assert(f(10,20)=='10%20\\n')\n"
    "assert(require('lib11')=='exported')\n";

/* Croot: lib1.sub is found in lib1 and its loader data is the image path. */
static const char script_croot[] =
    "local dir, suffix = ...\n"
    "local sub, data = require('lib1.sub')\n"
    "assert(sub.id(45)==45)\n"
    "assert(package.loaded['lib1.sub'] == sub, 'lib1.sub cached value')\n"
    "assert(data==dir..'/lib1'..suffix and x=='lib1.sub' and y==data)\n";

/* Hyphenated name: the file is lib2-v2 and the symbol is luaopen_lib2. */
static const char script_hyphen[] =
    "local dir, suffix = ...\n"
    "local module, data = require('lib2-v2')\n"
    "local a,b,c=module.id(45,46);assert(a==true and b==45 and c==46)\n"
    "assert(data==dir..'/lib2-v2'..suffix and x=='lib2-v2' and y==data)\n";

/* lib21 delegates its opener through the independently loaded lib2 image.
 * This needs global symbol visibility on POSIX and an actual DLL dependency
 * on Windows; both calls must use this state's original runtime image. */
static const char script_second_dependency[] =
    "local dir,suffix=...\n"
    "assert(package.loadlib(dir..'/lib2'..suffix,'*'))\n"
    "local module,data=require('lib21')\n"
    "local a,b=module.id(45,46);assert(a==45 and b==46)\n"
    "assert(data==dir..'/lib21'..suffix and x=='lib21' and y==data)\n";

/* lib22.c builds lib2-v2 and stores an external string in the registry; its code releases
 * the header during state close. The balance check after close verifies it. */
static const char script_registry_lib22[] =
    "local dir, suffix = ...\n"
    "assert(type(require('lib2-v2').newstr)=='function')\n";

/* ---- Retained native callback from a __gc metamethod ---- */

static int gc_probe_calls;
static int gc_probe_bad;

/* C finalizer. Its upvalue is the retained lib1.id function. It must receive
 * 42 and return 42. Errors are counted as bad rather than thrown, because
 * finalizer errors become warnings during close. */
static int gc_probe_finalizer(lua_State *L) {
    lua_Integer value;
    gc_probe_calls++;
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_pushinteger(L, 42);
    if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
        gc_probe_bad++;
        lua_pop(L, 1);
        return 0;
    }
    value = lua_tointeger(L, -1);
    if (!lua_isinteger(L, -1) || value != 42) gc_probe_bad++;
    lua_pop(L, 1);
    return 0;
}

/* Stop the collector so the only finalization in this case happens inside
 * lua_close. Calls the fixture id function through a retained upvalue. */
static int body_gc_callback(lua_State *L, struct provider *provider,
                            const char *dir) {
    (void)provider;
    (void)dir;
    gc_probe_calls = 0;
    gc_probe_bad = 0;
    lua_gc(L, LUA_GCSTOP);
    if (!require_module(L, "lib1.sub", "gc-retained-native-callback")) return 0;
    lua_getfield(L, -1, "id");
    if (lua_type(L, -1) != LUA_TFUNCTION) {
        return report("gc-retained-native-callback", "lib1.id is not a function");
    }
    /* Stack: module, id -> module, closure(id). */
    lua_pushcclosure(L, gc_probe_finalizer, 1);
    /* Stack: module, closure -> module, closure, metatable with __gc. */
    lua_newtable(L);
    lua_pushvalue(L, -2);
    lua_setfield(L, -2, "__gc");
    /* Stack: module, closure, metatable -> add the userdata with that
     * metatable. The userdata's last reference is dropped immediately. */
    lua_newuserdatauv(L, 1, 0);
    lua_pushvalue(L, -2);
    lua_setmetatable(L, -2);
    lua_pop(L, 1);
    return 1;
}

static int after_gc_callback(const struct provider *provider) {
    (void)provider;
    if (gc_probe_calls != 1 || gc_probe_bad != 0) {
        return report("gc-retained-native-callback",
                      "retained finalizer did not run exactly once with 42");
    }
    return 1;
}

/* ---- External-string bodies ---- */

/* The fixture allocates its STR header and payload. The test checks the
 * header fields against the wrapper, then tracks the header as one provider
 * block. Its single exact release occurs during lua_close. */
static int body_explicit_newstr(lua_State *L, struct provider *provider,
                                const char *dir) {
    size_t length = 0;
    const char *payload;
    struct ext_str_header *header;
    void *ud = NULL;
    lua_Alloc alloc;
    char source[256];
    (void)dir;
    if (!require_module(L, "lib2-v2", "explicit-lib2-newstr-external")) return 0;
    lua_getfield(L, -1, "newstr");
    if (lua_type(L, -1) != LUA_TFUNCTION) {
        return report("explicit-lib2-newstr-external", "lib2.newstr is not a function");
    }
    memset(source, 'a', sizeof source);
    lua_pushlstring(L, source, sizeof source);
    if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
        report_lua_error(L, "explicit-lib2-newstr-external");
        return 0;
    }
    if (lua_type(L, -1) != LUA_TSTRING) {
        return report("explicit-lib2-newstr-external", "newstr did not return a string");
    }
    payload = lua_tolstring(L, -1, &length);
    if (payload == NULL || length != sizeof source ||
        memcmp(payload, source, sizeof source) != 0) {
        return report("explicit-lib2-newstr-external", "external string length was not 256");
    }
    /* The header is immediately before the payload. Checking both fields
     * before tracking makes the wrapper the only path that can release it. */
    header = (struct ext_str_header *)(void *)((char *)payload - sizeof *header);
    alloc = lua_getallocf(L, &ud);
    if (alloc != provider_allocator || ud != (void *)provider) {
        return report("explicit-lib2-newstr-external", "state allocator is not the provider");
    }
    if (header->alloc != provider_allocator || header->ud != (void *)provider) {
        return report("explicit-lib2-newstr-external",
                      "fixture header does not name the provider");
    }
    if (provider->counts.blocks == 0) {
        return report("explicit-lib2-newstr-external", "no provider block recorded");
    }
    provider->tracked = header;
    provider->tracked_size = sizeof *header + length + 1;
    provider->tracked_frees = 0;
    provider->bad_free = 0;
    return 1;
}

static int after_explicit_newstr(const struct provider *provider) {
    if (provider->tracked != NULL || provider->tracked_frees != 1 ||
        provider->bad_free) {
        return report("explicit-lib2-newstr-external",
                      "external header was not released exactly once");
    }
    return 1;
}

/* ---- Script wrappers used by the case table ---- */

static int body_missing_open(lua_State *L, struct provider *provider,
                             const char *dir) {
    (void)provider;
    return run_script(L, "loadlib-missing-open-stage3values",
                      script_missing_open, dir);
}

static int body_cached_symbol(lua_State *L, struct provider *provider,
                              const char *dir) {
    (void)provider;
    return run_script(L, "loadlib-cached-missing-symbol-init-then-lookup",
                      script_cached_symbol, dir);
}

static int body_exports(lua_State *L, struct provider *provider,
                        const char *dir) {
    (void)provider;
    return run_script(L, "lib1-lib11-native-exports", script_exports, dir);
}

static int body_croot(lua_State *L, struct provider *provider,
                      const char *dir) {
    (void)provider;
    return run_script(L, "croot-lib1-sub-args-globals", script_croot, dir);
}

static int body_hyphen(lua_State *L, struct provider *provider,
                       const char *dir) {
    (void)provider;
    return run_script(L, "hyphen-lib2-v2-loader-data", script_hyphen, dir);
}

static int body_second_dependency(lua_State *L, struct provider *provider,
                                  const char *dir) {
    (void)provider;
    return run_script(L, "lib2-lib21-global-dependency",
                      script_second_dependency, dir);
}

static int body_registry_lib22(lua_State *L, struct provider *provider,
                               const char *dir) {
    (void)provider;
    return run_script(L, "registry-lib22-external-string", script_registry_lib22, dir);
}

/* ---- Case table ---- */

struct native_case {
    const char *name;
    int (*body)(lua_State *L, struct provider *provider, const char *dir);
    int (*after_close)(const struct provider *provider);
    const char *const *images; /* NULL-terminated; dependencies included */
};

static int no_after_close(const struct provider *provider) {
    (void)provider;
    return 1;
}

static const char *const no_images[] = {NULL};
static const char *const lib1_images[] = {"lib1", NULL};
static const char *const lib1_lib11_images[] = {"lib1", "lib11", NULL};
static const char *const lib2_v2_images[] = {"lib2-v2", NULL};
static const char *const lib2_lib21_images[] = {"lib2", "lib21", NULL};

static const struct native_case cases[] = {
    {"loadlib-missing-open-stage3values", body_missing_open,
     no_after_close, no_images},
    {"loadlib-cached-missing-symbol-init-then-lookup", body_cached_symbol,
     no_after_close, lib1_images},
    {"lib1-lib11-native-exports", body_exports, no_after_close,
     lib1_lib11_images},
    {"croot-lib1-sub-args-globals", body_croot, no_after_close, lib1_images},
    {"hyphen-lib2-v2-loader-data", body_hyphen, no_after_close, lib2_v2_images},
    {"lib2-lib21-global-dependency", body_second_dependency, no_after_close,
     lib2_lib21_images},
    {"gc-retained-native-callback", body_gc_callback, after_gc_callback,
     lib1_images},
    {"registry-lib22-external-string", body_registry_lib22, no_after_close,
     lib2_v2_images},
    {"explicit-lib2-newstr-external", body_explicit_newstr,
     after_explicit_newstr, lib2_v2_images},
};

/* One fresh provider-backed state per case. Every failure is printed with the
 * case name; the function returns nonzero only when every check passed. */
static int run_case(const struct native_case *test, const char *dir) {
    struct provider provider;
    lua_State *L;
    int ok;
    memset(&provider, 0, sizeof provider);
    L = lua_newstate(provider_allocator, &provider, CASE_SEED);
    if (L == NULL) return report(test->name, "lua_newstate refused");
    luaL_openlibs(L);
    ok = set_cpath(L, dir) || report(test->name, "package table unavailable");
    if (ok) ok = test->body(L, &provider, dir);
    /* Images must be resident while the script is still running. */
    if (ok) ok = check_images(dir, test->images, 1);
    lua_close(L);
    /* The state close must remove every fixture image and every provider
     * block. Checks run whether or not the body succeeded. */
    if (!check_images(dir, test->images, 0)) ok = 0;
    if (provider.counts.bytes != 0 || provider.counts.blocks != 0) {
        report(test->name, "provider bytes or blocks remain after close");
        ok = 0;
    }
    if (!test->after_close(&provider)) ok = 0;
    return ok;
}

int main(int argc, char **argv) {
    size_t i;
    int failures = 0;
    if (argc != 2) {
        fprintf(stderr, "usage: %s FIXTURE_DIRECTORY\n", argv[0]);
        return EXIT_FAILURE;
    }
    for (i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        if (run_case(&cases[i], argv[1])) {
            printf("PASS: native-module-%s\n", cases[i].name);
        } else {
            failures++;
            fprintf(stderr, "FAIL: native-module-%s\n", cases[i].name);
        }
    }
    return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
