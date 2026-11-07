/* Public luaL_Buffer contract regressions for C99 consumers.
 * Copyright (c) 2026 Lua Ada contributors. MIT; see ../../LICENSE.
 *
 * Each case below is an independently named protocol run in its own fresh
 * counted_allocator state. The same source compiles as a standalone C99
 * consumer (define nothing) or as the reusable bridge target behind
 * lua_ada_test_buffer(), which is selected by defining
 * LUA_ADA_BUFFER_CONTRACT_LIBRARY before including this file.
 *
 * Scope: only documented public luaL_Buffer functions and macros are used
 * (luaL_buffinit, luaL_buffinitsize, luaL_prepbuffer, luaL_prepbuffsize,
 * luaL_addsize, luaL_addchar, luaL_buffsub, luaL_buffaddr, luaL_bufflen,
 * luaL_addlstring, luaL_addstring, luaL_addvalue, luaL_pushresult,
 * luaL_pushresultsize), plus lua_closeslot for the abandon path. The one
 * internal layout detail referenced is the public B.init.b scratch array,
 * used only to check that small content stays in the fixed scratch.
 *
 * Allocation policy: the counted allocator is the only source of truth for
 * heap growth. Tests never assert exact allocation counts or capacities.
 * Refusals are injected only into growth requests (consumer_allocator.h),
 * and an error is accepted as a memory failure only when the allocator
 * actually refused a growth during that call. */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "consumer_allocator.h"

/* Per-case allocator state. Each case resets it before lua_newstate. */
static struct allocation_counts counts;

/* Observe ownership through the public provider contract, not a net change
 * in total bytes: a valid close can cache a C activation larger than the
 * released buffer. These fixed test-only records track actual raw regions
 * without assuming a Lua/Ada header or allocation order. IDs survive resize
 * and distinguish a later allocation that reuses the same address. */
struct live_allocation { void *block; size_t size, id; };
static struct live_allocation live[32768];
static size_t live_count, next_id, watched_id, watched_frees;
static int watched_provider;
static struct { struct allocation_counts *counts; } replacement_data;

static void *observe_allocation(struct allocation_counts *data, void *block,
                                size_t old_size, size_t new_size, int provider) {
    size_t index = 0;
    int fresh = block == NULL;
    void *result;
    if (!fresh) {
        while (index < live_count && live[index].block != block) ++index;
        assert(index < live_count && live[index].size == old_size);
    }
    result = counted_allocator(data, block, old_size, new_size);
    if (new_size == 0 && !fresh) {
        if (live[index].id == watched_id) {
            ++watched_frees;
            watched_provider = provider;
        }
        live[index] = live[--live_count];
    } else if (result != NULL) {
        if (fresh) {
            assert(live_count < sizeof live / sizeof live[0]);
            index = live_count++;
            live[index].id = ++next_id;
        }
        live[index].block = result;
        live[index].size = new_size;
    }
    return result;
}

static void *observed_allocator(void *data, void *block,
                                size_t old_size, size_t new_size) {
    assert(data == &counts);
    return observe_allocation(&counts, block, old_size, new_size, 1);
}

static void *replacement_allocator(void *data, void *block,
                                   size_t old_size, size_t new_size) {
    assert(data == &replacement_data && replacement_data.counts == &counts);
    return observe_allocation(replacement_data.counts, block,
                              old_size, new_size, 2);
}

static void watch_payload(const char *bytes, size_t size) {
    size_t index;
    uintptr_t address = (uintptr_t)(const void *)bytes;
    for (index = 0; index < live_count; ++index) {
        uintptr_t base = (uintptr_t)live[index].block;
        if (address >= base && address - base <= live[index].size &&
            size <= live[index].size - (address - base)) {
            watched_id = live[index].id;
            watched_frees = 0;
            watched_provider = 0;
            return;
        }
    }
    assert(!"public buffer bytes must belong to the selected provider");
}

