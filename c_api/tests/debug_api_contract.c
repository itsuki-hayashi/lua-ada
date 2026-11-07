/* Public debug API behavior, linked unchanged to Ada and isolated C Lua.
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
static lua_Hook saved_hook;
static int inspected_hook;
static int transfer_calls, transfer_returns;
static int return_first, return_count;

static void run(lua_State *L, const char *source) {
    int status = luaL_dostring(L, source);
    if (status != LUA_OK) fprintf(stderr, "%s\n", lua_tostring(L, -1));
    assert(status == LUA_OK);
}

static void function_information(lua_State *L) {
    lua_Debug ar;
    const char *source = "return function(a,b,...)\n local x=a+b\n return x\nend";
    assert(luaL_loadbuffer(L, source, strlen(source), "@debug-fixture.lua") == 0);
    lua_call(L, 0, 1);
    memset(&ar, 0, sizeof ar);
    lua_pushvalue(L, -1);
    assert(lua_getinfo(L, ">SlutnrfL", &ar) == 1);
    assert(strcmp(ar.source, "@debug-fixture.lua") == 0);
    assert(ar.srclen == strlen(ar.source));
    assert(strcmp(ar.short_src, "debug-fixture.lua") == 0);
    assert(strcmp(ar.what, "Lua") == 0);
    assert(ar.linedefined == 1 && ar.lastlinedefined == 4);
    assert(ar.currentline == -1 && ar.nparams == 2 && ar.isvararg == 1);
    assert(ar.nups == 0 && ar.istailcall == 0 && ar.extraargs == 0);
    assert(ar.ftransfer == 0 && ar.ntransfer == 0);
    assert(ar.name == NULL && strcmp(ar.namewhat, "") == 0);
    assert(lua_gettop(L) == 3 && lua_rawequal(L, 1, 2));
    assert(lua_istable(L, 3));
    lua_rawgeti(L, 3, 1); assert(lua_isnil(L, -1)); lua_pop(L, 1);
    lua_rawgeti(L, 3, 2); assert(lua_toboolean(L, -1)); lua_pop(L, 1);
    lua_rawgeti(L, 3, 3); assert(lua_toboolean(L, -1)); lua_pop(L, 1);
    lua_settop(L, 0);
}

static void selector_protocol(lua_State *L) {
    lua_Debug ar;
    run(L, "return function(x) return x end");
    memset(&ar, 0, sizeof ar);
    ar.currentline = 876;
    lua_pushvalue(L, -1);
    assert(lua_getinfo(L, ">ff?LLu", &ar) == 0);
    assert(lua_gettop(L) == 3 && lua_rawequal(L, 1, 2));
    assert(lua_istable(L, 3) && ar.currentline == 876 && ar.nparams == 1);
    lua_settop(L, 0);
}

static int native_identity(lua_State *L) { return lua_gettop(L); }

static void native_information(lua_State *L) {
    lua_Debug ar;
    lua_pushcfunction(L, native_identity);
    assert(lua_getinfo(L, ">SlutnrfL", &ar));
    assert(strcmp(ar.source, "=[C]") == 0 && ar.srclen == 4);
    assert(strcmp(ar.short_src, "[C]") == 0 && strcmp(ar.what, "C") == 0);
    assert(ar.linedefined == -1 && ar.lastlinedefined == -1);
    assert(ar.currentline == -1 && ar.nups == 0 && ar.nparams == 0);
    assert(ar.isvararg && ar.name == NULL && !*ar.namewhat);
    assert(lua_gettop(L) == 2 && lua_tocfunction(L, 1) == native_identity);
    assert(lua_isnil(L, 2));
    lua_settop(L, 0);
}

static void borrowed_lifetime_and_refusal(lua_State *L) {
    lua_Debug first, next;
    const char *source;
    int i;
    run(L, "return function(named) return named end");
    assert(lua_checkstack(L, 64));
    lua_pushvalue(L, 1); assert(lua_getinfo(L, ">S", &first));
    source = first.source;
    counts.refuse = 1;
    for (i = 0; i < 100; ++i) {
        lua_pushvalue(L, 1);
        assert(lua_getinfo(L, ">Sluntrf", &next));
        assert(next.source == source && next.nparams == 1);
        assert(lua_rawequal(L, 1, -1)); lua_pop(L, 1);
        assert(strcmp(lua_getlocal(L, NULL, 1), "named") == 0);
        assert(lua_gettop(L) == 1);
    }
    counts.refuse = 0;
    lua_gc(L, LUA_GCCOLLECT);
    assert(strcmp(first.source, source) == 0 && source[first.srclen] == '\0');
    lua_settop(L, 0);
}

static void inactive_parameter_names(lua_State *L) {
    int top;
    run(L, "return function(first,second,...) return first end");
    top = lua_gettop(L);
    assert(strcmp(lua_getlocal(L, NULL, 1), "first") == 0);
    assert(strcmp(lua_getlocal(L, NULL, 2), "second") == 0);
    assert(lua_getlocal(L, NULL, 0) == NULL);
    assert(lua_getlocal(L, NULL, -1) == NULL);
    assert(lua_getlocal(L, NULL, 3) == NULL && lua_gettop(L) == top);
    lua_pushcfunction(L, native_identity);
    assert(lua_getlocal(L, NULL, 1) == NULL && lua_gettop(L) == top + 1);
    lua_settop(L, 0);
}

static int inspect_c_locals(lua_State *L) {
    lua_Debug ar;
    int top = lua_gettop(L);
    assert(lua_getstack(L, 0, &ar));
    assert(strcmp(lua_getlocal(L, &ar, 1), "(C temporary)") == 0);
    assert(lua_tointeger(L, -1) == 12); lua_pop(L, 1);
    lua_pushinteger(L, 47);
    assert(strcmp(lua_setlocal(L, &ar, 2), "(C temporary)") == 0);
    assert(lua_gettop(L) == top && lua_tointeger(L, 2) == 47);
    lua_pushinteger(L, 91);
    assert(lua_setlocal(L, &ar, 1000) == NULL);
    assert(lua_gettop(L) == top + 1 && lua_tointeger(L, -1) == 91);
    lua_pop(L, 1);
    assert(lua_getlocal(L, &ar, -1) == NULL && lua_gettop(L) == top);
    lua_pushvalue(L, 2);
    return 1;
}

static void active_c_locals(lua_State *L) {
    lua_pushcfunction(L, inspect_c_locals);
    lua_pushinteger(L, 12); lua_pushinteger(L, 13);
    lua_call(L, 2, 1);
    assert(lua_tointeger(L, -1) == 47);
    lua_settop(L, 0);
}

static int inspect_lua_locals(lua_State *L) {
    lua_Debug ar;
    const char *name;
    int index, xslot = 0;
    assert(lua_getstack(L, 0, &ar));
    counts.refuse = 1;
    assert(lua_getinfo(L, "n", &ar));
    counts.refuse = 0;
    assert(strcmp(ar.namewhat, "global") == 0 && strcmp(ar.name, "probe") == 0);
    assert(lua_getstack(L, 1, &ar));
    assert(lua_getinfo(L, "Slu", &ar));
    assert(strcmp(lua_getlocal(L, &ar, 1), "a") == 0);
    assert(lua_tointeger(L, -1) == 11); lua_pop(L, 1);
    /* Lua 5.5 owns an actual vararg-table slot in this frame. Find the named
     * source local rather than assuming the private slot preceding it. */
    for (index = 2; index <= 8; ++index) {
        name = lua_getlocal(L, &ar, index);
        if (!name) continue;
        if (strcmp(name, "x") == 0) {
            xslot = index; assert(lua_tointeger(L, -1) == 7);
        }
        lua_pop(L, 1);
    }
    assert(xslot != 0);
    lua_pushinteger(L, 42);
    assert(strcmp(lua_setlocal(L, &ar, 1), "a") == 0);
    lua_pushinteger(L, 43);
    assert(strcmp(lua_setlocal(L, &ar, xslot), "x") == 0);
    name = lua_getlocal(L, &ar, -1);
    assert(name && strcmp(name, "(vararg)") == 0);
    assert(lua_tointeger(L, -1) == 22); lua_pop(L, 1);
    lua_pushinteger(L, 44);
    assert(strcmp(lua_setlocal(L, &ar, -2), "(vararg)") == 0);
    assert(lua_gettop(L) == 0);
    return 0;
}

