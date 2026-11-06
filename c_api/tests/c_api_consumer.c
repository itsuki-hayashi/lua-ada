/* Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE.
 * This is an ordinary C main using pinned public headers and the real Ada
 * library. It never calls an Ada initialization/finalization routine. */
#include "lua.h"
#include "lauxlib.h"
#include "lua_ada_boundary.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

static void test_state_allocator_lifetime(void) {
    /* Setup a real allocator callback. Construction must invoke it, querying
     * preserves callback/data identity, and closing releases every raw block. */
    struct allocation_counts counts = {0};
    void *data = NULL;
    lua_State *state = lua_newstate(counted_allocator, &counts, 872641U);
    assert(state != NULL && counts.bytes > 0 && counts.calls > 0);
    assert(lua_getallocf(state, &data) == counted_allocator && data == &counts);
    lua_setallocf(state, counted_allocator, &counts);
    lua_close(state);
    assert(counts.bytes == 0 && counts.blocks == 0);
    puts("C API PASS: state allocator lifetime");
}

static void test_constructor_refusal(void) {
    /* Refusal is a null constructor result rather than an Ada exception,
     * panic or leaked partially initialized universe. Then allow recovery. */
    struct allocation_counts counts = {0};
    counts.refuse = 1;
    lua_State *state = lua_newstate(counted_allocator, &counts, 17U);
    assert(state == NULL && counts.bytes == 0 && counts.blocks == 0);
    counts.refuse = 0;
    state = lua_newstate(counted_allocator, &counts, 17U);
    assert(state != NULL);
    lua_close(state);
    assert(counts.bytes == 0 && counts.blocks == 0);
    puts("C API PASS: constructor refusal and recovery");
}

static void test_cold_constructor_failure_sweep(void) {
    /* Measure the actual managed growth sequence, then refuse each growth
     * position persistently in a fresh universe. Every partial construction
     * must return null and release all earlier callback-owned allocations. */
    struct allocation_counts baseline = {0};
    lua_State *state = lua_newstate(counted_allocator, &baseline, 872641U);
    size_t limit, growths;
    assert(state != NULL);
    growths = baseline.growths;
    assert(growths > 0);
    lua_close(state);
    assert(baseline.bytes == 0 && baseline.blocks == 0);
    for (limit = 1; limit <= growths; limit++) {
        struct allocation_counts counts = {0};
        counts.fail_after = limit;
        state = lua_newstate(counted_allocator, &counts, 872641U);
        if (state != NULL) {
            fprintf(stderr, "unexpected constructor success at growth %zu/%zu\n",
                    limit, growths);
            lua_close(state);
            abort();
        }
        assert(counts.growths >= limit);
        assert(counts.bytes == 0 && counts.blocks == 0);
    }
    {
        struct allocation_counts counts = {0};
        counts.fail_after = growths + 1;
        state = lua_newstate(counted_allocator, &counts, 872641U);
        assert(state != NULL);
        lua_close(state);
        assert(counts.bytes == 0 && counts.blocks == 0);
    }
    printf("C API PASS: cold constructor failure sweep (%zu growth points)\n", growths);
}

static int allocation_failure(lua_State *state) {
    lua_pushstring(state, "a fresh C-owned allocator refusal target");
    assert(!"refused string allocation unexpectedly returned to C body");
    return 0;
}

static void test_guarded_allocator_refusal_and_recovery(void) {
    /* Exhaust the actual provider after initialization. The reserved error
     * slot must expose the real preallocated error object without allocation,
     * and the provider may be restored for further operations on this state. */
    struct allocation_counts counts = {0};
    lua_State *state = lua_newstate(counted_allocator, &counts, 99U);
    assert(state != NULL);
    counts.fail_after = counts.growths + 1;
    assert(lua_ada_guard_probe(state, allocation_failure) == LUA_ERRMEM);
    assert(lua_type(state, -1) == LUA_TSTRING);
    assert(strcmp(lua_tostring(state, -1), "not enough memory") == 0);
    counts.fail_after = 0;
    lua_settop(state, 0);
    lua_pushstring(state, "recovered");
    assert(strcmp(lua_tostring(state, -1), "recovered") == 0);
    lua_close(state);
    assert(counts.bytes == 0 && counts.blocks == 0);
    puts("C API PASS: guarded allocator refusal and recovery");
}