#ifdef NDEBUG
#error "buffer_api_contract.c relies on assert() checks; do not define NDEBUG"
#endif

/* Seed passed to lua_newstate; any value is valid, fixed for reproducibility. */
#define BUFFER_SEED 311U

/* Bytes in the large-growth and fault-sweep scenarios. LARGE_LEN is far above
 * LUAL_BUFFERSIZE, so these scenarios must leave the fixed scratch area. */
#define LARGE_LEN ((size_t)30000)

/* Size of one "big" value: longer than LUAL_BUFFERSIZE, so it forces a heap box. */
#define BIG_LEN ((size_t)LUAL_BUFFERSIZE * 2 + 9)

/* Fault-sweep scenario: SWEEP_CHUNKS writes of SWEEP_CHUNK bytes each. */
#define SWEEP_CHUNK 300U
#define SWEEP_CHUNKS 24U
#define SWEEP_TOTAL ((size_t)SWEEP_CHUNK * SWEEP_CHUNKS)

/* Message that lauxlib's resizebox raises when a box growth is refused. */
#define NOMEM_MESSAGE "not enough memory"

/* Deterministic, non-periodic-looking byte pattern. Including NUL bytes lets
 * the same data also check length-based (not NUL-terminated) copies.
 * Setup helper: called from the bridge function before each case runs. */
static char pattern_byte(size_t i) {
    return (char)((i * 131u + (i >> 7)) & 0xFFu);
}

static char pattern[LARGE_LEN];

static void fill_pattern(void) {
    size_t i;
    for (i = 0; i < LARGE_LEN; i++) pattern[i] = pattern_byte(i);
}

/* Assert that the Lua string at stack index 'idx' is exactly the 'len' bytes
 * at 'want'. The check uses lua_tolstring's length, so embedded NULs count. */
static void check_string(lua_State *L, int idx, const char *want, size_t len) {
    size_t got_len = 0;
    const char *got;
    assert(lua_type(L, idx) == LUA_TSTRING);
    got = lua_tolstring(L, idx, &got_len);
    assert(got_len == len);
    assert(len == 0 || memcmp(got, want, len) == 0);
}

/* Assert that 'got[0..len)' equals pattern bytes starting at 'offset'. Used
 * for raw buffer memory (luaL_buffaddr) that is not yet a Lua string. */
static void check_bytes(const char *got, size_t len, size_t offset) {
    size_t i;
    for (i = 0; i < len; i++) assert(got[i] == pattern_byte(offset + i));
}

/* Native lua_error recognizes its preallocated memory-error string, including
 * resizebox's interned literal. Refusal must therefore retain LUA_ERRMEM;
 * equal text with an ordinary runtime status cannot mask a wrong error class. */
static void check_memory_error(lua_State *L, int status) {
    assert(status == LUA_ERRMEM);
    assert(lua_type(L, -1) == LUA_TSTRING);
    assert(strcmp(lua_tostring(L, -1), NOMEM_MESSAGE) == 0);
}

/* Helper C callback used by several cases: appends its first argument three
 * times through a buffer, so the arguments and buffer nest on one stack. */
static int repeat_callback(lua_State *L) {
    luaL_Buffer B;
    int i;
    luaL_checktype(L, 1, LUA_TSTRING);
    luaL_buffinit(L, &B);
    for (i = 0; i < 3; i++) {
        lua_pushvalue(L, 1);
        luaL_addvalue(&B);
    }
    luaL_pushresult(&B);
    return 1;
}

/* ---------------------------------------------------------------------------
 * Cases. Each body runs in a fresh state with the libraries opened and must
 * leave the stack as it found it, so the bridge can verify balance at close.
 * ------------------------------------------------------------------------ */

/* Setup: fresh state, no bytes added. Action: init, then push the result.
 * Expected: exactly one stack slot is used while the buffer is open (the
 * placeholder), the result is the empty string, and the slot is replaced by
 * that string. Regression: a placeholder or an extra value left behind. */
