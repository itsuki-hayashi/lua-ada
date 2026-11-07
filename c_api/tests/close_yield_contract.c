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

int main(void) {
    lua_State *L = lua_newstate(counted_allocator, &counts, 371U);
    assert(L);
    luaL_openlibs(L);
    lua_register(L, "call_plain", call_plain);
    lua_register(L, "pcall_plain", pcall_plain);
    lua_register(L, "pcall_yieldable", pcall_yieldable);
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
    lua_close(L);
    assert(counts.bytes == 0 && counts.blocks == 0);
    puts("PASS: real C ownership during error closing");
    return 0;
}
