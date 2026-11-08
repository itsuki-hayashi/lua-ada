/* CLI-only C ABI transport. Policy and ownership remain in the Ada child.
 *
 * get_prompt in pinned lua.c calls these public operations directly from
 * its anonymous C activation. Calling the public Lua tostring builtin would
 * add another observable C frame. These tiny ordinary callbacks instead let
 * the existing guarded Ada VM expose the genuine host operation and its
 * scalar stack to __index/__tostring, including debug.getlocal. They contain
 * no interpreter, fallback policy, exception handling or executor loop. */
#include "lua.h"
#include "lauxlib.h"

int lua_ada_cli_primary_prompt(lua_State *L) {
    (void)lua_getglobal(L, "_PROMPT");
    return 1;
}

int lua_ada_cli_secondary_prompt(lua_State *L) {
    (void)lua_getglobal(L, "_PROMPT2");
    return 1;
}

int lua_ada_cli_string_prompt(lua_State *L) {
    (void)luaL_tolstring(L, 1, NULL);
    return 1;
}