static void test_constructor_leaves_standard_libraries_closed(lua_State *state) {
    /* Neither lua_newstate nor luaL_newstate opens libraries. The C facade
     * must not inherit the eager default globals used by Ada embedding. */
    lua_settop(state, 0);
    assert(lua_rawgeti(state, LUA_REGISTRYINDEX, LUA_RIDX_GLOBALS) == LUA_TTABLE);
    lua_pushstring(state, "_VERSION");
    assert(lua_rawget(state, 1) == LUA_TNIL);
    lua_pop(state, 1);
    lua_pushstring(state, "print");
    assert(lua_rawget(state, 1) == LUA_TNIL);
    lua_settop(state, 0);
    puts("C API PASS: constructors leave libraries closed");
}

static void test_stack_rotation_copy_and_bounds(lua_State *state) {
    /* Stack indices must be resolved before mutation. Cover negative index
     * rotation, nil extension, copying, truncation and impossible growth. */
    lua_settop(state, 0);
    lua_pushinteger(state, 11);
    lua_pushinteger(state, 22);
    lua_pushinteger(state, 33);
    assert(lua_absindex(state, -2) == 2);
    lua_rotate(state, -3, 1);
    assert(lua_tointeger(state, 1) == 33 && lua_tointeger(state, 3) == 22);
    lua_rotate(state, 1, -1);
    assert(lua_tointeger(state, 1) == 11 && lua_tointeger(state, 3) == 33);
    lua_copy(state, 1, -1);
    assert(lua_tointeger(state, 3) == 11);
    lua_settop(state, 5);
    assert(lua_gettop(state) == 5 && lua_type(state, -1) == LUA_TNIL);
    assert(lua_type(state, 6) == LUA_TNONE);
    assert(lua_checkstack(state, -1) == 0);
    assert(lua_checkstack(state, INT_MAX) == 0);
    assert(lua_checkstack(state, 64) != 0);
    lua_settop(state, -3);
    assert(lua_gettop(state) == 3);
    puts("C API PASS: stack rotation copy and bounds");
}

static void test_numeric_conversions(lua_State *state) {
    /* Lua integers and floats remain distinct, while numeric byte strings
     * convert without forcing the stored value to change its original type. */
    int valid;
    lua_settop(state, 0);
    lua_pushinteger(state, LLONG_MIN);
    assert(lua_isinteger(state, 1));
    assert(lua_tointegerx(state, 1, &valid) == LLONG_MIN && valid);
    lua_pushnumber(state, 2.5);
    assert(!lua_isinteger(state, 2));
    (void)lua_tointegerx(state, 2, &valid);
    assert(!valid);
    lua_pushstring(state, "0x1.8p1");
    assert(lua_isnumber(state, 3));
    assert(lua_tonumberx(state, 3, &valid) == 3.0 && valid);
    assert(lua_type(state, 3) == LUA_TSTRING);
    lua_pushboolean(state, 0);
    lua_pushinteger(state, 0);
    assert(!lua_toboolean(state, 4) && lua_toboolean(state, 5));
    puts("C API PASS: numeric conversions");
}

static void test_binary_strings_and_stable_addresses(lua_State *state) {
    /* Hold the first byte pointer while later allocations grow storage.
     * Embedded NUL/high bytes, the terminator and numeric conversion matter. */
    const char bytes[] = {'a', 0, (char)255, 'z'};
    const char *saved;
    size_t length;
    int index;
    lua_settop(state, 0);
    saved = lua_pushlstring(state, bytes, sizeof bytes);
    for (index = 0; index < 512; index++) lua_pushstring(state, "later");
    assert(lua_tolstring(state, 1, &length) == saved && length == sizeof bytes);
    assert(memcmp(saved, bytes, sizeof bytes) == 0 && saved[length] == 0);
    lua_settop(state, 1);
    lua_pushinteger(state, 123);
    assert(strcmp(lua_tostring(state, -1), "123") == 0);
    assert(lua_type(state, -1) == LUA_TSTRING);
    assert(lua_pushstring(state, NULL) == NULL && lua_isnil(state, -1));
    puts("C API PASS: binary strings and stable addresses");
}

