/* Actual auxiliary substitution within a bounded Ada session. */
#include "lua.h"
#include "lauxlib.h"
#include <string.h>

static int empty_pattern(lua_State *L) {
    luaL_gsub(L, "subject", "", "");
    return 1;
}

static int comparisons(lua_State *L) {
    char subject[513], pattern[129];
    memset(subject, 'a', sizeof subject - 1);
    subject[sizeof subject - 1] = '\0';
    memset(pattern, 'a', sizeof pattern - 1);
    pattern[sizeof pattern - 2] = 'b';
    pattern[sizeof pattern - 1] = '\0';
    /* Scanning the two C strings fits the quota. Repeated real shared-prefix
     * comparisons exceed it; a single charge per outer search would not. */
    luaL_gsub(L, subject, pattern, "replacement");
    return 1;
}

static int heap_then_abort(lua_State *L) {
    luaL_Buffer buffer;
    char prefix[2048];
    memset(prefix, 'h', sizeof prefix);
    luaL_buffinit(L, &buffer);
    luaL_addlstring(&buffer, prefix, sizeof prefix);
    /* The actual promoted buffer owns bytes before the empty-pattern loop.
     * Host disposal must free them without another Lua call or collection. */
    luaL_addgsub(&buffer, "", "", "");
    luaL_pushresult(&buffer);
    return 1;
}

lua_CFunction lua_ada_test_substitution_budget(int choice) {
    if (choice == 0) return empty_pattern;
    if (choice == 1) return comparisons;
    return heap_then_abort;
}
