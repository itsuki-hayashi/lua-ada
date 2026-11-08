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

/* The Ada child owns argument policy and iteration. These callbacks retain
 * its already loaded closure as an ordinary first parameter, so it and the
 * original table survive handler GC/global replacement as real stack roots.
 * Only public ABI primitives execute here; there is no argument-copy loop. */
int lua_ada_cli_argument_table(lua_State *L) {
    (void)lua_getglobal(L, "arg");
    return 2;
}

int lua_ada_cli_argument_length(lua_State *L) {
    lua_Integer length = luaL_len(L, 2);
    lua_pushinteger(L, length);
    return 3;
}
