/* Public allocator contract through the C ABI.
 * Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE.
 *
 * This standalone C99 consumer checks the two allocator symbols that pinned
 * Lua 5.5.1 defines in lauxlib.c, using only the public headers:
 *
 *   luaL_alloc    - stateless realloc/free with the lua_Alloc signature
 *   luaL_makeseed - unsigned seed for lua_newstate; takes a state, ignores it
 *
 * It never includes the C facade (c_api/c/lua_ada_allocator.c) and never
 * includes consumer_allocator.h. Its own counting callback, named
 * allocator_contract_counting, delegates to luaL_alloc and keeps an
 * independent ledger, so these cases stay separate from the other consumer
 * files that compile counted_allocator from consumer_allocator.h.
 *
 * Case layout: each behavior has its own function and returns 1 on pass or
 * 0 on failure. A failure prints the failing expression, file, and line to
 * stderr. Cases that create a state always close it and then check that the
 * ledger shows zero live bytes and zero live blocks. The bridge is
 *
 *     int lua_ada_test_allocator(unsigned which);
 *
 * where 'which' indexes the table below (0 .. 12). It returns 1 on pass, and
 * 0 on failure or for an index past the end of the table. Build without
 * LUA_ADA_ALLOCATOR_CONTRACT_LIBRARY for a standalone main that runs every
 * case and prints one PASS or FAIL line per case.
 *
 * The seed-related cases assert no value. They do not assume that two seeds
 * differ, and they do not assume any particular seed value or any particular
 * address. A seed call with a live state is checked only for stack height,
 * allocator-call count, and live bytes.
 *
 */

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

#include "lua.h"
#include "lauxlib.h"

