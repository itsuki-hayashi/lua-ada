#include "core_image_support.h"
#include "lauxlib.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    unsigned int index;
    /* A C-only executable has no Ada main binder. Construction initializes
     * the actual root SAL exactly once; repeated states cannot re-elaborate
     * or accidentally switch to a facade's independent runtime image. */
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
