/* Public lua_concat stack, callback, ownership and refusal regressions.
 * MIT license; see ../../LICENSE. The identical C99 source runs against the
 * pinned default/T C libraries and Lua Ada. Each named case owns a fresh
 * counted state, and successful close must release every provider block.
 *
 * The handler tests deliberately use debug.getlocal/setlocal on the actual
 * C caller. A captured copy of its arguments cannot satisfy these checks.
 * Collection is explicit and no exact capacity/allocation count is assumed.
 */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "consumer_allocator.h"

#ifdef NDEBUG
#error "concat_api_contract.c requires assert checks"
#endif

static struct allocation_counts counts;
static int refuse_once;
static unsigned transient_refusals;

static void *concat_allocator(void *data, void *block,
                              size_t old_size, size_t new_size) {
    if (refuse_once && (block == NULL || new_size > old_size) && new_size > 0) {
        refuse_once = 0;
        transient_refusals++;
        counts.calls++;
        counts.growths++;
        return NULL;
    }
    return counted_allocator(data, block, old_size, new_size);
}

static int concat_all(lua_State *L) {
    lua_concat(L, lua_gettop(L));
    assert(lua_gettop(L) == 1);
    return 1;
}

static int concat_prefix(lua_State *L) {
    assert(lua_gettop(L) == 4);
    lua_concat(L, 3);
    assert(lua_gettop(L) == 2);
    assert(strcmp(lua_tostring(L, 1), "prefix") == 0);
    return 1;
}

/* The only persistent strong edges to these tables are the real C slots.
 * The public weak table observes whether consumed/overwritten slots and
 * private handler transport packets retire at the proper safe points. */
static int concat_seed(lua_State *L) {
    int i;
    assert(lua_gettop(L) == 0);
    for (i = 1; i <= 3; i++) {
        char id[2] = {(char)('a' + i - 1), 0};
        lua_newtable(L);
        lua_pushstring(L, id);
        lua_setfield(L, -2, "id");
        lua_getglobal(L, "concat_mt");
        lua_setmetatable(L, -2);
        lua_getglobal(L, "concat_weak");
        lua_pushvalue(L, -2);
        lua_rawseti(L, -2, i);
        lua_pop(L, 1);
    }
    lua_concat(L, 3);
    assert(lua_gettop(L) == 1);
    return 1;
}

static void run(lua_State *L, const char *text) {
    int status = luaL_dostring(L, text);
    if (status != LUA_OK) fprintf(stderr, "%s\n", lua_tostring(L, -1));
    assert(status == LUA_OK);
}

/* Mutating an operand not yet reached by the right fold must change the
 * next call. The already folded right pair occupies one actual slot and
 * its old final slot is no longer a public C local. */
static void caller_mutation(lua_State *L) {
    run(L, "local step=0;local replacement={id='replacement'};"
        "local result={id='result'};local mt={__concat=function(x,y)"
        "step=step+1;assert(debug.getinfo(2,'f').func==concat_all);"
        "if step==1 then assert(x.id=='b' and y.id=='c');"
        "local _,a=debug.getlocal(2,1);local _,c=debug.getlocal(2,3);"
        "assert(a.id=='a' and c.id=='c');"
        "assert(debug.setlocal(2,1,replacement));return result "
        "else assert(x==replacement and y==result);"
        "local _,v=debug.getlocal(2,2);assert(v==result);"
        "assert(debug.getlocal(2,3)==nil);return 'joined'end end};"
        "setmetatable(replacement,mt);setmetatable(result,mt);"
        "assert(concat_all(setmetatable({id='a'},mt),"
        "setmetatable({id='b'},mt),setmetatable({id='c'},mt))=='joined');"
        "assert(step==2)");
}

/* Replacing a future operand removes its old sole edge immediately; the
 * current pair survives until its real handler returns and is then gone. */
static void weak_operand_lifetime(lua_State *L) {
    run(L, "local step=0;local replacement={id='replacement'};"
        "local result={id='result'};concat_weak=setmetatable({},{__mode='v'});"
        "concat_mt={__concat=function(x,y)step=step+1;"
        "assert(debug.getinfo(2,'f').func==concat_seed);"
        "if step==1 then assert(concat_weak[1] and concat_weak[2] "
        "and concat_weak[3]);assert(debug.setlocal(2,1,replacement));"
        "collectgarbage();assert(concat_weak[1]==nil);"
        "assert(concat_weak[2] and concat_weak[3]);return result "
        "else collectgarbage();assert(concat_weak[2]==nil "
        "and concat_weak[3]==nil);assert(x==replacement and y==result);"
        "return 'joined'end end};setmetatable(replacement,concat_mt);"
        "setmetatable(result,concat_mt);"
        "assert(concat_seed()=='joined' and step==2)");
}

