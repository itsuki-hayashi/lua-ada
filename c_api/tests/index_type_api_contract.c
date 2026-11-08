/* Integer indexing and type/version queries through the public C boundary.
 * Copyright (c) 2026 Lua Ada contributors. MIT; see ../../LICENSE. */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "consumer_allocator.h"

static struct allocation_counts counts;

/* Every Lua helper chunk runs through the public protected loader/call path.
 * An unexpected failure retains its actual diagnostic before the assertion
 * stops the consumer; it can never print the enclosing named PASS marker. */
static void run(lua_State *L, const char *source) {
    int status = luaL_dostring(L, source);
    if (status != LUA_OK) fprintf(stderr, "%s\n", lua_tostring(L, -1));
    assert(status == LUA_OK && lua_gettop(L) == 0);
}

/* Return the actual API type alongside the value so Lua assertions inspect
 * both the result and lua_geti's public C return protocol. The key is read
 * before the API pushes its result, preserving the caller's argument slots. */
static int get_integer(lua_State *L) {
    lua_Integer key = luaL_checkinteger(L, 2);
    int type = lua_geti(L, 1, key);
    lua_pushinteger(L, type);
    return 2;
}

static int set_integer(lua_State *L) {
    lua_Integer key = luaL_checkinteger(L, 2);
    lua_pushvalue(L, 3);
    lua_seti(L, 1, key);
    return 0;
}

/* These counterparts deliberately bypass handlers. They distinguish the
 * ordinary integer API from a superficially successful raw-table shortcut. */
static int raw_get_integer(lua_State *L) {
    lua_rawgeti(L, 1, luaL_checkinteger(L, 2));
    return 1;
}

static int raw_set_integer(lua_State *L) {
    lua_Integer key = luaL_checkinteger(L, 2);
    lua_pushvalue(L, 3);
    lua_rawseti(L, 1, key);
    return 0;
}

static void install(lua_State *L, const char *name, lua_CFunction function) {
    lua_pushcfunction(L, function);
    lua_setglobal(L, name);
}

static void version_null_state(lua_State *L) {
    size_t before = counts.calls;
    (void)L;
    /* lua_version explicitly ignores its state; NULL is a valid query. */
    assert(lua_version(NULL) == (lua_Number)LUA_VERSION_NUM);
    assert(counts.calls == before);
}

static void version_live_state(lua_State *L) {
    size_t before = counts.calls;
    assert(lua_version(L) == (lua_Number)LUA_VERSION_NUM);
    assert(lua_gettop(L) == 0 && counts.calls == before);
}

static void builtin_type_names(lua_State *L) {
    static const struct { int tag; const char *name; } rows[] = {
        {LUA_TNIL, "nil"}, {LUA_TBOOLEAN, "boolean"},
        {LUA_TLIGHTUSERDATA, "userdata"}, {LUA_TNUMBER, "number"},
        {LUA_TSTRING, "string"}, {LUA_TTABLE, "table"},
        {LUA_TFUNCTION, "function"}, {LUA_TUSERDATA, "userdata"},
        {LUA_TTHREAD, "thread"}
    };
    size_t i, before = counts.calls;
    const char *number = lua_typename(L, LUA_TNUMBER);
    for (i = 0; i < sizeof rows / sizeof rows[0]; ++i) {
        const char *name = lua_typename(L, rows[i].tag);
        assert(name != NULL && strcmp(name, rows[i].name) == 0);
    }
    /* A later query must not invalidate an earlier borrowed type name. */
    assert(strcmp(number, "number") == 0);
    assert(lua_gettop(L) == 0 && counts.calls == before);
}

static void absent_slot_type_name(lua_State *L) {
    int type;
    /* Reserve an acceptable but absent slot. Arbitrary out-of-range type
     * enums violate lua_typename's API precondition; LUA_TNONE is the valid
     * public representation for an unknown/absent stack value. */
    assert(lua_checkstack(L, 100));
    type = lua_type(L, 77);
    assert(type == LUA_TNONE);
    assert(strcmp(lua_typename(L, type), "no value") == 0);
    lua_pushnil(L);
    assert(lua_type(L, 1) == LUA_TNIL);
    assert(strcmp(lua_typename(L, lua_type(L, 1)), "nil") == 0);
    lua_pop(L, 1);
}

