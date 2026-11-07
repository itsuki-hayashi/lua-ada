/* Real public-API continuation and library consumers. Each numbered entry is
 * registered as a separate AUnit case. No reference interpreter is linked.
 * Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE. */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <stdint.h>
#include <string.h>

static int continued, returned, observed_status, opened;
static lua_KContext observed_context;
static int nested_depth;

static int record_continuation(lua_State *L, int status, lua_KContext context) {
    ++continued;
    observed_status = status;
    observed_context = context;
    return lua_gettop(L) - 1;
}

static int leaf(lua_State *L) { lua_pushinteger(L, 31); return 1; }
static int fail_leaf(lua_State *L) {
    lua_pushliteral(L, "consumer failure");
    return lua_error(L);
}

static int synchronous_call(lua_State *L) {
    lua_pushcfunction(L, leaf);
    lua_callk(L, 0, 1, (lua_KContext)123, record_continuation);
    ++returned;
    return 1;
}

static int synchronous_protection(lua_State *L) {
    int status;
    lua_pushcfunction(L, fail_leaf);
    status = lua_pcallk(L, 0, 1, 0, (lua_KContext)456,
                       record_continuation);
    ++returned;
    lua_pushinteger(L, status);
    return 2;
}

static int finish_yield(lua_State *L, int status, lua_KContext context) {
    ++continued;
    observed_status = status;
    observed_context = context;
    lua_settop(L, 0);
    lua_pushinteger(L, 42);
    return 1;
}

static int initial_yield(lua_State *L) {
    lua_pushinteger(L, 11);
    return lua_yieldk(L, 1, (lua_KContext)(INTPTR_MAX - 17), finish_yield);
}

static int repeat_yield(lua_State *L, int status, lua_KContext context) {
    ++continued;
    observed_status = status;
    lua_settop(L, 0);
    lua_pushinteger(L, (lua_Integer)context);
    if (context != 0) return lua_yieldk(L, 1, context - 1, repeat_yield);
    return 1;
}

static int initial_repeated_yield(lua_State *L) {
    lua_pushinteger(L, 3);
    return lua_yieldk(L, 1, 2, repeat_yield);
}

static int fixed_call(lua_State *L) {
    lua_pushvalue(L, 1);
    lua_callk(L, 0, 1, 1, record_continuation);
    ++returned;
    return 1;
}
static int zero_call(lua_State *L) {
    lua_pushvalue(L, 1);
    lua_callk(L, 0, 0, 0, record_continuation);
    ++returned;
    return 0;
}
static int multiple_call(lua_State *L) {
    lua_pushvalue(L, 1);
    lua_callk(L, 0, LUA_MULTRET, 2, record_continuation);
    ++returned;
    return lua_gettop(L) - 1;
}
static int protected_call(lua_State *L) {
    int status;
    lua_pushvalue(L, 1);
    status = lua_pcallk(L, 0, LUA_MULTRET, 0, 9, record_continuation);
    observed_status = status;
    ++returned;
    return lua_gettop(L) - 1;
}
static int unyieldable_call(lua_State *L) {
    lua_pushvalue(L, 1);
    lua_call(L, 0, LUA_MULTRET);
    return lua_gettop(L) - 1;
}

static int captured_finish(lua_State *L, int status, lua_KContext context) {
    (void)context;
    ++continued;
    observed_status = status;
    lua_getfield(L, lua_upvalueindex(1), "token");
    return 1;
}
static int captured_yield(lua_State *L) {
    return lua_yieldk(L, 0, 0, captured_finish);
}
static int no_continuation_yield(lua_State *L) {
    lua_pushinteger(L, 11);
    return lua_yield(L, 1);
}
static void yielding_count_hook(lua_State *L, lua_Debug *ar) {
    (void)ar;
    lua_yield(L, 0);
}

static int weak_table(lua_State *L) {
    int status = luaL_loadstring(L,
        "return setmetatable({}, {__mode='v'})");
    return status == LUA_OK ? lua_pcall(L, 0, 1, 0) : status;
}

static int module_opener(lua_State *L) {
    ++opened;
    lua_newtable(L);
    lua_pushinteger(L, opened);
    lua_setfield(L, -2, "generation");
    return 1;
}

static int nested_finish(lua_State *L, int status, lua_KContext context) {
    ++continued;
    if (status != LUA_YIELD || context != 34) observed_status = -1;
    lua_pushinteger(L, 34);
    return lua_gettop(L);
}

