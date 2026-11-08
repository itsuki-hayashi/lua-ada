/* Oracle-only observer regression; no reference implementation enters Ada. */
#include "lua.h"
#include "lauxlib.h"
#include "ltests.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>

LUA_API size_t conformance_live_bytes(void);
LUA_API size_t conformance_live_blocks(void);
LUA_API unsigned long long conformance_refusals(void);
LUA_API unsigned long long conformance_backing_refusals(void);

static void unchanged_bytes(const unsigned char *p) {
    size_t i;
    for (i = 0; i < 128; i++) assert(p[i] == (unsigned char)i);
}

int main(void) {
    lua_State *L = luaL_newstate();
    lua_Alloc allocator;
    void *data;
    unsigned char *block;
    void *result;
    unsigned long saved_limit, saved_count;
    unsigned long long before, backing;
    size_t i;
    assert(L != NULL);
    allocator = lua_getallocf(L, &data);
    assert(allocator == debug_realloc && data == &l_memcontrol);
    /* Loading T exercises the pinned allocator identity assertion too. */
    luaL_requiref(L, "T", luaB_opentests, 1);
    lua_pop(L, 1);
    puts("ALLOCATOR OBSERVER PASS: real debug allocator identity");

    before = conformance_refusals();
    block = allocator(data, NULL, 0, 128);
    assert(block != NULL && conformance_refusals() == before);
    for (i = 0; i < 128; i++) block[i] = (unsigned char)i;
    saved_limit = l_memcontrol.memlimit;
    saved_count = l_memcontrol.countlimit;

    l_memcontrol.failnext = 1;
    backing = conformance_backing_refusals();
    result = allocator(data, block, 128, 256);
    assert(result == NULL && conformance_refusals() == before + 1);
    assert(conformance_backing_refusals() == backing);
    unchanged_bytes(block);
    puts("ALLOCATOR OBSERVER PASS: fail-next leaves the old block intact");

    before = conformance_refusals();
    l_memcontrol.countlimit = 0;
    result = allocator(data, block, 128, 256);
    assert(result == NULL && conformance_refusals() == before + 1);
    assert(conformance_backing_refusals() == backing);
    unchanged_bytes(block);
    l_memcontrol.countlimit = saved_count;
    puts("ALLOCATOR OBSERVER PASS: count refusal before backing allocation");

    before = conformance_refusals();
    l_memcontrol.memlimit = l_memcontrol.total;
    result = allocator(data, block, 128, 256);
    assert(result == NULL && conformance_refusals() == before + 1);
    assert(conformance_backing_refusals() == backing);
    unchanged_bytes(block);
    l_memcontrol.memlimit = saved_limit;
    puts("ALLOCATOR OBSERVER PASS: byte refusal before backing allocation");

    /* The process is launched with an independent64MiB backing cap and a
     * larger debug test limit. This request must reach that backing cap. */
    before = conformance_refusals();
    result = allocator(data, NULL, 0, (size_t)80 * 1024 * 1024);
    assert(result == NULL && conformance_refusals() == before + 1);
    assert(conformance_backing_refusals() == backing + 1);
    unchanged_bytes(block);
    puts("ALLOCATOR OBSERVER PASS: backing refusal counted once in both views");

    before = conformance_refusals();
    result = allocator(data, block, 128, 256);
    assert(result != NULL && conformance_refusals() == before);
    block = result;
    unchanged_bytes(block);
    assert(allocator(data, block, 256, 0) == NULL);
    assert(conformance_refusals() == before);
    puts("ALLOCATOR OBSERVER PASS: successful growth and free are not refusals");

    lua_close(L);
    assert(conformance_live_bytes() == 0 && conformance_live_blocks() == 0);
    puts("ALLOCATOR OBSERVER PASS: original teardown and zero ownership");
    return 0;
}
