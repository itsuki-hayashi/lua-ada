#include "core_image_support.h"
#include "lauxlib.h"
#include <assert.h>

/* These are real symbols produced by GNAT for this private package. The
 * declarations are test-only observations of our selected compiler, never
 * proposed public Lua exports. An opaque byte suffices to compare the actual
 * pool object's address without copying or guessing its Ada representation.
 * GNAT's package-elaboration counter must remain one across repeated C entry
 * and an Ada main's own binder. No observer is compiled into the library. */
extern unsigned char lua__storage__pool;
extern short lua__storage_E;

void lua_ada_image_check_elaboration(void) {
    assert(lua__storage_E == 1);
}

void *lua_ada_image_make(void) {
    lua_State *state = luaL_newstate();
    assert(state != NULL);
    lua_ada_image_check_elaboration();
    lua_pushinteger(state, 37);
    assert(lua_pushthread(state) == 1);
    assert(lua_tothread(state, -1) == state);
    return state;
}

int lua_ada_image_check(void *address, void *pool, lua_Alloc allocator) {
    lua_State *state = (lua_State *)address;
    void *userdata = NULL;
    assert((void *)&lua__storage__pool == pool);
    assert(lua_getallocf(state, &userdata) == allocator);
    lua_ada_image_check_elaboration();
    assert(lua_gettop(state) == 3);
    assert(lua_tointeger(state, -1) == 42);
    assert(lua_tointeger(state, 1) == 37);
    assert(lua_tothread(state, 2) == state);
    return 1;
}

void lua_ada_image_close(void *address) {
    lua_close((lua_State *)address);
    lua_ada_image_check_elaboration();
}
