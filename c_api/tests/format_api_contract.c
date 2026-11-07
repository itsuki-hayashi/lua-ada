/* Public formatting regressions run unchanged against C Lua and Lua Ada.
 * Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE. */
#include "lua.h"
#include "lauxlib.h"
#include <assert.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "consumer_allocator.h"

static const char *forward(lua_State *L, const char *format, ...) {
    const char *result;
    va_list arguments;
    va_start(arguments, format);
    result = lua_pushvfstring(L, format, arguments);
    va_end(arguments);
    return result;
}

static void expect(lua_State *L, const char *result,
                   const char *bytes, size_t length) {
    size_t actual;
    assert(result != NULL && result == lua_tolstring(L, -1, &actual));
    assert(actual == length && memcmp(result, bytes, length) == 0);
    assert(result[length] == '\0');
    lua_pop(L, 1);
}

static void scalars(lua_State *L) {
    int top = lua_gettop(L);
    expect(L, lua_pushfstring(L, ""), "", 0);
    expect(L, lua_pushfstring(L, "x%s/%s", "abc", (char *)NULL),
           "xabc/(null)", 11);
    expect(L, forward(L, "%d/%I/%f/%%", -57, (lua_Integer)LLONG_MIN,
                      (lua_Number)2.0), "-57/-9223372036854775808/2.0/%", 30);
    /* Unknown conversions consume no argument in pinned Lua 5.5. */
    expect(L, forward(L, "%q%0%s", "kept"), "%q%0kept", 8);
    expect(L, forward(L, "a%cb%c", 0, 255), "a\0b\xff", 4);
    expect(L, forward(L, "%U%U%U%U", 0UL, 0x80UL, 0x1f600UL,
                      0x7fffffffUL),
           "\0\xc2\x80\xf0\x9f\x98\x80\xfd\xbf\xbf\xbf\xbf\xbf", 13);
    assert(lua_gettop(L) == top);
    puts("format-api-1: scalar, counted binary and extended UTF-8 results");
}

static void pointers(lua_State *L) {
    char expected[2 * sizeof(void *) + 8];
    int anchor, length;
    length = snprintf(expected, sizeof expected, "%p", (void *)&anchor);
    assert(length > 0 && (size_t)length < sizeof expected);
    expect(L, forward(L, "%p", (void *)&anchor), expected, (size_t)length);
    length = snprintf(expected, sizeof expected, "%p", (void *)NULL);
    assert(length > 0 && (size_t)length < sizeof expected);
    expect(L, forward(L, "%p", (void *)NULL), expected, (size_t)length);
    puts("format-api-2: native platform pointer rendering");
}

static char payload[4097];

static void long_result(lua_State *L) {
    int top = lua_gettop(L);
    size_t size;
    const char *result = forward(L, "[%s]%I", payload, (lua_Integer)19);
    assert(result != NULL && lua_gettop(L) == top + 1);
    assert(lua_tolstring(L, -1, &size) == result && size == 4100);
    assert(result[0] == '[' && memcmp(result + 1, payload, 4096) == 0);
    assert(memcmp(result + 4097, "]19", 3) == 0);
    lua_pop(L, 1);
}

static void allocation_sweep(void) {
    struct allocation_counts baseline = {0};
    lua_State *L = lua_newstate(counted_allocator, &baseline, 37U);
    size_t first, growths, offset;
    assert(L != NULL && lua_checkstack(L, 100));
    lua_gc(L, LUA_GCSTOP);
    first = baseline.growths;
    long_result(L);
    growths = baseline.growths - first;
    assert(growths > 0);
    lua_close(L);
    assert(baseline.bytes == 0 && baseline.blocks == 0);
    /* Refuse every actual growth of this implementation persistently. Its
     * allocation geometry is not compared with the independent C oracle. */
    for (offset = 1; offset <= growths; ++offset) {
        struct allocation_counts counts = {0};
        const char *result;
        L = lua_newstate(counted_allocator, &counts, 37U);
        assert(L != NULL && lua_checkstack(L, 100));
        lua_gc(L, LUA_GCSTOP);
        counts.fail_after = counts.growths + offset;
        result = forward(L, "[%s]%I", payload, (lua_Integer)19);
        if (result != NULL || lua_gettop(L) != 0)
            fprintf(stderr, "format refusal %zu/%zu: null=%d top=%d\n",
                    offset, growths, result == NULL, lua_gettop(L));
        assert(result == NULL && lua_gettop(L) == 0);
        counts.fail_after = 0;
        long_result(L);
        lua_close(L);
        assert(counts.bytes == 0 && counts.blocks == 0);
    }
    puts("format-api-3: actual growth refusal sweep and recovery");
}

static struct allocation_counts *active_counts;

static int refused_callback(lua_State *L) {
    active_counts->refuse = 1;
    (void)lua_pushfstring(L, "%s", payload);
    assert(0);  /* The variadic counterpart raises instead of returning NULL. */
    return 0;
}

static int rethrow_memory(lua_State *L) {
    lua_pushvalue(L, 1);
    return lua_error(L);
}

static void error_class(void) {
    struct allocation_counts counts = {0};
    lua_State *L = lua_newstate(counted_allocator, &counts, 41U);
    assert(L != NULL && lua_checkstack(L, 100));
    active_counts = &counts;
    lua_pushcfunction(L, refused_callback);
    assert(lua_pcall(L, 0, 0, 0) == LUA_ERRMEM);
    counts.refuse = 0;
    assert(lua_gettop(L) == 1);
    assert(strcmp(lua_tostring(L, -1), "not enough memory") == 0);
    lua_pushcfunction(L, rethrow_memory);
    lua_insert(L, -2);
    assert(lua_pcall(L, 1, 0, 0) == LUA_ERRMEM);
    lua_pop(L, 1);  /* The actual preallocated error keeps its error class. */
    long_result(L);
    lua_close(L);
    active_counts = NULL;
    assert(counts.bytes == 0 && counts.blocks == 0);
    puts("format-api-4: protected callback memory error class");
}

int main(void) {
    lua_State *L = luaL_newstate();
    assert(L != NULL);
    memset(payload, 'x', sizeof payload - 1);
    scalars(L);
    pointers(L);
    long_result(L);
    lua_close(L);
    allocation_sweep();
    error_class();
    puts("PASS: public formatting contract");
    return 0;
}
