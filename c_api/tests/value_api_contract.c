/* Public value operations, identical source for the independent C oracle.
 * Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE. */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <assert.h>
#include <float.h>
#include <limits.h>
#include <locale.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "consumer_allocator.h"

static void run(lua_State *L, const char *source) {
    int status = luaL_dostring(L, source);
    if (status != LUA_OK) fprintf(stderr, "%s\n", lua_tostring(L, -1));
    assert(status == LUA_OK && lua_gettop(L) == 0);
}

static int length_call(lua_State *L) {
    lua_len(L, 1);
    return 1;
}

static int concat_call(lua_State *L) {
    lua_concat(L, lua_gettop(L));
    return 1;
}

static void lengths(lua_State *L) {
    lua_pushcfunction(L, length_call); lua_setglobal(L, "c_length");
    run(L, "assert(c_length('a\\0b')==3);assert(c_length({1,2,3})==3);"
        "local marker={}; local t=setmetatable({1,2},"
        "{__len=function(a,b)assert(a==b);return marker end});"
        "assert(c_length(t)==marker);"
        "local ok,e=pcall(c_length,false);assert(not ok and "
        "e:find('length'));"
        "t=setmetatable({},{__len=function()error(marker)end});"
        "ok,e=pcall(c_length,t);assert(not ok and e==marker)");
    puts("value-api-1: length primitives, handler operands and errors");
}

static void concatenation(lua_State *L) {
    lua_pushcfunction(L, concat_call); lua_setglobal(L, "c_concat");
    run(L, "assert(c_concat()=='');assert(c_concat(false)==false);"
        "local t={};assert(c_concat(t)==t);"
        "assert(c_concat('a',2,3.0,'\\0b')=='a23.0\\0b');"
        "local trace={};local mt={}; mt.__concat=function(a,b)"
        "trace[#trace+1]=a.x..b.x;collectgarbage();"
        "return setmetatable({x=a.x..b.x},mt)end;"
        "local function obj(x)return setmetatable({x=x},mt)end;"
        "local r=c_concat(obj('a'),obj('b'),obj('c'));"
        "assert(r.x=='abc' and trace[1]=='bc' and trace[2]=='abc');"
        "local marker={};mt.__concat=function()error(marker)end;"
        "local ok,e=pcall(c_concat,obj('x'),obj('y'));"
        "assert(not ok and e==marker)");
    puts("value-api-2: concatenation count, right fold and retained roots");
}

static void yield_barriers(lua_State *L) {
    run(L, "for _,pair in ipairs{{c_length,'__len'},{c_concat,'__concat'}} do "
        "local t=setmetatable({},{[pair[2]]=coroutine.yield});"
        "local co=coroutine.create(function()return pair[1](t,t)end);"
        "local ok,e=coroutine.resume(co);assert(not ok and "
        "e:find('yield') and coroutine.status(co)=='dead')end");
    puts("value-api-3: C operations retain nonyieldable handler barriers");
}

static void caller_windows(lua_State *L) {
    run(L, "local marker={}; local function inspect(a,b)"
        "local i=debug.getinfo(2,'Sf');assert(i.what=='C');"
        "local name,x=debug.getlocal(2,1);assert(name=='(C temporary)');"
        "assert(x==marker);return 7 end;"
        "setmetatable(marker,{__len=inspect});"
        "assert(c_length(marker)==7)");
    puts("value-api-4: handler sees the actual public C caller");
}