static void active_lua_locals(lua_State *L) {
    lua_pushcfunction(L, inspect_lua_locals); lua_setglobal(L, "probe");
    run(L, "local function f(a,...) local x=7; probe(); return a,x,... end "
           "return f(11,22,33)");
    assert(lua_gettop(L) == 4 && lua_tointeger(L, 1) == 42);
    assert(lua_tointeger(L, 2) == 43 && lua_tointeger(L, 3) == 22);
    assert(lua_tointeger(L, 4) == 44);
    lua_settop(L, 0);
}

static void upvalue_values(lua_State *L) {
    const char *name;
    void *id;
    run(L, "local x,y=12,13; return function() return x+y end");
    id = lua_upvalueid(L, 1, 1); assert(id != NULL);
    name = lua_getupvalue(L, 1, 1); assert(name && strcmp(name, "x") == 0);
    assert(lua_tointeger(L, -1) == 12); lua_pop(L, 1);
    lua_pushinteger(L, 40);
    assert(strcmp(lua_setupvalue(L, 1, 2), "y") == 0);
    assert(lua_gettop(L) == 1 && lua_upvalueid(L, 1, 1) == id);
    assert(lua_getupvalue(L, 1, 0) == NULL && lua_upvalueid(L, 1, 90) == NULL);
    lua_pushinteger(L, 77);
    assert(lua_setupvalue(L, 1, 90) == NULL && lua_gettop(L) == 2);
    lua_pop(L, 1);
    lua_pushvalue(L, 1); lua_call(L, 0, 1);
    assert(lua_tointeger(L, -1) == 52);
    lua_settop(L, 0);
}

