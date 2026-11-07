/* First-party public reset/close regressions. MIT; see ../../LICENSE. */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "consumer_allocator.h"

static struct allocation_counts counts;
static const char *selected_case;
static unsigned matched_cases, reader_calls;
static int closed, expected_error, self_returned, outer_returned;

static void run(lua_State *L, const char *source) {
    int status = luaL_dostring(L, source);
    if (status != LUA_OK) fprintf(stderr, "%s\n", lua_tostring(L, -1));
    assert(status == LUA_OK);
}

static int record_close(lua_State *L) {
    closed++;
    assert(lua_gettop(L) == (expected_error ? 2 : 1));
    if (expected_error) {
        lua_getglobal(L, "marker");
        assert(lua_rawequal(L, 2, -1));
        lua_pop(L, 1);
    }
    return 0;
}

static int fail_close(lua_State *L) {
    closed++;
    lua_getglobal(L, "marker2");
    return lua_error(L);
}

static int many_close(lua_State *L) {
    int i;
    closed++;
    assert(lua_gettop(L) == 1);
    for (i = 0; i < 12; i++) lua_pushinteger(L, 37 + i);
    return 12;
}

static int error_close(lua_State *L) {
    closed++;
    assert(lua_gettop(L) == 2);
    lua_getglobal(L, "marker2");
    assert(lua_rawequal(L, 2, -1));
    return 0;
}

static int audit_close(lua_State *L) {
    (void)L;
    closed++;
    return 0;
}

static int cyield(lua_State *L) {
    lua_pushinteger(L, 17);
    return lua_yield(L, 1);
}

static int close_self(lua_State *L) {
    lua_closethread(L, L);
    self_returned++;
    return 0;
}

static int outer_call(lua_State *L) {
    lua_getglobal(L, "inner_close_self");
    lua_call(L, 0, 0);
    outer_returned++;
    return 0;
}

static lua_State *load_thread(lua_State *L, const char *source) {
    lua_State *co = lua_newthread(L);
    assert(co != NULL);
    assert(luaL_loadstring(co, source) == LUA_OK);
    return co;
}

static void reset_ok(lua_State *co, lua_State *from) {
    assert(lua_closethread(co, from) == LUA_OK);
    assert(lua_status(co) == LUA_OK && lua_gettop(co) == 0);
}

static void fresh_values(lua_State *L) {
    lua_State *co = lua_newthread(L);
    lua_Debug ar;
    lua_pushinteger(co, 17);
    reset_ok(co, L);
    assert(!lua_getstack(co, 0, &ar));
    lua_pop(L, 1);
}

static void suspended_lua(lua_State *L) {
    int n;
    lua_State *co;
    closed = expected_error = 0;
    co = load_thread(L,
        "local x <close> =setmetatable({},{__close=record_close});"
        "coroutine.yield(11,22)");
    assert(lua_resume(co, L, 0, &n) == LUA_YIELD && n == 2);
    assert(closed == 0);
    reset_ok(co, L);
    assert(closed == 1);
    reset_ok(co, L);
    assert(closed == 1);
    lua_pop(L, 1);
}

static void suspended_c(lua_State *L) {
    int n;
    lua_State *co;
    closed = expected_error = 0;
    co = load_thread(L,
        "local x <close> =setmetatable({},{__close=record_close});cyield()");
    assert(lua_resume(co, L, 0, &n) == LUA_YIELD && n == 1);
    reset_ok(co, NULL);
    assert(closed == 1);
    lua_pop(L, 1);
}

static void original_error(lua_State *L) {
    int n;
    lua_State *co;
    closed = 0;
    expected_error = 1;
    co = load_thread(L,
        "local x <close> =setmetatable({},{__close=record_close});"
        "error(marker)");
    assert(lua_resume(co, L, 0, &n) == LUA_ERRRUN && closed == 0);
    assert(lua_closethread(co, L) == LUA_ERRRUN && closed == 1);
    assert(lua_status(co) == LUA_OK && lua_gettop(co) == 1);
    lua_getglobal(L, "marker");
    lua_xmove(L, co, 1);
    assert(lua_rawequal(co, -1, -2));
    lua_pop(co, 1);
    reset_ok(co, L);
    assert(closed == 1);
    expected_error = 0;
    lua_pop(L, 1);
}

