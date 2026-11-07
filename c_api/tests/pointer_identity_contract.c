/* Public pointer-identity contract regressions for C99 consumers.
 * Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE.
 *
 * Each case below is an independently named check that runs in its own fresh
 * counted_allocator state (consumer_allocator.h) and closes that state before
 * returning. The same source compiles as a standalone C99 consumer (define
 * nothing) or as the bridge target behind
 *
 *     int lua_ada_test_identity(unsigned which);
 *
 * which is selected by defining LUA_ADA_POINTER_IDENTITY_CONTRACT_LIBRARY
 * before including this file. Standalone runs print one "PASS: ..." line per
 * case and never print an address.
 *
 * Scope: only documented public API is used: lua_topointer, lua_touserdata,
 * lua_tothread, lua_tocfunction, lua_tolstring, lua_pushfstring,
 * lua_pushcclosure, lua_newthread, lua_resume, lua_yield, lua_getglobal,
 * lua_call, luaL_tolstring, luaL_openlibs and lua_close. Lua-side helpers
 * (tostring and string.format) are looked up with lua_getglobal and invoked
 * with lua_call from C; no Lua source text is ever loaded.
 *
 * Expected text is computed natively: a value's address is formatted with the
 * host snprintf("%p") from lua_topointer(L, index). The one deliberate
 * exception is a NULL pointer through string.format("%p"), where Lua 5.5
 * documents the text "(null)" instead of the native null spelling. Those two
 * spellings are checked separately so no test relies on one platform's
 * output. Nothing is compared against a hard-coded address.
 *
 * Every input value is kept on the stack (rooted) before any formatting call
 * allocates, so a collection cannot free a value a check still reads.
 *
 * Case layout (eight cases, each returns 1 on pass; a failure aborts through
 * assert with the failing expression, file and line):
 *   table-identity              table pointer, raw __name prefixes
 *   full-userdata-identity      payload from lua_touserdata
 *   light-userdata-identity     nonnull caller-owned address
 *   null-light-userdata-identity NULL light userdata text rules
 *   light-cfunction-identity    function pointer identity and callback
 *   captured-closure-identity   upvalue-capturing C closure identity
 *   coroutine-identity          thread identity across yield and completion
 *   raw-string-identity         string identity and counted result
 */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "consumer_allocator.h"

#ifdef NDEBUG
#error "pointer identity contract requires active assertions"
#endif

/* Fixed seed reused by every fresh state so failures are reproducible. */
#define IDENTITY_SEED 2718U

/* Buffer for one native "%p" rendering. C99 does not bound %p, so 64 bytes
 * covers every common pointer spelling with room to spare. */
#define POINTER_TEXT 128

/* Buffer for "<kind>: <native pointer>" with a short kind name. */
#define IDENTITY_TEXT (POINTER_TEXT + 32)

/* Sample storage whose address is a nonnull caller-owned light userdata. The
 * contents are never read; only the address matters. */
static char caller_slot[16];

/* Sample C function used for the light function and callback cases. It returns
 * the pointer text of its first argument via lua_pushfstring, so the same
 * native formatting path is exercised from inside a C function. */
static int identity_callback(lua_State *L) {
    /* lua_topointer returns NULL for non-collectable values such as
     * numbers; the callback then formats NULL, the native result. */
    const void *pointer = lua_topointer(L, 1);
    lua_pushfstring(L, "%p", (void *)pointer);
    return 1;
}

/* Exported callback factory for the primary Ada unit. Returning the callback
 * through lua_CFunction keeps the public function identity observable from
 * the Ada side without depending on any implementation-private symbol. */
lua_CFunction lua_ada_test_identity_callback(void);

lua_CFunction lua_ada_test_identity_callback(void) {
    return identity_callback;
}

/* Closure body: returns its first upvalue, proving that the captured value is
 * still visible after the closure is re-pushed and compared. */
static int upvalue_reader(lua_State *L) {
    lua_pushvalue(L, lua_upvalueindex(1));
    return 1;
}

