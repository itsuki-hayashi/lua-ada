/* Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE.
 * Focused public-header consumer cases for the production hook boundary.
 * No private runtime layouts or test-adapter observations are used. */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include "../../c_api/tests/consumer_allocator.h"

struct hook_observation {
    lua_State *expected;
    int calls, failed, remove_self;
    lua_Debug retained;
};
static struct hook_observation *observation;
static int closed, close_failed, expected_close_error, close_continued;
static int hook_generation, count_generation, combined_lines, combined_failed;
static int view_mode, view_hits, view_failed;

static int fail_in_hook(lua_State *L) {
    lua_pushliteral(L, "nested hook failure");
    return lua_error(L);
}

/* Report callback failures through the owning named case rather than aborting
 * the complete AUnit process. The line identifies the violated public fact. */
#define VIEW_CHECK(condition) do { if (!(condition)) { \
    view_failed = __LINE__; return; } } while (0)
static void stack_view_hook(lua_State *L, lua_Debug *ar) {
    static const char *const names[] = {"a", "b", "x"};
    static const lua_Integer values[] = {5, 7, 37};
    lua_Debug frame;
    int before, i;
    if (ar->event != LUA_HOOKLINE || ar->currentline != 3) return;
    ++view_hits;
    before = lua_gettop(L);
    VIEW_CHECK(before >= 3);
    VIEW_CHECK(lua_getstack(L, 0, &frame));
    VIEW_CHECK(lua_getinfo(L, "S", &frame));
    VIEW_CHECK(strcmp(frame.what, "Lua") == 0);
    for (i = 1; i <= 3; ++i) {
        const char *name;
        VIEW_CHECK(lua_isinteger(L, i) &&
                   lua_tointeger(L, i) == values[i-1]);
        name = lua_getlocal(L, &frame, i);
        VIEW_CHECK(name && strcmp(name, names[i-1]) == 0);
        VIEW_CHECK(lua_tointeger(L, -1) == values[i-1]);
        lua_pop(L, 1);
        VIEW_CHECK(lua_gettop(L) == before);
    }
    /* Removing the installation cannot remove this active hook's borrowed
     * cells or its real hook origin during a nested Lua call. */
    lua_sethook(L, NULL, 0, 0);
    if (view_mode == 2) {
        lua_getglobal(L, "hook_nested");
        lua_pushinteger(L, 40);
        lua_call(L, 1, 1);
        VIEW_CHECK(lua_gettop(L) == before + 1 &&
                   lua_tointeger(L, -1) == 41);
        lua_pop(L, 1);
    } else if (view_mode == 3) {
        lua_pushcfunction(L, fail_in_hook);
        VIEW_CHECK(lua_pcall(L, 0, 1, 0) == LUA_ERRRUN);
        VIEW_CHECK(lua_gettop(L) == before + 1);
        VIEW_CHECK(strcmp(lua_tostring(L, -1), "nested hook failure") == 0);
        lua_pop(L, 1);
    } else if (view_mode == 4) {
        lua_pushinteger(L, 17);
        lua_error(L);
        VIEW_CHECK(0);
    } else if (view_mode == 5) {
        lua_getglobal(L, "hook_yield");
        VIEW_CHECK(lua_pcall(L, 0, 0, 0) == LUA_ERRRUN);
        VIEW_CHECK(strstr(lua_tostring(L, -1), "C-call boundary"));
        lua_pop(L, 1);
    } else if (view_mode == 6) {
        /* A direct hook yield returns zero normally, then suspends only
         * after the hook returns. No foreign jump may cross an Ada frame. */
        VIEW_CHECK(lua_yield(L, 0) == 0);
        return;
    }
    VIEW_CHECK(lua_gettop(L) == before);
    lua_pushinteger(L, 40);
    lua_replace(L, 3);
    VIEW_CHECK(lua_gettop(L) == before && lua_tointeger(L, 3) == 40);
}
#undef VIEW_CHECK