static void joined_upvalue_identity(lua_State *L) {
    run(L, "local a,b=5,6; return function() return a end,"
           " function() return b end");
    assert(lua_upvalueid(L, 1, 1) != lua_upvalueid(L, 2, 1));
    lua_upvaluejoin(L, 1, 1, 2, 1);
    assert(lua_upvalueid(L, 1, 1) == lua_upvalueid(L, 2, 1));
    lua_pushinteger(L, 83); assert(lua_setupvalue(L, 2, 1));
    lua_pop(L, 1); lua_gc(L, LUA_GCCOLLECT);
    lua_call(L, 0, 1); assert(lua_tointeger(L, -1) == 83);
    lua_settop(L, 0);
}

static void c_upvalue_identity(lua_State *L) {
    void *id;
    lua_pushinteger(L, 12); lua_pushinteger(L, 13);
    lua_pushcclosure(L, native_identity, 2);
    id = lua_upvalueid(L, 1, 1);
    assert(id && id != lua_upvalueid(L, 1, 2));
    assert(strcmp(lua_getupvalue(L, 1, 1), "") == 0);
    assert(lua_tointeger(L, -1) == 12); lua_pop(L, 1);
    lua_pushinteger(L, 33); assert(strcmp(lua_setupvalue(L, 1, 1), "") == 0);
    assert(lua_upvalueid(L, 1, 1) == id);
    lua_pushcfunction(L, native_identity);
    assert(lua_upvalueid(L, -1, 1) == NULL && lua_getupvalue(L, -1, 1) == NULL);
    lua_settop(L, 0);
}

static int invoke_saved_hook(lua_State *L) {
    lua_Debug ar;
    assert(lua_getstack(L, 0, &ar));
    ar.event = LUA_HOOKCOUNT; ar.currentline = 123;
    saved_hook(L, &ar);
    return 0;
}