/* Coroutine body: yields once with no values, then completes with no results
 * when resumed again. Returning lua_yield's result is the documented C pattern
 * for a yield without a continuation. */
static int yield_once(lua_State *L) {
    return lua_yield(L, 0);
}

/* Converts a function pointer to a data pointer through memcpy. C99 does not
 * define a function-pointer to object-pointer conversion, but lua_topointer
 * documents light C functions as their code address on every supported
 * platform. The assert guards the assumed size match. */
static const void *function_address(lua_CFunction function) {
    const void *address;
    assert(sizeof address == sizeof function);
    memcpy(&address, &function, sizeof address);
    return address;
}

/* Creates a fresh state over a zeroed counted allocator. The state is opened
 * with the standard libraries because tostring and string.format are the
 * Lua-side helpers the cases compare against. */
static lua_State *new_state(struct allocation_counts *counts) {
    lua_State *L;
    memset(counts, 0, sizeof *counts);
    L = lua_newstate(counted_allocator, counts, IDENTITY_SEED);
    assert(L != NULL);
    luaL_openlibs(L);
    assert(lua_gettop(L) == 0);
    return L;
}

/* Clears the stack, closes the state and checks that every block the allocator
 * handed out has been released. Returns 1 so cases can end with it. */
static int finish_state(lua_State *L, struct allocation_counts *counts) {
    lua_settop(L, 0);
    lua_close(L);
    assert(counts->bytes == 0 && counts->blocks == 0);
    return 1;
}

/* Pops the string on top of the stack and asserts that it has exactly the
 * expected bytes. The length check catches an embedded NUL that a strcmp
 * alone would hide. */
static void expect_top_string(lua_State *L, const char *expected) {
    size_t length;
    const char *actual = lua_tolstring(L, -1, &length);
    assert(actual != NULL);
    assert(length == strlen(expected));
    if (strcmp(actual, expected) != 0)
        fprintf(stderr, "pointer text mismatch: [%s] expected [%s]\n",
                actual, expected);
    assert(strcmp(actual, expected) == 0);
    lua_pop(L, 1);
}

/* Calls the Lua global tostring on the value at 'index' through the public
 * stack API and checks the returned string. The stack height is unchanged. */
static void check_lua_tostring(lua_State *L, int index, const char *expected) {
    int top = lua_gettop(L);
    lua_getglobal(L, "tostring");
    lua_pushvalue(L, index);
    lua_call(L, 1, 1);
    expect_top_string(L, expected);
    assert(lua_gettop(L) == top);
}

/* Calls string.format("%p", value) through the public API and checks the
 * returned string. string.format is looked up on the global string table at
 * each call so no Lua-side helper is cached across cases. */
static void check_lua_format_spec(lua_State *L, int index, const char *spec,
                                   const char *expected) {
    int top = lua_gettop(L);
    lua_getglobal(L, "string");
    lua_getfield(L, -1, "format");
    lua_pushstring(L, spec);
    lua_pushvalue(L, index);
    lua_call(L, 2, 1);
    expect_top_string(L, expected);
    lua_pop(L, 1); /* the string table */
    assert(lua_gettop(L) == top);
}

static void check_lua_format_pointer(lua_State *L, int index,
                                     const char *expected) {
    check_lua_format_spec(L, index, "%p", expected);
}

/* Checks one value's identity text. 'kind' is the luaL_tolstring type name
 * expected from the default branch (or the raw __name prefix). The address is
 * read from lua_topointer(L, index) and compared with 'ptr'. The expected
 * text is built natively from that same address. */