static void retained_prefix(lua_State *L) {
    run(L, "local step=0;local replacement={};local result={};"
        "local mt={__concat=function(x,y)step=step+1;"
        "assert(debug.getinfo(2,'f').func==concat_prefix);"
        "local _,p=debug.getlocal(2,1);assert(p=='prefix');"
        "if step==1 then assert(x.id=='b' and y.id=='c');"
        "assert(debug.setlocal(2,2,replacement));return result "
        "else assert(x==replacement and y==result);"
        "assert(debug.getlocal(2,4)==nil);return 'joined'end end};"
        "setmetatable(replacement,mt);setmetatable(result,mt);"
        "assert(concat_prefix('prefix',setmetatable({id='a'},mt),"
        "setmetatable({id='b'},mt),setmetatable({id='c'},mt))=='joined');"
        "assert(step==2)");
}

static void error_location(lua_State *L) {
    run(L, "local ok,e=pcall(concat_all,'x',{});assert(not ok "
        "and e=='attempt to concatenate a table value',tostring(e))");
}

/* Even the currently executing handler may remove every public edge to
 * its operands. A hidden continuation argument snapshot must not keep them
 * alive after the handler clears its own parameters and the C slots. */
static void current_pair_roots(lua_State *L) {
    run(L, "local step=0;concat_weak=setmetatable({},{__mode='v'});"
        "concat_mt={__concat=function(x,y)step=step+1;"
        "if step==1 then assert(x.id=='b' and y.id=='c');"
        "debug.setlocal(2,2,nil);debug.setlocal(2,3,nil);x,y=nil,nil;"
        "collectgarbage();assert(concat_weak[2]==nil and concat_weak[3]==nil);"
        "local r=setmetatable({id='r'},concat_mt);concat_weak[4]=r;return r "
        "else assert(x.id=='a' and y.id=='r');"
        "debug.setlocal(2,1,nil);debug.setlocal(2,2,nil);x,y=nil,nil;"
        "collectgarbage();assert(concat_weak[1]==nil and concat_weak[4]==nil);"
        "return 'joined'end end};"
        "assert(concat_seed()=='joined' and step==2)");
}

static void primitive_suffix(lua_State *L) {
    run(L, "local calls=0;local a=setmetatable({},"
        "{__concat=function(x,y)calls=calls+1;assert(y=='bc');"
        "assert(debug.getinfo(2,'f').func==concat_prefix);"
        "local _,p=debug.getlocal(2,1);local _,v=debug.getlocal(2,3);"
        "assert(p=='prefix' and v=='bc' and debug.getlocal(2,4)==nil);"
        "return 'joined'end});"
        "assert(concat_prefix('prefix',a,'b','c')=='joined' and calls==1)");
}

static void numeric_primitives(lua_State *L) {
    lua_pushliteral(L, "prefix");
    lua_pushliteral(L, "a");
    lua_pushinteger(L, 1);
    lua_pushnumber(L, 2.5);
    lua_concat(L, 3);
    assert(lua_gettop(L) == 2);
    assert(strcmp(lua_tostring(L, 1), "prefix") == 0);
    assert(strcmp(lua_tostring(L, 2), "a12.5") == 0);
    lua_pop(L, 2);
}

static void empty_result(lua_State *L) {
    lua_pushinteger(L, 71);
    lua_concat(L, 0);
    assert(lua_gettop(L) == 2 && lua_tointeger(L, 1) == 71);
    assert(lua_type(L, 2) == LUA_TSTRING && lua_rawlen(L, 2) == 0);
    lua_pop(L, 2);
}

static void singleton_identity(lua_State *L) {
    const void *identity;
    lua_newtable(L);
    identity = lua_topointer(L, 1);
    lua_concat(L, 1);
    assert(lua_gettop(L) == 1 && lua_topointer(L, 1) == identity);
    lua_pop(L, 1);
}

/* The ordinary empty short string shortcuts reuse the long operand object.
 * Refuse every growth only after both values and the real C frame exist.
 * The zero-growth assertion is a supported shortcut, not a capacity guess. */