static void test_raw_tables_and_pointer_identity(lua_State *state) {
    /* Raw operations bypass metamethod dispatch, preserve integer keys and
     * distinguish a null light-userdata key from nil. Iteration sees real rows. */
    int key, count = 0;
    lua_settop(state, 0);
    lua_newtable(state);
    lua_pushstring(state, "value"); lua_rawseti(state, 1, 7);
    assert(lua_rawgeti(state, 1, 7) == LUA_TSTRING);
    assert(strcmp(lua_tostring(state, -1), "value") == 0);
    lua_pop(state, 1);
    lua_pushinteger(state, 91); lua_rawsetp(state, 1, &key);
    assert(lua_rawgetp(state, 1, &key) == LUA_TNUMBER);
    assert(lua_tointeger(state, -1) == 91); lua_pop(state, 1);
    lua_pushlightuserdata(state, NULL);
    assert(lua_type(state, -1) == LUA_TLIGHTUSERDATA);
    assert(lua_touserdata(state, -1) == NULL);
    lua_pushboolean(state, 1); lua_rawset(state, 1);
    lua_pushlightuserdata(state, NULL); lua_rawget(state, 1);
    assert(lua_toboolean(state, -1)); lua_pop(state, 1);
    lua_pushnil(state);
    while (lua_next(state, 1)) { count++; lua_pop(state, 1); }
    assert(count == 3 && lua_gettop(state) == 1);
    lua_pushvalue(state, 1);
    assert(lua_rawequal(state, 1, 2));
    assert(lua_topointer(state, 1) == lua_topointer(state, 2));
    puts("C API PASS: raw tables and pointer identity");
}

static void test_threads_registry_extra_space_and_moves(lua_State *state) {
    /* New thread surfaces share the owning universe but have independent
     * stacks. Extra space is copied from main, and registry indices are real. */
    lua_State *thread;
    unsigned char *extra = (unsigned char *)lua_getextraspace(state);
    size_t index;
    lua_settop(state, 0);
    for (index = 0; index < LUA_EXTRASPACE; index++) extra[index] = (unsigned char)(index + 3);
    thread = lua_newthread(state);
    assert(thread != NULL && lua_tothread(state, -1) == thread);
    assert(memcmp(lua_getextraspace(thread), extra, LUA_EXTRASPACE) == 0);
    assert(lua_gettop(thread) == 0);
    lua_pushinteger(state, 41); lua_pushinteger(state, 42);
    lua_xmove(state, thread, 2);
    assert(lua_gettop(state) == 1 && lua_gettop(thread) == 2);
    assert(lua_tointeger(thread, 1) == 41 && lua_tointeger(thread, 2) == 42);
    assert(lua_pushthread(thread) == 0 && lua_tothread(thread, -1) == thread);
    assert(lua_rawgeti(thread, LUA_REGISTRYINDEX, LUA_RIDX_MAINTHREAD) == LUA_TTHREAD);
    assert(lua_tothread(thread, -1) == state);
    assert(lua_rawgeti(state, LUA_REGISTRYINDEX, LUA_RIDX_GLOBALS) == LUA_TTABLE);
    puts("C API PASS: threads registry extra space and moves");
}

static int raw_nil_failure(lua_State *state) {
    lua_newtable(state);
    lua_pushnil(state);
    lua_pushinteger(state, 1);
    lua_rawset(state, -3);
    assert(!"failing Ada operation unexpectedly returned to C body");
    return 0;
}

