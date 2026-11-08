/* Reuse the same native-paired public C contract in each AUnit case. */
#define LUA_ADA_CONCAT_CONTRACT_LIBRARY
#include "../../c_api/tests/concat_api_contract.c"

static int completed;

static int primitive_budget(lua_State *L) {
    int i;
    assert(lua_checkstack(L, 3000));
    lua_pushliteral(L, "");
    for (i = 1; i < 3000; i++) lua_pushvalue(L, 1);
    /* Every result can reuse the ordinary empty string, so this reaches the
     * actual fold loop without result allocation or Lua bytecode callbacks. */
    lua_concat(L, 3000);
    completed++;
    return 1;
}

static int extent_budget(lua_State *L) {
    char bytes[160];
    memset(bytes, 'b', sizeof bytes);
    lua_pushlstring(L, bytes, sizeof bytes);
    lua_pushlstring(L, bytes, sizeof bytes);
    lua_concat(L, 2);
    completed++;
    return 1;
}

static int handler_budget(lua_State *L) {
    lua_concat(L, lua_gettop(L));
    completed++;
    return 1;
}

static int byte_budget(lua_State *L) {
    char bytes[400];
    memset(bytes, 'c', sizeof bytes);
    lua_pushlstring(L, bytes, sizeof bytes);
    lua_pushlstring(L, bytes, sizeof bytes);
    /* Both inputs fit, and the suffix has only two values. The actual
     * builder byte copies, rather than operand count, exceed this quota. */
    lua_concat(L, 2);
    completed++;
    return 1;
}

lua_CFunction lua_ada_test_concat_budget(int choice) {
    completed = 0;
    if (choice == 0) return primitive_budget;
    if (choice == 1) return extent_budget;
    if (choice == 2) return handler_budget;
    return byte_budget;
}

int lua_ada_test_concat_completed(void) { return completed; }