static void lua_hook_identity(lua_State *L) {
    run(L, "last=nil; hookfn=function(e,l) last={e,l} end; "
           "debug.sethook(hookfn,'l',7)");
    saved_hook = lua_gethook(L);
    assert(saved_hook && lua_gethookmask(L) == (LUA_MASKLINE | LUA_MASKCOUNT));
    assert(lua_gethookcount(L) == 7);
    lua_sethook(L, NULL, 0, 0); assert(lua_gethook(L) == NULL);
    lua_sethook(L, saved_hook, LUA_MASKLINE, 0);
    assert(lua_gethook(L) == saved_hook);
    run(L, "assert(debug.gethook()==hookfn); local x=1\nx=x+1");
    lua_sethook(L, NULL, 0, 0);
    lua_pushcfunction(L, invoke_saved_hook); lua_call(L, 0, 0);
    run(L, "assert(last[1]=='count' and last[2]==123)");
    lua_settop(L, 0);
}

static void removing_hook(lua_State *L, lua_Debug *ar) {
    lua_Debug current;
    (void)ar;
    lua_sethook(L, NULL, 0, 0);
    assert(lua_getstack(L, 0, &current));
    assert(lua_getinfo(L, "S", &current) && strcmp(current.what, "main") == 0);
    lua_getglobal(L, "hook_target"); lua_call(L, 0, 2);
    assert(strcmp(lua_tostring(L, -2), "hook") == 0);
    assert(strcmp(lua_tostring(L, -1), "?") == 0);
    lua_pop(L, 2); ++inspected_hook;
}

static void hook_mutation_frame_identity(lua_State *L) {
    run(L, "function hook_target() local d=debug.getinfo(1,'n');"
           "return d.namewhat,d.name end");
    inspected_hook = 0;
    lua_sethook(L, removing_hook, LUA_MASKLINE, 0);
    run(L, "local x=1\nx=x+1");
    assert(inspected_hook == 1 && lua_gethook(L) == NULL);
    lua_settop(L, 0);
}

static int inserted_receivers(lua_State *L) {
    lua_Debug ar;
    assert(lua_getstack(L, 0, &ar) && lua_getinfo(L, "tu", &ar));
    assert(ar.extraargs == 2 && !ar.istailcall && ar.isvararg);
    assert(lua_gettop(L) == 3 && lua_tointeger(L, 3) == 42);
    lua_pushinteger(L, ar.extraargs);
    return 1;
}

static void call_metamethod_metadata(lua_State *L) {
    lua_pushcfunction(L, inserted_receivers); lua_setglobal(L, "receivers");
    run(L, "local first,second={},{}; "
           "setmetatable(first,{__call=second}); "
           "setmetatable(second,{__call=receivers}); return first(42)");
    assert(lua_tointeger(L, -1) == 2);
    lua_settop(L, 0);
}

static void transfer_hook(lua_State *L, lua_Debug *ar) {
    assert(lua_getinfo(L, "r", ar));
    if (ar->event == LUA_HOOKCALL) {
        assert(ar->ftransfer == 1 && ar->ntransfer == 2); ++transfer_calls;
    } else {
        if (ar->event != LUA_HOOKRET || ar->ftransfer != return_first)
            fprintf(stderr, "return event=%d first=%d count=%d\n",
                    ar->event, ar->ftransfer, ar->ntransfer);
        assert(ar->event == LUA_HOOKRET && ar->ftransfer == return_first);
        assert(ar->ntransfer == return_count);
        ++transfer_returns;
    }
}

static void hook_transfer_metadata(lua_State *L) {
    run(L, "return function(a,b) return a,b,33 end");
    transfer_calls = transfer_returns = 0;
    return_first = return_count = 3;
    lua_sethook(L, transfer_hook, LUA_MASKCALL | LUA_MASKRET, 0);
    lua_pushinteger(L, 11); lua_pushinteger(L, 22); lua_call(L, 2, 3);
    lua_sethook(L, NULL, 0, 0);
    assert(transfer_calls == 1 && transfer_returns == 1);
    assert(lua_gettop(L) == 3 && lua_tointeger(L, 3) == 33);
    lua_settop(L, 0);
}

static int c_values(lua_State *L) {
    lua_pushinteger(L, 77); lua_pushinteger(L, 88); lua_pushinteger(L, 99);
    return 2;
}

