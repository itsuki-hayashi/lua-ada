/* Callable standard library identities through the real public C ABI.
 * Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE. */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "consumer_allocator.h"

static struct allocation_counts counts;
static lua_CFunction degrees, direct_pairs, direct_yield, direct_error;
static lua_CFunction direct_pcall;
static int after_direct;

static void run(lua_State *L, const char *source) {
    int status = luaL_dostring(L, source);
    if (status != LUA_OK) fprintf(stderr, "%s\n", lua_tostring(L, -1));
    assert(status == LUA_OK);
}

static lua_CFunction field(lua_State *L, const char *module, const char *name) {
    lua_CFunction result;
    if (module) {
        lua_getglobal(L, module); lua_getfield(L, -1, name);
        lua_remove(L, -2);
    } else lua_getglobal(L, name);
    assert(lua_iscfunction(L, -1));
    result = lua_tocfunction(L, -1); assert(result);
    return result;
}

static void exposed_functions(lua_State *L) {
    static const char *const globals[] =
        {"assert", "error", "next", "pcall", "print", "select", "tonumber",
         "tostring", "pairs", "ipairs", "load", "require"};
    static const char *const modules[] =
        {"math", "string", "table", "utf8", "coroutine", "debug", "io", "os"};
    static const char *const names[] =
        {"deg", "format", "concat", "codes", "yield", "getinfo", "open", "time"};
    size_t i;
    lua_Debug ar;
    for (i = 0; i < sizeof globals / sizeof globals[0]; ++i) {
        (void)field(L, NULL, globals[i]); lua_pop(L, 1);
    }
    for (i = 0; i < sizeof modules / sizeof modules[0]; ++i) {
        lua_CFunction function = field(L, modules[i], names[i]);
        lua_pushcfunction(L, function);
        assert(lua_rawequal(L, -1, -2));
        assert(lua_topointer(L, -1) == lua_topointer(L, -2));
        assert(lua_getinfo(L, ">u", &ar));
        assert(ar.nups == 0 && ar.nparams == 0 && ar.isvararg);
        lua_pop(L, 1);
    }
}

static void stateless_roundtrip(lua_State *L) {
    degrees = field(L, "math", "deg");
    lua_pushcfunction(L, degrees); assert(lua_rawequal(L, 1, 2));
    lua_pushnumber(L, 3); lua_call(L, 1, 1);
    assert(fabs(lua_tonumber(L, -1) - 171.88733853924697) < 1e-10);
    lua_settop(L, 0);
}

static void repeated_opener_identity(lua_State *L) {
    lua_CFunction before = field(L, "math", "deg");
    lua_pushcfunction(L, luaopen_math); lua_call(L, 0, 1);
    lua_getfield(L, -1, "deg");
    assert(lua_tocfunction(L, -1) == before && lua_rawequal(L, 1, -1));
    lua_settop(L, 0);
}

static void direct_host_call(lua_State *L) {
    lua_pushnumber(L, 3);
    assert(degrees(L) == 1);
    assert(fabs(lua_tonumber(L, -1) - 171.88733853924697) < 1e-10);
    lua_settop(L, 0);
}

static int forward_degrees(lua_State *L) { return degrees(L); }
static int forward_pairs(lua_State *L) {
    int results = direct_pairs(L);
    ++after_direct;
    return results;
}
static int forward_yield(lua_State *L) {
    int results = direct_yield(L);
    ++after_direct;
    return results;
}
static int forward_error(lua_State *L) { return direct_error(L); }
static int forward_pcall(lua_State *L) { return direct_pcall(L); }

static void direct_c_call(lua_State *L) {
    lua_pushcfunction(L, forward_degrees); lua_pushnumber(L, 3);
    lua_call(L, 1, 1);
    assert(fabs(lua_tonumber(L, -1) - 171.88733853924697) < 1e-10);
    lua_settop(L, 0);
}