static void closing_error(lua_State *L) {
    int n;
    lua_State *co;
    closed = 0;
    co = load_thread(L,
        "local x <close> =setmetatable({},{__close=fail_close});"
        "coroutine.yield()");
    assert(lua_resume(co, L, 0, &n) == LUA_YIELD);
    assert(lua_closethread(co, L) == LUA_ERRRUN);
    assert(closed == 1 && lua_status(co) == LUA_OK && lua_gettop(co) == 1);
    lua_getglobal(L, "marker2");
    lua_xmove(L, co, 1);
    assert(lua_rawequal(co, -1, -2));
    lua_pop(co, 1);
    reset_ok(co, L);
    assert(closed == 1);
    lua_pop(L, 1);
}

static void reinitialize_thread(lua_State *L) {
    int n;
    lua_State *co = load_thread(L, "coroutine.yield(1)");
    assert(lua_resume(co, L, 0, &n) == LUA_YIELD);
    reset_ok(co, L);
    assert(luaL_loadstring(co, "return 37") == LUA_OK);
    assert(lua_resume(co, L, 0, &n) == LUA_OK && n == 1);
    assert(lua_tointeger(co, -1) == 37);
    reset_ok(co, L);
    lua_pop(L, 1);
}

static void weak_prefix_lifetime(lua_State *L) {
    int n;
    lua_State *co;
    /* The ordinary local below the pending close slot stays live until its
       closer returns, then disappears. A copied closer value is insufficient. */
    run(L, "weak_reset=setmetatable({},{__mode='v'});reset_alive=false");
    co = load_thread(L,
        "local x={};weak_reset[1]=x;local c <close> =setmetatable({},"
        "{__close=function()collectgarbage('collect');"
        "reset_alive=weak_reset[1]~=nil end});coroutine.yield()");
    assert(lua_resume(co, L, 0, &n) == LUA_YIELD);
    reset_ok(co, L);
    lua_getglobal(L, "reset_alive");
    assert(lua_toboolean(L, -1));
    lua_pop(L, 1);
    lua_gc(L, LUA_GCCOLLECT);
    lua_getglobal(L, "weak_reset");
    lua_rawgeti(L, -1, 1);
    assert(lua_isnil(L, -1));
    lua_settop(L, 0);
}

static void no_closer_refusal(lua_State *L) {
    int n;
    lua_State *co = load_thread(L, "local a=7;coroutine.yield(a)");
    assert(lua_resume(co, L, 0, &n) == LUA_YIELD);
    counts.refuse = 1;
    reset_ok(co, L);
    counts.refuse = 0;
    lua_pop(L, 1);
}

static void self_close_direct(lua_State *L) {
    int n;
    lua_State *co = lua_newthread(L);
    self_returned = 0;
    lua_pushcfunction(co, close_self);
    assert(lua_resume(co, L, 0, &n) == LUA_OK && n == 0);
    assert(!self_returned && lua_status(co) == LUA_OK && lua_gettop(co) == 0);
    lua_pop(L, 1);
}

static void self_close_nested(lua_State *L) {
    int n;
    lua_State *co;
    closed = expected_error = self_returned = outer_returned = 0;
    run(L, "function inner_close_self()close_self()end");
    co = load_thread(L,
        "local x <close> =setmetatable({},{__close=record_close});"
        "outer_call();error('returned')");
    assert(lua_resume(co, L, 0, &n) == LUA_OK && n == 0 && closed == 1);
    assert(!self_returned && !outer_returned);
    lua_pop(L, 1);
}

static void self_close_lua_resume(lua_State *L) {
    closed = expected_error = self_returned = outer_returned = 0;
    run(L,
        "local co=coroutine.create(function()local x <close> ="
        "setmetatable({},{__close=record_close});outer_call();"
        "error('returned')end);local ok,e=coroutine.resume(co);"
        "assert(ok and e==nil and coroutine.status(co)=='dead')");
    assert(closed == 1 && !self_returned && !outer_returned);
}

static void base_c_settop(lua_State *L) {
    closed = expected_error = 0;
    run(L, "return setmetatable({},{__close=record_close})");
    lua_toclose(L, 1);
    lua_pushinteger(L, 23);
    lua_settop(L, 0);
    assert(closed == 1);
}

static void base_c_closeslot(lua_State *L) {
    closed = expected_error = 0;
    run(L, "return setmetatable({},{__close=record_close})");
    lua_toclose(L, 1);
    lua_closeslot(L, 1);
    assert(closed == 1 && lua_gettop(L) == 1 && lua_isnil(L, 1));
    lua_pop(L, 1);
    assert(closed == 1);
}

