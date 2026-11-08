/* Actual public conversion request on a bounded Ada-owned universe. */
#include "lua.h"

static int convert_number(lua_State *L) {
    const char *text = lua_tostring(L, 1);
    return text != NULL && lua_stringtonumber(L, text) != 0;
}
lua_CFunction lua_ada_test_convert_number(void) { return convert_number; }