static void empty_result(lua_State *L) {
    luaL_Buffer B;
    luaL_buffinit(L, &B);
    if (B.b == B.init.b) assert(B.size <= sizeof B.init.b);
    assert(lua_gettop(L) == 1);
    assert(luaL_bufflen(&B) == 0);
    luaL_pushresult(&B);
    assert(lua_gettop(L) == 1);
    check_string(L, 1, "", 0);
    lua_pop(L, 1);
}

/* Setup: a small binary string with an embedded NUL. Action: luaL_addlstring
 * with an explicit length of 3. Expected: the content stays in the fixed
 * scratch (no heap box), the NUL is kept, and the result has length 3.
 * Regression: strlen-based truncation at the embedded NUL. */
static void fixed_binary_nul(lua_State *L) {
    luaL_Buffer B;
    luaL_buffinit(L, &B);
    luaL_addlstring(&B, "a\0b", 3);
    assert(luaL_bufflen(&B) == 3);
    assert(luaL_buffaddr(&B) == B.init.b);
    luaL_pushresult(&B);
    check_string(L, 1, "a\0b", 3);
    lua_pop(L, 1);
}

/* Setup: a buffer that has not grown. Action: luaL_addlstring with a NULL
 * pointer and length 0, then a normal append. Expected: the zero-length add
 * is a no-op (lauxlib skips memcpy when the length is zero) and the next
 * append is correct. Regression: a zero-length add that changes the length
 * or dereferences the NULL pointer. */
static void zero_null_add(lua_State *L) {
    luaL_Buffer B;
    luaL_buffinit(L, &B);
    luaL_addlstring(&B, NULL, 0);
    assert(luaL_bufflen(&B) == 0);
    luaL_addlstring(&B, "ok", 2);
    luaL_pushresult(&B);
    check_string(L, 1, "ok", 2);
    lua_pop(L, 1);
}

/* Setup: C strings appended with luaL_addstring, including an empty one.
 * Action: add "xy", "", and "z". Expected: the C terminator is not part of
 * the content, so the result is "xyz" with length 3. Regression: the
 * terminator being copied, or an empty C string changing the length. */
static void addstring_terminator(lua_State *L) {
    luaL_Buffer B;
    luaL_buffinit(L, &B);
    luaL_addstring(&B, "xy");
    luaL_addstring(&B, "");
    luaL_addstring(&B, "z");
    assert(luaL_bufflen(&B) == 3);
    luaL_pushresult(&B);
    check_string(L, 1, "xyz", 3);
    lua_pop(L, 1);
}

/* Setup: a fresh buffer. Action: write directly into luaL_prepbuffer space
 * (LUAL_BUFFERSIZE bytes guaranteed), commit 6 bytes with luaL_addsize, then
 * ask for 1 more byte with luaL_prepbuffsize, write it, and commit it.
 * Expected: the result is "direct!". Regression: prepared space not being
 * the writable area starting at the current length, or addsize mis-tracking. */
static void direct_prep_addsize(lua_State *L) {
    luaL_Buffer B;
    char *p;
    luaL_buffinit(L, &B);
    p = luaL_prepbuffer(&B);
    memcpy(p, "direct", 6);
    luaL_addsize(&B, 6);
    p = luaL_prepbuffsize(&B, 1);
    p[0] = '!';
    luaL_addsize(&B, 1);
    assert(luaL_bufflen(&B) == 7);
    luaL_pushresult(&B);
    check_string(L, 1, "direct!", 7);
    lua_pop(L, 1);
}

/* Setup: luaL_buffinitsize with a small size (fits in scratch). Action:
 * write 10 bytes into the returned area and finish with luaL_pushresultsize.
 * Expected: the result is the 10 written bytes and the stack holds only the
 * result afterwards. Regression: the size argument ignored, or the returned
 * pointer not addressing the buffer contents. */