static void c_return_transfer_metadata(lua_State *L) {
    transfer_calls = transfer_returns = 0;
    return_first = 4; return_count = 2;
    lua_pushcfunction(L, c_values);
    lua_sethook(L, transfer_hook, LUA_MASKCALL | LUA_MASKRET, 0);
    lua_pushinteger(L, 11); lua_pushinteger(L, 22); lua_call(L, 2, 2);
    lua_sethook(L, NULL, 0, 0);
    assert(transfer_calls == 1 && transfer_returns == 1);
    assert(lua_gettop(L) == 2 && lua_tointeger(L, 1) == 88);
    assert(lua_tointeger(L, 2) == 99);
    lua_settop(L, 0);
}

static void suspended_capture_local(lua_State *L) {
    lua_State *co = lua_newthread(L);
    lua_Debug ar;
    int results = -1;
    assert(luaL_loadstring(co, "local x=11; local function get() return x end;"
           "coroutine.yield(get); return x") == LUA_OK);
    assert(lua_resume(co, L, 0, &results) == LUA_YIELD && results == 1);
    assert(lua_getstack(co, 1, &ar) && lua_getinfo(co, "S", &ar));
    assert(strcmp(ar.what, "main") == 0);
    assert(strcmp(lua_getlocal(co, &ar, 1), "x") == 0);
    assert(lua_tointeger(co, -1) == 11); lua_pop(co, 1);
    lua_pushinteger(co, 52);
    assert(strcmp(lua_setlocal(co, &ar, 1), "x") == 0);
    lua_pushvalue(co, 1); lua_xmove(co, L, 1); lua_call(L, 0, 1);
    assert(lua_tointeger(L, -1) == 52); lua_pop(L, 1);
    lua_settop(co, 0);
    assert(lua_resume(co, L, 0, &results) == LUA_OK && results == 1);
    assert(lua_tointeger(co, -1) == 52);
    lua_settop(L, 0);
}

static int query_lines(lua_State *L) {
    lua_Debug ar;
    lua_pushvalue(L, 1);
    assert(lua_getinfo(L, ">L", &ar));
    return 1;
}

static void lines_refusal_and_recovery(lua_State *L) {
    int i, status;
    run(L, "return function(a) return a+1 end");
    assert(lua_checkstack(L, 64));
    for (i = 0; i < 3; ++i) {
        lua_pushcfunction(L, query_lines); lua_pushvalue(L, 1);
        counts.refuse = 1;
        status = lua_pcall(L, 1, 1, 0);
        counts.refuse = 0;
        assert(status == LUA_ERRMEM && lua_gettop(L) == 2);
        lua_pop(L, 1);
        lua_pushcfunction(L, query_lines); lua_pushvalue(L, 1);
        assert(lua_pcall(L, 1, 1, 0) == LUA_OK && lua_istable(L, -1));
        lua_pop(L, 1);
    }
    lua_settop(L, 0);
}

struct dump_bytes { char *data; size_t length; };
static int save_dump(lua_State *L, const void *piece, size_t size, void *data) {
    struct dump_bytes *dump = (struct dump_bytes *)data;
    char *grown;
    (void)L;
    if (!size) return 0;
    grown = (char *)realloc(dump->data, dump->length + size);
    assert(grown);
    dump->data = grown; memcpy(grown + dump->length, piece, size);
    dump->length += size;
    return 0;
}

static void stripped_metadata(lua_State *L) {
    struct dump_bytes dump = {NULL, 0};
    lua_Debug ar;
    const char *name;
    run(L, "local x=1; return function(parameter) return x+parameter end");
    assert(lua_dump(L, save_dump, &dump, 1) == 0);
    assert(luaL_loadbufferx(L, dump.data, dump.length, "@discarded", "b") == 0);
    free(dump.data);
    assert(lua_getlocal(L, NULL, 1) == NULL);
    name = lua_getupvalue(L, -1, 1);
    assert(name && strcmp(name, "(no name)") == 0); lua_pop(L, 1);
    assert(lua_getinfo(L, ">SluL", &ar));
    assert(strcmp(ar.source, "=?") == 0 && ar.srclen == 2);
    assert(strcmp(ar.short_src, "?") == 0 && ar.nparams == 1);
    assert(ar.currentline == -1 && lua_istable(L, -1));
    lua_pushnil(L); assert(lua_next(L, -2) == 0);
    lua_settop(L, 0);
}