static int nested_call(lua_State *L) {
    /* Remove this level's incoming argument before calling the next. Each
     * abandoned C body owns a different sentinel even in the same thread. */
    lua_settop(L, 0);
    --nested_depth;
    if (nested_depth == 0) {
        lua_getglobal(L, "coroutine");
        lua_getfield(L, -1, "yield");
        lua_remove(L, -2);
    } else lua_pushcfunction(L, nested_call);
    lua_pushliteral(L, "hello");
    lua_callk(L, 1, LUA_MULTRET, 34, nested_finish);
    ++returned;
    return lua_gettop(L);
}

/* Every coroutine remains rooted on its parent's actual stack while its
 * yielded public window is inspected and while collection runs. */
static int run_call_case(lua_State *L, int which) {
    lua_State *co = lua_newthread(L);
    int count = -1, status;
    lua_CFunction callback = which == 5 || which == 21 ? fixed_call :
        which == 6 ? zero_call : which == 7 ? multiple_call :
        which == 8 || which == 17 ? protected_call : unyieldable_call;
    lua_pushcfunction(co, callback);
    status = luaL_loadstring(co, which == 17 ? "error('after yield',0)" :
        which == 8 || which == 21 ?
        "coroutine.yield('wait'); error('after yield',0)" :
        "coroutine.yield('wait'); return 10,20");
    if (status != LUA_OK) return 101;
    status = lua_resume(co, L, 1, &count);
    if (which == 17) {
        if (status != LUA_OK || count != 1 || continued != 1 ||
            returned != 0 || observed_status != LUA_ERRRUN ||
            observed_context != 9) return 112;
        return lua_isstring(co, -1) &&
            strcmp(lua_tostring(co, -1), "after yield") == 0 ? 0 : 113;
    }
    if (which == 9) {
        /* Error unwinding can retain the callee/argument traceback window;
         * nresults therefore need not be one. Its top object is the error. */
        if (status != LUA_ERRRUN || lua_status(co) != LUA_ERRRUN || count < 1 ||
            !lua_isstring(co, -1) ||
            strstr(lua_tostring(co, -1), "yield") == NULL) return 102;
        return 0;
    }
    if (status != LUA_YIELD || count != 1 ||
        strcmp(lua_tostring(co, -1), "wait") != 0) return 103;
    status = lua_resume(co, L, 0, &count);
    if (which == 21) {
        /* callk has no protected-error boundary after its C body is gone. */
        if (status != LUA_ERRRUN || continued != 0 || returned != 0 ||
            count < 1 || !lua_isstring(co, -1)) return 114;
        return strcmp(lua_tostring(co, -1), "after yield") == 0 ? 0 : 115;
    }
    if (status != LUA_OK || continued != 1 || returned != 0) return 104;
    if (observed_status != (which == 8 ? LUA_ERRRUN : LUA_YIELD)) return 105;
    if (observed_context != (which == 5 ? 1 : which == 6 ? 0 :
                             which == 7 ? 2 : 9)) return 106;
    if (which == 6) return count == 0 ? 0 : 107;
    if (count != (which == 7 ? 2 : 1)) return 108;
    if (which == 8)
        return strcmp(lua_tostring(co, -1), "after yield") == 0 ? 0 : 109;
    if (lua_tointeger(co, -count) != 10) return 110;
    if (which == 7 && lua_tointeger(co, -1) != 20) return 111;
    return 0;
}