static void test_c_owned_guard_and_recovery(lua_State *state) {
    /* A real exported raw setter fails inside Ada. The boundary returns its
     * action before the C guard jumps, and the same state remains usable. */
    lua_settop(state, 0);
    assert(lua_ada_guard_probe(state, raw_nil_failure) == LUA_ERRRUN);
    assert(lua_type(state, -1) == LUA_TSTRING);
    assert(strstr(lua_tostring(state, -1), "nil") != NULL);
    lua_settop(state, 0);
    lua_pushinteger(state, 62);
    assert(lua_tointeger(state, -1) == 62);
    puts("C API PASS: C-owned guard and recovery");
}

static int add_callback(lua_State *state) {
    /* Positive/negative indices address this callback's arguments, not the
     * retained caller prefix. The callback returns only its newly pushed sum. */
    assert(lua_gettop(state) == 2);
    assert(lua_absindex(state, -1) == 2);
    lua_pushinteger(state, lua_tointeger(state, 1) + lua_tointeger(state, 2));
    return 1;
}

static int captured_counter(lua_State *state) {
    lua_Integer next = lua_tointeger(state, lua_upvalueindex(1)) + 1;
    assert(lua_gettop(state) == 0);
    lua_pushinteger(state, next);
    lua_copy(state, -1, lua_upvalueindex(1));
    return 1;
}

static int error_callback(lua_State *state) {
    lua_pushvalue(state, 1);
    return lua_error(state);
}

static int nested_callback(lua_State *state) {
    assert(lua_gettop(state) == 1 && lua_tointeger(state, 1) == 40);
    lua_pushcfunction(state, add_callback);
    lua_pushvalue(state, 1);
    lua_pushinteger(state, 1);
    lua_call(state, 2, 1);
    assert(lua_gettop(state) == 2 && lua_tointeger(state, 1) == 40);
    lua_pushinteger(state, lua_tointeger(state, -1) + 1);
    return 1;
}

static void test_light_c_function_identity(lua_State *state) {
    /* Zero-upvalue C functions have pointer identity without allocating a
     * distinct native closure for each push. A different pointer differs. */
    lua_settop(state, 0);
    lua_pushcfunction(state, add_callback);
    lua_pushcfunction(state, add_callback);
    lua_pushcfunction(state, error_callback);
    assert(lua_type(state, 1) == LUA_TFUNCTION && lua_iscfunction(state, 1));
    assert(lua_tocfunction(state, 1) == add_callback);
    assert(lua_rawequal(state, 1, 2) && !lua_rawequal(state, 1, 3));
    puts("C API PASS: light C function identity");
}

static void test_callback_stack_window(lua_State *state) {
    /* Keep a sentinel below the callee/arguments. The real C callback must
     * see only its two arguments, and fixed-result adjustment appends nil. */
    int status;
    lua_settop(state, 0);
    lua_pushstring(state, "caller");
    lua_pushcfunction(state, add_callback);
    lua_pushinteger(state, 20);
    lua_pushinteger(state, 22);
    status = lua_pcall(state, 2, 2, 0);
    if (status != LUA_OK)
        fprintf(stderr, "callback status=%d error=%s\n", status,
                lua_tostring(state, -1));
    assert(status == LUA_OK);
    assert(lua_gettop(state) == 3);
    assert(strcmp(lua_tostring(state, 1), "caller") == 0);
    assert(lua_tointeger(state, 2) == 42 && lua_isnil(state, 3));
    puts("C API PASS: callback stack window and results");
}

static void test_c_closure_cells(lua_State *state) {
    /* A nonzero-upvalue C closure owns real mutable cells. Updating through
     * a pseudo-index must persist across independent calls to that closure. */
    lua_settop(state, 0);
    lua_pushinteger(state, 40);
    lua_pushcclosure(state, captured_counter, 1);
    assert(lua_tocfunction(state, 1) == captured_counter);
    lua_pushvalue(state, 1);
    lua_call(state, 0, 1);
    assert(lua_tointeger(state, -1) == 41);
    lua_pop(state, 1);
    lua_pushvalue(state, 1);
    lua_call(state, 0, 1);
    assert(lua_tointeger(state, -1) == 42);
    puts("C API PASS: C closure mutable cells");
}