static int stack_view_contract(lua_State *L, int which) {
    lua_State *thread;
    int status, count;
    luaL_openlibs(L);
    if (luaL_dostring(L,
        "function hook_target(a,b)\n local x=37\n return a+x,b\nend\n"
        "function hook_nested(x)local n=debug.getinfo(1,'n');"
        "assert(n.namewhat=='hook' and n.name=='?');return x+1 end\n"
        "function hook_yield()coroutine.yield(9)end") != LUA_OK) return 70;
    view_mode = which; view_hits = view_failed = 0;
    thread = which >= 5 ? lua_newthread(L) : L;
    lua_getglobal(L, "hook_target");
    if (thread != L) lua_xmove(L, thread, 1);
    lua_pushinteger(thread, 5);
    lua_pushinteger(thread, 7);
    lua_sethook(thread, stack_view_hook, LUA_MASKLINE, 0);
    if (which >= 5) {
        status = lua_resume(thread, L, 2, &count);
        if (which == 6) {
            if (status != LUA_YIELD || count != 0 || view_hits != 1)
                return 71;
            status = lua_resume(thread, L, 0, &count);
        }
        if (status != LUA_OK || count != 2) return 72;
    } else status = lua_pcall(L, 2, 2, 0);
    if (view_failed) return view_failed;
    if (view_hits != 1) return 73;
    if (which == 4) {
        if (status != LUA_ERRRUN || lua_tointeger(L, -1) != 17) return 74;
        lua_settop(L, 0);
        if (luaL_dostring(L, "return 37") != LUA_OK ||
            lua_tointeger(L, -1) != 37) return 75;
    } else if (status != LUA_OK ||
        lua_tointeger(thread, -2) != (which == 6 ? 42 : 45) ||
        lua_tointeger(thread, -1) != 7) return 76;
    return 0;
}

static int captured_result(lua_State *L) {
    lua_pushvalue(L, lua_upvalueindex(1));
    return 1;
}

static int returned_value(lua_State *L) {
    if (view_mode == 10) {
        lua_newtable(L);
        lua_getglobal(L, "weak_hook_value");
        lua_pushvalue(L, 1);
        lua_rawseti(L, -2, 1);
        lua_pop(L, 1);
    } else lua_pushinteger(L, 11);
    return 1;
}

static void returned_value_hook(lua_State *L, lua_Debug *ar) {
    int selected, top;
    if (ar->event != LUA_HOOKRET) return;
    if (!lua_getinfo(L, "fr", ar)) { view_failed=86; return; }
    selected = lua_tocfunction(L, -1) == returned_value;
    lua_pop(L, 1);
    if (!selected) return;
    ++view_hits;
    lua_sethook(L, NULL, 0, 0);
    top = lua_gettop(L);
    if (ar->ntransfer != 1 || ar->ftransfer < 1 ||
        ar->ftransfer > top) { view_failed=87; return; }
    if (view_mode == 10) lua_pushnil(L);
    else lua_pushinteger(L, 37);
    /* A custom C hook edits the same actual result cell through a raw
     * index. The result count is retained; only its value changes. */
    lua_replace(L, ar->ftransfer);
    if (view_mode == 10) {
        lua_gc(L, LUA_GCCOLLECT);
        lua_getglobal(L, "weak_hook_value");
        lua_rawgeti(L, -1, 1);
        if (!lua_isnil(L, -1)) view_failed=88;
        lua_pop(L, 2);
    }
    if (lua_gettop(L) != top) view_failed=89;
}

static int returned_value_contract(lua_State *L, int which) {
    int status;
    luaL_openlibs(L);
    if (luaL_dostring(L,
        "weak_hook_value=setmetatable({},{__mode='v'})") != LUA_OK)
        return 96;
    view_mode=which; view_hits=view_failed=0;
    lua_pushcfunction(L, returned_value);
    lua_sethook(L, returned_value_hook, LUA_MASKRET, 0);
    status=lua_pcall(L, 0, 1, 0);
    lua_sethook(L, NULL, 0, 0);
    if (status != LUA_OK || view_hits != 1) return 97;
    if (view_failed) return view_failed;
    if (which == 10) return lua_isnil(L, -1) ? 0 : 98;
    return lua_tointeger(L, -1) == 37 ? 0 : 99;
}