static int empty_shortcut(lua_State *L) {
    int original = (int)lua_tointeger(L, 3);
    const void *identity = lua_topointer(L, original);
    size_t growths;
    lua_pop(L, 1);
    growths = counts.growths;
    counts.refuse = 1;
    lua_concat(L, 2);
    counts.refuse = 0;
    assert(counts.growths == growths);
    assert(lua_gettop(L) == 1 && lua_topointer(L, 1) == identity);
    return 1;
}

static int concat_storage(lua_State *L) {
    int i;
    assert(lua_gettop(L) == 0 && lua_checkstack(L, 4100));
    lua_pushliteral(L, "x");
    for (i = 1; i < 4096; i++) lua_pushvalue(L, 1);
    /* Input slots already exist. Permit ample constant construction growth,
     * while rejecting thousands of intermediate prefix/suffix objects. This
     * checks a real provider limit, not native pool order or exact counts. */
    counts.fail_after = counts.growths + 32;
    lua_concat(L, 4096);
    counts.fail_after = 0;
    assert(lua_gettop(L) == 1 && lua_rawlen(L, 1) == 4096);
    return 1;
}

static int concat_transient(lua_State *L) {
    assert(lua_gettop(L) == 3);
    transient_refusals = 0;
    refuse_once = 1;
    lua_concat(L, 3);
    assert(refuse_once == 0 && transient_refusals == 1);
    assert(lua_gettop(L) == 1 && lua_rawlen(L, 1) == 600);
    return 1;
}

static void empty_right_refusal(lua_State *L) {
    run(L, "local long=string.rep('r',200);"
        "assert(empty_shortcut(long,'',1)==long)");
}

static void empty_left_refusal(lua_State *L) {
    run(L, "local long=string.rep('l',200);"
        "assert(empty_shortcut('',long,2)==long)");
}

/* luaV_concat deliberately excludes external empty strings from isemptystr.
 * With a long nonempty neighbour it creates a fresh equal string instead
 * of returning that neighbour. Static external bytes need no deallocator. */
static void external_empty_copy(lua_State *L) {
    char text[201];
    const void *identity;
    memset(text, 'x', sizeof text - 1);
    text[sizeof text - 1] = 0;
    lua_pushlstring(L, text, sizeof text - 1);
    identity = lua_topointer(L, 1);
    lua_pushexternalstring(L, "", 0, NULL, NULL);
    lua_concat(L, 2);
    assert(lua_gettop(L) == 1 && lua_topointer(L, 1) != identity);
    assert(lua_rawlen(L, 1) == sizeof text - 1);
    assert(memcmp(lua_tostring(L, 1), text, sizeof text) == 0);
    lua_pop(L, 1);
}

static void external_empty_left_copy(lua_State *L) {
    char text[201];
    const void *identity;
    memset(text, 'y', sizeof text - 1);
    text[sizeof text - 1] = 0;
    lua_pushexternalstring(L, "", 0, NULL, NULL);
    lua_pushlstring(L, text, sizeof text - 1);
    identity = lua_topointer(L, 2);
    lua_concat(L, 2);
    assert(lua_gettop(L) == 1 && lua_topointer(L, 1) != identity);
    assert(lua_rawlen(L, 1) == sizeof text - 1);
    assert(memcmp(lua_tostring(L, 1), text, sizeof text) == 0);
    lua_pop(L, 1);
}

static void empty_handler_result(lua_State *L) {
    run(L, "local calls=0;local t;t=setmetatable({},"
        "{__concat=function(x,y)calls=calls+1;assert(x==t);"
        "if calls==1 then assert(y==t)else assert(y==nil)end end});"
        "assert(select('#',concat_all(t,t,t))==1);"
        "assert(calls==2);calls=0;"
        "assert(concat_all(t,t)==nil and calls==1)");
}

static void number_before_handler(lua_State *L) {
    run(L, "local t;t=setmetatable({},{__concat=function(x,y)"
        "assert(type(x)=='number' and x==37 and y==t);return 'joined'end});"
        "assert(concat_all(37,t)=='joined')");
}

static void number_after_handler(lua_State *L) {
    run(L, "local t;t=setmetatable({},{__concat=function(x,y)"
        "assert(x==t and type(y)=='number' and y==37);return 'joined'end});"
        "assert(concat_all(t,37)=='joined')");
}