static void test_protected_c_error_identity(lua_State *state) {
    /* lua_error longjmps only over the C callback, after its failing Ada API
     * entry returned. lua_pcall receives the same table object and recovers. */
    const void *identity;
    lua_settop(state, 0);
    lua_newtable(state);
    identity = lua_topointer(state, 1);
    lua_pushcfunction(state, error_callback);
    lua_pushvalue(state, 1);
    assert(lua_pcall(state, 1, LUA_MULTRET, 0) == LUA_ERRRUN);
    assert(lua_gettop(state) == 2 && lua_topointer(state, 2) == identity);
    lua_settop(state, 0);
    lua_pushcfunction(state, add_callback);
    lua_pushinteger(state, 1); lua_pushinteger(state, 2);
    assert(lua_pcall(state, 2, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 3);
    puts("C API PASS: protected C error identity and recovery");
}

static void test_reentrant_c_to_c_calls(lua_State *state) {
    /* The outer C callback requests a nested call while its own C guard is
     * active. Both pumps must use one iterative scheduler and distinct bases. */
    lua_settop(state, 0);
    lua_pushcfunction(state, nested_callback);
    lua_pushinteger(state, 40);
    assert(lua_pcall(state, 1, 1, 0) == LUA_OK);
    assert(lua_gettop(state) == 1 && lua_tointeger(state, 1) == 42);
    puts("C API PASS: reentrant C calls on one scheduler");
}

static void test_canonical_lua_calls_c(lua_State *state) {
    /* Load real canonical Lua, then pass it a real C function. This is code
     * execution through the Ada compiler/VM, never a linked C interpreter. */
    const char *source = "local f=...;return f(20,22),f(1,2)";
    lua_settop(state, 0);
    assert(luaL_loadbufferx(state, source, strlen(source), "=c-callback", "t")
           == LUA_OK);
    lua_pushcfunction(state, add_callback);
    assert(lua_pcall(state, 1, LUA_MULTRET, 0) == LUA_OK);
    assert(lua_gettop(state) == 2);
    assert(lua_tointeger(state, 1) == 42 && lua_tointeger(state, 2) == 3);
    lua_settop(state, 0);
    assert(luaL_loadbufferx(state, "return )", 8, "=bad-source", "t")
           == LUA_ERRSYNTAX);
    assert(lua_type(state, -1) == LUA_TSTRING);
    puts("C API PASS: canonical Lua calls C and load errors");
}

static void test_loadstring_requires_text(lua_State *state) {
    /* The auxiliary convenience entry uses text mode even though loadbufferx
     * accepts either format by default. Reject a binary signature before the
     * decoder inspects its truncated header, then prove recovery with text. */
    lua_settop(state, 0);
    assert(luaL_loadstring(state, LUA_SIGNATURE) == LUA_ERRSYNTAX);
    assert(strstr(lua_tostring(state, -1), "mode") != NULL);
    assert(strstr(lua_tostring(state, -1), "'t'") != NULL);
    lua_settop(state, 0);
    assert(luaL_loadstring(state, "return 42") == LUA_OK);
    assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 42);
    puts("C API PASS: loadstring requires text mode and recovers");
}

int main(void) {
    lua_State *state;
    test_state_allocator_lifetime();
    test_constructor_refusal();
    test_cold_constructor_failure_sweep();
    test_guarded_allocator_refusal_and_recovery();
    state = luaL_newstate();
    assert(state != NULL && lua_version(state) == LUA_VERSION_NUM);
    test_constructor_leaves_standard_libraries_closed(state);
    test_stack_rotation_copy_and_bounds(state);
    test_numeric_conversions(state);
    test_binary_strings_and_stable_addresses(state);
    test_raw_tables_and_pointer_identity(state);
    test_threads_registry_extra_space_and_moves(state);
    test_c_owned_guard_and_recovery(state);
    test_light_c_function_identity(state);
    test_callback_stack_window(state);
    test_c_closure_cells(state);
    test_protected_c_error_identity(state);
    test_reentrant_c_to_c_calls(state);
    test_canonical_lua_calls_c(state);
    test_loadstring_requires_text(state);
    lua_close(state);
    puts("PASS: real Ada C API bootstrap consumer");
    return 0;
}