int lua_ada_test_continuation_contract(int which) {
    lua_State *L = luaL_newstate(), *co;
    int result = 0, status, count = -1, i, saved_top;
    if (L == NULL) return 1;
    continued = returned = observed_status = opened = 0;
    observed_context = 0;
    luaL_openlibs(L);
    switch (which) {
    case 1:
        /* A nonyieldable host call returns to its original C body. The
         * unused K pointer must neither execute nor replace its result. */
        lua_pushcfunction(L, synchronous_call);
        status = lua_pcall(L, 0, 1, 0);
        if (status != LUA_OK || continued != 0 || returned != 1 ||
            lua_tointeger(L, -1) != 31) result = 11;
        break;
    case 2:
        /* On the main host boundary K is ignored, including an immediate
         * protected error. The original C body receives the actual status. */
        lua_pushcfunction(L, synchronous_protection);
        status = lua_pcall(L, 0, 2, 0);
        if (status != LUA_OK || continued != 0 || returned != 1 ||
            lua_tointeger(L, -1) != LUA_ERRRUN ||
            strcmp(lua_tostring(L, -2), "consumer failure") != 0) result = 12;
        break;
    case 3:
        /* The second resume runs K after abandoning the original C stack.
         * A near-maximum intptr context catches narrowing to a C int. */
        co = lua_newthread(L);
        lua_pushcfunction(co, initial_yield);
        status = lua_resume(co, L, 0, &count);
        if (status != LUA_YIELD || lua_status(co) != LUA_YIELD || count != 1 ||
            lua_tointeger(co, -1) != 11) { result = 13; break; }
        status = lua_resume(co, L, 0, &count);
        if (status != LUA_OK || lua_status(co) != LUA_OK || count != 1 ||
            lua_tointeger(co, -1) != 42 ||
            continued != 1 || observed_status != LUA_YIELD ||
            observed_context != (lua_KContext)(INTPTR_MAX - 17)) result = 14;
        break;
    case 4:
        /* K can itself yield three times. Every public window contains only
         * that delivery, and the final resume completes rather than repeats. */
        co = lua_newthread(L);
        lua_pushcfunction(co, initial_repeated_yield);
        for (i = 3; i >= 0; --i) {
            status = lua_resume(co, L, 0, &count);
            if (status != (i == 0 ? LUA_OK : LUA_YIELD) || count != 1 ||
                lua_tointeger(co, -1) != i) { result = 15; break; }
        }
        if (continued != 3) result = 16;
        break;
    case 5: case 6: case 7: case 8: case 9:
        /* Each separately registered case resumes a real Lua callee through
         * a C boundary with zero/fixed/open results, errors or forbidden yield. */
        result = run_call_case(L, which);
        break;
    case 10:
        /* The first resume completes a C root. A later resume must expose a
         * real dead-coroutine error without rerunning the original function. */
        co = lua_newthread(L);
        lua_pushcfunction(co, leaf);
        status = lua_resume(co, L, 0, &count);
        if (status != LUA_OK || count != 1) { result = 17; break; }
        /* Remove the returned31 before trying to resume an empty dead root.
         * Leaving it there asks native Lua to call31 as a fresh function. */
        lua_settop(co, 0);
        status = lua_resume(co, L, 0, &count);
        if (status != LUA_ERRRUN || count != 1 ||
            strstr(lua_tostring(co, -1), "dead") == NULL) result = 18;
        break;
    case 11:
        /* No outside reference retains the captured table. Its C closure and
         * suspended activation must trace it through an actual full collection. */
        co = lua_newthread(L);
        lua_newtable(co);
        lua_pushinteger(co, 73);
        lua_setfield(co, -2, "token");
        lua_pushcclosure(co, captured_yield, 1);
        status = lua_resume(co, L, 0, &count);
        if (status != LUA_YIELD || count != 0) { result = 19; break; }
        lua_gc(L, LUA_GCCOLLECT);
        status = lua_resume(co, L, 0, &count);
        if (status != LUA_OK || count != 1 || lua_tointeger(co, -1) != 73 ||
            continued != 1 || observed_status != LUA_YIELD) result = 20;
        break;
    case 12:
        /* Requiring twice and reading the global must identify one actual
         * module table, with only one invocation of its public C opener. */
        luaL_requiref(L, "consumer.module", module_opener, 1);
        luaL_requiref(L, "consumer.module", module_opener, 0);
        lua_getglobal(L, "consumer.module");
        if (opened != 1 || !lua_rawequal(L, -1, -2) ||
            !lua_rawequal(L, -2, -3)) result = 21;
        break;
    case 13:
        /* A false loaded entry requests reopening. This differs from a true
         * cached result and must produce another real module instance. */
        luaL_requiref(L, "consumer.module", module_opener, 0);
        lua_getfield(L, LUA_REGISTRYINDEX, LUA_LOADED_TABLE);
        lua_pushboolean(L, 0);
        lua_setfield(L, -2, "consumer.module");
        lua_pop(L, 1);
        luaL_requiref(L, "consumer.module", module_opener, 0);
        if (opened != 2 || lua_rawequal(L, -1, -2)) result = 22;
        break;
    case 14:
        /* A fresh bare state opens only base/package and preloads coroutine.
         * Requiring it later executes the real opener and caches its result. */
        lua_close(L);
        L = luaL_newstate();
        if (L == NULL) return 2;
        luaL_openselectedlibs(L, LUA_GLIBK | LUA_LOADLIBK, LUA_COLIBK);
        lua_getglobal(L, "coroutine");
        if (!lua_isnil(L, -1)) { result = 23; break; }
        lua_pop(L, 1);
        status = luaL_loadstring(L,
            "local c=require'coroutine'; assert(type(c)=='table'); "
            "assert(require'coroutine'==c); return 87");
        if (status == LUA_OK) status = lua_pcall(L, 0, 1, 0);
        if (status != LUA_OK || lua_tointeger(L, -1) != 87) result = 24;
        break;
    case 15:
        /* A bit selected in both masks is opened eagerly. Its public global
         * and registry entry must identify the same installed module. */
        luaL_openselectedlibs(L, LUA_COLIBK, LUA_COLIBK);
        lua_getglobal(L, "coroutine");
        lua_getfield(L, LUA_REGISTRYINDEX, LUA_LOADED_TABLE);
        lua_getfield(L, -1, "coroutine");
        if (!lua_istable(L, -1) || !lua_rawequal(L, -1, -3)) result = 25;
        break;
    case 16:
        /* Ordinary public indexing must run the real Lua metamethod. Raw
         * lookup of another absent key bypasses it and leaves the count. */
        status = luaL_loadstring(L,
            "return setmetatable({n=0},{__index=function(t,k) "
            "t.n=t.n+1; return 12 end,__newindex=function(t,k,v) "
            "rawset(t,k,v*2) end})");
        if (status == LUA_OK) status = lua_pcall(L, 0, 1, 0);
        if (status != LUA_OK) { result = 26; break; }
        lua_getfield(L, -1, "missing");
        if (lua_tointeger(L, -1) != 12) { result = 27; break; }
        lua_pop(L, 1);
        lua_pushinteger(L, 4);
        lua_setfield(L, -2, "stored");
        lua_pushliteral(L, "stored");
        lua_rawget(L, -2);
        if (lua_tointeger(L, -1) != 8) { result = 28; break; }
        lua_pop(L, 1);
        lua_pushliteral(L, "other");
        lua_rawget(L, -2);
        if (!lua_isnil(L, -1)) { result = 29; break; }
        lua_pop(L, 1);
        lua_getfield(L, -1, "n");
        if (lua_tointeger(L, -1) != 1) result = 30;
        break;
    case 17:
        /* In a yieldable frame immediate protected errors invoke K even when
         * the called Lua function has never yielded; the C body is abandoned. */
        result = run_call_case(L, which);
        break;
    case 18:
        /* Being yieldable does not alone invoke K. An ordinary synchronous
         * success returns to its C body, unlike immediate protected errors. */
        co = lua_newthread(L);
        lua_pushcfunction(co, synchronous_call);
        status = lua_resume(co, L, 0, &count);
        if (status != LUA_OK || count != 1 || continued != 0 ||
            returned != 1 || lua_tointeger(co, -1) != 31) result = 31;
        break;
    case 19:
        /* 'from' supplies C-call depth and may be an independent state.
         * It must not replace the resumed coroutine's owning universe. */
        {
            lua_State *from = luaL_newstate();
            if (from == NULL) { result = 32; break; }
            co = lua_newthread(L);
            lua_pushcfunction(co, leaf);
            status = lua_resume(co, from, 0, &count);
            if (status != LUA_OK || count != 1 ||
                lua_tointeger(co, -1) != 31) result = 33;
            lua_pushinteger(from, 99);
            if (lua_tointeger(co, -1) != 31 ||
                lua_tointeger(from, -1) != 99) result = 34;
            lua_close(from);
        }
        break;
    case 20:
        /* Three live C pumps suspend in order. Each must mark and later
         * resume its own boundary, yielding hello then collecting three34s.
         * Marking the nearest sentinel repeatedly loses the outer owners. */
        nested_depth = 3;
        co = lua_newthread(L);
        lua_pushcfunction(co, nested_call);
        lua_pushnil(co);
        status = lua_resume(co, L, 1, &count);
        if (status != LUA_YIELD || count != 1 ||
            !lua_isstring(co, -1) ||
            strcmp(lua_tostring(co, -1), "hello") != 0) {
            result = 35;
            break;
        }
        status = lua_resume(co, L, 0, &count);
        if (status != LUA_OK || count != 3 || continued != 3 ||
            returned != 0 || observed_status == -1) {
            result = 36;
            break;
        }
        for (i = 1; i <= 3; ++i)
            if (lua_tointeger(co, -i) != 34) result = 37;
        break;
    case 21:
        /* Unlike pcallk, an unprotected callk cannot recover a callee error
         * after suspension by invoking K as if the protected call failed. */
        result = run_call_case(L, which);
        break;
    case 22:
        /* The outer call owns K even when its C child yields without K.
         * Looking only at the deepest activation loses the outer boundary. */
        co = lua_newthread(L);
        lua_pushcfunction(co, fixed_call);
        lua_pushcfunction(co, no_continuation_yield);
        status = lua_resume(co, L, 1, &count);
        if (status != LUA_YIELD || count != 1 ||
            lua_tointeger(co, -1) != 11) { result = 38; break; }
        lua_pushinteger(co, 97);
        status = lua_resume(co, L, 1, &count);
        if (status != LUA_OK || count != 1 || continued != 1 || returned ||
            lua_tointeger(co, -1) != 97) result = 39;
        break;
    case 23:
        /* Lua consumes the first delivery. Later C pushes and resume must
         * use a separate public window, preserving retained Lua locals. */
        status = luaL_loadstring(L,
            "local co=coroutine.create(function() local keep=19; "
            "local x=coroutine.yield('lua delivery'); return keep,x end); "
            "local ok,v=coroutine.resume(co); "
            "assert(ok and v=='lua delivery'); return co");
        if (status == LUA_OK) status = lua_pcall(L, 0, 1, 0);
        if (status != LUA_OK) { result = 40; break; }
        co = lua_tothread(L, -1);
        if (co == NULL) { result = 41; break; }
        lua_pushinteger(co, 97);
        status = lua_resume(co, L, 1, &count);
        if (status != LUA_OK || count != 2 ||
            lua_tointeger(co, -2) != 19 || lua_tointeger(co, -1) != 97)
            result = 42;
        break;
    case 24:
        /* Dead high temporaries of a retained Lua frame must not become
         * roots merely because public C yield results occupy higher slots. */
        if (weak_table(L) != LUA_OK) { result = 43; break; }
        co = lua_newthread(L);
        status = luaL_loadstring(co,
            "local w=...; do local a,b,c={},{},{}; "
            "w[1],w[2],w[3]=a,b,c end; coroutine.yield(); return true");
        if (status != LUA_OK) { result = 44; break; }
        lua_pushvalue(L, 1);
        lua_xmove(L, co, 1);
        status = lua_resume(co, L, 1, &count);
        if (status != LUA_YIELD || count != 0) { result = 45; break; }
        lua_gc(L, LUA_GCCOLLECT);
        for (i = 1; i <= 3; ++i) {
            lua_rawgeti(L, 1, i);
            if (!lua_isnil(L, -1)) result = 46;
            lua_pop(L, 1);
        }
        status = lua_resume(co, L, 0, &count);
        if (status != LUA_OK || count != 1 || !lua_toboolean(co, -1))
            result = 47;
        break;
    case 25:
        /* A hook interrupts an instruction, so its resume arguments are
         * discarded. Keeping them in a hidden Lua result packet leaks roots. */
        if (weak_table(L) != LUA_OK) { result = 48; break; }
        co = lua_newthread(L);
        status = luaL_loadstring(co, "local a=1; a=a+1; return a");
        if (status != LUA_OK) { result = 49; break; }
        lua_sethook(co, yielding_count_hook, LUA_MASKCOUNT, 1);
        status = lua_resume(co, L, 0, &count);
        if (status != LUA_YIELD || count != 0) { result = 50; break; }
        saved_top = lua_gettop(co);
        /* Hook suspension leaves a Lua frame at its actual top. Public C
         * pushes must first request space, as the instrumented API checks. */
        if (!lua_checkstack(co, 2)) { result = 54; break; }
        lua_newtable(co);
        lua_pushvalue(co, -1);
        lua_xmove(co, L, 1);
        lua_rawseti(L, 1, 1);
        status = lua_resume(co, L, 1, &count);
        if (status != LUA_YIELD || count != 0) { result = 51; break; }
        /* Native traceexec exposes ci.top, including the capacity requested
         * above. Explicitly retire that public tail before observing weak
         * reachability; this does not remove any hidden argument packet. */
        lua_settop(co, saved_top);
        lua_gc(L, LUA_GCCOLLECT);
        lua_rawgeti(L, 1, 1);
        if (!lua_isnil(L, -1)) result = 52;
        lua_sethook(co, NULL, 0, 0);
        status = lua_resume(co, L, 0, &count);
        if (status != LUA_OK || count != 1 || lua_tointeger(co, -1) != 2)
            result = 53;
        break;
    default: result = 3;
    }
    lua_close(L);
    return result;
}
