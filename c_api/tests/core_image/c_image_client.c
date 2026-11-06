#include "core_image_support.h"
#include "lauxlib.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    unsigned int index;
    /* This ordinary C main never calls an Ada initialization API; GPRbuild
     * may still supply generated binder glue. Construction uses the actual
     * root SAL once; repeated states cannot re-elaborate or switch images. */
    for (index = 0; index != 3; ++index) {
        lua_State *state = luaL_newstate();
        assert(state != NULL);
        lua_ada_image_check_elaboration();
        lua_pushinteger(state, 73);
        assert(lua_tointeger(state, -1) == 73);
        lua_close(state);
        lua_ada_image_check_elaboration();
    }
    puts("CORE IMAGE C STARTUP OK");
    return 0;
}