static void weak_view_hook(lua_State *L, lua_Debug *ar) {
    int selected;
    if (ar->event != LUA_HOOKCALL) return;
    if (!lua_getinfo(L, "f", ar)) { view_failed = 80; return; }
    if (view_mode == 7) {
        lua_getglobal(L, "type");
        selected = lua_rawequal(L, -1, -2);
        lua_pop(L, 1);
    } else selected = lua_tocfunction(L, -1) == captured_result;
    lua_pop(L, 1);
    if (!selected) return;
    ++view_hits;
    lua_sethook(L, NULL, 0, 0);
    /* Replacing the real argument/upvalue removes its only strong edge.
     * Collector-visible copied call packets must already have retired. */
    lua_pushnil(L);
    lua_replace(L, view_mode == 7 ? 1 : lua_upvalueindex(1));
    lua_gc(L, LUA_GCCOLLECT);
    lua_getglobal(L, "weak_hook_value");
    lua_rawgeti(L, -1, 1);
    if (!lua_isnil(L, -1)) view_failed = 81;
    lua_pop(L, 2);
}

static int weak_view_contract(lua_State *L, int which) {
    int status;
    luaL_openlibs(L);
    if (luaL_dostring(L,
        "local v={};weak_hook_value=setmetatable({v},{__mode='v'});"
        "return v") != LUA_OK) return 82;
    view_mode = which; view_hits = view_failed = 0;
    if (which == 8) {
        lua_pushcclosure(L, captured_result, 1);
    } else {
        lua_getglobal(L, "type");
        lua_insert(L, -2);
    }
    lua_sethook(L, weak_view_hook, LUA_MASKCALL, 0);
    status = lua_pcall(L, which == 7 ? 1 : 0, 1, 0);
    lua_sethook(L, NULL, 0, 0);
    if (status != LUA_OK || view_hits != 1) return 83;
    if (view_failed) return view_failed;
    if (which == 7) {
        if (!lua_isstring(L, -1) || strcmp(lua_tostring(L, -1), "nil") != 0)
            return 84;
    } else if (!lua_isnil(L, -1)) return 85;
    return 0;
}

struct release_view { lua_State *state; int released, failed; };
static void *release_in_lua(void *data, void *block, size_t old,
                            size_t size) {
    struct release_view *view = (struct release_view *)data;
    lua_State *L = view->state;
    lua_Debug frame;
    int base = lua_gettop(L), i;
    if (size != 0 || old != 65 ||
        !lua_getstack(L, 0, &frame) || !lua_getinfo(L, "S", &frame) ||
        strcmp(frame.what, "Lua") != 0 || base == 0) view->failed = 90;
    if (!lua_checkstack(L, 100)) view->failed = 91;
    if (!view->failed) {
        lua_pushinteger(L, base);
        lua_setglobal(L, "borrow_base");
        for (i = 0; i < 3; ++i) {
            char id[2] = {(char)('a' + i), 0};
            lua_newtable(L);
            lua_pushstring(L, id);
            lua_setfield(L, -2, "id");
            lua_getglobal(L, "borrow_mt");
            lua_setmetatable(L, -2);
        }
        lua_concat(L, 3);
        if (lua_gettop(L) != base + 1 || !lua_isstring(L, -1) ||
            strcmp(lua_tostring(L, -1), "joined") != 0) view->failed = 92;
        lua_pop(L, 1);
        if (lua_gettop(L) != base) view->failed = 93;
    }
    ++view->released;
    free(block);
    return NULL;
}