static void check_identity(lua_State *L, int index, const void *ptr,
                           const char *kind) {
    char native[POINTER_TEXT];
    char expected[IDENTITY_TEXT];
    const void *actual;
    int written;
    index = lua_absindex(L, index);
    actual = lua_topointer(L, index);
    assert(actual == ptr);
    written = snprintf(native, sizeof native, "%p", actual);
    assert(written > 0 && (size_t)written < sizeof native);
    written = snprintf(expected, sizeof expected, "%s: %s", kind, native);
    assert(written > 0 && (size_t)written < sizeof expected);
    /* luaL_tolstring's default branch: "<__name or type>: <pointer>". */
    luaL_tolstring(L, index, NULL);
    expect_top_string(L, expected);
    check_lua_tostring(L, index, expected);
    /* string.format("%p") prints the native spelling for every non-NULL
     * pointer. A NULL pointer is the documented "(null)" text instead. */
    check_lua_format_pointer(L, index, actual == NULL ? "(null)" : native);
    {
        static const char *const formats[] = {"%20p", "%-20p", "%99p",
                                               "%-99p"};
        size_t i;
        for (i = 0; i < sizeof formats / sizeof formats[0]; ++i) {
            char text[POINTER_TEXT];
            if (actual == NULL) {
                char format[8];
                size_t size = strlen(formats[i]);
                memcpy(format, formats[i], size + 1);
                format[size - 1] = 's';
                written = snprintf(text, sizeof text, format, "(null)");
            }
            else
                written = snprintf(text, sizeof text, formats[i], actual);
            assert(written > 0 && (size_t)written < sizeof text);
            check_lua_format_spec(L, index, formats[i], text);
        }
    }
}

/* Case 1: a table's pointer is stable across pushes and matches the default
 * tostring text. The metatable branch exercises the raw __name field with an
 * empty prefix and an embedded NUL. No __index or __tostring handler is set,
 * so luaL_tolstring's raw lookup is the only path taken. */
static int case_table_identity(void) {
    struct allocation_counts counts;
    lua_State *L = new_state(&counts);
    const void *table_pointer;
    lua_newtable(L); /* 1 */
    table_pointer = lua_topointer(L, 1);
    assert(table_pointer != NULL);
    lua_pushvalue(L, 1); /* 2: a second reference to the same table */
    assert(lua_topointer(L, 2) == table_pointer);
    check_identity(L, 1, table_pointer, "table");

    /* 3: metatable with an empty __name. Only the raw field is set. */
    lua_newtable(L);
    lua_pushstring(L, "");
    lua_setfield(L, 3, "__name");
    /* 4: object using the empty-name metatable. */
    lua_newtable(L);
    lua_pushvalue(L, 3);
    lua_setmetatable(L, 4);
    check_identity(L, 4, lua_topointer(L, 4), "");

    /* 5: metatable whose __name holds an embedded NUL after "x". The
     * formatting path reads C text, so only "x" is the displayed prefix. */
    lua_newtable(L);
    lua_pushlstring(L, "x\0y", 3);
    lua_setfield(L, 5, "__name");
    /* 6: object using the NUL-prefixed metatable. */
    lua_newtable(L);
    lua_pushvalue(L, 5);
    lua_setmetatable(L, 6);
    check_identity(L, 6, lua_topointer(L, 6), "x");
    return finish_state(L, &counts);
}

/* Case 2: full userdata. The payload pointer returned by lua_touserdata is
 * the identity; lua_topointer must agree with it. The payload is written and
 * re-read through lua_touserdata to show the block is the caller's storage. */
static int case_full_userdata_identity(void) {
    struct allocation_counts counts;
    lua_State *L = new_state(&counts);
    void *payload;
    unsigned char *bytes;
    payload = lua_newuserdatauv(L, 32, 1); /* 1 */
    assert(payload != NULL);
    memset(payload, 0x5a, 32);
    assert(lua_touserdata(L, 1) == payload);
    assert(lua_topointer(L, 1) == payload);
    bytes = (unsigned char *)lua_touserdata(L, 1);
    assert(bytes[0] == 0x5a && bytes[31] == 0x5a);
    check_identity(L, 1, payload, "userdata");
    return finish_state(L, &counts);
}

/* Case 3: light userdata with a nonnull caller-owned address. Two pushes of
 * the same address are equal values, and the identity text is the native
 * spelling of that address. */
