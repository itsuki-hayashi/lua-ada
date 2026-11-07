/* Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE.
 * This is an ordinary C main using pinned public headers and the real Ada
 * library. It never calls an Ada initialization/finalization routine. */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "lua_ada_boundary.h"
#include <assert.h>
#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "consumer_allocator.h"

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

static void test_number_macro_without_validity_output(lua_State *state) {
    /* The public convenience macro passes a null isnum pointer. Exercise
     * successful and failed conversion through that expansion, not merely
     * the corresponding function with a writable validity output. */
    lua_settop(state, 0);
    lua_pushstring(state, "0x1.8p1");
    assert(lua_tonumber(state, 1) == 3.0);
    assert(lua_type(state, 1) == LUA_TSTRING);
    lua_pushstring(state, "not a number");
    assert(lua_tonumber(state, 2) == 0.0);
    lua_pushnil(state);
    assert(lua_tonumber(state, 3) == 0.0);
    assert(lua_tonumber(state, 4) == 0.0);
    assert(lua_gettop(state) == 3);
    puts("C API PASS: number macro with null validity output");
}

static void test_none_or_nil_macro(lua_State *state) {
    /* Optional arguments distinguish missing/nil from a supplied false or
     * zero value. These checks run in the ordinary consumer in both builds. */
    lua_settop(state, 0);
    assert(lua_isnoneornil(state, 1));
    lua_pushnil(state);
    assert(lua_isnoneornil(state, 1));
    lua_pushboolean(state, 0);
    lua_pushinteger(state, 0);
    assert(!lua_isnoneornil(state, 2));
    assert(!lua_isnoneornil(state, -1));
    assert(lua_isnoneornil(state, 4));
    assert(lua_gettop(state) == 3);
    puts("C API PASS: optional argument none or nil macro");
}