static void direct_callback_frame(lua_State *L) {
    direct_pairs = field(L, NULL, "pairs"); lua_pop(L, 1);
    lua_pushcfunction(L, forward_pairs); lua_setglobal(L, "forward_pairs");
    after_direct = 0;
    run(L, "local t=setmetatable({},{__pairs=function(self) "
           "assert(debug.getinfo(2,'f').func==forward_pairs);"
           "return next,{value=91},nil end});"
           "local f,s,v=forward_pairs(t);assert(f==next and s.value==91 "
           "and v==nil)");
    assert(after_direct == 1);
}

static void captured_roundtrip(lua_State *L) {
    lua_CFunction random = field(L, "math", "random");
    lua_CFunction seed = field(L, "math", "randomseed");
    lua_Integer first, repeated;
    const char *name = lua_getupvalue(L, 1, 1);
    assert(name && !*name && lua_isuserdata(L, -1));
    lua_pushcclosure(L, random, 1);
    assert(!lua_rawequal(L, 1, 3) && lua_tocfunction(L, 3) == random);
    assert(lua_upvalueid(L, 1, 1) != lua_upvalueid(L, 3, 1));
    assert(lua_getupvalue(L, 1, 1)); lua_pushcclosure(L, seed, 1);
    lua_pushvalue(L, 4); lua_pushinteger(L, 123); lua_pushinteger(L, 456);
    lua_call(L, 2, 0);
    lua_pushvalue(L, 1); lua_pushinteger(L, 1); lua_pushinteger(L, 100000);
    lua_call(L, 2, 1); first = lua_tointeger(L, -1); lua_pop(L, 1);
    lua_pushvalue(L, 4); lua_pushinteger(L, 123); lua_pushinteger(L, 456);
    lua_call(L, 2, 0);
    lua_pushvalue(L, 3); lua_pushinteger(L, 1); lua_pushinteger(L, 100000);
    lua_call(L, 2, 1); repeated = lua_tointeger(L, -1);
    assert(first == repeated);
    lua_settop(L, 0);
}

static void iterator_identity(lua_State *L) {
    run(L, "local a=ipairs{};local b=ipairs{};assert(a==b);"
           "local a=utf8.codes('a');local b=utf8.codes('b');assert(a==b);"
           "local c=utf8.codes('a',true);local d=utf8.codes('b',true);"
           "assert(c==d and a~=c);"
           "return string.gmatch('a','.'),string.gmatch('b','.')");
    assert(!lua_rawequal(L, 1, 2));
    assert(lua_tocfunction(L, 1) &&
           lua_tocfunction(L, 1) == lua_tocfunction(L, 2));
    lua_settop(L, 0);
}

static void pointer_formats(lua_State *L) {
    run(L, "local p=function(v)return string.format('%p',v)end;"
           "assert(p(print)~='(null)' and p(print)==p(print));"
           "assert(p(assert)~=p(print));"
           "assert(p(coroutine.running())~='(null)');"
           "assert(p(io.stdin)~='(null)' and p(io.stdin)==p(io.stdin));"
           "assert(p(nil)=='(null)' and p(4)=='(null)');"
           "assert(#string.format('%90p',print)==90)");
}

static void direct_error_identity(lua_State *L) {
    direct_error = field(L, NULL, "error"); lua_pop(L, 1);
    lua_pushcfunction(L, forward_error); lua_setglobal(L, "forward_error");
    run(L, "local marker={};local ok,e=pcall(forward_error,marker);"
           "assert(not ok and e==marker)");
}

static void direct_protected_results(lua_State *L) {
    direct_pcall = field(L, NULL, "pcall"); lua_pop(L, 1);
    lua_pushcfunction(L, forward_pcall); lua_setglobal(L, "forward_pcall");
    run(L, "local r=table.pack(forward_pcall(function()return 11,22 end));"
           "assert(r.n==3 and r[1]==true and r[2]==11 and r[3]==22);"
           "local marker={};local r=table.pack(forward_pcall(function()"
           "error(marker)end));assert(r.n==2 and r[1]==false and r[2]==marker)");
}

