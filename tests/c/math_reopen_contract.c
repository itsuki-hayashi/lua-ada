/* Public C library reopening regressions. The same contract runs against the
 * separately built pinned C oracle and the actual Ada implementation.
 * Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE. */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <assert.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include "../../c_api/tests/consumer_allocator.h"

static int run(lua_State *L, const char *source) {
    int status = luaL_loadbufferx(L, source, strlen(source),
                                 "@math-reopen-contract", "t");
    if (status == LUA_OK) status = lua_pcall(L, 0, 0, 0);
    return status;
}

static int second_math(lua_State *L) {
    lua_pushcfunction(L, luaopen_math);
    if (lua_pcall(L, 0, 1, 0) != LUA_OK) return 1;
    lua_setglobal(L, "second");
    return 0;
}

int lua_ada_test_math_reopen_contract(int which) {
    lua_State *L = luaL_newstate();
    int result = 0;
    struct allocation_counts counts = {0};
    if (L == NULL) return 100;
    luaL_openlibs(L);
    lua_getglobal(L, "math");
    lua_setglobal(L, "first");
    switch (which) {
    case 1:
        /* Allocating/opening another math table must not reset the first
         * table's deterministic stream, even before the second is seeded. */
        result = run(L, "first.randomseed(1007,0); "
            "EXPECTED=first.random(0); first.randomseed(1007,0)");
        if (!result) result = second_math(L);
        if (!result) result = run(L, "assert(first~=second); "
            "assert(first.random(0)==EXPECTED)");
        break;
    case 2:
        /* Each pair of exports shares one generator, while two opened tables
         * seeded identically advance independently rather than interleaving. */
        result = second_math(L);
        if (!result) result = run(L,
            "first.randomseed(17,-9); second.randomseed(17,-9); "
            "local a,b=first.random(0),first.random(0); "
            "assert(second.random(0)==a and second.random(0)==b); "
            "second.randomseed(99,0); first.randomseed(17,-9); "
            "assert(first.random(0)==a)");
        break;
    case 3:
        /* A retained random/randomseed pair must retain its actual userdata
         * after every library/global reference to the old table is dropped. */
        result = run(L,
            "old_random,old_seed=first.random,first.randomseed; "
            "old_seed(1007,0); EXPECTED=old_random(0); old_seed(1007,0)");
        if (!result) result = second_math(L);
        if (!result) result = run(L,
            "first=nil; math=second; package.loaded.math=second; "
            "collectgarbage(); assert(old_random(0)==EXPECTED); "
            "old_seed(1007,0); second.randomseed(99,0); "
            "collectgarbage(); assert(old_random(0)==EXPECTED)");
        break;
    case 4:
        /* Lua exposes one actual userdata upvalue shared by this module's
         * two random closures. Another module owns a distinct payload. */
        result = second_math(L);
        if (!result) result = run(L,
            "local _,a=debug.getupvalue(first.random,1); "
            "local _,b=debug.getupvalue(first.randomseed,1); "
            "local _,c=debug.getupvalue(second.random,1); "
            "assert(type(a)=='userdata' and rawequal(a,b)); "
            "assert(not rawequal(a,c))");
        break;
    case 5:
        /* Sustained provider refusal may interrupt module construction at
         * any real allocation. The existing generator must remain untouched,
         * and restoring allocation must permit a later successful opening. */
        lua_close(L);
        L = lua_newstate(counted_allocator, &counts, 0);
        if (L == NULL) return 102;
        luaL_openlibs(L);
        lua_getglobal(L, "math");
        lua_setglobal(L, "first");
        result = run(L, "first.randomseed(1007,0); "
            "EXPECTED=first.random(0); first.randomseed(1007,0)");
        if (!result) {
            lua_pushcfunction(L, luaopen_math);
            counts.refuse = 1;
            result = lua_pcall(L, 0, 1, 0);
            counts.refuse = 0;
            if (result != LUA_ERRMEM) result = 103;
            else {
                lua_pop(L, 1);
                result = run(L, "assert(first.random(0)==EXPECTED)");
                if (!result) result = second_math(L);
            }
        }
        break;
    default: result = 101;
    }
    lua_close(L);
    if (which == 5 && (counts.bytes != 0 || counts.blocks != 0)) result = 104;
    return result;
}