static void test_global_table_macro(lua_State *state) {
    /* The macro pushes the registry-owned environment with exactly one new
     * stack slot. Its identity must agree with the public registry lookup. */
    const void *identity;
    lua_settop(state, 0);
    lua_pushglobaltable(state);
    assert(lua_gettop(state) == 1 && lua_istable(state, 1));
    identity = lua_topointer(state, 1);
    assert(identity != NULL);
    assert(lua_rawgeti(state, LUA_REGISTRYINDEX, LUA_RIDX_GLOBALS) == LUA_TTABLE);
    assert(lua_gettop(state) == 2 && lua_topointer(state, 2) == identity);
    lua_settop(state, 0);
    puts("C API PASS: registry-owned global table macro");
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

static int message_calls;

static int integer_message_handler(lua_State *state) {
    message_calls++;
    assert(lua_gettop(state) == 1);
    lua_pushinteger(state, 42);
    return 1;
}

static int empty_message_handler(lua_State *state) {
    (void)state;
    return 0;
}

static int recursive_message_handler(lua_State *state) {
    if (lua_type(state, 1) != LUA_TNUMBER) {
        lua_pushvalue(state, 1);
        return 1;
    }
    if (lua_tointeger(state, 1) == 0) {
        lua_pushliteral(state, "END");
        return 1;
    }
    lua_pushinteger(state, lua_tointeger(state, 1) - 1);
    return lua_error(state);
}

static int failing_message_handler(lua_State *state) {
    lua_pushliteral(state, "handler failed");
    return lua_error(state);
}

static void test_message_handler_results(lua_State *state) {
    /* Error handlers receive the actual arbitrary error and adjust to exactly
     * one result. They must not run on successful calls. The handler's stack
     * index remains valid while the callee and its arguments are consumed. */
    lua_settop(state, 0);
    message_calls = 0;
    lua_pushcfunction(state, integer_message_handler);
    lua_pushcfunction(state, add_callback);
    lua_pushinteger(state, 20); lua_pushinteger(state, 22);
    assert(lua_pcall(state, 2, 1, 1) == LUA_OK && message_calls == 0);
    lua_settop(state, 1);
    lua_pushcfunction(state, error_callback);
    lua_newtable(state);
    assert(lua_pcall(state, 1, LUA_MULTRET, 1) == LUA_ERRRUN);
    assert(message_calls == 1 && lua_gettop(state) == 2);
    assert(lua_tointeger(state, -1) == 42);
    lua_settop(state, 0);
    lua_pushcfunction(state, empty_message_handler);
    lua_pushcfunction(state, error_callback);
    lua_pushinteger(state, 7);
    assert(lua_pcall(state, 1, 1, 1) == LUA_ERRRUN);
    assert(strcmp(lua_tostring(state, -1), "<no error object>") == 0);
    puts("C API PASS: message handler results and nil normalization");
}

static void test_recursive_message_handler(lua_State *state) {
    /* A handler may raise a different error which the same handler eventually
     * resolves. This is recursive error handling, not nested pcall success. */
    lua_settop(state, 0);
    lua_pushcfunction(state, recursive_message_handler);
    lua_pushcfunction(state, error_callback);
    lua_pushinteger(state, 170);
    assert(lua_pcall(state, 1, 1, 1) == LUA_ERRRUN);
    assert(strcmp(lua_tostring(state, -1), "END") == 0);
    lua_settop(state, 1);
    lua_pushcfunction(state, error_callback);
    lua_pushinteger(state, 300);
    assert(lua_pcall(state, 1, 1, 1) == LUA_ERRRUN);
    assert(strstr(lua_tostring(state, -1), "C stack overflow") != NULL);
    puts("C API PASS: recursively transformed message errors");
}

static void test_error_in_message_handler(lua_State *state) {
    /* A handler that can never return exhausts the configured error reserve.
     * The protected API returns ERRERR and a real stable error object. */
    lua_settop(state, 0);
    lua_pushcfunction(state, failing_message_handler);
    lua_pushcfunction(state, error_callback);
    lua_pushinteger(state, 1);
    assert(lua_pcall(state, 1, 1, 1) == LUA_ERRERR);
    assert(strcmp(lua_tostring(state, -1), "error in error handling") == 0);
    lua_settop(state, 0);
    lua_pushcfunction(state, add_callback);
    lua_pushinteger(state, 1); lua_pushinteger(state, 2);
    assert(lua_pcall(state, 2, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 3);
    puts("C API PASS: error-handler failure status and recovery");
}

static int unprotected_nested_error(lua_State *state) {
    lua_pushcfunction(state, error_callback);
    lua_pushinteger(state, 7);
    lua_call(state, 1, 0);
    assert(!"nested error returned to its abandoned C body");
    return 0;
}

static void test_inherited_handler_runs_once(lua_State *state) {
    /* An unprotected nested call inherits the outer handler. The transformed
     * error crosses a C guard afterward, carrying its handled bit; processing
     * it again would visibly call this handler twice. */
    lua_settop(state, 0);
    message_calls = 0;
    lua_pushcfunction(state, integer_message_handler);
    lua_pushcfunction(state, unprotected_nested_error);
    assert(lua_pcall(state, 0, 1, 1) == LUA_ERRRUN);
    assert(message_calls == 1 && lua_tointeger(state, -1) == 42);
    puts("C API PASS: inherited handler crosses C guard once");
}

static void test_lua_message_handler(lua_State *state) {
    /* The handler itself may be an actual canonical Lua closure. It receives
     * the same table object and returns a field through normal VM adjustment. */
    lua_settop(state, 0);
    assert(luaL_loadstring(state, "return function(e)return e.code end")
           == LUA_OK);
    lua_call(state, 0, 1);
    assert(lua_isfunction(state, 1) && !lua_iscfunction(state, 1));
    lua_pushcfunction(state, error_callback);
    lua_newtable(state);
    lua_pushstring(state, "code");
    lua_pushinteger(state, 42);
    lua_rawset(state, -3);
    assert(lua_pcall(state, 1, 1, 1) == LUA_ERRRUN);
    assert(lua_tointeger(state, -1) == 42);
    puts("C API PASS: canonical Lua message handler");
}

static int memory_failure_callback(lua_State *state) {
    void *data;
    (void)lua_getallocf(state, &data);
    ((struct allocation_counts *)data)->refuse = 1;
    lua_pushliteral(state, "force a real managed callback allocation refusal");
    return 1;
}

static void test_protected_callback_memory_failure(void) {
    /* Refusal begins inside the callback and remains active until pcall has
     * returned to ordinary C. Publishing false/error must allocate nothing;
     * host-side refusal reset then permits the same state to execute again. */
    struct allocation_counts counts = {0};
    lua_State *state = lua_newstate(counted_allocator, &counts, 123);
    int status;
    assert(state != NULL);
    lua_pushcfunction(state, memory_failure_callback);
    status = lua_pcall(state, 0, 1, 0);
    counts.refuse = 0;
    assert(status == LUA_ERRMEM);
    assert(strstr(lua_tostring(state, -1), "memory") != NULL);
    lua_settop(state, 0);
    lua_pushcfunction(state, add_callback);
    lua_pushinteger(state, 20); lua_pushinteger(state, 22);
    assert(lua_pcall(state, 2, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 42);
    lua_close(state);
    assert(counts.bytes == 0 && counts.blocks == 0);
    puts("C API PASS: protected callback memory failure and recovery");
}

static jmp_buf panic_target;

static int capture_panic(lua_State *state) {
    assert(lua_type(state, -1) == LUA_TSTRING);
    assert(strstr(lua_tostring(state, -1), "call") != NULL);
    longjmp(panic_target, 1);
}

static void test_panic_after_ada_returns(lua_State *state) {
    /* A host panic may jump to its own C checkpoint. The failed driver must
     * already be released: a later protected call proves logical recovery. */
    lua_CFunction previous = lua_atpanic(state, capture_panic);
    lua_settop(state, 0);
    if (setjmp(panic_target) == 0) {
        lua_pushinteger(state, 7);
        lua_call(state, 0, 0);
        assert(!"non-callable unprotected call returned");
    }
    lua_atpanic(state, previous);
    lua_settop(state, 0);
    lua_pushcfunction(state, add_callback);
    lua_pushinteger(state, 20); lua_pushinteger(state, 22);
    assert(lua_pcall(state, 2, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 42);
    puts("C API PASS: panic after Ada return and state recovery");
}

static int another_universe_callback(lua_State *state) {
    lua_State *other = (lua_State *)lua_touserdata(state, lua_upvalueindex(1));
    lua_settop(other, 0);
    lua_pushcfunction(other, add_callback);
    lua_pushinteger(other, 20); lua_pushinteger(other, 22);
    assert(lua_pcall(other, 2, 1, 0) == LUA_OK);
    lua_pushinteger(state, lua_tointeger(other, -1));
    lua_settop(other, 0);
    return 1;
}

static void test_reentrant_independent_universes(lua_State *state) {
    /* Call another owned universe while the first callback is active. There
     * must be no process-global current-world pointer or shared C stack base. */
    lua_State *other = luaL_newstate();
    assert(other != NULL);
    lua_settop(state, 0);
    lua_pushlightuserdata(state, other);
    lua_pushcclosure(state, another_universe_callback, 1);
    assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 42 && lua_gettop(other) == 0);
    lua_close(other);
    puts("C API PASS: reentrant independent universes");
}

union userdata_max_alignment {
    long double real;
    long long integer;
    void *pointer;
};
struct userdata_alignment_probe {
    char prefix;
    union userdata_max_alignment value;
};

static void test_userdata_payload_alignment(lua_State *state) {
    const size_t lengths[] = {0, 1, 3, 17, 97};
    const size_t alignment = offsetof(struct userdata_alignment_probe, value);
    size_t i;
    void *empty = NULL;
    lua_settop(state, 0);
    /* Each pointer is the actual writable payload, never a copied address
     * token. Keep all values rooted while comparing their zero-size identity
     * and verifying bytes after unrelated managed allocations. */
    for (i = 0; i < sizeof lengths / sizeof lengths[0]; ++i) {
        unsigned char *payload = lua_newuserdatauv(state, lengths[i], 0);
        assert(payload != NULL && (uintptr_t)payload % alignment == 0);
        assert(lua_type(state, -1) == LUA_TUSERDATA);
        assert(lua_isuserdata(state, -1));
        assert(lua_rawlen(state, -1) == lengths[i]);
        assert(lua_touserdata(state, -1) == payload);
        assert(lua_topointer(state, -1) == payload);
        if (lengths[i] != 0) memset(payload, (int)(i + 1), lengths[i]);
        if (i == 0) empty = payload;
    }
    assert(lua_newuserdatauv(state, 0, 0) != empty);
    for (i = 1; i < sizeof lengths / sizeof lengths[0]; ++i) {
        size_t byte;
        const unsigned char *payload = lua_touserdata(state, (int)i + 1);
        for (byte = 0; byte < lengths[i]; ++byte)
            assert(payload[byte] == (unsigned char)(i + 1));
    }
    lua_settop(state, 0);
    puts("C API PASS: aligned stable userdata payloads");
}

static void test_userdata_uservalue_results(lua_State *state) {
    int top, number;
    lua_settop(state, 0);
    lua_newuserdatauv(state, 1, 3);
    for (number = 1; number <= 3; ++number) {
        assert(lua_getiuservalue(state, 1, number) == LUA_TNIL);
        assert(lua_isnil(state, -1));
        lua_pop(state, 1);
    }
    /* A successful nil get and an invalid index both push nil, but only the
     * latter returns LUA_TNONE. Invalid sets still pop their source value. */
    top = lua_gettop(state);
    assert(lua_getiuservalue(state, 1, 0) == LUA_TNONE);
    assert(lua_isnil(state, -1) && lua_gettop(state) == top + 1);
    lua_pop(state, 1);
    lua_pushliteral(state, "owned uservalue");
    assert(lua_setiuservalue(state, 1, 2) == 1);
    assert(lua_gettop(state) == top);
    assert(lua_getiuservalue(state, 1, 2) == LUA_TSTRING);
    assert(strcmp(lua_tostring(state, -1), "owned uservalue") == 0);
    lua_pop(state, 1);
    lua_pushinteger(state, 42);
    assert(lua_setiuservalue(state, 1, -1) == 0);
    assert(lua_gettop(state) == top);
    lua_pushinteger(state, 42);
    assert(lua_setiuservalue(state, 1, 4) == 0);
    assert(lua_gettop(state) == top);
    lua_settop(state, 0);
    puts("C API PASS: userdata uservalue count and pop rules");
}

static void test_userdata_metatable_identity(lua_State *state) {
    const void *payload;
    lua_settop(state, 0);
    payload = lua_newuserdatauv(state, 0, 0);
    assert(lua_getmetatable(state, 1) == 0 && lua_gettop(state) == 1);
    lua_newtable(state);
    lua_pushliteral(state, "__metatable");
    lua_pushliteral(state, "protected");
    lua_rawset(state, 2);
    lua_pushvalue(state, 2);
    assert(lua_setmetatable(state, 1) == 1 && lua_gettop(state) == 2);
    /* The public C API deliberately bypasses the base library's protection
     * string; it returns the actual metatable object with stable identity. */
    assert(lua_getmetatable(state, 1) == 1);
    assert(lua_rawequal(state, 2, 3));
    lua_pop(state, 1);
    lua_pushnil(state);
    assert(lua_setmetatable(state, 1) == 1);
    assert(lua_getmetatable(state, 1) == 0);
    assert(lua_touserdata(state, 1) == payload);
    lua_settop(state, 0);
    puts("C API PASS: real raw userdata metatables");
}

static void test_userdata_maximum_uservalue_count(lua_State *state) {
    lua_settop(state, 0);
    /* Pinned lapi.c requires nuvalue < SHRT_MAX, rather than USHRT_MAX.
     * Exercise the last valid slot without any invalid C API precondition. */
    lua_newuserdatauv(state, 0, SHRT_MAX - 1);
    lua_pushinteger(state, 42);
    assert(lua_setiuservalue(state, 1, SHRT_MAX - 1));
    assert(lua_getiuservalue(state, 1, SHRT_MAX - 1) == LUA_TNUMBER);
    assert(lua_tointeger(state, -1) == 42);
    lua_pop(state, 1);
    assert(lua_getiuservalue(state, 1, SHRT_MAX) == LUA_TNONE);
    assert(lua_isnil(state, -1));
    lua_settop(state, 0);
    puts("C API PASS: maximum valid userdata uservalue count");
}

/* Insert these cases into the ordinary real-C consumer after the coherent
 * window migration. They use public API behavior, not the Ada dispatch ABI. */
static void test_initial_free_stack_needs_no_growth(void) {
    struct allocation_counts counts = {0};
    lua_State *state = lua_newstate(counted_allocator, &counts, 123);
    size_t growths;
    int index;
    assert(state != NULL);
    growths = counts.growths;
    /* A freshly constructed Lua state guarantees LUA_MINSTACK free slots.
     * Their physical scalar/cell storage must already belong to its provider;
     * ordinary nonallocating integer pushes cannot trigger a late arena copy. */
    for (index = 1; index <= LUA_MINSTACK; ++index)
        lua_pushinteger(state, index);
    assert(lua_gettop(state) == LUA_MINSTACK && counts.growths == growths);
    for (index = 1; index <= LUA_MINSTACK; ++index)
        assert(lua_tointeger(state, index) == index);
    lua_close(state);
    assert(counts.bytes == 0 && counts.blocks == 0);
    puts("C API PASS: initial native stack slots need no allocation");
}

static void test_failed_checkstack_keeps_state_usable(lua_State *state) {
    lua_settop(state, 0);
    /* The mathematical request cannot fit in either configured MAXSTACK.
     * A false result leaves the existing prefix intact and does not become
     * a thrown language error or restart the next protected call's budget. */
    lua_pushinteger(state, 17);
    assert(lua_checkstack(state, INT_MAX) == 0);
    assert(lua_gettop(state) == 1 && lua_tointeger(state, 1) == 17);
    assert(lua_checkstack(state, LUA_MINSTACK));
    lua_pushcfunction(state, add_callback);
    lua_pushinteger(state, 20); lua_pushinteger(state, 22);
    assert(lua_pcall(state, 2, 1, 0) == LUA_OK);
    assert(lua_gettop(state) == 2 && lua_tointeger(state, 1) == 17);
    assert(lua_tointeger(state, 2) == 42);
    lua_settop(state, 0);
    puts("C API PASS: failed checkstack preserves caller and recovery");
}

/* Valid public C API expectations for the non-yieldable branch of callk.
 * The continuation is intentionally unreachable, rather than a fake callback. */
static int forbidden_nonyieldable_continuation(lua_State *state, int status,
                                               lua_KContext context) {
    (void)state; (void)status; (void)context;
    assert(!"a non-yieldable call invoked its unused continuation");
    return 0;
}

static void test_public_yieldability(lua_State *state) {
    lua_State *thread;
    lua_settop(state, 0);
    assert(lua_isyieldable(state) == 0);
    thread = lua_newthread(state);
    /* A new secondary thread has no active no-yield boundary, independently
     * from whether it is currently executing or has yet been resumed. */
    assert(lua_isyieldable(thread) != 0);
    assert(lua_isyieldable(state) == 0);
    lua_pop(state, 1);
    puts("C API PASS: real main and secondary thread yieldability");
}

static void test_nonyieldable_callk(lua_State *state) {
    lua_settop(state, 0);
    lua_pushcfunction(state, add_callback);
    lua_pushinteger(state, 20); lua_pushinteger(state, 22);
    /* Pinned lapi.c ignores K when this state cannot yield. Synchronous
     * completion returns to this original C activation with ordinary results. */
    lua_callk(state, 2, 1, (lua_KContext)0x123456,
              forbidden_nonyieldable_continuation);
    assert(lua_gettop(state) == 1 && lua_tointeger(state, -1) == 42);
    lua_settop(state, 0);
    puts("C API PASS: non-yieldable callk ignores continuation");
}

static void test_nonyieldable_pcallk(lua_State *state) {
    const void *error;
    int status;
    lua_settop(state, 0);
    lua_pushcfunction(state, add_callback);
    lua_pushinteger(state, 20); lua_pushinteger(state, 22);
    status = lua_pcallk(state, 2, 1, 0, (lua_KContext)0x654321,
                       forbidden_nonyieldable_continuation);
    assert(status == LUA_OK && lua_tointeger(state, -1) == 42);
    lua_settop(state, 0);
    lua_newtable(state); error = lua_topointer(state, -1);
    lua_pushcfunction(state, error_callback);
    lua_pushvalue(state, 1);
    status = lua_pcallk(state, 1, 1, 0, (lua_KContext)0x654321,
                       forbidden_nonyieldable_continuation);
    assert(status == LUA_ERRRUN && lua_gettop(state) == 2);
    assert(lua_topointer(state, -1) == error);
    lua_settop(state, 0);
    puts("C API PASS: non-yieldable pcallk returns result and exact error");
}

/* Real public C warning callbacks; no first-party or oracle internals. */
struct warning_trace {
    lua_State *state;
    char bytes[128];
    size_t length;
    int calls;
    int nesting;
};
static void trace_warning(void *data, const char *message, int to_continue) {
    struct warning_trace *trace = (struct warning_trace *)data;
    size_t length = strlen(message);
    assert(trace->length + length + 1 < sizeof trace->bytes);
    memcpy(trace->bytes + trace->length, message, length);
    trace->length += length;
    trace->bytes[trace->length++] = to_continue ? '+' : '|';
    trace->bytes[trace->length] = '\0';
    trace->calls++;
}
static void test_custom_warning_literals(lua_State *state) {
    struct warning_trace trace = {state, {0}, 0, 0, 0};
    lua_setwarnf(state, trace_warning, &trace);
    /* Commands belong to the auxiliary default handler. A custom callback
     * receives their literal spelling and the original continuation bit. */
    lua_warning(state, "@off", 0);
    lua_warning(state, "first", 1);
    lua_warning(state, "second", 0);
    assert(trace.calls == 3 && strcmp(trace.bytes, "@off|first+second|") == 0);
    lua_setwarnf(state, NULL, NULL);
    lua_warning(state, "ignored", 0);
    assert(trace.calls == 3);
    puts("C API PASS: custom warning data, controls and fragments");
}
static void nested_warning(void *data, const char *message, int to_continue) {
    struct warning_trace *trace = (struct warning_trace *)data;
    trace_warning(trace, message, to_continue);
    if (!trace->nesting) {
        trace->nesting = 1;
        lua_pushinteger(trace->state, 42);
        lua_warning(trace->state, "inner", 0);
        /* A nested dispatch must not overwrite the outer borrowed string
         * or its C-owned callback data while that callback remains active. */
        assert(strcmp(message, "outer") == 0);
        assert(lua_tointeger(trace->state, -1) == 42);
        lua_pop(trace->state, 1);
    }
}
static void test_reentrant_warning(lua_State *state) {
    struct warning_trace trace = {state, {0}, 0, 0, 0};
    lua_settop(state, 0);
    lua_setwarnf(state, nested_warning, &trace);
    lua_warning(state, "outer", 0);
    assert(trace.calls == 2 && strcmp(trace.bytes, "outer|inner|") == 0);
    assert(lua_gettop(state) == 0);
    lua_setwarnf(state, NULL, NULL);
    puts("C API PASS: warning callback reentry preserves outer message");
}
static void refusing_warning(void *data, const char *message, int to_continue) {
    struct warning_trace *trace = (struct warning_trace *)data;
    (void)message; (void)to_continue;
    lua_pushvalue(trace->state, 1);
    lua_error(trace->state);
}
static int trigger_warning(lua_State *state) {
    lua_warning(state, "failure", 0);
    assert(!"a throwing warning callback returned to its C body");
    return 0;
}
static void test_warning_error_boundary(lua_State *state) {
    struct warning_trace trace = {state, {0}, 0, 0, 0};
    const void *error;
    lua_settop(state, 0);
    lua_newtable(state); error = lua_topointer(state, -1);
    lua_setwarnf(state, refusing_warning, &trace);
    lua_pushcfunction(state, trigger_warning); lua_pushvalue(state, 1);
    assert(lua_pcall(state, 1, 1, 0) == LUA_ERRRUN);
    assert(lua_gettop(state) == 2 && lua_topointer(state, -1) == error);
    lua_setwarnf(state, NULL, NULL);
    lua_settop(state, 0);
    lua_pushcfunction(state, add_callback);
    lua_pushinteger(state, 20); lua_pushinteger(state, 22);
    assert(lua_pcall(state, 2, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 42);
    lua_settop(state, 0);
    puts("C API PASS: warning error crosses only C guard and recovers");
}
static void test_warning_uses_no_allocator(void) {
    struct allocation_counts counts = {0, 0, 0, 0, 0, 0};
    struct warning_trace trace = {0, {0}, 0, 0, 0};
    lua_State *state = lua_newstate(counted_allocator, &counts, 1);
    size_t before;
    assert(state);
    trace.state = state;
    lua_setwarnf(state, trace_warning, &trace);
    before = counts.calls;
    counts.refuse = 1;
    /* Warning delivery itself allocates nothing in pinned C Lua. A permanent
     * allocator refusal therefore cannot prevent this literal callback. */
    lua_warning(state, "allocation-free", 0);
    assert(counts.calls == before && trace.calls == 1);
    counts.refuse = 0;
    lua_close(state);
    assert(counts.blocks == 0 && counts.bytes == 0);
    puts("C API PASS: warning delivery allocates no Lua storage");
}

#include "io_contract.h"

#include "gc_contract.h"

#include "load_dump_contract.h"

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
    test_number_macro_without_validity_output(state);
    test_none_or_nil_macro(state);
    test_global_table_macro(state);
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
    test_message_handler_results(state);
    test_recursive_message_handler(state);
    test_error_in_message_handler(state);
    test_inherited_handler_runs_once(state);
    test_lua_message_handler(state);
    test_protected_callback_memory_failure();
    test_panic_after_ada_returns(state);
    test_reentrant_independent_universes(state);
    test_userdata_payload_alignment(state);
    test_userdata_uservalue_results(state);
    test_userdata_metatable_identity(state);
    test_userdata_maximum_uservalue_count(state);
    test_initial_free_stack_needs_no_growth();
    test_failed_checkstack_keeps_state_usable(state);
    test_public_yieldability(state);
    test_nonyieldable_callk(state);
    test_nonyieldable_pcallk(state);
    test_custom_warning_literals(state);
    test_reentrant_warning(state);
    test_warning_error_boundary(state);
    test_warning_uses_no_allocator();
    test_io_opener_and_stream_layout(state);
    test_os_opener_without_global_publication(state);
    test_file_payload_closer_callback(state);
    test_gc_controls_without_allocation();
    test_gc_modes_and_stopped_steps(state);
    test_gc_finalizer_callback_order(state);
    test_gc_finalizer_storage_refusal();
    test_close_drains_c_finalizers();
    test_close_refusal_releases_storage();
    test_gc_and_close_warning_callbacks();
    test_load_dump_contract(state);
    lua_close(state);
    puts("PASS: real Ada C API bootstrap consumer");
    return 0;
}