static void direct_yield_continuation(lua_State *L) {
    lua_State *co;
    int results = -1;
    direct_yield = field(L, "coroutine", "yield"); lua_pop(L, 1);
    lua_pushcfunction(L, forward_yield); lua_setglobal(L, "forward_yield");
    co = lua_newthread(L); after_direct = 0;
    assert(luaL_loadstring(co, "return forward_yield(10,20)") == LUA_OK);
    assert(lua_resume(co, L, 0, &results) == LUA_YIELD && results == 2);
    assert(lua_tointeger(co, -2) == 10 && lua_tointeger(co, -1) == 20);
    lua_pop(co, results); lua_pushinteger(co, 31); lua_pushinteger(co, 32);
    assert(lua_resume(co, L, 2, &results) == LUA_OK && results == 2);
    assert(lua_tointeger(co, -2) == 31 && lua_tointeger(co, -1) == 32);
    assert(after_direct == 0);
    lua_settop(L, 0);
}

static void direct_callback_yield(lua_State *L) {
    lua_State *co = lua_newthread(L);
    int results = -1;
    after_direct = 0;
    assert(luaL_loadstring(co,
        "local t=setmetatable({},{__pairs=function()coroutine.yield(71);"
        "return next,{value=92},nil end});"
        "local f,s,v=forward_pairs(t);assert(f==next and v==nil);"
        "return s.value") == LUA_OK);
    assert(lua_resume(co, L, 0, &results) == LUA_YIELD && results == 1);
    assert(lua_tointeger(co, -1) == 71); lua_pop(co, 1);
    assert(lua_resume(co, L, 0, &results) == LUA_OK && results == 1);
    assert(lua_tointeger(co, -1) == 92 && after_direct == 0);
    lua_settop(L, 0);
}

static void scalar_refusal(lua_State *L) {
    lua_Debug ar;
    assert(lua_checkstack(L, 64));
    counts.refuse = 1;
    lua_pushcfunction(L, degrees);
    assert(lua_tocfunction(L, -1) == degrees && lua_topointer(L, -1));
    assert(lua_getinfo(L, ">u", &ar) && ar.nups == 0);
    counts.refuse = 0;
}

static int push_captured(lua_State *L) {
    lua_pushinteger(L, 11); lua_pushcclosure(L, degrees, 1);
    return 1;
}
static void captured_refusal_recovery(lua_State *L) {
    int status;
    lua_pushcfunction(L, push_captured); counts.refuse = 1;
    status = lua_pcall(L, 0, 1, 0); counts.refuse = 0;
    assert(status == LUA_ERRMEM); lua_pop(L, 1);
    lua_pushcfunction(L, push_captured); assert(lua_pcall(L, 0, 1, 0) == LUA_OK);
    assert(lua_tocfunction(L, -1) == degrees);
    lua_pushnumber(L, 3); lua_call(L, 1, 1);
    assert(fabs(lua_tonumber(L, -1) - 171.88733853924697) < 1e-10);
    lua_settop(L, 0);
}

static void check(const char *name, void (*body)(lua_State *), lua_State *L) {
    assert(lua_gettop(L) == 0); body(L); assert(lua_gettop(L) == 0);
    printf("PASS: builtin-%s\n", name); fflush(stdout);
}

int main(void) {
    lua_State *L = lua_newstate(counted_allocator, &counts, 971U);
    assert(L); luaL_openlibs(L);
    check("exposed-functions", exposed_functions, L);
    check("stateless-roundtrip", stateless_roundtrip, L);
    check("repeated-opener-identity", repeated_opener_identity, L);
    check("direct-host-call", direct_host_call, L);
    check("direct-c-call", direct_c_call, L);
    check("direct-callback-frame", direct_callback_frame, L);
    check("captured-roundtrip", captured_roundtrip, L);
    check("iterator-identity", iterator_identity, L);
    check("pointer-formats", pointer_formats, L);
    check("direct-error-identity", direct_error_identity, L);
    check("direct-protected-results", direct_protected_results, L);
    check("direct-yield-continuation", direct_yield_continuation, L);
    check("direct-callback-yield", direct_callback_yield, L);
    check("scalar-refusal", scalar_refusal, L);
    check("captured-refusal-recovery", captured_refusal_recovery, L);
    lua_close(L); assert(counts.bytes == 0 && counts.blocks == 0);
    puts("PASS: public builtin contract");
    return 0;
}