static int release_view_contract(lua_State *L) {
    struct release_view view = {L, 0, 0};
    char *payload;
    int status;
    luaL_openlibs(L);
    lua_gc(L, LUA_GCSTOP);
    payload = (char *)malloc(65);
    if (payload == NULL) return 94;
    memset(payload, 'e', 64); payload[64] = 0;
    lua_pushexternalstring(L, payload, 64, release_in_lua, &view);
    lua_setglobal(L, "external_pending");
    status = luaL_dostring(L,
        "local step=0;local replacement={id='replacement'};local result={};"
        "borrow_mt={__concat=function(x,y)step=step+1;"
        "assert(debug.getinfo(2,'f').func==borrow_worker);"
        "if step==1 then assert(x.id=='b' and y.id=='c');"
        "local _,v=debug.getlocal(2,borrow_base+1);assert(v.id=='a');"
        "local _,c=debug.getlocal(2,borrow_base+3);assert(c.id=='c');"
        "assert(debug.setlocal(2,borrow_base+1,replacement));return result "
        "else assert(x==replacement and y==result);"
        "assert(debug.getlocal(2,borrow_base+3)==nil);return 'joined'end end};"
        "setmetatable(replacement,borrow_mt);setmetatable(result,borrow_mt);"
        "function borrow_worker()external_pending=nil;"
        "for i=1,20000 do local t={i,i,i}end end");
    if (status == LUA_OK) {
        lua_gc(L, LUA_GCRESTART);
        status = luaL_dostring(L, "borrow_worker()");
    }
    /* Complete physical teardown while callback userdata is still alive.
     * The caller must not use L after this separately owned case returns. */
    lua_close(L);
    if (status != LUA_OK || view.released != 1) return 95;
    return view.failed;
}

static void combined_hook(lua_State *L, lua_Debug *ar) {
    if (ar->event == LUA_HOOKCOUNT) count_generation = hook_generation;
    else if (ar->event == LUA_HOOKLINE) {
        ++combined_lines;
        if (count_generation != hook_generation) combined_failed = 1;
    }
    lua_yield(L, 0);
}

static int combined_hook_contract(lua_State *L) {
    lua_State *co = lua_newthread(L);
    int status, count = -1;
    combined_lines = combined_failed = count_generation = 0;
    status = luaL_loadstring(co, "local x=1\nx=x+1\nreturn x\n");
    if (status != LUA_OK) return 40;
    lua_sethook(co, combined_hook, LUA_MASKLINE | LUA_MASKCOUNT, 1);
    /* A native instruction delivers both due events before one suspension.
     * Generation is incremented only by a real host resume, never by a hook. */
    for (hook_generation = 1; hook_generation <= 200; ++hook_generation) {
        status = lua_resume(co, L, 0, &count);
        if (status != LUA_YIELD) break;
        if (count != 0) return 41;
    }
    if (status != LUA_OK || count != 1 || lua_tointeger(co, -1) != 2 ||
        combined_lines < 2 || combined_failed) return 42;
    return 0;
}

static int observe_close(lua_State *L) {
    ++closed;
    lua_getfield(L, 1, "token");
    if (lua_tointeger(L, -1) != 71) close_failed = 1;
    lua_pop(L, 1);
    if (expected_close_error) {
        lua_getglobal(L, "close_error");
        if (!lua_rawequal(L, 2, -1)) close_failed = 2;
        lua_pop(L, 1);
    } else if (lua_gettop(L) != 1) close_failed = 3;
    /* Collect while the retiring C frame's result/error is held by the
     * actual unwind continuation. Neither value may be only a C local. */
    lua_gc(L, LUA_GCCOLLECT);
    return 0;
}

static int mark_and_return(lua_State *L) {
    lua_toclose(L, 1);
    lua_pushliteral(L, "retained result");
    return 1;
}

static int mark_and_error(lua_State *L) {
    lua_toclose(L, 1);
    lua_pushvalue(L, 2);
    return lua_error(L);
}

static int mark_and_trim(lua_State *L) {
    lua_pushvalue(L, 1);
    lua_setglobal(L, "close_item");
    lua_toclose(L, 1);
    lua_settop(L, 0);
    if (closed != 1) close_failed = 5;
    lua_getglobal(L, "close_item");
    lua_toclose(L, 1);
    lua_pushliteral(L, "retained result");
    return 1;
}

static int mark_and_close_slot(lua_State *L) {
    lua_toclose(L, 1);
    lua_closeslot(L, 1);
    if (closed != 1 || !lua_isnil(L, 1)) close_failed = 6;
    lua_pushliteral(L, "retained result");
    return 1;
}

static int return_31(lua_State *L) { lua_pushinteger(L, 31); return 1; }