static void base_c_reset(lua_State *L) {
    int n;
    lua_State *co = lua_newthread(L);
    /* A returned thread can acquire real host C closing slots without a
       callback frame. Reset consumes that same slot exactly once. */
    assert(luaL_loadstring(co,
        "return setmetatable({},{__close=record_close})") == LUA_OK);
    assert(lua_resume(co, L, 0, &n) == LUA_OK && n == 1);
    closed = expected_error = 0;
    lua_toclose(co, 1);
    assert(lua_closethread(co, L) == LUA_OK && closed == 1);
    assert(lua_gettop(co) == 0);
    lua_pop(L, 1);
}

static const char *reader_close_self(lua_State *L, void *data, size_t *size) {
    (void)data;
    reader_calls++;
    *size = 0;
    lua_closethread(L, L);
    self_returned++;
    return NULL;
}

static const char *reader_partial_self(lua_State *L, void *data, size_t *size) {
    static const char prefix[] = "return 37, ";
    if (reader_calls == 0) {
        reader_calls++;
        *size = sizeof prefix - 1;
        return prefix;
    }
    return reader_close_self(L, data, size);
}

static int load_close_self(lua_State *L) {
    lua_load(L, reader_close_self, NULL, "=self-reader", NULL);
    self_returned++;
    return 0;
}

static void self_close_reader(lua_State *L) {
    int n;
    lua_State *co = lua_newthread(L);
    self_returned = 0;
    reader_calls = 0;
    lua_pushcfunction(co, load_close_self);
    assert(lua_resume(co, L, 0, &n) == LUA_OK && n == 0 && !self_returned);
    assert(reader_calls == 1);
    lua_pop(L, 1);
}

static int writer_close_self(lua_State *L, const void *bytes,
                             size_t size, void *data) {
    (void)bytes;
    (void)size;
    (void)data;
    lua_closethread(L, L);
    self_returned++;
    return 0;
}

static int dump_close_self(lua_State *L) {
    assert(luaL_loadstring(L, "return 37") == LUA_OK);
    lua_dump(L, writer_close_self, NULL, 0);
    self_returned++;
    return 0;
}

static void self_close_writer(lua_State *L) {
    int n;
    lua_State *co = lua_newthread(L);
    self_returned = 0;
    lua_pushcfunction(co, dump_close_self);
    assert(lua_resume(co, L, 0, &n) == LUA_OK && n == 0 && !self_returned);
    lua_pop(L, 1);
}

static void warning_close_self(void *data, const char *message, int continued) {
    lua_State *L = (lua_State *)data;
    (void)message;
    (void)continued;
    lua_closethread(L, L);
    self_returned++;
}

static void self_close_warning(lua_State *L) {
    int n;
    lua_State *co;
    self_returned = 0;
    co = load_thread(L, "warn('self close')");
    lua_setwarnf(co, warning_close_self, co);
    assert(lua_resume(co, L, 0, &n) == LUA_OK && n == 0 && !self_returned);
    lua_setwarnf(L, NULL, NULL);
    lua_pop(L, 1);
}

static void hook_close_self(lua_State *L, lua_Debug *ar) {
    (void)ar;
    lua_closethread(L, L);
    self_returned++;
}

static void self_close_hook(lua_State *L) {
    int n;
    lua_State *co;
    self_returned = 0;
    co = load_thread(L, "local x=1;return x");
    lua_sethook(co, hook_close_self, LUA_MASKCOUNT, 1);
    assert(lua_resume(co, L, 0, &n) == LUA_OK && n == 0 && !self_returned);
    lua_pop(L, 1);
}

static void self_close_error(lua_State *L) {
    int n;
    lua_State *co;
    closed = self_returned = 0;
    co = load_thread(L,
        "local c <close> =setmetatable({},{__close=fail_close});close_self()");
    assert(lua_resume(co, L, 0, &n) == LUA_ERRRUN);
    assert(closed == 1 && !self_returned);
    /* Reset publishes its error; the outer resume adds the terminal copy. */
    assert(lua_status(co) == LUA_ERRRUN && lua_gettop(co) == 2 && n == 2);
    assert(lua_rawequal(co, 1, 2));
    assert(lua_closethread(co, L) == LUA_ERRRUN);
    assert(lua_status(co) == LUA_OK && closed == 1);
    reset_ok(co, L);
    lua_pop(L, 1);
}

static void c_closer_refusal(lua_State *L) {
    int n, status;
    size_t before;
    lua_State *co;
    closed = expected_error = 0;
    co = load_thread(L,
        "local c <close> =setmetatable({},{__close=record_close});"
        "coroutine.yield()");
    assert(lua_resume(co, L, 0, &n) == LUA_YIELD);
    before = counts.growths;
    counts.refuse = 1;
    status = lua_closethread(co, L);
    counts.refuse = 0;
    assert(status == LUA_OK && closed == 1 && counts.growths == before);
    reset_ok(co, L);
    lua_pop(L, 1);
}

