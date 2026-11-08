/* Real C-call ownership during yieldable error closing. The same public
 * source links unchanged to Ada and isolated pinned C Lua.
 * Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE. */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "consumer_allocator.h"

static struct allocation_counts counts;
static int callk_continued;
static int refusal_closed, refusal_stable;
static size_t refusal_growths;

static int call_plain(lua_State *L) {
    lua_getglobal(L, "close_target");
    lua_call(L, 0, LUA_MULTRET);
    return lua_gettop(L);
}

static int pcall_plain(lua_State *L) {
    int status;
    lua_getglobal(L, "close_target");
    status = lua_pcall(L, 0, LUA_MULTRET, 0);
    lua_pushinteger(L, status);
    lua_insert(L, 1);
    return lua_gettop(L);
}

static int pcall_cont(lua_State *L, int status, lua_KContext context) {
    (void)context;
    lua_pushinteger(L, status);
    lua_insert(L, 1);
    return lua_gettop(L);
}

static int pcall_yieldable(lua_State *L) {
    int status;
    lua_getglobal(L, "close_target");
    status = lua_pcallk(L, 0, LUA_MULTRET, 0, 0, pcall_cont);
    return pcall_cont(L, status, 0);
}

static int callk_cont(lua_State *L, int status, lua_KContext context) {
    (void)context;
    assert(status == LUA_YIELD);
    ++callk_continued;
    return lua_gettop(L);
}

static int call_yieldable(lua_State *L) {
    lua_getglobal(L, "close_target");
    lua_callk(L, 0, LUA_MULTRET, 0, callk_cont);
    return lua_gettop(L);
}

static int call_refusing(lua_State *L) {
    lua_getglobal(L, "close_target");
    lua_pushvalue(L, 1);
    lua_call(L, 1, LUA_MULTRET);
    return lua_gettop(L);
}

static int raise_refusing(lua_State *L) {
    lua_pushinteger(L, 17);
    if (lua_toboolean(L, 1)) {
        refusal_growths = counts.growths;
        counts.refuse = 1;
    }
    return lua_error(L);
}

static int release_refusal(lua_State *L) {
    assert(lua_gettop(L) == 2 && lua_tointeger(L, 2) == 17);
    if (counts.refuse) refusal_stable = counts.growths == refusal_growths;
    counts.refuse = 0;
    ++refusal_closed;
    return 0;
}

static void run(lua_State *L, const char *source) {
    int status = luaL_dostring(L, source);
    if (status != LUA_OK) fprintf(stderr, "%s\n", lua_tostring(L, -1));
    assert(status == LUA_OK);
}

/* A body's C stack is a real barrier until its own typed callback guard has
 * returned. A failing lua_call abandons that body before outer protected
 * closing; lua_pcall retains it, while pcallk transfers to its K function. */
static const char setup[] =
    "function check_close_yield(kind,mode) "
    "close_target=function() "
    "local outer <close> =setmetatable({},{__close=function(_,e) "
    "local i=debug.getinfo(2,'f');coroutine.yield('outer',i.func==pcall,"
    "i.func==call_plain,i.func==pcall_yieldable,e)end});"
    "if mode=='bodyerror' then error(17)end;"
    "local inner <close> =setmetatable({},{__close=function()"
    "if mode=='closeerror' then error(17)end end});return 100 end;"
    "local co=coroutine.wrap(function()return pcall(_G[kind])end);"
    "local a=table.pack(pcall(co));"
    "if kind=='pcall_plain' or (kind=='call_plain' and mode=='normal') then "
    "if kind=='pcall_plain' then assert(a.n==4 and a[1] and a[2] "
    "and a[3]==2 and a[4]=='attempt to yield across a C-call boundary') "
    "else assert(a.n==3 and a[1] and not a[2] and "
    "a[3]=='attempt to yield across a C-call boundary')end;"
    "local b=table.pack(pcall(co));assert(b.n==2 and not b[1] "
    "and b[2]=='cannot resume dead coroutine') "
    "else assert(a.n==6 and a[1] and a[2]=='outer' and "
    "a[3]==(kind=='call_plain') and not a[4] and "
    "a[5]==(kind=='pcall_yieldable' and mode~='normal') and "
    "a[6]==(mode~='normal' and 17 or nil));"
    "local b=table.pack(pcall(co));"
    "if kind=='call_plain' then assert(b.n==3 and b[1] and not b[2] "
    "and b[3]==17)else assert(b.n==4 and b[1] and b[2] and "
    "b[3]==(mode=='normal' and 1 or 2) and "
    "b[4]==(mode=='normal' and 100 or 17))end end end";

static void check(lua_State *L, const char *kind, const char *mode) {
    assert(lua_gettop(L) == 0);
    lua_getglobal(L, "check_close_yield");
    lua_pushstring(L, kind);
    lua_pushstring(L, mode);
    lua_call(L, 2, 0);
    assert(lua_gettop(L) == 0);
    printf("PASS: close-yield-%s-%s\n", kind, mode);
    fflush(stdout);
}

