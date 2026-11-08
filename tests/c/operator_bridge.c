/* Real C operator calls borrowing a bounded Ada-owned universe. */
#include "lua.h"

static int add(lua_State *L) { lua_arith(L, LUA_OPADD); return 1; }
static int less(lua_State *L) {
    lua_pushboolean(L, lua_compare(L, 1, 2, LUA_OPLT)); return 1;
}
lua_CFunction lua_ada_test_operator_add(void) { return add; }
lua_CFunction lua_ada_test_operator_less(void) { return less; }