static int refusal_reuse_contract(void) {
    int offset, refusals = 0;
    for (offset = 1; offset <= 64; ++offset) {
        struct allocation_counts counts = {0};
        lua_State *L = lua_newstate(counted_allocator, &counts, 0), *co;
        int status, count;
        if (L == NULL) return 50;
        luaL_openlibs(L);
        co = lua_newthread(L);
        status = luaL_loadstring(co,
            "local t={}; for i=1,100 do t[i]={i} end; "
            "coroutine.yield('pause'); return 31");
        if (status != LUA_OK) { lua_close(L); return 51; }
        counts.fail_after = counts.growths + (size_t)offset;
        status = lua_resume(co, L, 0, &count);
        /* A failed resume retains its precise public error class. Query it
         * before restoring allocation: lua_status is a scalar observation,
         * not a new allocation or a request to restart the failed thread. */
        if (status == LUA_ERRMEM && lua_status(co) != LUA_ERRMEM) {
            counts.fail_after = 0;
            lua_close(L); return 58;
        }
        counts.fail_after = 0;
        if (status == LUA_ERRMEM) ++refusals;
        else if (status == LUA_YIELD) {
            status = lua_resume(co, L, 0, &count);
            if (status != LUA_OK) { lua_close(L); return 52; }
        } else if (status != LUA_OK) { lua_close(L); return 53; }
        /* A refused child drive cannot strand the healthy caller's driver
         * or the child's ordinary scalar stack API. A failed coroutine is
         * dead; calling Lua on it without resetting is outside the native
         * API contract, so only the healthy parent performs a new call. */
        lua_pushcfunction(L, return_31);
        if (lua_pcall(L, 0, 1, 0) != LUA_OK || lua_tointeger(L, -1) != 31) {
            lua_close(L); return 54;
        }
        lua_settop(co, 0);
        lua_pushinteger(co, 31);
        if (lua_tointeger(co, -1) != 31) {
            lua_close(L); return 55;
        }
        /* Clearing/reusing the public stack must not erase the retained
         * memory failure or reclassify it as an ordinary runtime error. */
        if (status == LUA_ERRMEM && lua_status(co) != LUA_ERRMEM) {
            lua_close(L); return 59;
        }
        lua_close(L);
        if (counts.bytes != 0 || counts.blocks != 0) return 56;
    }
    return refusals > 0 ? 0 : 57;
}

static int suspended_index_contract(lua_State *L) {
    lua_State *co;
    int count, status;
    luaL_openlibs(L);
    co = lua_newthread(L);
    status = luaL_loadstring(co,
        "local t=setmetatable({token=7},{__index=function() "
        "collectgarbage('collect'); return 23 end,"
        "__newindex=function(t,k,v) rawset(t,k,v*2) end}); "
        "coroutine.yield(t); return t.token+t.stored+16");
    if (status != LUA_OK) return 60;
    status = lua_resume(co, L, 0, &count);
    if (status != LUA_YIELD || count != 1 || !lua_istable(co, 1)) return 61;
    /* Public indexing may execute a nonyieldable handler above a suspended
     * CallInfo. Its temporary root entry cannot consume the old activation
     * or erase unrelated values in the detached public result window. */
    if (lua_getfield(co, 1, "missing") != LUA_TNUMBER ||
        lua_tointeger(co, -1) != 23 || lua_gettop(co) != 2) return 62;
    lua_pop(co, 1);
    lua_pushinteger(co, 4);
    lua_setfield(co, 1, "stored");
    if (lua_gettop(co) != 1 || lua_status(co) != LUA_YIELD) return 63;
    lua_settop(co, 0);
    status = lua_resume(co, L, 0, &count);
    if (status != LUA_OK || count != 1 || lua_tointeger(co, -1) != 31)
        return 64;
    return 0;
}

static int call_base_error(lua_State *L) {
    lua_getglobal(L, "error");
    lua_pushliteral(L, "C caller error");
    lua_call(L, 1, 0);
    return 0;
}

static int close_continuation(lua_State *L, int status, lua_KContext context) {
    (void)L;
    ++close_continued;
    if (status != LUA_YIELD || context != 91) close_failed = 4;
    return 1;
}

static int mark_and_call(lua_State *L) {
    lua_toclose(L, 1);
    lua_pushvalue(L, 2);
    lua_callk(L, 0, 1, 91, close_continuation);
    return 1;
}

