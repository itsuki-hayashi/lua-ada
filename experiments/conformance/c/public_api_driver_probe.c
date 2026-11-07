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
    return open_api(L);
}
