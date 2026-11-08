/* Real host base-C closing slots and allocation-free thread queries.
 * Copyright (c) 2026 Lua Ada contributors. MIT; see ../../LICENSE. */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "consumer_allocator.h"

static struct allocation_counts counts;
static int closed, order[4];

static void run(lua_State *L, const char *source) {
    int status = luaL_dostring(L, source);
    if (status != LUA_OK) fprintf(stderr, "%s\n", lua_tostring(L, -1));
    assert(status == LUA_OK);
}
static int record_close(lua_State *L) {
    assert(lua_gettop(L) == 1);
    assert(closed < (int)(sizeof order / sizeof order[0]));
    lua_getfield(L, 1, "id"); order[closed++] = (int)lua_tointeger(L, -1);
    return 0;
}
static void closable(lua_State *L, int id) {
    lua_newtable(L); lua_pushinteger(L, id); lua_setfield(L, -2, "id");
    lua_newtable(L); lua_pushcfunction(L, record_close);
    lua_setfield(L, -2, "__close"); lua_setmetatable(L, -2);
}
static void base_settop(lua_State *L) {
    closable(L, 17); lua_toclose(L, 1); lua_pushinteger(L, 23);
    lua_settop(L, 0); assert(closed == 1 && order[0] == 17);
}
static void base_closeslot(lua_State *L) {
    closable(L, 19); lua_toclose(L, 1); lua_closeslot(L, -1);
    assert(closed == 1 && order[0] == 19);
    assert(lua_gettop(L) == 1 && lua_isnil(L, 1));
    lua_pop(L, 1); assert(closed == 1);
}
static void reverse_order(lua_State *L) {
    closable(L, 1); lua_toclose(L, 1);
    closable(L, 2); lua_toclose(L, 2); lua_settop(L, 0);
    assert(closed == 2 && order[0] == 2 && order[1] == 1);
}
static void actual_slot_value(lua_State *L) {
    closable(L, 1); lua_toclose(L, 1); closable(L, 2);
    /* The close link belongs to the stack slot, not its former value. */
    lua_copy(L, 2, 1); lua_pop(L, 1); lua_settop(L, 0);
    assert(closed == 1 && order[0] == 2);
}
static void registration_refusal(lua_State *L) {
    size_t before;
    closable(L, 29); before = counts.calls; counts.refuse = 1;
    lua_toclose(L, 1); assert(counts.calls == before);
    counts.refuse = 0; lua_settop(L, 0);
    assert(closed == 1 && order[0] == 29);
}
static void grown_registration_refusal(lua_State *L) {
    size_t before;
    assert(lua_checkstack(L, 128)); lua_settop(L, 80);
    closable(L, 31); before = counts.calls; counts.refuse = 1;
    lua_toclose(L, 81); assert(counts.calls == before);
    counts.refuse = 0; lua_settop(L, 0);
    assert(closed == 1 && order[0] == 31);
}
static int callback_mark(lua_State *L) {
    size_t before;
    assert(lua_gettop(L) == 1); before = counts.calls; counts.refuse = 1;
    lua_toclose(L, 1); assert(counts.calls == before);
    counts.refuse = 0; return 0;
}
static void callback_registration_refusal(lua_State *L) {
    lua_pushcfunction(L, callback_mark); closable(L, 37); lua_call(L, 1, 0);
    assert(closed == 1 && order[0] == 37);
}
static void false_registration(lua_State *L) {
    size_t before;
    lua_pushnil(L); lua_pushboolean(L, 0);
    before = counts.calls; counts.refuse = 1;
    lua_toclose(L, 1); lua_toclose(L, 2); assert(counts.calls == before);
    counts.refuse = 0; lua_settop(L, 0); assert(closed == 0);
}
static void thread_query_refusal(lua_State *L) {
    lua_State *co;
    const void *identity;
    size_t before;
    /* No previous C conversion has exposed this Lua-created coroutine. */
    run(L, "return coroutine.create(function()return 37 end)");
    before = counts.calls; counts.refuse = 1;
    co = lua_tothread(L, 1); identity = lua_topointer(L, 1);
    assert(co != NULL && identity == co && counts.calls == before);
    assert(lua_status(co) == LUA_OK);
    counts.refuse = 0; lua_pop(L, 1);
}
static void host_prefix_collection(lua_State *L) {
    run(L, "weak_base=setmetatable({},{__mode='v'});"
        "local x={};weak_base[1]=x;return x,setmetatable({},"
        "{__close=function()collectgarbage('collect');"
        "assert(weak_base[1]~=nil)end})");
    lua_toclose(L, 2); lua_settop(L, 0); lua_gc(L, LUA_GCCOLLECT);
    lua_getglobal(L, "weak_base"); lua_rawgeti(L, -1, 1);
    assert(lua_isnil(L, -1)); lua_settop(L, 0);
}
static void state_close(lua_State *L) {
    closable(L, 41); lua_toclose(L, 1);
    /* The runner closes this owning state while the real base slot is live. */
}
static int callback_result(lua_State *L) {
    lua_toclose(L, 1); lua_pushinteger(L, 73); return 1;
}
static void callback_return_value(lua_State *L) {
    lua_pushcfunction(L, callback_result); closable(L, 43); lua_call(L, 1, 1);
    assert(closed == 1 && order[0] == 43 && lua_tointeger(L, -1) == 73);
    lua_pop(L, 1);
}
static int error_close(lua_State *L) {
    assert(lua_gettop(L) == 2); lua_getglobal(L, "base_marker");
    assert(lua_rawequal(L, 2, -1)); closed++; return 0;
}
static int callback_error(lua_State *L) {
    lua_toclose(L, 1); lua_getglobal(L, "base_marker"); return lua_error(L);
}
static void callback_error_value(lua_State *L) {
    lua_newtable(L); lua_setglobal(L, "base_marker");
    lua_pushcfunction(L, callback_error); closable(L, 47);
    assert(lua_getmetatable(L, -1)); lua_pushcfunction(L, error_close);
    lua_setfield(L, -2, "__close"); lua_pop(L, 1);
    assert(lua_pcall(L, 1, 0, 0) == LUA_ERRRUN && closed == 1);
    lua_getglobal(L, "base_marker"); assert(lua_rawequal(L, -1, -2));
    lua_pop(L, 2);
}