static int case_light_userdata_identity(void) {
    struct allocation_counts counts;
    lua_State *L = new_state(&counts);
    lua_pushlightuserdata(L, caller_slot); /* 1 */
    lua_pushlightuserdata(L, caller_slot); /* 2 */
    assert(lua_rawequal(L, 1, 2));
    assert(lua_touserdata(L, 1) == (void *)caller_slot);
    assert(lua_topointer(L, 1) == (const void *)caller_slot);
    check_identity(L, 1, caller_slot, "userdata");
    return finish_state(L, &counts);
}

/* Case 4: NULL light userdata. lua_topointer and lua_touserdata both return
 * NULL. luaL_tolstring and the Lua tostring still print the native spelling
 * of NULL, while string.format("%p") prints the documented "(null)" text. */
static int case_null_light_userdata_identity(void) {
    struct allocation_counts counts;
    lua_State *L = new_state(&counts);
    lua_pushlightuserdata(L, NULL); /* 1 */
    assert(lua_touserdata(L, 1) == NULL);
    assert(lua_topointer(L, 1) == NULL);
    check_identity(L, 1, NULL, "userdata");
    return finish_state(L, &counts);
}

/* Case 5: light C function. Two pushes of the same function are the same
 * value, lua_topointer equals the function's code address, and calling the
 * function through the public API returns the native text of its argument's
 * address. The argument table is rooted before the call. */
static int case_light_cfunction_identity(void) {
    struct allocation_counts counts;
    lua_State *L = new_state(&counts);
    lua_CFunction callback = lua_ada_test_identity_callback();
    const void *table_pointer;
    char native[POINTER_TEXT];
    int written;
    lua_pushcfunction(L, callback); /* 1 */
    lua_pushcfunction(L, callback); /* 2 */
    assert(lua_rawequal(L, 1, 2));
    assert(lua_tocfunction(L, 1) == callback);
    assert(lua_topointer(L, 1) == function_address(callback));
    check_identity(L, 1, function_address(callback), "function");

    /* 3: the argument table, rooted on the stack before the call. */
    lua_newtable(L);
    table_pointer = lua_topointer(L, 3);
    assert(table_pointer != NULL);
    /* Calls the C callback with the rooted table as its first argument. */
    lua_pushvalue(L, 1); /* 4: function */
    lua_pushvalue(L, 3); /* 5: argument */
    lua_call(L, 1, 1);
    written = snprintf(native, sizeof native, "%p", table_pointer);
    assert(written > 0 && (size_t)written < sizeof native);
    expect_top_string(L, native);
    return finish_state(L, &counts);
}

/* Case 6: captured C closure. A closure built with one upvalue keeps the same
 * identity across pushes and reads back the captured value. A second closure
 * over the same code but a different upvalue is a distinct object and gets a
 * distinct address while both are live. */
static int case_captured_closure_identity(void) {
    struct allocation_counts counts;
    lua_State *L = new_state(&counts);
    const void *first;
    lua_pushinteger(L, 42);
    lua_pushcclosure(L, upvalue_reader, 1); /* 1 */
    first = lua_topointer(L, 1);
    assert(first != NULL);
    lua_pushvalue(L, 1); /* 2 */
    assert(lua_topointer(L, 2) == first);
    check_identity(L, 1, first, "function");
    /* Calls the closure; the captured value is still the one pushed above. */
    lua_pushvalue(L, 1);
    lua_call(L, 0, 1);
    assert(lua_tointeger(L, -1) == 42);
    lua_pop(L, 1);

    lua_pushinteger(L, 7);
    lua_pushcclosure(L, upvalue_reader, 1); /* 3 */
    assert(lua_topointer(L, 3) != first);
    check_identity(L, 3, lua_topointer(L, 3), "function");
    return finish_state(L, &counts);
}

/* Case 7: coroutine identity. The thread's pointer from lua_tothread and from
 * lua_topointer agree and match the default tostring text before the first
 * resume, after the yield, and after the coroutine completes. The thread
 * stays rooted on the stack in every phase. */
