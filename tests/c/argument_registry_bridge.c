/* Fresh counted states reuse the same actual C protocols as the consumer. */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include "../../c_api/tests/consumer_allocator.h"
#include "argument_registry_callbacks.h"

int lua_ada_test_argument_registry(unsigned which) {
    struct allocation_counts counts = {0};
    lua_State *L = lua_newstate(counted_allocator, &counts, 331U);
    assert(L != NULL);
    luaL_openlibs(L);
    registry_contract(L, which);
    lua_close(L);
    assert(counts.bytes == 0 && counts.blocks == 0);
    return 1;
}