static void multiple_closers_refusal(lua_State *L) {
    int n, status;
    size_t before;
    lua_State *co;
    closed = expected_error = 0;
    /* Twelve ignored C results must stay in their real C window; constructing
       an unused result packet would allocate after the callback returns. */
    co = load_thread(L,
        "local a <close> =setmetatable({},{__close=record_close});"
        "local b <close> =setmetatable({},{__close=many_close});"
        "coroutine.yield()");
    assert(lua_resume(co, L, 0, &n) == LUA_YIELD);
    before = counts.growths;
    counts.refuse = 1;
    status = lua_closethread(co, L);
    counts.refuse = 0;
    assert(status == LUA_OK && closed == 2 && counts.growths == before);
    reset_ok(co, L);
    lua_pop(L, 1);
}

static void closer_error_refusal(lua_State *L) {
    int n, status;
    size_t before;
    lua_State *co;
    closed = 0;
    /* The first failing closer passes its original error to the next closer.
       Neither error publication nor the next close may consume fresh storage. */
    co = load_thread(L,
        "local a <close> =setmetatable({},{__close=error_close});"
        "local b <close> =setmetatable({},{__close=fail_close});"
        "coroutine.yield()");
    assert(lua_resume(co, L, 0, &n) == LUA_YIELD);
    before = counts.growths;
    counts.refuse = 1;
    status = lua_closethread(co, L);
    counts.refuse = 0;
    assert(status == LUA_ERRRUN && closed == 2 && counts.growths == before);
    assert(lua_status(co) == LUA_OK && lua_gettop(co) == 1);
    lua_getglobal(L, "marker2");
    lua_xmove(L, co, 1);
    assert(lua_rawequal(co, 1, 2));
    reset_ok(co, L);
    lua_pop(L, 1);
}

static void recursive_self_close(lua_State *L) {
    int n;
    lua_State *co;
    closed = expected_error = self_returned = 0;
    /* Both requests run inside the original resume. The second request
       abandons the currently executing closer and still closes its predecessor. */
    co = load_thread(L,
        "local a <close> =setmetatable({},{__close=record_close});"
        "local b <close> =setmetatable({},{__close=close_self});close_self()");
    assert(lua_resume(co, L, 0, &n) == LUA_OK && n == 0);
    assert(closed == 1 && !self_returned);
    reset_ok(co, L);
    lua_pop(L, 1);
}

static void reset_memory_recovery(lua_State *L) {
    unsigned offset, refused = 0;
    /* Refuse each early growth point in an allocating Lua closer. The older
       C closer must still run, error publication must finish, and the same
       thread must reset again. Allocation positions are runtime dependent;
       the assertions concern public status, cleanup and subsequent recovery. */
    for (offset = 1; offset <= 24; offset++) {
        int n, status;
        lua_State *co;
        closed = 0;
        co = load_thread(L,
            "local a <close> =setmetatable({},{__close=audit_close});"
            "local b <close> =setmetatable({},{__close=function()"
            "local t={};for i=1,32 do t[i]=string.rep('r',128+i)end end});"
            "coroutine.yield()");
        assert(lua_resume(co, L, 0, &n) == LUA_YIELD);
        counts.fail_after = counts.growths + offset;
        status = lua_closethread(co, L);
        counts.fail_after = 0;
        assert(status == LUA_OK || status == LUA_ERRMEM);
        assert(closed == 1 && lua_status(co) == LUA_OK);
        if (status == LUA_ERRMEM) {
            refused++;
            assert(lua_gettop(co) == 1 && lua_type(co, 1) == LUA_TSTRING);
        }
        reset_ok(co, L);
        assert(luaL_loadstring(co, "return 37") == LUA_OK);
        assert(lua_resume(co, L, 0, &n) == LUA_OK && n == 1);
        assert(lua_tointeger(co, -1) == 37);
        reset_ok(co, L);
        lua_pop(L, 1);
    }
    assert(refused > 0);
}

static void check(const char *name, void (*body)(lua_State *), lua_State *L) {
    if (selected_case && strcmp(selected_case, name) != 0) return;
    matched_cases++;
    assert(lua_gettop(L) == 0);
    body(L);
    assert(lua_gettop(L) == 0);
    printf("PASS: reset-%s\n", name);
    fflush(stdout);
}