static int close_contract(lua_State *L, int which) {
    lua_State *co = NULL;
    int status, count;
    closed = close_failed = close_continued = 0;
    expected_close_error = which == 8;
    luaL_openlibs(L);
    lua_pushcfunction(L, observe_close);
    lua_setglobal(L, "observe_close");
    if (which == 9) co = lua_newthread(L);
    else co = L;
    lua_pushcfunction(co, which == 7 ? mark_and_return :
                     which == 8 ? mark_and_error :
                     which == 11 ? mark_and_trim :
                     which == 12 ? mark_and_close_slot : mark_and_call);
    status = luaL_loadstring(co,
        "return setmetatable({token=71},{__close=observe_close})");
    if (status == LUA_OK) status = lua_pcall(co, 0, 1, 0);
    if (status != LUA_OK) return 21;
    if (which == 8) {
        lua_newtable(co);
        lua_pushvalue(co, -1);
        lua_setglobal(co, "close_error");
    } else if (which == 9) {
        status = luaL_loadstring(co,
            "coroutine.yield('pause'); return 'retained result'");
        if (status != LUA_OK) return 22;
        status = lua_resume(co, L, 2, &count);
        if (status != LUA_YIELD || count != 1 || closed != 0 ||
            strcmp(lua_tostring(co, -1), "pause") != 0) return 23;
        status = lua_resume(co, L, 0, &count);
        if (status != LUA_OK || count != 1 || close_continued != 1)
            return 24;
    }
    if (which != 9) status = lua_pcall(co, which == 8 ? 2 : 1, 1, 0);
    if (status != (which == 8 ? LUA_ERRRUN : LUA_OK) ||
        closed != (which == 11 ? 2 : 1) ||
        close_failed != 0) return 25 + close_failed;
    if (which == 8) {
        lua_getglobal(co, "close_error");
        if (!lua_rawequal(co, -1, -2)) return 30;
    } else if (!lua_isstring(co, -1) ||
               strcmp(lua_tostring(co, -1), "retained result") != 0)
        return 31;
    return 0;
}

static void observe_hook(lua_State *L, lua_Debug *ar) {
    struct hook_observation *o = observation;
    lua_Debug current = *ar;
    if (o == NULL) return;
    o->calls++;
    if (L != o->expected) o->failed = 1;
    if (ar->event == LUA_HOOKLINE) {
        lua_Debug selected;
        if (ar->currentline <= 0 || !lua_getinfo(L, "l", &current) ||
            current.currentline != ar->currentline) o->failed = 2;
        /* Level zero inside a C hook denotes the interrupted Lua frame,
         * rather than a synthetic callback used by the transport layer. */
        if (!lua_getstack(L, 0, &selected) ||
            !lua_getinfo(L, "l", &selected) ||
            selected.currentline != ar->currentline) o->failed = 3;
        o->retained = *ar;
    }
    if (o->remove_self) lua_sethook(L, NULL, 0, 0);
}

static int run_chunk(lua_State *L) {
    const char source[] = "local x = 0\n"
        "for i = 1, 6 do\n x = x + i\n end\nreturn x\n";
    if (luaL_loadbufferx(L, source, sizeof source - 1, "@hook-contract", "t")
            != LUA_OK) return 1;
    if (lua_pcall(L, 0, 1, 0) != LUA_OK) return 2;
    if (lua_tointeger(L, -1) != 21) return 3;
    lua_pop(L, 1);
    return 0;
}