static void buffinitsize_small(lua_State *L) {
    luaL_Buffer B;
    char *p = luaL_buffinitsize(L, &B, 10);
    memcpy(p, "0123456789", 10);
    luaL_pushresultsize(&B, 10);
    assert(lua_gettop(L) == 1);
    check_string(L, 1, "0123456789", 10);
    lua_pop(L, 1);
}

/* Setup: luaL_buffinitsize with a size larger than LUAL_BUFFERSIZE. Action:
 * write the whole pattern into the returned area and finish with
 * luaL_pushresultsize. Expected: the buffer is on the heap (its address is
 * no longer the fixed scratch) and the result equals the pattern bytes.
 * Regression: buffinitsize returning a too-small area or losing the bytes
 * when the box is created up front. */
static void buffinitsize_heap(lua_State *L) {
    luaL_Buffer B;
    size_t want = (size_t)LUAL_BUFFERSIZE * 4 + 17;
    char *p = luaL_buffinitsize(L, &B, want);
    assert(luaL_buffaddr(&B) != B.init.b);
    memcpy(p, pattern, want);
    luaL_pushresultsize(&B, want);
    check_string(L, 1, pattern, want);
    lua_pop(L, 1);
}

/* Setup: an unrelated table below the buffer (the sentinel) and a big string
 * value pushed above the placeholder. Action: force a full GC after pushing
 * the value and before luaL_addvalue, so the string must survive while the
 * buffer grows; then addvalue an integer and a float, GC again, and finish.
 * Expected: the value is popped by addvalue, the box replaces the
 * placeholder, the sentinel keeps its field, and the content is the big
 * string followed by "4242" and "2.5" (numbers are converted to strings).
 * Regression: addvalue reading the wrong slot (box below the value), the
 * value collected during growth, or the sentinel disturbed. */
static void addvalue_growth(lua_State *L) {
    luaL_Buffer B;
    assert(lua_checkstack(L, 8));
    lua_newtable(L);                         /* index 1: sentinel */
    lua_pushstring(L, "keep");
    lua_setfield(L, 1, "tag");
    luaL_buffinit(L, &B);                    /* index 2: placeholder */
    lua_pushlstring(L, pattern, BIG_LEN);    /* index 3: big string */
    lua_gc(L, LUA_GCCOLLECT);
    luaL_addvalue(&B);                       /* box replaces index 2 */
    assert(lua_gettop(L) == 2);
    assert(luaL_bufflen(&B) == BIG_LEN);
    check_bytes(luaL_buffaddr(&B), BIG_LEN, 0);
    lua_pushinteger(L, 4242);
    luaL_addvalue(&B);
    lua_pushnumber(L, 2.5);
    luaL_addvalue(&B);
    lua_gc(L, LUA_GCCOLLECT);
    assert(lua_gettop(L) == 2);
    luaL_pushresult(&B);
    assert(lua_gettop(L) == 2);
    assert(lua_type(L, 2) == LUA_TSTRING);
    assert(lua_rawlen(L, 2) == BIG_LEN + 7);   /* "4242" + "2.5" */
    check_bytes(lua_tostring(L, 2), BIG_LEN, 0);
    assert(memcmp(lua_tostring(L, 2) + BIG_LEN, "42422.5", 7) == 0);
    lua_getfield(L, 1, "tag");
    assert(lua_type(L, -1) == LUA_TSTRING);
    assert(strcmp(lua_tostring(L, -1), "keep") == 0);
    lua_pop(L, 3);
}

/* Setup: fresh buffer, 30000 bytes of pattern. Action: append in increasing
 * chunk sizes (1, 2, 4, ... capped at 4096) so the buffer grows several times.
 * After every append the full prefix written so far is checked, and at the
 * end the whole result is compared. Expected: the content is exact at every
 * prefix. The allocator observes at least two growth requests, since the
 * buffer must leave scratch for 30000 bytes. Regression: data loss or
 * misplaced copies when the buffer is reallocated many times.
 * Limit: the growth count is a lower bound, not an exact figure. */