static int inspect_pending_temporary(lua_State *L) {
    lua_Debug ar;
    const char *name;
    int top = lua_gettop(L);
    /* The actual caller keeps (a+1) pending below this function's call slot.
     * Read and edit that real operand, then verify neither the function nor
     * its arguments appear as caller temporaries. A rejected setter retains
     * its own pushed value, as required by the public C stack protocol. */
    assert(top == 1 && lua_tointeger(L, 1) == 9);
    assert(lua_getstack(L, 1, &ar));
    name = lua_getlocal(L, &ar, 3);
    assert(name && strcmp(name, "(temporary)") == 0);
    assert(lua_tointeger(L, -1) == 1); lua_pop(L, 1);
    assert(lua_getlocal(L, &ar, 4) == NULL && lua_gettop(L) == top);
    assert(lua_getlocal(L, &ar, 5) == NULL && lua_gettop(L) == top);
    lua_pushinteger(L, 10);
    name = lua_setlocal(L, &ar, 3);
    assert(name && strcmp(name, "(temporary)") == 0);
    assert(lua_gettop(L) == top);
    lua_pushinteger(L, 99);
    assert(lua_setlocal(L, &ar, 4) == NULL);
    assert(lua_gettop(L) == top + 1 && lua_tointeger(L, -1) == 99);
    lua_pop(L, 1);
    lua_pushinteger(L, 20);
    return 1;
}

static void caller_temporary_extent(lua_State *L) {
    lua_pushcfunction(L, inspect_pending_temporary);
    lua_setglobal(L, "temporary_probe");
    run(L, "local function g(a,b) return (a+1)+temporary_probe(9) end "
           "return g(0,0)");
    assert(lua_gettop(L) == 1 && lua_tointeger(L, 1) == 30);
    lua_settop(L, 0);
}

static void suspended_pending_temporary(lua_State *L) {
    lua_State *co = lua_newthread(L);
    lua_Debug ar;
    const char *name;
    int results = -1;
    /* Suspension retains both actual windows. Collection cannot replace the
     * pending scalar or invalidate the child-function boundary. Resume must
     * consume the same register that lua_setlocal changes here. */
    assert(luaL_loadstring(co,
           "local function f() coroutine.yield(); return 20 end "
           "local function g(a,b) return (a+1)+f() end return g(0,0)") == 0);
    assert(lua_resume(co, L, 0, &results) == LUA_YIELD && results == 0);
    lua_gc(L, LUA_GCCOLLECT);
    assert(lua_getstack(co, 2, &ar));
    name = lua_getlocal(co, &ar, 3);
    assert(name && strcmp(name, "(temporary)") == 0);
    assert(lua_tointeger(co, -1) == 1); lua_pop(co, 1);
    assert(lua_getlocal(co, &ar, 4) == NULL && lua_gettop(co) == 0);
    lua_pushinteger(co, 10);
    name = lua_setlocal(co, &ar, 3);
    assert(name && strcmp(name, "(temporary)") == 0);
    lua_pushinteger(co, 99);
    assert(lua_setlocal(co, &ar, 4) == NULL);
    assert(lua_gettop(co) == 1 && lua_tointeger(co, -1) == 99);
    lua_pop(co, 1);
    assert(lua_resume(co, L, 0, &results) == LUA_OK && results == 1);
    assert(lua_tointeger(co, -1) == 30);
    lua_settop(L, 0);
}

static int origin_queries;