int lua_ada_test_hook_contract(int which) {
    lua_State *L = luaL_newstate();
    lua_State *other = NULL;
    struct hook_observation observed;
    int result = 0;
    if (L == NULL) return 100;
    memset(&observed, 0, sizeof observed);
    observed.expected = L;
    observation = &observed;
    if (which >= 25 && which <= 26) {
        result = returned_value_contract(L, which - 16);
        observation = NULL;
        lua_close(L);
        return result;
    }
    if (which == 24) {
        observation = NULL;
        return release_view_contract(L);
    }
    if (which >= 16 && which <= 23) {
        result = which <= 21 ? stack_view_contract(L, which - 15) :
            weak_view_contract(L, which - 15);
        observation = NULL;
        lua_close(L);
        return result;
    }
    if (which == 15) {
        result = suspended_index_contract(L);
        observation = NULL;
        lua_close(L);
        return result;
    }
    if (which == 14) {
        result = combined_hook_contract(L);
        observation = NULL;
        lua_close(L);
        return result;
    }
    if (which == 10) {
        /* Lua error's default location names its real logical caller. A C
         * caller contributes no invented source/line or scheduler holder. */
        luaL_openlibs(L);
        lua_pushcfunction(L, call_base_error);
        result = lua_pcall(L, 0, 0, 0);
        result = result == LUA_ERRRUN && lua_isstring(L, -1) &&
            strcmp(lua_tostring(L, -1), "C caller error") == 0 ? 0 : 40;
        observation = NULL;
        lua_close(L);
        return result;
    }
    if (which == 13) {
        observation = NULL;
        lua_close(L);
        return refusal_reuse_contract();
    }
    if ((which >= 7 && which <= 9) || which == 11 || which == 12) {
        result = close_contract(L, which);
        observation = NULL;
        lua_close(L);
        return result;
    }
    switch (which) {
    case 1:
        /* Callback identity, all mask bits and signed requested count are
         * actual per-state API data, rather than a fabricated Lua closure. */
        lua_sethook(L, observe_hook,
            LUA_MASKCALL | LUA_MASKRET | LUA_MASKLINE | LUA_MASKCOUNT, 7);
        if (lua_gethook(L) != observe_hook || lua_gethookmask(L) != 15 ||
            lua_gethookcount(L) != 7) result = 1;
        lua_sethook(L, observe_hook, LUA_MASKLINE, -3);
        if (lua_gethookcount(L) != -3) result = 2;
        break;
    case 2:
        /* Real canonical line events expose their interrupted frame. The C
         * lua_getinfo line query must agree with the delivered lua_Debug. */
        lua_sethook(L, observe_hook, LUA_MASKLINE, 0);
        result = run_chunk(L);
        if (!result && (observed.calls < 2 || observed.failed)) result = 10;
        break;
    case 3:
        /* A count-only mask must fire repeatedly while executing actual Lua
         * instructions, even though its textual call/return/line mask is empty. */
        lua_sethook(L, observe_hook, LUA_MASKCOUNT, 2);
        result = run_chunk(L);
        if (!result && (observed.calls < 2 || observed.failed)) result = 11;
        break;
    case 4:
        /* Disabling from inside the callback affects the next instruction,
         * without redispatching a saved callback or retaining a stale mask. */
        observed.remove_self = 1;
        lua_sethook(L, observe_hook, LUA_MASKLINE, 0);
        result = run_chunk(L);
        if (!result && (observed.calls != 1 || lua_gethook(L) != NULL ||
            lua_gethookmask(L) != 0)) result = 12;
        break;
    case 5:
        /* Two simultaneously live universes keep distinct callback state.
         * Running the state with no hook cannot invoke its neighbour's hook. */
        other = luaL_newstate();
        if (other == NULL) { result = 101; break; }
        lua_sethook(L, observe_hook, LUA_MASKLINE, 0);
        result = run_chunk(other);
        if (!result && (observed.calls != 0 || lua_gethook(other) != NULL))
            result = 13;
        if (!result) result = run_chunk(L);
        if (!result && (observed.calls == 0 || observed.failed)) result = 14;
        break;
    case 6:
        /* A frame token is a borrowed active-frame identity. Once the chunk
         * returns it cannot be dereferenced as if it were still an activation. */
        lua_sethook(L, observe_hook, LUA_MASKLINE, 0);
        result = run_chunk(L);
        if (!result && (observed.retained.i_ci == NULL ||
            lua_getinfo(L, "l", &observed.retained) != 0 ||
            lua_getstack(L, 0, &observed.retained) != 0)) result = 15;
        break;
    default:
        result = 102;
    }
    lua_sethook(L, NULL, 0, 0);
    observation = NULL;
    if (other != NULL) lua_close(other);
    lua_close(L);
    return result;
}
