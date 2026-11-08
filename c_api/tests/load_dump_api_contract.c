/* First-party reader/writer contract, shared unchanged by both runtimes.
 * Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE. */
#include "lua.h"
#include "lauxlib.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "consumer_allocator.h"
#include "load_dump_contract.h"

int main(void) {
    struct allocation_counts counts = {0};
    lua_State *state = lua_newstate(counted_allocator, &counts, 311U);
    assert(state != NULL);
    test_load_dump_contract(state);
    lua_close(state);
    assert(counts.bytes == 0 && counts.blocks == 0);
    puts("PASS: public reader/writer contract");
    return 0;
}