static int run_protocol(const char *name, int skip_warning) {
    lua_State *L;
    memset(&counts, 0, sizeof counts);
    selected_case = name;
    matched_cases = reader_calls = 0;
    closed = expected_error = self_returned = outer_returned = 0;
    L = lua_newstate(counted_allocator, &counts, 223U);
    assert(L != NULL);
    luaL_openlibs(L);
    lua_pushcfunction(L, record_close); lua_setglobal(L, "record_close");
    lua_pushcfunction(L, fail_close); lua_setglobal(L, "fail_close");
    lua_pushcfunction(L, many_close); lua_setglobal(L, "many_close");
    lua_pushcfunction(L, error_close); lua_setglobal(L, "error_close");
    lua_pushcfunction(L, audit_close); lua_setglobal(L, "audit_close");
    lua_pushcfunction(L, cyield); lua_setglobal(L, "cyield");
    lua_pushcfunction(L, close_self); lua_setglobal(L, "close_self");
    lua_pushcfunction(L, outer_call); lua_setglobal(L, "outer_call");
    run(L, "marker={};marker2={}");
    check("fresh-values", fresh_values, L);
    check("suspended-lua", suspended_lua, L);
    check("suspended-c", suspended_c, L);
    check("original-error", original_error, L);
    check("closing-error", closing_error, L);
    check("reinitialize-thread", reinitialize_thread, L);
    check("weak-prefix-lifetime", weak_prefix_lifetime, L);
    check("no-closer-refusal", no_closer_refusal, L);
    check("self-close-direct", self_close_direct, L);
    check("self-close-nested", self_close_nested, L);
    check("self-close-lua-resume", self_close_lua_resume, L);
    check("base-c-settop", base_c_settop, L);
    check("base-c-closeslot", base_c_closeslot, L);
    check("base-c-reset", base_c_reset, L);
    check("self-reader", self_close_reader, L);
    check("self-writer", self_close_writer, L);
    if (skip_warning) {
        if (!selected_case || strcmp(selected_case, "self-warning") == 0) {
            matched_cases++;
            puts("SKIP: reset-self-warning (native T lock rejects API reentry)");
        }
    } else check("self-warning", self_close_warning, L);
    check("self-hook", self_close_hook, L);
    check("self-close-error", self_close_error, L);
    check("c-closer-refusal", c_closer_refusal, L);
    check("multiple-closers-refusal", multiple_closers_refusal, L);
    check("closer-error-refusal", closer_error_refusal, L);
    check("recursive-self-close", recursive_self_close, L);
    check("reset-memory-recovery", reset_memory_recovery, L);
    assert(matched_cases > 0);
    lua_close(L);
    assert(counts.bytes == 0 && counts.blocks == 0);
    selected_case = NULL;
    puts("PASS: public thread reset/base closing contract");
    return 0;
}

/* Test-only exports let AUnit exercise the identical C-owned protocol and an
   Ada-owned driver with real C callbacks. The partial-reader variant is an
   additional Ada cleanup regression: pinned C skips its parser cleanup after
   a self-close on its second refill and leaks parser scratch. It is deliberately
   excluded from the balanced, native-paired protocol above. */
int lua_ada_test_reset_case(const char *name) {
    return run_protocol(name, 0);
}

static int install_self_warning(lua_State *L) {
    lua_setwarnf(L, warning_close_self, L);
    return 0;
}

static int clear_self_warning(lua_State *L) {
    lua_setwarnf(L, NULL, NULL);
    return 0;
}

static int load_partial_self(lua_State *L) {
    lua_load(L, reader_partial_self, NULL, "=self-partial-reader", NULL);
    self_returned++;
    return 0;
}

lua_CFunction lua_ada_test_reset_reader(void) { return load_partial_self; }
lua_CFunction lua_ada_test_reset_self(void) { return close_self; }
lua_CFunction lua_ada_test_reset_warn_install(void) {
    return install_self_warning;
}
lua_CFunction lua_ada_test_reset_warn_clear(void) { return clear_self_warning; }
void lua_ada_test_reset_counters(void) {
    self_returned = outer_returned = 0;
    reader_calls = 0;
}
int lua_ada_test_reset_returned(void) { return self_returned + outer_returned; }
unsigned lua_ada_test_reset_reads(void) { return reader_calls; }

#ifndef LUA_ADA_RESET_CONTRACT_LIBRARY
int main(int argc, char **argv) {
    int skip_warning = 0, i;
    const char *name = NULL;
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--without-warning-reentry") == 0) skip_warning = 1;
        else if (strcmp(argv[i], "--case") == 0 && i + 1 < argc) name = argv[++i];
        else {
            fputs("invalid reset fixture argument\n", stderr);
            return 2;
        }
    }
    return run_protocol(name, skip_warning);
}
#endif
