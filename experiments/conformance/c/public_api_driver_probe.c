/* Oracle-only public adapter probe. MIT; see ../../../LICENSE.
 * Compile against the separately selected reference shared library. The same
 * first-party public C driver is linked into the Ada test hosts; this module
 * proves that driver parsing/helper behavior independently of the runtime.
 * It contains no C interpreter implementation or private Lua structure. */
#include "../../../tests/c/conformance_api.c"

#if defined(_WIN32)
__declspec(dllexport)
#endif
int luaopen_public_api_driver(lua_State *L) {
    int original;
    /* Native T's genuine control C function needs no private structure or
     * fake allocator. Preserve it before the caller replaces global T. */
    lua_getglobal(L, "T");
    original = lua_gettop(L);
    if (lua_istable(L, -1)) {
        lua_getfield(L, -1, "alloccount");
        if (lua_iscfunction(L, -1)) {
            lua_pushvalue(L, -1);
            lua_setfield(L, LUA_REGISTRYINDEX, LUA_ADA_T_COUNT_KEY);
        }
        lua_pop(L, 1);
    }
    open_api(L);
    if (lua_istable(L, original)) {
        lua_getfield(L, original, "alloccount");
        lua_setfield(L, -2, "alloccount");
        lua_getfield(L, original, "totalmem");
        lua_setfield(L, -2, "totalmem");
        lua_getfield(L, original, "newuserdata");
        lua_setfield(L, -2, "newuserdata");
    }
    lua_remove(L, original);
    return 1;
}
