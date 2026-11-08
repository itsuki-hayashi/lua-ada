/* CLI-only primitive transport. Ada selects each next operation and owns the
 * error-object, fallback, display and exit policies. A fallible public API
 * call begins only after the Ada selector has returned: no C error transfer
 * can cross a live Ada policy frame. The whole loop is one genuine anonymous
 * C activation, whose first argument remains the actual inspectable error. */
#include "lua.h"
#include "lauxlib.h"

extern int lua_ada_cli_handler_action(int previous, int result, int type);
extern const char *lua_ada_cli_handler_format(void);

int lua_ada_cli_message_handler(lua_State *L) {
    int action = -1;
    int result = 0;
    int type = LUA_TNONE;
    const char *message = NULL;
    for (;;) {
        action = lua_ada_cli_handler_action(action, result, type);
        switch (action) {
            case 0:
                message = lua_tostring(L, 1);
                result = (message != NULL);
                break;
            case 1:
                result = luaL_callmeta(L, 1, "__tostring");
                type = lua_type(L, -1);
                break;
            case 2:
                message = lua_pushfstring(L, lua_ada_cli_handler_format(),
                                         luaL_typename(L, 1));
                break;
            case 3:
                luaL_traceback(L, L, message, 1);
                break;
            case 4:
                return 1;
            default:
                return 0; /* The closed Ada action type cannot select this. */
        }
    }
}

/* Ada prepares [handler, function, arguments...] after loading/pushargs. This
 * is only the public protected-call primitive and its scalar result envelope;
 * policy, status interpretation, result retention and signal scope are Ada.
 * Keeping this real C caller also preserves the native CLI's bottom ancestry.
 */
int lua_ada_cli_protected_call(lua_State *L) {
    int status = lua_pcall(L, lua_gettop(L) - 2, LUA_MULTRET, 1);
    lua_remove(L, 1);
    lua_pushinteger(L, status);
    lua_insert(L, 1);
    return lua_gettop(L);
}