static void type_name_ignores_metatable_label(lua_State *L) {
    lua_newuserdatauv(L, 1, 0);
    lua_newtable(L);
    lua_pushliteral(L, "custom-public-name");
    lua_setfield(L, -2, "__name");
    assert(lua_setmetatable(L, -2));
    assert(strcmp(lua_typename(L, lua_type(L, -1)), "userdata") == 0);
    lua_pop(L, 1);
}

static void get_existing_integer_value(lua_State *L) {
    lua_newtable(L);
    lua_pushinteger(L, 29); lua_rawseti(L, 1, 7);
    assert(lua_geti(L, 1, 7) == LUA_TNUMBER);
    assert(lua_gettop(L) == 2 && lua_isinteger(L, -1));
    assert(lua_tointeger(L, -1) == 29);
    lua_settop(L, 0);
}

static void get_absent_integer_value(lua_State *L) {
    lua_newtable(L);
    assert(lua_geti(L, 1, 7) == LUA_TNIL);
    assert(lua_gettop(L) == 2 && lua_isnil(L, -1));
    lua_settop(L, 0);
}

static void get_numeric_key_identity(lua_State *L) {
    lua_newtable(L);
    lua_pushnumber(L, 7.0); lua_pushliteral(L, "numeric");
    lua_rawset(L, 1);
    lua_pushliteral(L, "string"); lua_setfield(L, 1, "7");
    assert(lua_geti(L, 1, 7) == LUA_TSTRING);
    assert(strcmp(lua_tostring(L, -1), "numeric") == 0);
    lua_pop(L, 1);
    lua_getfield(L, 1, "7");
    assert(strcmp(lua_tostring(L, -1), "string") == 0);
    lua_settop(L, 0);
}

static void get_signed_integer_extremes(lua_State *L) {
    lua_newtable(L);
    lua_pushinteger(L, 11); lua_rawseti(L, 1, LUA_MININTEGER);
    lua_pushinteger(L, 13); lua_rawseti(L, 1, LUA_MAXINTEGER);
    assert(lua_geti(L, 1, LUA_MININTEGER) == LUA_TNUMBER);
    assert(lua_tointeger(L, -1) == 11); lua_pop(L, 1);
    assert(lua_geti(L, 1, LUA_MAXINTEGER) == LUA_TNUMBER);
    assert(lua_tointeger(L, -1) == 13);
    lua_settop(L, 0);
}

static void get_relative_index_before_push(lua_State *L) {
    lua_pushinteger(L, 701); lua_newtable(L);
    lua_pushinteger(L, 31); lua_rawseti(L, -2, 5);
    assert(lua_geti(L, -1, 5) == LUA_TNUMBER);
    assert(lua_gettop(L) == 3 && lua_tointeger(L, 1) == 701);
    assert(lua_istable(L, 2) && lua_tointeger(L, 3) == 31);
    lua_settop(L, 0);
}

static void get_index_handler_operands(lua_State *L) {
    run(L, "local marker={};local t; t=setmetatable({},"
        "{__index=function(self,key)assert(self==t and "
        "key==math.mininteger and math.type(key)=='integer');"
        "collectgarbage();return marker end});"
        "local value,tag=index_geti(t,math.mininteger);"
        "assert(value==marker and tag==5)");
}

static void get_index_table_chain(lua_State *L) {
    run(L, "local fallback={[math.maxinteger]='fallback'};"
        "local t=setmetatable({},{__index=fallback});"
        "local value,tag=index_geti(t,math.maxinteger);"
        "assert(value=='fallback' and tag==4)");
}

static void get_existing_key_bypasses_handler(lua_State *L) {
    run(L, "local t=setmetatable({[3]='stored'},"
        "{__index=function()error('unexpected index handler')end});"
        "local value,tag=index_geti(t,3);assert(value=='stored' and tag==4)");
}

static void get_raw_bypasses_handler(lua_State *L) {
    run(L, "local calls=0;local t=setmetatable({},"
        "{__index=function()calls=calls+1;return 'handled'end});"
        "assert(index_geti(t,2)=='handled' and calls==1);"
        "assert(index_rawgeti(t,2)==nil and calls==1)");
}

static void get_error_identity_and_recovery(lua_State *L) {
    run(L, "local marker={};local t=setmetatable({},"
        "{__index=function()error(marker)end});"
        "local ok,e=pcall(index_geti,t,1);assert(not ok and e==marker);"
        "assert(index_geti({[1]=41},1)==41)");
}