static int inspect_call_origin(lua_State *L) {
    lua_Debug ar;
    const char *kind = lua_tostring(L, 1);
    const char *name = lua_tostring(L, 2);
    assert(kind != NULL);
    assert(lua_getstack(L, 1, &ar));
    /* These names belong to a real calling opcode, finalizer entry or
     * protection boundary. The n query must borrow them without allocating,
     * including when the handler itself runs during collection. */
    counts.refuse = 1;
    assert(lua_getinfo(L, "n", &ar));
    counts.refuse = 0;
    if (strcmp(ar.namewhat, kind) != 0) {
        int level;
        fprintf(stderr, "origin expected %s/%s, got %s/%s\n", kind,
                name ? name : "(nil)", ar.namewhat,
                ar.name ? ar.name : "(nil)");
        for (level = 0; level < 8; ++level) {
            lua_Debug frame;
            if (!lua_getstack(L, level, &frame)) break;
            assert(lua_getinfo(L, "nS", &frame));
            fprintf(stderr, "  %d %s %s/%s\n", level, frame.what,
                    frame.namewhat, frame.name ? frame.name : "(nil)");
        }
    }
    assert(strcmp(ar.namewhat, kind) == 0);
    if (name) assert(ar.name && strcmp(ar.name, name) == 0);
    else assert(ar.name == NULL);
    ++origin_queries;
    return 0;
}

static void prepare_origin_query(lua_State *L) {
    origin_queries = 0;
    lua_pushcfunction(L, inspect_call_origin);
    lua_setglobal(L, "origin_probe");
}

static void arithmetic_call_origin(lua_State *L) {
    prepare_origin_query(L);
    run(L, "local a=setmetatable({}, {__add=function() "
           "origin_probe('metamethod','add'); return 7 end});"
           "assert(a+1==7)");
    assert(origin_queries == 1);
}

static void index_call_origin(lua_State *L) {
    prepare_origin_query(L);
    run(L, "local a=setmetatable({}, {__index=function() "
           "origin_probe('metamethod','index'); return 7 end});"
           "assert(a.x==7)");
    assert(origin_queries == 1);
}

static void close_call_origin(lua_State *L) {
    prepare_origin_query(L);
    run(L, "do local x <close> =setmetatable({}, {__close=function() "
           "origin_probe('metamethod','close') end}) end");
    assert(origin_queries == 1);
}

static void error_close_call_origin(lua_State *L) {
    prepare_origin_query(L);
    run(L, "local function f() local x <close> =setmetatable({}, "
           "{__close=function()origin_probe('',nil)end});error('boom')end;"
           "assert(not pcall(f))");
    assert(origin_queries == 1);
}

static void coroutine_close_call_origin(lua_State *L) {
    prepare_origin_query(L);
    run(L, "local co=coroutine.create(function()local x <close> ="
           "setmetatable({}, {__close=function()origin_probe('',nil)end});"
           "coroutine.yield()end);assert(coroutine.resume(co));"
           "assert(coroutine.close(co))");
    assert(origin_queries == 1);
}

static void finalizer_call_origin(lua_State *L) {
    prepare_origin_query(L);
    run(L, "setmetatable({}, {__gc=function()"
           "origin_probe('metamethod','__gc')end});collectgarbage()");
    assert(origin_queries == 1);
}

static void collect_from_hook(lua_State *L, lua_Debug *ar) {
    (void)ar;
    /* Removing the installation leaves this actual invocation hooked until
     * it returns. A direct lua_gc API call adds no ordinary C call frame. */
    lua_sethook(L, NULL, 0, 0);
    lua_pushnil(L); lua_setglobal(L, "hook_finalizer_target");
    lua_gc(L, LUA_GCCOLLECT);
}

static void hooked_finalizer_call_origin(lua_State *L) {
    int i;
    prepare_origin_query(L);
    run(L, "return function()origin_probe('hook','?')end");
    lua_createtable(L, 0, 1);
    lua_pushvalue(L, 1); lua_setfield(L, 2, "__gc");
    lua_newuserdatauv(L, 0, 0);
    lua_pushvalue(L, 2); lua_setmetatable(L, 3);
    lua_setglobal(L, "hook_finalizer_target");
    lua_settop(L, 0);
    /* A Lua hook protects the interrupted activation's complete register
     * window. Clear old host temporaries so no stale slot retains the target
     * after the hook removes its only intended global owner. */
    assert(lua_checkstack(L, 64));
    for (i = 0; i < 64; ++i) lua_pushnil(L);
    lua_settop(L, 0);
    lua_sethook(L, collect_from_hook, LUA_MASKLINE, 0);
    run(L, "local x=1; x=x+1");
    assert(lua_gethook(L) == NULL && origin_queries == 1);
}