static void unhandled_traceback(lua_State *L) {
    lua_State *co;
    lua_Debug ar;
    const char *name;
    int count = 0;
    /* lua_resume's error catch does not reset its failed CallInfo graph or
     * close TBC slots. Both ordinary locals remain inspectable/rooted until
     * an explicit reset; an outer Lua pcall has different closing semantics. */
    run(L, "closed=0;failed_weak=setmetatable({},{__mode='v'});"
        "close_target=function()local before={};failed_weak[1]=before;"
        "local c <close> =setmetatable({},{__close=function()closed=closed+1 "
        "end});local after={};failed_weak[2]=after;error(17)end");
    co = lua_newthread(L);
    lua_pushcfunction(co, call_plain);
    assert(lua_resume(co, L, 0, &count) == LUA_ERRRUN && count >= 1);
    assert(lua_tointeger(co, -1) == 17);
    lua_getglobal(L, "closed");
    assert(lua_tointeger(L, -1) == 0);
    lua_pop(L, 1);
    lua_gc(L, LUA_GCCOLLECT);
    run(L, "assert(failed_weak[1] and failed_weak[2] and closed==0)");
    assert(lua_getstack(co, 1, &ar));
    assert(lua_getinfo(co, "S", &ar) && strcmp(ar.what, "Lua") == 0);
    /* getlocal pushes onto the failed thread's current C API window. */
    assert(lua_checkstack(co, 2));
    name = lua_getlocal(co, &ar, 1);
    assert(name && strcmp(name, "before") == 0 && lua_istable(co, -1));
    lua_pop(co, 1);
    name = lua_getlocal(co, &ar, 3);
    assert(name && strcmp(name, "after") == 0 && lua_istable(co, -1));
    lua_pop(co, 1);
    lua_settop(L, 0);
    puts("PASS: close-yield-unhandled-traceback");
}

static void suspended_callk_inner_protection(lua_State *L) {
    /* An error caught inside the Lua callee cannot abandon the surrounding
     * callk continuation. Its already suspended C body still owns a valid K. */
    callk_continued = 0;
    run(L, "close_target=function()coroutine.yield('first');"
        "local a,b=pcall(error,23);assert(not a and b==23);return 77 end;"
        "local co=coroutine.wrap(function()return pcall(call_yieldable)end);"
        "assert(co()=='first');local a,b=co();assert(a and b==77)");
    assert(callk_continued == 1);
    puts("PASS: close-yield-suspended-callk-inner-protection");
}

static void suspended_callk_error_closing(lua_State *L) {
    /* An escaping error never calls an unprotected callk's K. Its original
     * guard is already gone, so the outer Lua pcall owns yieldable closing. */
    callk_continued = 0;
    run(L, "close_target=function()coroutine.yield('first');"
        "local c <close> =setmetatable({},{__close=function(_,e)"
        "assert(debug.getinfo(2,'f').func==pcall);"
        "coroutine.yield('closing',e)end});error(17)end;"
        "local co=coroutine.wrap(function()return pcall(call_yieldable)end);"
        "assert(co()=='first');local a,b=co();assert(a=='closing' and b==17);"
        "a,b=co();assert(a==false and b==17)");
    assert(callk_continued == 0);
    puts("PASS: close-yield-suspended-callk-error-closing");
}

static void refusing_error_transfer(lua_State *L) {
    /* Warm actual frames/packet capacity, then refuse every growth after the
     * C error object is ready until its first real closer runs after guard ACK.
     * Deferring/adopting scopes and publishing the error view must not retry
     * an allocator or replace the original integer error with memory failure. */
    refusal_closed = refusal_stable = 0;
    run(L, "refusal_object=setmetatable({},{__close=release_refusal});"
        "close_target=function(refuse)local c <close> =refusal_object;"
        "raise_refusing(refuse)end;"
        "for i=1,2 do local a,b=pcall(call_refusing,false);"
        "assert(not a and b==17)end;"
        "local a,b=pcall(call_refusing,true);assert(not a and b==17)");
    assert(refusal_closed == 3 && refusal_stable && !counts.refuse);
    puts("PASS: close-yield-refusing-error-transfer");
}

int main(void) {
    lua_State *L = lua_newstate(counted_allocator, &counts, 371U);
    assert(L);
    luaL_openlibs(L);
    lua_register(L, "call_plain", call_plain);
    lua_register(L, "pcall_plain", pcall_plain);
    lua_register(L, "pcall_yieldable", pcall_yieldable);
    lua_register(L, "call_yieldable", call_yieldable);
    lua_register(L, "call_refusing", call_refusing);
    lua_register(L, "raise_refusing", raise_refusing);
    lua_register(L, "release_refusal", release_refusal);
    run(L, setup);
    check(L, "call_plain", "normal");
    check(L, "call_plain", "bodyerror");
    check(L, "call_plain", "closeerror");
    check(L, "pcall_plain", "normal");
    check(L, "pcall_plain", "bodyerror");
    check(L, "pcall_plain", "closeerror");
    check(L, "pcall_yieldable", "normal");
    check(L, "pcall_yieldable", "bodyerror");
    check(L, "pcall_yieldable", "closeerror");
    unhandled_traceback(L);
    suspended_callk_inner_protection(L);
    suspended_callk_error_closing(L);
    refusing_error_transfer(L);
    lua_close(L);
    assert(counts.bytes == 0 && counts.blocks == 0);
    puts("PASS: real C ownership during error closing");
    return 0;
}