static void large_growth_prefix(lua_State *L) {
    luaL_Buffer B;
    size_t off = 0, chunk = 1, growths_before = counts.growths;
    luaL_buffinit(L, &B);
    while (off < LARGE_LEN) {
        size_t rest = LARGE_LEN - off;
        size_t take = chunk < rest ? chunk : rest;
        luaL_addlstring(&B, pattern + off, take);
        off += take;
        assert(luaL_bufflen(&B) == off);
        check_bytes(luaL_buffaddr(&B), off, 0);
        if (chunk < 4096) chunk *= 2;
    }
    assert(counts.growths - growths_before >= 2);
    luaL_pushresult(&B);
    check_string(L, 1, pattern, LARGE_LEN);
    lua_pop(L, 1);
}

/* Setup: fresh buffer grown past scratch with the luaL_addchar macro. Action:
 * shrink with luaL_buffsub, then add 'y', a NUL char, and 'z' with addchar.
 * Expected: after buffsub the length is 3 ("xxx"), and the final result is
 * "xxxy\0z" with length 6. Regression: buffsub not adjusting the length, or
 * addchar writing past the logical end after heap growth. */
static void buffsub_addchar(lua_State *L) {
    luaL_Buffer B;
    size_t i, total = BIG_LEN;
    luaL_buffinit(L, &B);
    for (i = 0; i < total; i++) luaL_addchar(&B, 'x');
    assert(luaL_bufflen(&B) == total);
    luaL_buffsub(&B, total - 3);
    assert(luaL_bufflen(&B) == 3);
    luaL_addchar(&B, 'y');
    luaL_addchar(&B, '\0');
    luaL_addchar(&B, 'z');
    luaL_pushresult(&B);
    check_string(L, 1, "xxxy\0z", 6);
    lua_pop(L, 1);
}

/* Setup: an outer buffer that is already on the heap, and an inner buffer
 * opened above it. The inner buffer is also on the heap.
 * Action: write into the inner buffer, pushresult it, addvalue the result to
 * the outer buffer, add a literal tail to the outer buffer, and push the
 * outer result. Only LIFO use is valid, so the inner buffer is closed before
 * the outer buffer is touched again.
 * Expected: the stack shows the outer box plus the inner result (two slots)
 * before addvalue, and the final string is "outer-prefix", "in:",
 * pattern[1..], "|end" in that order. Regression: addvalue reading the wrong
 * slot, or inner close disturbing the outer box. */
static void nested_buffers(lua_State *L) {
    luaL_Buffer outer, inner;
    size_t inner_len = (size_t)LUAL_BUFFERSIZE + 11, i, pos;
    assert(lua_checkstack(L, 8));
    luaL_buffinit(L, &outer);
    luaL_addlstring(&outer, pattern, BIG_LEN);
    luaL_buffinit(L, &inner);
    luaL_addlstring(&inner, "in:", 3);
    luaL_addlstring(&inner, pattern + 1, inner_len - 3);
    luaL_pushresult(&inner);
    assert(lua_gettop(L) == 2);
    luaL_addvalue(&outer);
    assert(lua_gettop(L) == 1);
    luaL_addstring(&outer, "|end");
    luaL_pushresult(&outer);
    assert(lua_gettop(L) == 1);
    check_bytes(lua_tostring(L, 1), BIG_LEN, 0);
    pos = BIG_LEN;
    assert(memcmp(lua_tostring(L, 1) + pos, "in:", 3) == 0);
    pos += 3;
    for (i = 0; i < inner_len - 3; i++)
        assert(lua_tostring(L, 1)[pos + i] == pattern_byte(1 + i));
    pos += inner_len - 3;
    assert(memcmp(lua_tostring(L, 1) + pos, "|end", 4) == 0);
    assert(lua_rawlen(L, 1) == pos + 4);
    lua_pop(L, 1);
}

