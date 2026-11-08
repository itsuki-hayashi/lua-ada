/* Shared arithmetic/comparison through the actual public C boundary.
 * Copyright (c) 2026 Lua Ada contributors. MIT; see ../../LICENSE. */
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
static int pending_op;
static void run(lua_State *L, const char *source) {
    int status = luaL_dostring(L, source);
    if (status != LUA_OK) fprintf(stderr, "%s\n", lua_tostring(L, -1));
    assert(status == LUA_OK);
}
static int add(lua_State *L) { lua_arith(L, LUA_OPADD); return 1; }
static int unary(lua_State *L) { lua_arith(L, LUA_OPUNM); return 1; }
static int compare(lua_State *L) {
    lua_pushboolean(L, lua_compare(L, 1, 2, pending_op)); return 1;
}
static int arithmetic_error(lua_State *L) {
    lua_arith(L, pending_op); return 1;
}
static void install(lua_State *L, const char *name, lua_CFunction body) {
    lua_pushcfunction(L, body); lua_setglobal(L, name);
}
static void primitive_arithmetic(lua_State *L) {
    static const struct { int op, integer; lua_Number result; } rows[] = {
        {LUA_OPADD,1,22},{LUA_OPSUB,1,12},{LUA_OPMUL,1,85},
        {LUA_OPMOD,1,2},{LUA_OPPOW,0,1419857},{LUA_OPDIV,0,17.0/5.0},
        {LUA_OPIDIV,1,3},{LUA_OPBAND,1,1},{LUA_OPBOR,1,21},
        {LUA_OPBXOR,1,20},{LUA_OPSHL,1,544},{LUA_OPSHR,1,0}};
    size_t i;
    for (i=0;i<sizeof rows/sizeof rows[0];++i) {
        lua_pushinteger(L,701); lua_pushinteger(L,17); lua_pushinteger(L,5);
        lua_arith(L, rows[i].op);
        assert(lua_gettop(L)==2 && lua_tointeger(L,1)==701);
        assert(lua_isinteger(L,2)==rows[i].integer);
        assert(lua_tonumber(L,2)==rows[i].result); lua_settop(L,0);
    }
}
static void unary_and_wrap(lua_State *L) {
    lua_pushinteger(L,7); lua_arith(L,LUA_OPUNM);
    assert(lua_gettop(L)==1 && lua_tointeger(L,1)==-7); lua_pop(L,1);
    lua_pushinteger(L,7); lua_arith(L,LUA_OPBNOT);
    assert(lua_gettop(L)==1 && lua_tointeger(L,1)==-8); lua_pop(L,1);
    lua_pushinteger(L,LUA_MAXINTEGER); lua_pushinteger(L,1);
    lua_arith(L,LUA_OPADD); assert(lua_tointeger(L,-1)==LUA_MININTEGER);
    lua_pop(L,1); lua_pushinteger(L,-17); lua_pushinteger(L,5);
    lua_arith(L,LUA_OPIDIV); assert(lua_tointeger(L,-1)==-4); lua_pop(L,1);
}
static void primitive_comparison(lua_State *L) {
    assert(!lua_compare(L,1,2,LUA_OPEQ)); lua_pushnil(L);
    assert(!lua_compare(L,1,2,LUA_OPEQ)); lua_settop(L,0);
    lua_pushinteger(L,9007199254740993LL); lua_pushnumber(L,9007199254740992.0);
    assert(!lua_compare(L,1,2,LUA_OPEQ));
    assert(!lua_compare(L,1,2,LUA_OPLT)); assert(lua_compare(L,2,1,LUA_OPLT));
    lua_settop(L,0); lua_pushlstring(L,"a\0b",3); lua_pushlstring(L,"a\0c",3);
    assert(lua_compare(L,1,2,LUA_OPLT) && lua_compare(L,1,2,LUA_OPLE));
    assert(lua_gettop(L)==2); lua_settop(L,0);
}
static void primitive_refusal(lua_State *L) {
    size_t before;
    assert(lua_checkstack(L,64)); before=counts.calls; counts.refuse=1;
    lua_pushinteger(L,17); lua_pushinteger(L,5); lua_arith(L,LUA_OPBAND);
    assert(lua_tointeger(L,-1)==1); lua_pushnumber(L,1);
    assert(lua_compare(L,1,2,LUA_OPEQ)); lua_settop(L,0);
    lua_pushnumber(L,3.0); lua_arith(L,LUA_OPBNOT);
    assert(lua_isinteger(L,-1) && lua_tointeger(L,-1)==-4); lua_settop(L,0);
    assert(counts.calls==before); counts.refuse=0;
}
static void string_handlers(lua_State *L) {
    lua_pushstring(L,"3"); lua_pushinteger(L,5); lua_arith(L,LUA_OPADD);
    assert(lua_tonumber(L,-1)==8); lua_pop(L,1);
    lua_pushinteger(L,3); lua_pushstring(L,"5"); lua_arith(L,LUA_OPMUL);
    assert(lua_tonumber(L,-1)==15); lua_pop(L,1);
}
static void metamethod_arithmetic(lua_State *L) {
    install(L,"c_add",add); install(L,"c_unary",unary);
    run(L,"local a=setmetatable({},{__add=function(a,b)assert(b==5);return 37 end});"
          "assert(c_add(a,5)==37);local b=setmetatable({},{__unm=function(a,b)"
          "assert(a==b);return 41 end});assert(c_unary(b)==41)");
}
static void numeric_bitwise_handler(lua_State *L) {
    run(L,"local mt={__band=function(a,b)assert(a==3.5 and b==1);return 47 end};"
          "debug.setmetatable(0,mt)");
    lua_pushnumber(L,3.5); lua_pushinteger(L,1); lua_arith(L,LUA_OPBAND);
    assert(lua_tointeger(L,-1)==47); lua_pop(L,1);
    run(L,"debug.setmetatable(0,nil)");
}
static void arbitrary_handler_error(lua_State *L) {
    run(L,"marker={};bad_arith=setmetatable({},{__add=function()error(marker)end})");
    lua_pushcfunction(L,add); lua_getglobal(L,"bad_arith"); lua_pushinteger(L,1);
    assert(lua_pcall(L,2,1,0)==LUA_ERRRUN); lua_getglobal(L,"marker");
    assert(lua_rawequal(L,-1,-2)); lua_settop(L,0);
}
static void arithmetic_diagnostics(lua_State *L) {
    pending_op=LUA_OPIDIV; lua_pushcfunction(L,arithmetic_error);
    lua_pushinteger(L,1); lua_pushinteger(L,0);
    assert(lua_pcall(L,2,1,0)==LUA_ERRRUN);
    assert(strstr(lua_tostring(L,-1),"divide by zero")); lua_pop(L,1);
    pending_op=LUA_OPBAND; lua_pushcfunction(L,arithmetic_error);
    lua_pushnumber(L,3.5); lua_pushinteger(L,1);
    assert(lua_pcall(L,2,1,0)==LUA_ERRRUN);
    assert(strstr(lua_tostring(L,-1),"no integer representation")); lua_pop(L,1);
    lua_pushcfunction(L,arithmetic_error); lua_newtable(L); lua_pushinteger(L,1);
    assert(lua_pcall(L,2,1,0)==LUA_ERRRUN);
    assert(strcmp(lua_tostring(L,-1),
                  "attempt to perform bitwise operation on a table value")==0);
    lua_pop(L,1);
}
static void bare_string_no_handler(lua_State *L) {
    struct allocation_counts own={0}; lua_State *bare;
    (void)L; bare=lua_newstate(counted_allocator,&own,211U); assert(bare);
    pending_op=LUA_OPADD; lua_pushcfunction(bare,arithmetic_error);
    lua_pushinteger(bare,3); lua_pushstring(bare,"5");
    assert(lua_pcall(bare,2,1,0)==LUA_ERRRUN);
    assert(strcmp(lua_tostring(bare,-1),
                  "attempt to perform arithmetic on a string value")==0);
    lua_close(bare); assert(own.bytes==0 && own.blocks==0);
}
static void comparison_handlers(lua_State *L) {
    install(L,"c_compare",compare);
    pending_op=LUA_OPEQ;
    run(L,"local a=setmetatable({},{__eq=function()return {} end});"
          "assert(c_compare(a,{}));assert(not c_compare(a,1))");
    pending_op=LUA_OPLT;
    run(L,"local a=setmetatable({},{__lt=function(a,b)return b==71 end});"
          "assert(c_compare(a,71));assert(not c_compare(a,72))");
    pending_op=LUA_OPLE;
    run(L,"local a=setmetatable({},{__le=function(a,b)return b==79 end});"
          "assert(c_compare(a,79));assert(not c_compare(a,80))");
}
static int caller_add(lua_State *L) {
    lua_arith(L,LUA_OPADD);
    assert(lua_gettop(L)==2 && lua_tointeger(L,1)==901);
    assert(lua_tointeger(L,2)==83); return 1;
}
static void arithmetic_caller_window(lua_State *L) {
    install(L,"caller_add",caller_add);
    run(L,"local a=setmetatable({},{__add=function(a,b)"
          "assert(debug.getinfo(2,'f').func==caller_add);"
          "local n,v=debug.getlocal(2,1);assert(n=='(C temporary)' and v==900);"
          "assert(select(2,debug.getlocal(2,2))==a);"
          "assert(select(2,debug.getlocal(2,3))==b);"
          "assert(debug.getlocal(2,4)==nil);"
          "assert(debug.setlocal(2,1,901)=='(C temporary)');return 83 end});"
          "assert(caller_add(900,a,5)==83)");
}
static int caller_unary(lua_State *L) {
    lua_arith(L,LUA_OPUNM);
    assert(lua_gettop(L)==2 && lua_tointeger(L,1)==907);
    assert(lua_tointeger(L,2)==89); return 1;
}
static void unary_caller_fake_operand(lua_State *L) {
    install(L,"caller_unary",caller_unary);
    run(L,"local a=setmetatable({},{__unm=function(a,b)assert(a==b);"
          "assert(debug.getinfo(2,'f').func==caller_unary);"
          "assert(select(2,debug.getlocal(2,1))==900);"
          "assert(select(2,debug.getlocal(2,2))==a);"
          "assert(select(2,debug.getlocal(2,3))==a);"
          "assert(debug.getlocal(2,4)==nil);debug.setlocal(2,1,907);"
          "return 89 end});assert(caller_unary(900,a)==89)");
}
static int caller_compare(lua_State *L) {
    int result=lua_compare(L,1,2,LUA_OPLT);
    assert(result && lua_gettop(L)==3 && lua_tointeger(L,3)==919);
    lua_getglobal(L,"replacement"); assert(lua_rawequal(L,1,-1)); lua_pop(L,1);
    lua_pushboolean(L,result); return 1;
}
static void comparison_caller_mutation(lua_State *L) {
    install(L,"caller_compare",caller_compare);
    run(L,"replacement={};local a=setmetatable({},{__lt=function(a,b)"
          "assert(debug.getinfo(2,'f').func==caller_compare);"
          "assert(select(2,debug.getlocal(2,1))==a);"
          "assert(select(2,debug.getlocal(2,2))==b);"
          "assert(select(2,debug.getlocal(2,3))==900);"
          "assert(debug.getlocal(2,4)==nil);debug.setlocal(2,3,919);"
          "debug.setlocal(2,1,replacement);return true end});"
          "assert(caller_compare(a,5,900))");
}
static void comparison_error_identity(lua_State *L) {
    pending_op=LUA_OPLT;
    run(L,"bad_compare=setmetatable({},{__lt=function()error(marker)end})");
    lua_pushcfunction(L,compare); lua_getglobal(L,"bad_compare"); lua_pushinteger(L,1);
    assert(lua_pcall(L,2,1,0)==LUA_ERRRUN); lua_getglobal(L,"marker");
    assert(lua_rawequal(L,-1,-2)); lua_settop(L,0);
}
static void comparison_type_errors(lua_State *L) {
    pending_op=LUA_OPLT; lua_pushcfunction(L,compare);
    lua_newtable(L); lua_newtable(L);
    assert(lua_pcall(L,2,1,0)==LUA_ERRRUN);
    assert(strcmp(lua_tostring(L,-1),"attempt to compare two table values")==0);
    lua_pop(L,1); lua_pushcfunction(L,compare); lua_newtable(L);
    lua_pushinteger(L,1); assert(lua_pcall(L,2,1,0)==LUA_ERRRUN);
    assert(strcmp(lua_tostring(L,-1),"attempt to compare table with number")==0);
    lua_pop(L,1);
}
static void handler_cannot_yield(lua_State *L) {
    run(L,"local a=setmetatable({},{__add=function()coroutine.yield(1)end});"
          "local co=coroutine.create(function()return c_add(a,1)end);"
          "local ok,e=coroutine.resume(co);assert(not ok and "
          "string.find(e,'yield across a C%-call boundary'))");
}
static void check(const char *name,void (*body)(lua_State *),lua_State *L) {
    assert(lua_gettop(L)==0); body(L); assert(lua_gettop(L)==0);
    printf("PASS: operator-%s\n",name); fflush(stdout);
}
int main(void) {
    lua_State *L=lua_newstate(counted_allocator,&counts,199U); assert(L);
    luaL_openlibs(L);
    check("primitive-arithmetic",primitive_arithmetic,L);
    check("unary-wrap",unary_and_wrap,L);
    check("primitive-comparison",primitive_comparison,L);
    check("primitive-refusal",primitive_refusal,L);
    check("string-handlers",string_handlers,L);
    check("metamethod-arithmetic",metamethod_arithmetic,L);
    check("numeric-bitwise-handler",numeric_bitwise_handler,L);
    check("arbitrary-handler-error",arbitrary_handler_error,L);
    check("arithmetic-diagnostics",arithmetic_diagnostics,L);
    check("bare-string-no-handler",bare_string_no_handler,L);
    check("comparison-handlers",comparison_handlers,L);
    check("arithmetic-caller-window",arithmetic_caller_window,L);
    check("unary-caller-fake-operand",unary_caller_fake_operand,L);
    check("comparison-caller-mutation",comparison_caller_mutation,L);
    check("comparison-error-identity",comparison_error_identity,L);
    check("comparison-type-errors",comparison_type_errors,L);
    check("handler-cannot-yield",handler_cannot_yield,L);
    lua_close(L); assert(counts.bytes==0 && counts.blocks==0);
    puts("PASS: public C operator contract"); return 0;
}