static void get_nonyieldable_handler(lua_State *L) {
    run(L, "local t=setmetatable({},{__index=coroutine.yield});"
        "local co=coroutine.create(function()return index_geti(t,1)end);"
        "local ok,e=coroutine.resume(co);assert(not ok and "
        "type(e)=='string' and e:find('yield') and "
        "coroutine.status(co)=='dead')");
}

static void get_nonindexable_error(lua_State *L) {
    run(L, "local ok,e=pcall(index_geti,false,1);"
        "assert(not ok and type(e)=='string' and e:find('index'));"
        "assert(index_geti({[1]=43},1)==43)");
}

static void set_integer_value_and_pop(lua_State *L) {
    lua_newtable(L); lua_pushinteger(L, 47);
    lua_seti(L, 1, 9);
    assert(lua_gettop(L) == 1);
    lua_rawgeti(L, 1, 9);
    assert(lua_isinteger(L, -1) && lua_tointeger(L, -1) == 47);
    lua_settop(L, 0);
}

static void set_signed_integer_extremes(lua_State *L) {
    lua_newtable(L);
    lua_pushinteger(L, 53); lua_seti(L, 1, LUA_MININTEGER);
    lua_pushinteger(L, 59); lua_seti(L, 1, LUA_MAXINTEGER);
    assert(lua_gettop(L) == 1);
    lua_rawgeti(L, 1, LUA_MININTEGER);
    assert(lua_tointeger(L, -1) == 53); lua_pop(L, 1);
    lua_rawgeti(L, 1, LUA_MAXINTEGER);
    assert(lua_tointeger(L, -1) == 59);
    lua_settop(L, 0);
}

static void set_relative_index_before_pop(lua_State *L) {
    lua_pushinteger(L, 709); lua_newtable(L); lua_pushinteger(L, 61);
    lua_seti(L, -2, 4);
    assert(lua_gettop(L) == 2 && lua_tointeger(L, 1) == 709);
    lua_rawgeti(L, 2, 4);
    assert(lua_tointeger(L, -1) == 61);
    lua_settop(L, 0);
}

/* The top table is simultaneously destination and consumed value. Retain
 * another alias only for verification after the public operation pops it. */
static void set_integer_self_value(lua_State *L) {
    lua_newtable(L); lua_pushvalue(L, 1);
    lua_seti(L, -1, 200);
    assert(lua_gettop(L) == 1);
    lua_rawgeti(L, 1, 200);
    assert(lua_rawequal(L, 1, 2));
    lua_settop(L, 0);
}

static void set_field_self_value(lua_State *L) {
    lua_newtable(L); lua_pushvalue(L, 1);
    lua_setfield(L, 2, "self");
    assert(lua_gettop(L) == 1);
    lua_getfield(L, 1, "self");
    assert(lua_rawequal(L, 1, 2));
    lua_settop(L, 0);
}

static void set_integer_self_handler(lua_State *L) {
    run(L, "global self_target=setmetatable({},{__newindex="
        "function(t,k,v)assert(t==v and k==200);collectgarbage();"
        "rawset(t,k,v)end})");
    lua_getglobal(L, "self_target"); lua_pushvalue(L, 1);
    lua_seti(L, -1, 200);
    assert(lua_gettop(L) == 1);
    lua_rawgeti(L, 1, 200); assert(lua_rawequal(L, 1, 2));
    lua_settop(L, 0);
}

static void set_newindex_handler_operands(lua_State *L) {
    run(L, "local marker={};local calls=0;local t;"
        "t=setmetatable({},{__newindex=function(self,key,value)"
        "assert(self==t and key==math.maxinteger and "
        "math.type(key)=='integer' and value==marker);"
        "collectgarbage();calls=calls+1 end});"
        "assert(select('#',index_seti(t,math.maxinteger,marker))==0);"
        "assert(calls==1 and rawget(t,math.maxinteger)==nil)");
}

static void set_newindex_table_chain(lua_State *L) {
    run(L, "local fallback={};local t=setmetatable({},"
        "{__newindex=fallback});index_seti(t,math.mininteger,'forwarded');"
        "assert(rawget(t,math.mininteger)==nil and "
        "rawget(fallback,math.mininteger)=='forwarded')");
}

static void set_existing_key_bypasses_handler(lua_State *L) {
    run(L, "local t=setmetatable({[3]='old'},"
        "{__newindex=function()error('unexpected newindex handler')end});"
        "index_seti(t,3,'new');assert(rawget(t,3)=='new')");
}