static void grouped_storage(lua_State *L) {
    run(L, "local s=concat_storage();assert(#s==4096 and "
        "s==string.rep('x',4096))");
}

static void transient_growth_retry(lua_State *L) {
    run(L, "local a,b,c=string.rep('a',200),string.rep('b',200),"
        "string.rep('c',200);local s=concat_transient(a,b,c);"
        "assert(s==a..b..c)");
}

static void binary_run(lua_State *L) {
    static const char expected[] = {'a', 0, 'b', '3', '7', 0, 'c'};
    lua_pushliteral(L, "prefix");
    lua_pushlstring(L, "a\0b", 3);
    lua_pushinteger(L, 37);
    lua_pushlstring(L, "\0c", 2);
    lua_concat(L, 3);
    assert(lua_gettop(L) == 2 && lua_rawlen(L, 2) == sizeof expected);
    assert(strcmp(lua_tostring(L, 1), "prefix") == 0);
    assert(memcmp(lua_tostring(L, 2), expected, sizeof expected) == 0);
    lua_pop(L, 2);
}

static void handler_error_identity(lua_State *L) {
    run(L, "local marker={};local t=setmetatable({},"
        "{__concat=function()error(marker)end});"
        "local ok,e=pcall(concat_all,t,t,t);assert(not ok and e==marker);"
        "assert(concat_all('re','covered')=='recovered')");
}

static void nonyieldable_handler(lua_State *L) {
    run(L, "local t=setmetatable({},{__concat=coroutine.yield});"
        "local co=coroutine.create(function()return concat_all(t,t)end);"
        "local ok,e=coroutine.resume(co);assert(not ok and "
        "e=='attempt to yield across a C-call boundary');"
        "assert(coroutine.status(co)=='dead');"
        "local closed,err=coroutine.close(co);assert(not closed and err==e)");
}

typedef void (*concat_case)(lua_State *L);
static const struct { const char *name; concat_case body; } cases[] = {
    {"caller-mutation", caller_mutation},
    {"weak-operand-lifetime", weak_operand_lifetime},
    {"retained-prefix", retained_prefix},
    {"error-location", error_location},
    {"current-pair-roots", current_pair_roots},
    {"primitive-suffix", primitive_suffix},
    {"numeric-primitives", numeric_primitives},
    {"empty-result", empty_result},
    {"singleton-identity", singleton_identity},
    {"empty-right-refusal", empty_right_refusal},
    {"empty-left-refusal", empty_left_refusal},
    {"external-empty-copy", external_empty_copy},
    {"handler-error-identity", handler_error_identity},
    {"nonyieldable-handler", nonyieldable_handler},
    {"external-empty-left-copy", external_empty_left_copy},
    {"empty-handler-result", empty_handler_result},
    {"number-before-handler", number_before_handler},
    {"number-after-handler", number_after_handler},
    {"grouped-storage", grouped_storage},
    {"transient-growth-retry", transient_growth_retry},
    {"binary-run", binary_run}
};

#define CONCAT_CASE_COUNT (sizeof cases / sizeof cases[0])

int lua_ada_test_concat(unsigned which) {
    lua_State *L;
    assert(which < CONCAT_CASE_COUNT);
    memset(&counts, 0, sizeof counts);
    refuse_once = 0;
    transient_refusals = 0;
    L = lua_newstate(concat_allocator, &counts, 317U);
    assert(L != NULL);
    luaL_openlibs(L);
    lua_register(L, "concat_all", concat_all);
    lua_register(L, "concat_prefix", concat_prefix);
    lua_register(L, "concat_seed", concat_seed);
    lua_register(L, "empty_shortcut", empty_shortcut);
    lua_register(L, "concat_storage", concat_storage);
    lua_register(L, "concat_transient", concat_transient);
    cases[which].body(L);
    assert(lua_gettop(L) == 0);
    counts.refuse = 0;
    lua_close(L);
    assert(counts.bytes == 0 && counts.blocks == 0);
    return 1;
}

#ifndef LUA_ADA_CONCAT_CONTRACT_LIBRARY
int main(void) {
    unsigned i;
    for (i = 0; i < CONCAT_CASE_COUNT; i++) {
        assert(lua_ada_test_concat(i));
        printf("PASS: concat-%s\n", cases[i].name);
        fflush(stdout);
    }
    puts("PASS: public lua_concat contract");
    return 0;
}
#endif