static int direct_gc_finalizers;
static int direct_gc_hook_events;

static int direct_gc_finalizer(lua_State *L) {
    (void)L;
    ++direct_gc_finalizers;
    return 0;
}

static void direct_gc_hook(lua_State *L, lua_Debug *ar) {
    (void)L; (void)ar;
    ++direct_gc_hook_events;
}

static void direct_gc_no_transport_events(lua_State *L) {
    int i;
    /* Direct API collection enters no public function. Its actual finalizer
     * suppresses hooks too. A protected implementation pump must not invent
     * call/return events before or after that callback. */
    lua_newuserdatauv(L, 0, 0);
    lua_createtable(L, 0, 1);
    lua_pushcfunction(L, direct_gc_finalizer);
    lua_setfield(L, 2, "__gc");
    lua_setmetatable(L, 1);
    lua_settop(L, 0);
    assert(lua_checkstack(L, 64));
    for (i = 0; i < 64; ++i) lua_pushnil(L);
    lua_settop(L, 0);
    direct_gc_finalizers = 0;
    direct_gc_hook_events = 0;
    lua_sethook(L, direct_gc_hook, LUA_MASKCALL | LUA_MASKRET, 0);
    lua_gc(L, LUA_GCCOLLECT);
    lua_sethook(L, NULL, 0, 0);
    assert(direct_gc_finalizers == 1 && direct_gc_hook_events == 0);
}

static void check(const char *name, void (*body)(lua_State *), lua_State *L) {
    assert(lua_gettop(L) == 0);
    body(L);
    assert(lua_gettop(L) == 0);
    printf("PASS: debug-%s\n", name); fflush(stdout);
}

int main(void) {
    lua_State *L = lua_newstate(counted_allocator, &counts, 191U);
    assert(L); luaL_openlibs(L);
    check("function-information", function_information, L);
    check("selector-protocol", selector_protocol, L);
    check("native-information", native_information, L);
    check("borrowed-lifetime-and-refusal", borrowed_lifetime_and_refusal, L);
    check("inactive-parameter-names", inactive_parameter_names, L);
    check("active-c-locals", active_c_locals, L);
    check("active-lua-locals", active_lua_locals, L);
    check("upvalue-values", upvalue_values, L);
    check("joined-upvalue-identity", joined_upvalue_identity, L);
    check("c-upvalue-identity", c_upvalue_identity, L);
    check("lua-hook-identity", lua_hook_identity, L);
    check("hook-mutation-frame-identity", hook_mutation_frame_identity, L);
    check("call-metamethod-metadata", call_metamethod_metadata, L);
    check("hook-transfer-metadata", hook_transfer_metadata, L);
    check("lines-refusal-and-recovery", lines_refusal_and_recovery, L);
    check("stripped-metadata", stripped_metadata, L);
    check("c-return-transfer-metadata", c_return_transfer_metadata, L);
    check("suspended-capture-local", suspended_capture_local, L);
    check("caller-temporary-extent", caller_temporary_extent, L);
    check("suspended-pending-temporary", suspended_pending_temporary, L);
    check("arithmetic-call-origin", arithmetic_call_origin, L);
    check("index-call-origin", index_call_origin, L);
    check("close-call-origin", close_call_origin, L);
    check("error-close-call-origin", error_close_call_origin, L);
    check("coroutine-close-call-origin", coroutine_close_call_origin, L);
    check("finalizer-call-origin", finalizer_call_origin, L);
    check("hooked-finalizer-call-origin", hooked_finalizer_call_origin, L);
    check("direct-gc-no-transport-events", direct_gc_no_transport_events, L);
    lua_close(L); assert(counts.bytes == 0 && counts.blocks == 0);
    puts("PASS: public debug contract");
    return 0;
}