static void set_raw_bypasses_handler(lua_State *L) {
    run(L, "local calls=0;local t=setmetatable({},"
        "{__newindex=function()calls=calls+1 end});"
        "index_seti(t,2,'handled');assert(rawget(t,2)==nil and calls==1);"
        "index_rawseti(t,2,'raw');assert(rawget(t,2)=='raw' and calls==1)");
}

static void set_error_identity_and_recovery(lua_State *L) {
    run(L, "local marker={};local t=setmetatable({},"
        "{__newindex=function()error(marker)end});"
        "local ok,e=pcall(index_seti,t,1,'value');assert(not ok and e==marker);"
        "local plain={};index_seti(plain,1,67);assert(plain[1]==67)");
}

static void set_nonyieldable_handler(lua_State *L) {
    run(L, "local t=setmetatable({},{__newindex=coroutine.yield});"
        "local co=coroutine.create(function()index_seti(t,1,'value')end);"
        "local ok,e=coroutine.resume(co);assert(not ok and "
        "type(e)=='string' and e:find('yield') and "
        "coroutine.status(co)=='dead')");
}

static void set_nonindexable_error(lua_State *L) {
    run(L, "local ok,e=pcall(index_seti,false,1,'value');"
        "assert(not ok and type(e)=='string' and e:find('index'));"
        "local plain={};index_seti(plain,1,71);assert(plain[1]==71)");
}

/* Each named case must finish with the same C frame extent it started with.
 * Its PASS line is emitted only after both the operation's assertions and
 * the independent frame-height assertion have completed. */
static void check(const char *name, void (*body)(lua_State *), lua_State *L) {
    assert(lua_gettop(L) == 0);
    body(L);
    assert(lua_gettop(L) == 0);
    printf("PASS: index-type-%s\n", name);
    fflush(stdout);
}

int main(void) {
    lua_State *L = lua_newstate(counted_allocator, &counts, 1201U);
    assert(L != NULL);
    luaL_openlibs(L);
    install(L, "index_geti", get_integer);
    install(L, "index_seti", set_integer);
    install(L, "index_rawgeti", raw_get_integer);
    install(L, "index_rawseti", raw_set_integer);
    check("version-null-state", version_null_state, L);
    check("version-live-state", version_live_state, L);
    check("builtin-type-names", builtin_type_names, L);
    check("absent-slot-type-name", absent_slot_type_name, L);
    check("type-name-ignores-metatable-label", type_name_ignores_metatable_label, L);
    check("get-existing-integer-value", get_existing_integer_value, L);
    check("get-absent-integer-value", get_absent_integer_value, L);
    check("get-numeric-key-identity", get_numeric_key_identity, L);
    check("get-signed-integer-extremes", get_signed_integer_extremes, L);
    check("get-relative-index-before-push", get_relative_index_before_push, L);
    check("get-index-handler-operands", get_index_handler_operands, L);
    check("get-index-table-chain", get_index_table_chain, L);
    check("get-existing-key-bypasses-handler", get_existing_key_bypasses_handler, L);
    check("get-raw-bypasses-handler", get_raw_bypasses_handler, L);
    check("get-error-identity-and-recovery", get_error_identity_and_recovery, L);
    check("get-nonyieldable-handler", get_nonyieldable_handler, L);
    check("get-nonindexable-error", get_nonindexable_error, L);
    check("set-integer-value-and-pop", set_integer_value_and_pop, L);
    check("set-signed-integer-extremes", set_signed_integer_extremes, L);
    check("set-relative-index-before-pop", set_relative_index_before_pop, L);
    check("set-integer-self-value", set_integer_self_value, L);
    check("set-field-self-value", set_field_self_value, L);
    check("set-integer-self-handler", set_integer_self_handler, L);
    check("set-newindex-handler-operands", set_newindex_handler_operands, L);
    check("set-newindex-table-chain", set_newindex_table_chain, L);
    check("set-existing-key-bypasses-handler", set_existing_key_bypasses_handler, L);
    check("set-raw-bypasses-handler", set_raw_bypasses_handler, L);
    check("set-error-identity-and-recovery", set_error_identity_and_recovery, L);
    check("set-nonyieldable-handler", set_nonyieldable_handler, L);
    check("set-nonindexable-error", set_nonindexable_error, L);
    lua_close(L);
    assert(counts.bytes == 0 && counts.blocks == 0);
    puts("PASS: public integer-index and type contract");
    return 0;
}