/* Setup: a C callback that builds its result with a buffer and pushes the
 * argument three times, so the heap box is created inside the callback.
 * Action: call the callback from Lua with a LUAL_BUFFERSIZE-plus-seven byte
 * string and read the single returned value.
 * Expected: the result is the argument repeated three times exactly.
 * Regression: callback-local buffers corrupting the caller's stack, or the
 * result being left in the wrong slot. */
static void callback_result(lua_State *L) {
    size_t len = (size_t)LUAL_BUFFERSIZE + 7, i;
    const char *got;
    size_t got_len = 0;
    lua_pushcfunction(L, repeat_callback);
    lua_pushlstring(L, pattern, len);
    lua_call(L, 1, 1);
    assert(lua_gettop(L) == 1);
    got = lua_tolstring(L, 1, &got_len);
    assert(got_len == 3 * len);
    for (i = 0; i < got_len; i++) assert(got[i] == pattern_byte(i % len));
    lua_pop(L, 1);
}

/* Setup: a C callback that builds a heap buffer and then raises an integer
 * error (77) with the buffer still open. The error value is an integer so
 * the error path itself allocates nothing.
 * Action: call it under lua_pcall.
 * Expected: status LUA_ERRRUN with integer 77, and the box was closed while
 * unwinding, releasing its observed provider region exactly once. Regression: a heap box leaked
 * when the callback raises (the box's __close never releases its memory).
 * Release is observed through actual provider allocation identity, without
 * reading an internal box representation or assuming net byte-count drops. */
static int raise_after_heap(lua_State *L) {
    luaL_Buffer B;
    luaL_buffinit(L, &B);
    luaL_addlstring(&B, pattern, BIG_LEN);
    watch_payload(luaL_buffaddr(&B), luaL_bufflen(&B));
    lua_pushinteger(L, 77);
    return lua_error(L);
}

static void callback_error_closes(lua_State *L) {
    int status;
    lua_pushcfunction(L, raise_after_heap);
    status = lua_pcall(L, 0, 0, 0);
    assert(status == LUA_ERRRUN);
    assert(lua_isinteger(L, -1) && lua_tointeger(L, -1) == 77);
    assert(watched_frees == 1);
    lua_pop(L, 1);
}

/* Setup: a heap-backed buffer whose box is the top slot. Action: abandon the
 * buffer without pushresult, using lua_closeslot on the box (the legal way to
 * close a to-be-closed slot). Raw removal of a to-be-closed slot is not used
 * because the slot link would stay on the stack position (see
 * base_closing_api_contract.c). Expected: closing the slot releases the box
 * memory immediately, releasing the observed allocation once; the
 * slot becomes nil and is then popped normally.
 * Regression: an abandoned heap buffer that keeps its memory until a full
 * collection, or a close that frees the wrong slot. */
static void abandoned_closeslot(lua_State *L) {
    luaL_Buffer B;
    luaL_buffinit(L, &B);
    luaL_addlstring(&B, pattern, BIG_LEN);
    watch_payload(luaL_buffaddr(&B), luaL_bufflen(&B));
    lua_closeslot(L, -1);
    assert(watched_frees == 1);
    assert(lua_gettop(L) == 1 && lua_isnil(L, 1));
    lua_pop(L, 1);
}

/* C callback used by the fault sweep: writes SWEEP_TOTAL bytes in fixed
 * chunks through prepbuffsize + addsize, then pushes the result. */
static int sweep_build(lua_State *L) {
    luaL_Buffer B;
    size_t chunk, written = 0;
    luaL_buffinit(L, &B);
    for (chunk = 0; chunk < SWEEP_CHUNKS; chunk++) {
        char *p = luaL_prepbuffsize(&B, SWEEP_CHUNK);
        size_t j;
        for (j = 0; j < SWEEP_CHUNK; j++) p[j] = pattern_byte(written + j);
        luaL_addsize(&B, SWEEP_CHUNK);
        written += SWEEP_CHUNK;
    }
    luaL_pushresult(&B);
    return 1;
}