static const struct {
    const char *name;
    void (*body)(lua_State *L);
} cases[] = {
    {"settop", base_settop}, {"closeslot", base_closeslot},
    {"reverse-order", reverse_order}, {"actual-slot", actual_slot_value},
    {"registration-refusal", registration_refusal},
    {"grown-registration-refusal", grown_registration_refusal},
    {"callback-registration-refusal", callback_registration_refusal},
    {"false-registration", false_registration},
    {"thread-query-refusal", thread_query_refusal},
    {"prefix-collection", host_prefix_collection},
    {"state-close", state_close},
    {"callback-return-value", callback_return_value},
    {"callback-error-value", callback_error_value}
};

/* Each AUnit wrapper runs one actual public C protocol in an independent
 * owning state. The same source also executes against both C Lua oracles. */
int lua_ada_test_base_closing(unsigned which) {
    lua_State *L;
    assert(which < sizeof cases / sizeof cases[0]);
    memset(&counts, 0, sizeof counts); closed = 0;
    L = lua_newstate(counted_allocator, &counts, 227U); assert(L);
    luaL_openlibs(L); cases[which].body(L);
    if (cases[which].body != state_close) assert(lua_gettop(L) == 0);
    lua_close(L);
    if (cases[which].body == state_close)
        assert(closed == 1 && order[0] == 41);
    assert(counts.bytes == 0 && counts.blocks == 0);
    return 1;
}

#ifndef LUA_ADA_BASE_CONTRACT_LIBRARY
int main(void) {
    unsigned i;
    for (i = 0; i < sizeof cases / sizeof cases[0]; ++i) {
        assert(lua_ada_test_base_closing(i));
        printf("PASS: base-C-%s\n", cases[i].name); fflush(stdout);
    }
    puts("PASS: public host base C closing contract"); return 0;
}
#endif