static void number_text(lua_State *L) {
    static const lua_Number numbers[] =
        {0.0, -0.0, 1.1, 2.0, 1e-5, 1e-4, 1e14, 1e15,
         1.2345678901234567, DBL_MAX, DBL_MIN, 0x1p-1074,
         INFINITY, -INFINITY, NAN};
    char buffer[LUA_N2SBUFFSZ];
    size_t i;
    /* An absent slot is still required to be within the C frame's reserved
     * acceptable index extent, including in instrumented API-check builds. */
    assert(lua_checkstack(L, 100));
    for (i = 0; i < sizeof numbers / sizeof numbers[0]; ++i) {
        unsigned length;
        const char *expected;
        lua_pushnumber(L, numbers[i]);
        length = lua_numbertocstring(L, -1, buffer);
        assert(length == strlen(buffer) + 1 && lua_type(L, -1) == LUA_TNUMBER);
        lua_pushvalue(L, -1); expected = lua_tostring(L, -1);
        assert(expected != NULL && strcmp(expected, buffer) == 0);
        printf("value-number-%zu: %s\n", i, buffer);
        lua_pop(L, 2);
    }
    lua_pushinteger(L, (lua_Integer)LLONG_MIN);
    assert(lua_numbertocstring(L, -1, buffer) == 21);
    assert(strcmp(buffer, "-9223372036854775808") == 0);
    lua_pop(L, 1);
    strcpy(buffer, "unchanged");
    lua_pushliteral(L, "12");
    assert(lua_numbertocstring(L, -1, buffer) == 0);
    assert(strcmp(buffer, "unchanged") == 0);
    lua_pop(L, 1);
    assert(lua_numbertocstring(L, 77, buffer) == 0);
    puts("value-api-5: number spelling, type preservation and invalid slots");
}

static void refusal_number(void) {
    struct allocation_counts counts = {0};
    lua_State *L = lua_newstate(counted_allocator, &counts, 53U);
    char buffer[LUA_N2SBUFFSZ];
    size_t calls;
    assert(L != NULL && lua_checkstack(L, 100));
    lua_pushnumber(L, 1.2345678901234567);
    calls = counts.calls; counts.refuse = 1;
    assert(lua_numbertocstring(L, -1, buffer) > 0);
    assert(strcmp(buffer, "1.2345678901234567") == 0);
    assert(counts.calls == calls && lua_type(L, -1) == LUA_TNUMBER);
    counts.refuse = 0;
    lua_close(L);
    assert(counts.bytes == 0 && counts.blocks == 0);
    puts("value-api-6: number conversion makes no allocator request");
}

static void seeded_number_text(void) {
    struct allocation_counts counts = {0};
    lua_State *L = lua_newstate(counted_allocator, &counts, 59U);
    uint64_t seed = UINT64_C(0x8ec765a421390bd7);
    uint64_t hash = UINT64_C(14695981039346656037);
    size_t calls;
    unsigned i;
    int trace = getenv("LUA_ADA_NUMBER_TRACE") != NULL;
    assert(L != NULL && lua_checkstack(L, 100));
    assert(sizeof(lua_Number) == sizeof seed);
    calls = counts.calls; counts.refuse = 1;
    for (i = 0; i < 20000; ++i) {
        lua_Number number;
        char text[LUA_N2SBUFFSZ];
        unsigned length, j;
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17;
        memcpy(&number, &seed, sizeof number);
        lua_pushnumber(L, number);
        length = lua_numbertocstring(L, -1, text);
        assert(length > 0 && length <= sizeof text);
        if (trace) printf("number-trace %016llx %s\n",
                          (unsigned long long)seed, text);
        /* Include NUL separators so the process fingerprint binds the exact
         * spelling sequence, not an ambiguous concatenation of numbers. */
        for (j = 0; j < length; ++j) {
            hash ^= (unsigned char)text[j];
            hash *= UINT64_C(1099511628211);
        }
        lua_pop(L, 1);
    }
    assert(counts.calls == calls);
    counts.refuse = 0;
    lua_close(L);
    assert(counts.blocks == 0 && counts.bytes == 0);
    printf("value-api-7: seeded binary64 text %016llx\n",
           (unsigned long long)hash);
}

int main(void) {
    lua_State *L = luaL_newstate();
    assert(L != NULL);
    luaL_openlibs(L);
    lengths(L);
    concatenation(L);
    yield_barriers(L);
    caller_windows(L);
    number_text(L);
    lua_close(L);
    refusal_number();
    seeded_number_text();
    puts("PASS: public value operation contract");
    return 0;
}