/* Recreate the same seed, libraries and stack reservation for each refused
 * growth. Previous failures must not change the next attempt's cache or GC
 * history and thereby silently remove the growth being tested. The callback
 * uses only its own state's provider; the outer named-case state is idle. */
static size_t fault_attempt(size_t offset, int *memory_errors) {
    struct allocation_counts local;
    lua_State *child;
    size_t base, growths;
    int status;
    memset(&local, 0, sizeof local);
    child = lua_newstate(counted_allocator, &local, BUFFER_SEED);
    assert(child != NULL);
    luaL_openlibs(child);
    assert(lua_checkstack(child, 16));
    base = local.growths;
    if (offset != 0) local.fail_after = base + offset;
    lua_pushcfunction(child, sweep_build);
    status = lua_pcall(child, 0, 1, 0);
    growths = local.growths - base;
    local.fail_after = 0;
    assert(offset == 0 || growths >= offset);
    if (status == LUA_OK) check_string(child, 1, pattern, SWEEP_TOTAL);
    else {
        assert(offset != 0);
        check_memory_error(child, status);
        ++*memory_errors;
    }
    lua_pop(child, 1);
    assert(lua_gettop(child) == 0);
    /* The actual refused state must recover, not just the next new state. */
    lua_pushcfunction(child, sweep_build);
    assert(lua_pcall(child, 0, 1, 0) == LUA_OK);
    check_string(child, 1, pattern, SWEEP_TOTAL);
    lua_pop(child, 1);
    lua_close(child);
    assert(local.bytes == 0 && local.blocks == 0);
    return growths;
}

/* Measure one successful construction, then independently refuse each actual
 * growth and verify the exact memory-error class, immediate healthy retry,
 * content and shutdown balance. Private allocation counts may differ across
 * implementations; each implementation measures its own finite campaign. */
static void fault_sweep(lua_State *L) {
    size_t offset, measured;
    int memory_errors = 0;
    (void)L;
    measured = fault_attempt(0, &memory_errors);
    assert(measured > 0);
    for (offset = 1; offset <= measured; ++offset)
        (void)fault_attempt(offset, &memory_errors);
    assert(memory_errors > 0);
}

/* Setup: a C callback that builds a heap buffer, then turns on a growth
 * refusal and calls luaL_pushresult. The header of the result string needs a
 * fresh allocation, so the push must fail. Action: run under lua_pcall, clear
 * the refusal, then inspect the error. Expected: the call fails with a memory
 * error, at least one refused growth occurred, and the heap buffer's memory
 * was released before the error reached the caller. luaS_newextlstr frees the
 * external buffer through the allocator when header creation fails, and the
 * box's close releases any remaining box memory. The watched provider
 * allocation must be released exactly once before the protected return. Regression: a leaked buffer after pushresult
 * fails, or the error being reported as a non-memory error. */
static size_t push_growths;

static int refused_push(lua_State *L) {
    luaL_Buffer B;
    luaL_buffinit(L, &B);
    luaL_addlstring(&B, pattern, BIG_LEN);
    watch_payload(luaL_buffaddr(&B), luaL_bufflen(&B));
    push_growths = counts.growths;
    counts.refuse = 1;
    luaL_pushresult(&B);   /* must fail while growth is refused */
    return 1;
}

static void pushresult_header_refusal(lua_State *L) {
    int status;
    lua_pushcfunction(L, refused_push);
    status = lua_pcall(L, 0, 1, 0);
    counts.refuse = 0;
    assert(status != LUA_OK);
    assert(counts.growths > push_growths);
    check_memory_error(L, status);
    assert(watched_frees == 1);
    lua_pop(L, 1);
    assert(lua_gettop(L) == 0);
}

