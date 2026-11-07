/* Real C deallocator reentry under the host's existing bounded policy. */
#include "lua.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>

static unsigned releases;
static void *release_external(void *data, void *block, size_t old_size,
                               size_t new_size) {
    lua_State *L = (lua_State *)data;
    assert(old_size == 65 && new_size == 0);
    free(block); releases++;
    lua_getglobal(L, "onrelease"); lua_call(L, 0, 0);
    return NULL;
}
static int make_external(lua_State *L) {
    char *bytes = (char *)malloc(65); assert(bytes);
    memset(bytes, 'e', 64); bytes[64] = 0;
    lua_pushexternalstring(L, bytes, 64, release_external, L);
    return 1;
}
lua_CFunction lua_ada_test_make_external(void) { return make_external; }
unsigned lua_ada_test_external_releases(void) { return releases; }