static int case_coroutine_identity(void) {
    struct allocation_counts counts;
    lua_State *L = new_state(&counts);
    lua_State *co;
    const void *thread_pointer;
    int nres = -1;
    int status;
    co = lua_newthread(L); /* 1: rooted in L */
    assert(co != NULL);
    thread_pointer = (const void *)lua_tothread(L, 1);
    assert(thread_pointer != NULL);
    assert(lua_topointer(L, 1) == thread_pointer);
    lua_pushcfunction(co, yield_once);
    check_identity(L, 1, thread_pointer, "thread");

    status = lua_resume(co, L, 0, &nres);
    assert(status == LUA_YIELD);
    assert(nres == 0);
    assert((const void *)lua_tothread(L, 1) == thread_pointer);
    assert(lua_topointer(L, 1) == thread_pointer);
    check_identity(L, 1, thread_pointer, "thread");

    status = lua_resume(co, L, 0, &nres);
    assert(status == LUA_OK);
    assert((const void *)lua_tothread(L, 1) == thread_pointer);
    assert(lua_topointer(L, 1) == thread_pointer);
    check_identity(L, 1, thread_pointer, "thread");
    return finish_state(L, &counts);
}

/* Case 8: use the public identity without asserting any private relationship
 * to string byte storage. tostring and luaL_tolstring return the string
 * value itself, while format uses the public lua_topointer identity. */
static int case_raw_string_identity(void) {
    struct allocation_counts counts;
    lua_State *L = new_state(&counts);
    const char *data;
    const void *object;
    char native[POINTER_TEXT];
    int written;
    lua_pushstring(L, "identity"); /* 1 */
    data = lua_tostring(L, 1);
    object = lua_topointer(L, 1);
    assert(data != NULL && object != NULL);

    /* The string value itself is the text, for both luaL_tolstring and the
     * Lua tostring global, so no address text is involved here. */
    luaL_tolstring(L, 1, NULL);
    expect_top_string(L, "identity");
    check_lua_tostring(L, 1, "identity");

    /* %p formats the actual public identity, independent of byte storage. */
    written = snprintf(native, sizeof native, "%p", object);
    assert(written > 0 && (size_t)written < sizeof native);
    check_lua_format_pointer(L, 1, native);
    return finish_state(L, &counts);
}

struct identity_case {
    const char *name;
    int (*run)(void);
};

static const struct identity_case identity_cases[] = {
    {"table-identity", case_table_identity},
    {"full-userdata-identity", case_full_userdata_identity},
    {"light-userdata-identity", case_light_userdata_identity},
    {"null-light-userdata-identity", case_null_light_userdata_identity},
    {"light-cfunction-identity", case_light_cfunction_identity},
    {"captured-closure-identity", case_captured_closure_identity},
    {"coroutine-identity", case_coroutine_identity},
    {"raw-string-identity", case_raw_string_identity}
};

#define IDENTITY_CASE_COUNT \
    (sizeof(identity_cases) / sizeof(identity_cases[0]))

/* Bridge for an external runner (for example AUnit). Returns 1 when case
 * 'which' passes, and 0 for an index past IDENTITY_CASE_COUNT. A failed check
 * aborts through assert, so a 0 return never hides a partial failure. */
int lua_ada_test_identity(unsigned which) {
    if (which >= IDENTITY_CASE_COUNT) return 0;
    return identity_cases[which].run();
}

#ifndef LUA_ADA_POINTER_IDENTITY_CONTRACT_LIBRARY
int main(void) {
    unsigned int i;
    for (i = 0; i < IDENTITY_CASE_COUNT; i++) {
        assert(lua_ada_test_identity(i));
        printf("PASS: pointer-identity-%s\n", identity_cases[i].name);
        fflush(stdout);
    }
    puts("PASS: public pointer identity contract");
    return EXIT_SUCCESS;
}
#endif