/* A published heap buffer is an external payload with the allocator/data
 * pair captured at publication. Replace the state's compatible allocator,
 * then collect the string: the payload must still invoke the original pair
 * exactly once, while ordinary runtime storage uses the replacement. */
static void captured_deallocator(lua_State *L) {
    luaL_Buffer B;
    size_t size;
    const char *text;
    luaL_buffinit(L, &B);
    luaL_addlstring(&B, pattern, BIG_LEN);
    luaL_pushresult(&B);
    text = lua_tolstring(L, -1, &size);
    assert(size == BIG_LEN);
    watch_payload(text, size + 1);
    lua_setallocf(L, replacement_allocator, &replacement_data);
    lua_pop(L, 1);
    lua_gc(L, LUA_GCCOLLECT);
    assert(watched_frees == 1 && watched_provider == 1);
}

/* ---------------------------------------------------------------------------
 * Case table and bridge. Each name is printed as a PASS marker only after
 * the case has returned from its close-and-balance check.
 * ------------------------------------------------------------------------ */

typedef void (*buffer_case)(lua_State *L);

static const struct {
    const char *name;
    buffer_case body;
} cases[] = {
    {"empty-result", empty_result},
    {"fixed-binary-nul", fixed_binary_nul},
    {"zero-null-add", zero_null_add},
    {"addstring-terminator", addstring_terminator},
    {"direct-prep-addsize", direct_prep_addsize},
    {"buffinitsize-small", buffinitsize_small},
    {"buffinitsize-heap", buffinitsize_heap},
    {"addvalue-growth-gc", addvalue_growth},
    {"large-growth-prefix", large_growth_prefix},
    {"buffsub-addchar", buffsub_addchar},
    {"nested-buffers", nested_buffers},
    {"callback-result", callback_result},
    {"callback-error-closes", callback_error_closes},
    {"abandoned-closeslot", abandoned_closeslot},
    {"fault-sweep-growth", fault_sweep},
    {"pushresult-header-refusal", pushresult_header_refusal},
    {"captured-deallocator-pair", captured_deallocator}
};

#define BUFFER_CASE_COUNT (sizeof cases / sizeof cases[0])

/* Run one case in a fresh counted state. The state is opened, the body runs
 * with an empty stack, and the state is closed. The byte and block counts
 * must return to zero only after lua_close, so any leak fails the case. */
static int run_case(buffer_case body) {
    lua_State *L;
    memset(&counts, 0, sizeof counts);
    assert(live_count == 0);
    next_id = watched_id = watched_frees = 0;
    replacement_data.counts = &counts;
    L = lua_newstate(observed_allocator, &counts, BUFFER_SEED);
    assert(L != NULL);
    luaL_openlibs(L);
    assert(lua_checkstack(L, 16));
    body(L);
    assert(lua_gettop(L) == 0);
    counts.refuse = 0;
    counts.fail_after = 0;
    lua_close(L);
    assert(counts.bytes == 0 && counts.blocks == 0);
    assert(live_count == 0);
    return 1;
}

/* Reusable AUnit entry point. Pass an index below BUFFER_CASE_COUNT and the
 * function returns 1 on success; any failed check aborts via assert. */
int lua_ada_test_buffer(unsigned which) {
    assert(which < BUFFER_CASE_COUNT);
    fill_pattern();
    return run_case(cases[which].body);
}

#ifndef LUA_ADA_BUFFER_CONTRACT_LIBRARY
int main(void) {
    unsigned i;
    for (i = 0; i < BUFFER_CASE_COUNT; i++) {
        assert(lua_ada_test_buffer(i));
        printf("PASS: buffer-%s\n", cases[i].name);
        fflush(stdout);
    }
    puts("PASS: public luaL_Buffer contract");
    return 0;
}
#endif
