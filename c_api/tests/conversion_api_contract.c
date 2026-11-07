/* Public numeric C conversions and exported identity data.
 * Copyright (c) 2026 Lua Ada contributors. MIT; see ../../LICENSE. */
#include "lua.h"
#include "lauxlib.h"
#include <assert.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "consumer_allocator.h"

static struct allocation_counts counts;
static void converted(lua_State *L, const char *text, int integer,
                       lua_Number expected) {
    size_t length = strlen(text) + 1;
    int before = lua_gettop(L);
    assert(lua_stringtonumber(L, text) == length);
    assert(lua_gettop(L) == before + 1 && lua_isinteger(L, -1) == integer);
    assert(lua_tonumber(L, -1) == expected); lua_pop(L, 1);
}
static void identity_data(lua_State *L) {
    static const char expected[] = "$LuaVersion: " LUA_COPYRIGHT " $"
                                   "$LuaAuthors: " LUA_AUTHORS " $";
    (void)L; assert(strcmp(lua_ident, expected) == 0);
}
static void decimal_integers(lua_State *L) {
    converted(L, "0", 1, 0); converted(L, " -0 \t", 1, 0);
    assert(lua_stringtonumber(L, "9223372036854775807") == 20);
    assert(lua_isinteger(L, -1) && lua_tointeger(L, -1) == LUA_MAXINTEGER);
    lua_pop(L, 1);
    assert(lua_stringtonumber(L, "-9223372036854775808") == 21);
    assert(lua_isinteger(L, -1) && lua_tointeger(L, -1) == LUA_MININTEGER);
    lua_pop(L, 1);
}
static void hexadecimal_integers(lua_State *L) {
    assert(lua_stringtonumber(L, "0xffffffffffffffff") == 19);
    assert(lua_isinteger(L, -1) && lua_tointeger(L, -1) == -1); lua_pop(L, 1);
    assert(lua_stringtonumber(L, "-0xffffffffffffffff") == 20);
    assert(lua_isinteger(L, -1) && lua_tointeger(L, -1) == 1); lua_pop(L, 1);
    converted(L, "0x10000000000000000", 1, 0);
}
static void floating_syntax(lua_State *L) {
    converted(L, "1.25", 0, 1.25); converted(L, "  .5e+1 \n", 0, 5);
    converted(L, "0x1.8p+2", 0, 6); converted(L, "0X.8P-1", 0, .25);
    converted(L, "9223372036854775808", 0, 9223372036854775808.0);
}
static void extreme_floats(lua_State *L) {
    assert(lua_stringtonumber(L, "-0.0") == 5);
    assert(!lua_isinteger(L, -1) && signbit(lua_tonumber(L, -1))); lua_pop(L, 1);
    assert(lua_stringtonumber(L, "1e50000") == 8);
    assert(isinf(lua_tonumber(L, -1))); lua_pop(L, 1);
    converted(L, "1e-50000", 0, 0);
    converted(L, "4.9406564584124654e-324", 0, 0x1p-1074);
}
static void failure_preserves_stack(lua_State *L) {
    static const char *const invalid[] =
        {"", " ", "+", "0x", "1.2.3", "1e+", "0x1p", "1x", "nan", "inf",
         "1_0", "16#ff#", "1 2", "0x1.0p1junk"};
    size_t i; lua_pushinteger(L, 701);
    for (i = 0; i < sizeof invalid / sizeof invalid[0]; ++i) {
        assert(lua_stringtonumber(L, invalid[i]) == 0);
        assert(lua_gettop(L) == 1 && lua_tointeger(L, 1) == 701);
    }
    lua_pop(L, 1);
}
static void c_string_extent(lua_State *L) {
    static const char text[] = {'1','2','\0','x','\0'};
    assert(lua_stringtonumber(L, text) == 3);
    assert(lua_isinteger(L, -1) && lua_tointeger(L, -1) == 12); lua_pop(L, 1);
}
static void refusal_no_growth(lua_State *L) {
    size_t calls;
    lua_pushstring(L, "3.0"); lua_pushstring(L, "not-a-number");
    assert(lua_checkstack(L, 64)); calls = counts.calls; counts.refuse = 1;
    converted(L, "1.25", 0, 1.25); converted(L, "0x1.8p+2", 0, 6);
    assert(lua_tonumber(L, 1) == 3 && lua_tointeger(L, 1) == 3);
    assert(lua_isnumber(L, 1) && !lua_isnumber(L, 2));
    assert(lua_type(L, 1) == LUA_TSTRING && lua_type(L, 2) == LUA_TSTRING);
    assert(lua_stringtonumber(L, "1e+") == 0);
    assert(counts.calls == calls); counts.refuse = 0; lua_settop(L, 0);
}
static void long_cancellation(lua_State *L) {
    char *text = (char *)malloc(10032); size_t calls; assert(text);
    text[0] = '1'; memset(text + 1, '0', 10000);
    strcpy(text + 10001, ".0e-10000");
    assert(lua_checkstack(L, 64)); calls = counts.calls; counts.refuse = 1;
    converted(L, text, 0, 1); assert(counts.calls == calls);
    counts.refuse = 0; free(text);
}
static void remote_midpoint(lua_State *L) {
    static const char half[] =
        "1.00000000000000011102230246251565404236316680908203125";
    char text[4096]; size_t offset = sizeof half - 1, calls;
    memcpy(text, half, offset); memset(text + offset, '0', 3000);
    text[offset + 3000] = 0;
    assert(lua_checkstack(L, 64)); calls = counts.calls; counts.refuse = 1;
    converted(L, text, 0, 1);
    text[offset + 3000] = '1'; text[offset + 3001] = 0;
    converted(L, text, 0, 0x1.0000000000001p0);
    assert(counts.calls == calls); counts.refuse = 0;
}
static void seeded_roundtrips(lua_State *L) {
    uint64_t word = UINT64_C(0x82f136ca8e594ba1); unsigned i; size_t calls;
    assert(lua_checkstack(L, 64)); calls = counts.calls; counts.refuse = 1;
    for (i = 0; i < 2000; ++i) {
        lua_Number value, actual; uint64_t result; char text[64];
        word ^= word << 13; word ^= word >> 7; word ^= word << 17;
        if ((word & UINT64_C(0x7ff0000000000000)) ==
                    UINT64_C(0x7ff0000000000000)) continue;
        memcpy(&value, &word, sizeof value);
        snprintf(text, sizeof text, "%.17g", (double)value);
        assert(lua_stringtonumber(L, text) == strlen(text) + 1);
        actual = lua_tonumber(L, -1); memcpy(&result, &actual, sizeof result);
        assert(result == word); lua_pop(L, 1);
    }
    assert(counts.calls == calls); counts.refuse = 0;
}
static void check(const char *name, void (*body)(lua_State *), lua_State *L) {
    assert(lua_gettop(L) == 0); body(L); assert(lua_gettop(L) == 0);
    printf("PASS: conversion-%s\n", name); fflush(stdout);
}
int main(void) {
    lua_State *L = lua_newstate(counted_allocator, &counts, 193U); assert(L);
    check("identity-data", identity_data, L);
    check("decimal-integers", decimal_integers, L);
    check("hexadecimal-integers", hexadecimal_integers, L);
    check("floating-syntax", floating_syntax, L);
    check("extreme-floats", extreme_floats, L);
    check("failure-preserves-stack", failure_preserves_stack, L);
    check("c-string-extent", c_string_extent, L);
    check("refusal-no-growth", refusal_no_growth, L);
    check("long-cancellation", long_cancellation, L);
    check("remote-midpoint", remote_midpoint, L);
    check("seeded-roundtrips", seeded_roundtrips, L);
    lua_close(L); assert(counts.bytes == 0 && counts.blocks == 0);
    puts("PASS: public numeric conversion contract"); return 0;
}