/* Check one condition. On failure, print it and return 0 from the enclosing
** case function. Every case below is 'static int f(void)', so this is safe.
*/
#define EXPECT(cond)                                                       \
    do {                                                                   \
        if (!(cond)) {                                                     \
            fprintf(stderr, "%s:%d: expectation failed: %s\n",             \
                    __FILE__, __LINE__, #cond);                            \
            return 0;                                                      \
        }                                                                  \
    } while (0)

/* Alignment of type T, measured by the offset of a member placed after a
** single char in a struct. This needs no C11 _Alignof. */
#define ALIGN_OF(T) offsetof(struct { char c; T v; }, v)

/* Independent ledger for the counting callback. 'live_bytes' follows the
** sizes Lua reports: osize is only meaningful when the block pointer is not
** NULL. A NULL pointer means "new block", and osize is then a type tag. */
struct allocator_contract_ledger {
    size_t calls;
    size_t live_blocks;
    size_t live_bytes;
};

/* Counting lua_Alloc. It delegates every request to the public luaL_alloc,
** so the counts describe the standard allocator's behavior exactly. Lua
** always passes the real old size when freeing or resizing a block it owns,
** so the ledger can balance on close. */
static void *allocator_contract_counting(void *ud, void *ptr, size_t osize,
                                         size_t nsize) {
    struct allocator_contract_ledger *ledger =
        (struct allocator_contract_ledger *)ud;
    void *result = luaL_alloc(ud, ptr, osize, nsize);
    ledger->calls++;
    if (nsize == 0) {
        if (ptr != NULL) {
            ledger->live_blocks--;
            ledger->live_bytes -= osize;
        }
        return NULL;
    }
    if (result == NULL) return NULL;  /* refusal: nothing changes */
    if (ptr == NULL) {
        ledger->live_blocks++;
        ledger->live_bytes += nsize;
    }
    else {
        ledger->live_bytes = ledger->live_bytes - osize + nsize;
    }
    return result;
}

/* Fill 'n' bytes at 'p' with a repeating pattern based on 'seed'. */
static void fill_pattern(unsigned char *p, size_t n, unsigned seed) {
    size_t i;
    for (i = 0; i < n; i++) p[i] = (unsigned char)(seed + i * 7u);
}

/* Return 1 if 'n' bytes at 'p' still match fill_pattern(seed). */
static int check_pattern(const unsigned char *p, size_t n, unsigned seed) {
    size_t i;
    for (i = 0; i < n; i++) {
        if (p[i] != (unsigned char)(seed + i * 7u)) return 0;
    }
    return 1;
}

/* ---- Standalone luaL_alloc behavior ------------------------------------ */

/* Setup: none. Action: request 32 bytes with NULL block and an arbitrary old
** size of 99999, which the pinned reference ignores. Expected: non-NULL,
** writable block; the pattern survives a write and read; a free returns NULL.
** Protects: NULL + arbitrary osize is treated as a fresh allocation. */
static int case_null_block_ignores_old_size(void) {
    unsigned char *p = (unsigned char *)luaL_alloc(NULL, NULL, 99999, 32);
    EXPECT(p != NULL);
    fill_pattern(p, 32, 0x5au);
    EXPECT(check_pattern(p, 32, 0x5au));
    EXPECT(luaL_alloc(NULL, p, 32, 0) == NULL);
    return 1;
}

/* Setup: none. Action: free a real block, and also free NULL with nsize 0.
** Expected: both return NULL, and neither crashes.
** Protects: zero-size requests free the block and never return a pointer;
** a NULL block with nsize 0 is a safe no-op. */
static int case_zero_size_frees_and_returns_null(void) {
    void *p = luaL_alloc(NULL, NULL, 0, 64);
    EXPECT(p != NULL);
    EXPECT(luaL_alloc(NULL, p, 64, 0) == NULL);
    EXPECT(luaL_alloc(NULL, NULL, 0, 0) == NULL);
    return 1;
}

/* Setup: an 8-byte block with a known pattern. Action: grow it to 4096 bytes.
** Expected: non-NULL; the first 8 bytes equal the original pattern; the new
** tail is writable and reads back.
** Protects: realloc growth keeps the leading bytes intact. */
static int case_grow_preserves_prefix(void) {
    unsigned char *p = (unsigned char *)luaL_alloc(NULL, NULL, 0, 8);
    unsigned char *q;
    EXPECT(p != NULL);
    fill_pattern(p, 8, 0x11u);
    q = (unsigned char *)luaL_alloc(NULL, p, 8, 4096);
    EXPECT(q != NULL);
    EXPECT(check_pattern(q, 8, 0x11u));
    fill_pattern(q + 8, 4096 - 8, 0x33u);
    EXPECT(check_pattern(q + 8, 4096 - 8, 0x33u));
    EXPECT(luaL_alloc(NULL, q, 4096, 0) == NULL);
    return 1;
}

/* Setup: a 4096-byte block with a known pattern. Action: shrink it to 16
** bytes. Expected: non-NULL; the first 16 bytes still hold the pattern.
** Protects: shrinking keeps the retained prefix. */
static int case_shrink_preserves_prefix(void) {
    unsigned char *p = (unsigned char *)luaL_alloc(NULL, NULL, 0, 4096);
    unsigned char *q;
    EXPECT(p != NULL);
    fill_pattern(p, 4096, 0x77u);
    q = (unsigned char *)luaL_alloc(NULL, p, 4096, 16);
    EXPECT(q != NULL);
    EXPECT(check_pattern(q, 16, 0x77u));
    EXPECT(luaL_alloc(NULL, q, 16, 0) == NULL);
    return 1;
}

/* Setup: a 128-byte block, then freed. Action: allocate 128 bytes again.
** Expected: the new block is non-NULL and writable. The test does not assert
** that the address is reused, because the allocator may hand out any block.
** Protects: a freed block does not poison later fresh allocations. */
static int case_fresh_allocation_after_free(void) {
    unsigned char *p = (unsigned char *)luaL_alloc(NULL, NULL, 0, 128);
    unsigned char *q;
    EXPECT(p != NULL);
    EXPECT(luaL_alloc(NULL, p, 128, 0) == NULL);
    q = (unsigned char *)luaL_alloc(NULL, NULL, 0, 128);
    EXPECT(q != NULL);
    fill_pattern(q, 128, 0x9cu);
    EXPECT(check_pattern(q, 128, 0x9cu));
    EXPECT(luaL_alloc(NULL, q, 128, 0) == NULL);
    return 1;
}

/* Setup: an array of Lua public numeric types and pointers. Action: check
** each type's alignment against the returned block, and write and read
** values through typed pointers. Expected: every type's alignment divides the
** address; the values round-trip.
** Protects: userdata blocks are aligned for lua_Number, lua_Integer, long
** double, and pointers, which Lua relies on for numeric userdata. */
static int case_numeric_userdata_alignment(void) {
    union max_align {
        lua_Number n;
        lua_Integer i;
        void *p;
        long double ld;
        long long ll;
    };
    size_t bytes = sizeof(union max_align) * 4;
    void *block = luaL_alloc(NULL, NULL, 0, bytes);
    lua_Number *nums;
    lua_Integer *ints;
    EXPECT(block != NULL);
    EXPECT((uintptr_t)block % ALIGN_OF(lua_Number) == 0);
    EXPECT((uintptr_t)block % ALIGN_OF(lua_Integer) == 0);
    EXPECT((uintptr_t)block % ALIGN_OF(void *) == 0);
    EXPECT((uintptr_t)block % ALIGN_OF(long double) == 0);
    EXPECT((uintptr_t)block % ALIGN_OF(union max_align) == 0);
    nums = (lua_Number *)block;
    ints = (lua_Integer *)block;
    nums[0] = (lua_Number)3.25;
    ints[1] = (lua_Integer)-42;
    EXPECT(nums[0] == (lua_Number)3.25);
    EXPECT(ints[1] == (lua_Integer)-42);
    EXPECT(luaL_alloc(NULL, block, bytes, 0) == NULL);
    return 1;
}

/* Setup: a 32-byte block with a known pattern. Action: request SIZE_MAX bytes
** through a volatile variable, so the compiler cannot reject it at compile
** time. Expected: NULL is returned, and the original 32 bytes still hold the
** pattern, so the block was not freed or corrupted by the refusal.
** Protects: a refused growth preserves the old block (the refusal rule). */
static int case_huge_refusal_preserves_old_block(void) {
    unsigned char *p = (unsigned char *)luaL_alloc(NULL, NULL, 0, 32);
    volatile size_t huge = SIZE_MAX;
    void *refused;
    EXPECT(p != NULL);
    fill_pattern(p, 32, 0xa5u);
    refused = luaL_alloc(NULL, p, 32, huge);
    EXPECT(refused == NULL);
    EXPECT(check_pattern(p, 32, 0xa5u));
    EXPECT(luaL_alloc(NULL, p, 32, 0) == NULL);
    return 1;
}

/* ---- States built on the public allocator ------------------------------- */

/* Setup: a state from lua_newstate with the public luaL_alloc and NULL user
** data. Action: query the allocator and run a small chunk that allocates
** tables. Expected: lua_getallocf returns luaL_alloc with NULL user data, and
** the chunk returns 100; close succeeds.
** Protects: a state created with the public allocator reports it back
** unchanged and can allocate and collect through it. */
static int case_public_allocator_identity_and_use(void) {
    static int sentinel;  /* non-NULL start value, so the NULL check is real */
    lua_State *L = lua_newstate(luaL_alloc, NULL, 0x2b7e1516U);
    void *ud = &sentinel;
    lua_Alloc f;
    EXPECT(L != NULL);
    f = lua_getallocf(L, &ud);
    EXPECT(f == luaL_alloc);
    EXPECT(ud == NULL);
    EXPECT(luaL_loadstring(L,
        "local t = {} for i = 1, 100 do t[i] = i end return #t") == LUA_OK);
    EXPECT(lua_pcall(L, 0, 1, 0) == LUA_OK);
    EXPECT(lua_tointeger(L, -1) == 100);
    lua_close(L);
    return 1;
}

/* Setup: a state from luaL_newstate. Action: query its allocator and panic.
** Expected: lua_getallocf returns luaL_alloc with NULL user data, and the
** auxiliary constructor has installed its default panic handler.
** Protects: the default state's allocator matches the public one exactly. */
static int case_default_state_allocator_identity(void) {
    static int sentinel;  /* non-NULL start value, so the NULL check is real */
    lua_State *L = luaL_newstate();
    void *ud = &sentinel;
    lua_Alloc f;
    EXPECT(L != NULL);
    f = lua_getallocf(L, &ud);
    EXPECT(f == luaL_alloc);
    EXPECT(ud == NULL);
    EXPECT(lua_atpanic(L, NULL) != NULL);
    lua_close(L);
    return 1;
}

/* Setup: a counted state with a value pushed on the stack. Action: call
** luaL_makeseed with the live state. Expected: the stack height is unchanged,
** the allocator is not called, and the ledger still matches the state's
** blocks. The seed value itself is not checked.
** Protects: luaL_makeseed takes a state but neither touches it nor allocates
** through its provider. */
static int case_makeseed_live_state_is_inert(void) {
    struct allocator_contract_ledger ledger = {0, 0, 0};
    lua_State *L = lua_newstate(allocator_contract_counting, &ledger, 0U);
    int top_before;
    size_t calls_before, bytes_before, blocks_before;
    unsigned int seed;
    EXPECT(L != NULL);
    lua_pushinteger(L, 7);
    top_before = lua_gettop(L);
    calls_before = ledger.calls;
    bytes_before = ledger.live_bytes;
    blocks_before = ledger.live_blocks;
    seed = luaL_makeseed(L);
    (void)seed;
    EXPECT(lua_gettop(L) == top_before);
    EXPECT(ledger.calls == calls_before);
    EXPECT(ledger.live_bytes == bytes_before);
    EXPECT(ledger.live_blocks == blocks_before);
    lua_close(L);
    EXPECT(ledger.live_bytes == 0 && ledger.live_blocks == 0);
    return 1;
}

/* Setup: none. Action: call luaL_makeseed with NULL, twice. Expected: each
** call returns an unsigned value and does not crash. No value is compared.
** Protects: NULL is accepted, because luaL_newstate passes NULL. */
static int case_makeseed_accepts_null(void) {
    unsigned int first = luaL_makeseed(NULL);
    unsigned int second = luaL_makeseed(NULL);
    (void)first;
    (void)second;
    return 1;
}

/* Setup: a counted state built on the public seed value. Action: run a
** chunk that allocates tables and strings, then close. Expected: the chunk
** succeeds, and after lua_close the ledger shows zero live bytes and zero
** live blocks, with at least one allocator call made.
** Protects: a full state's allocations and frees balance through a counted
** provider, so no block is leaked and none is freed twice. */
static int case_counted_state_closes_balanced(void) {
    struct allocator_contract_ledger ledger = {0, 0, 0};
    lua_State *L = lua_newstate(allocator_contract_counting, &ledger,
                                luaL_makeseed(NULL));
    EXPECT(L != NULL);
    /* Core-only chunk: no standard library is opened here, so string methods
    ** (the string metatable) are unavailable. Concatenation allocates strings
    ** through the core alone. */
    EXPECT(luaL_loadstring(L,
        "local t = {} for i = 1, 50 do t[i] = 'x' .. i end "
        "return #t") == LUA_OK);
    EXPECT(lua_pcall(L, 0, 1, 0) == LUA_OK);
    EXPECT(lua_tointeger(L, -1) == 50);
    EXPECT(ledger.calls > 0);
    lua_close(L);
    EXPECT(ledger.live_bytes == 0);
    EXPECT(ledger.live_blocks == 0);
    return 1;
}

/* Setup: a counted state closed with a non-empty stack. Action: close it.
** Expected: the ledger shows zero live bytes and zero live blocks; leftover
** values do not leak.
** Protects: lua_close frees every allocation, even ones still referenced from
** the stack at close time. */
static int case_close_with_live_stack_balances(void) {
    struct allocator_contract_ledger ledger = {0, 0, 0};
    lua_State *L = lua_newstate(allocator_contract_counting, &ledger,
                                0x6a09e667U);
    EXPECT(L != NULL);
    lua_pushstring(L, "retained on stack at close");
    lua_newtable(L);
    lua_close(L);
    EXPECT(ledger.live_bytes == 0);
    EXPECT(ledger.live_blocks == 0);
    return 1;
}

/* ---- Bridge and optional standalone main -------------------------------- */

struct allocator_case {
    const char *name;
    int (*run)(void);
};

static const struct allocator_case allocator_cases[] = {
    {"null-block-ignores-old-size", case_null_block_ignores_old_size},
    {"zero-size-frees-and-returns-null",
     case_zero_size_frees_and_returns_null},
    {"grow-preserves-prefix", case_grow_preserves_prefix},
    {"shrink-preserves-prefix", case_shrink_preserves_prefix},
    {"fresh-allocation-after-free", case_fresh_allocation_after_free},
    {"numeric-userdata-alignment", case_numeric_userdata_alignment},
    {"huge-refusal-preserves-old-block",
     case_huge_refusal_preserves_old_block},
    {"public-allocator-identity-and-use",
     case_public_allocator_identity_and_use},
    {"default-state-allocator-identity",
     case_default_state_allocator_identity},
    {"makeseed-live-state-is-inert", case_makeseed_live_state_is_inert},
    {"makeseed-accepts-null", case_makeseed_accepts_null},
    {"counted-state-closes-balanced", case_counted_state_closes_balanced},
    {"close-with-live-stack-balances", case_close_with_live_stack_balances}
};

#define ALLOCATOR_CASE_COUNT \
    (sizeof(allocator_cases) / sizeof(allocator_cases[0]))

/* Bridge for an external runner (for example AUnit). Returns 1 when case
** 'which' passes. Returns 0 when it fails or when 'which' is past the table,
** which has ALLOCATOR_CASE_COUNT entries. */
int lua_ada_test_allocator(unsigned which) {
    if (which >= ALLOCATOR_CASE_COUNT) return 0;
    return allocator_cases[which].run();
}

#ifndef LUA_ADA_ALLOCATOR_CONTRACT_LIBRARY
int main(int argc, char **argv) {
    unsigned int i;
    unsigned int failures = 0;
    /* Run the installed public panic function directly in named subprocess
     * probes. This observes its exact diagnostic without deliberately
     * aborting the host or installing a foreign jump over an Ada frame. */
    if (argc == 2 && (strcmp(argv[1], "--panic-string") == 0 ||
                      strcmp(argv[1], "--panic-number") == 0)) {
        lua_State *L = luaL_newstate();
        lua_CFunction panic;
        int kind;
        if (L == NULL) return EXIT_FAILURE;
        panic = lua_atpanic(L, NULL);
        if (panic == NULL) { lua_close(L); return EXIT_FAILURE; }
        if (strcmp(argv[1], "--panic-string") == 0)
            lua_pushliteral(L, "allocator panic witness");
        else
            lua_pushinteger(L, 42);
        kind = lua_type(L, -1);
        if (panic(L) != 0 || lua_gettop(L) != 1 || lua_type(L, -1) != kind) {
            lua_close(L);
            return EXIT_FAILURE;
        }
        lua_close(L);
        return EXIT_SUCCESS;
    }
    if (argc != 1) return EXIT_FAILURE;
    for (i = 0; i < ALLOCATOR_CASE_COUNT; i++) {
        if (lua_ada_test_allocator(i)) {
            printf("PASS: allocator-api-%u %s\n", i, allocator_cases[i].name);
        }
        else {
            printf("FAIL: allocator-api-%u %s\n", i, allocator_cases[i].name);
            failures++;
        }
    }
    if (failures == 0) puts("PASS: public allocator contract");
    return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
#endif
