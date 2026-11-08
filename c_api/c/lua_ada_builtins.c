/* Stable public C function identities for existing Ada implementations.
 * Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE. */
#include "lua_ada_boundary.h"
#include <string.h>

enum builtin_id {
#define LUA_ADA_BUILTIN(symbol, name) builtin_##symbol,
#include "lua_ada_builtins.def"
#undef LUA_ADA_BUILTIN
    builtin_count
};

#define LUA_ADA_BUILTIN(symbol, name) \
    static int builtin_call_##symbol(lua_State *L) { \
        return lua_ada_invoke_builtin(L, builtin_##symbol); \
    }
#include "lua_ada_builtins.def"
#undef LUA_ADA_BUILTIN

struct descriptor { const char *name; lua_CFunction handler; };
static const struct descriptor builtins[] = {
#define LUA_ADA_BUILTIN(symbol, name) {name, builtin_call_##symbol},
#include "lua_ada_builtins.def"
#undef LUA_ADA_BUILTIN
};

typedef char builtin_pointer_size[
    sizeof(lua_CFunction) == sizeof(void *) ? 1 : -1];
int lua_ada_builtin_count(void) { return builtin_count; }
const char *lua_ada_builtin_name(int id) {
    return id >= 0 && id < builtin_count ? builtins[id].name : NULL;
}
void *lua_ada_builtin_address(int id) {
    void *address = NULL;
    if (id >= 0 && id < builtin_count)
        memcpy(&address, &builtins[id].handler, sizeof address);
    return address;
}
int lua_ada_builtin_find(void *address) {
    lua_CFunction handler;
    int id;
    memcpy(&handler, &address, sizeof handler);
    for (id = 0; id < builtin_count; ++id)
        if (handler == builtins[id].handler) return id;
    return -1;
}
