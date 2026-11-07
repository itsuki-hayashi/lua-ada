/* Test-only public API drivers, derived from the invariants exercised by
 * Lua 5.5.1 ltests.c at 7579fc9d7ed90240487251dfb69168f8e64e9294.
 * See lua.h for the upstream copyright notice. No C private layouts are used.
 */
#include "lua.h"
#include "lauxlib.h"
#include "conformance_api.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <limits.h>

struct adapter_result {
    int count;
    int text_length;
    lua_Integer integers[3];
    char text[256];
};
extern void lua_ada_test_inspect(void *, int, struct adapter_result *);
extern lua_CFunction lua_ada_test_platform_callback(int);

/* Per-universe counterpart of ltests.c:85-169. The registry owns this real
 * userdata until after state-close finalizers finish. Unlike the oracle's
 * static buffer, independent Ada sessions cannot overwrite each other. */
struct warning_state {
    lua_State *L;
    int enabled, mode, continued;
    size_t length;
    char text[200];
};
static const char warning_registry_key = 0;
static unsigned long long expected_finalizer_warnings;

/* gc.lua's ten state-close callbacks each reach this distinctive error only
 * after their ordering/stored-warning assertions. Count completed deliveries,
 * not fragments or Lua registrations; the process driver reads after close. */
unsigned long long lua_ada_test_expected_finalizer_warnings(void) {
    return expected_finalizer_warnings;
}

static void warning_failure(const char *reason, const char *message) {
    fprintf(stderr, "T warning failure: %s: %s\n", reason, message);
    fflush(stderr);
    abort();
}

static void test_warning(void *data, const char *message, int continued) {
    struct warning_state *w = (struct warning_state *)data;
    lua_State *L = w->L;
    size_t length = strlen(message);
    int top;
    if (!w->continued && !continued && message[0] == '@') {
        if (w->length != 0) warning_failure("unfinished control", message);
        if (strcmp(message, "@on") == 0) w->enabled = 1;
        else if (strcmp(message, "@off") == 0) w->enabled = 0;
        else if (strcmp(message, "@normal") == 0) w->mode = 0;
        else if (strcmp(message, "@allow") == 0) w->mode = 1;
        else if (strcmp(message, "@store") == 0) w->mode = 2;
        else warning_failure("unknown control", message);
        return;
    }
    if (length >= sizeof(w->text) - w->length)
        warning_failure("buffer overflow", message);
    memcpy(w->text + w->length, message, length + 1);
    w->length += length;
    w->continued = continued;
    if (continued) return;
    /* Only public raw access is needed: the test's _WARN is a raw global,
     * not a delegation request. Calls execute under the real warning guard. */
    top = lua_gettop(L);
    if (!lua_checkstack(L, 3)) warning_failure("stack refusal", w->text);
    lua_pushglobaltable(L);
    lua_pushliteral(L, "_WARN");
    lua_rawget(L, -2);
    if (lua_toboolean(L, -1)) warning_failure("unhandled warning", w->text);
    lua_pop(L, 1);
    if (w->mode == 2) {
        lua_pushliteral(L, "_WARN");
        lua_pushlstring(L, w->text, w->length);
        lua_rawset(L, -3);
    } else if (w->enabled) {
        if (w->mode == 0 && w->text[0] != '#')
            warning_failure("unexpected warning", w->text);
        fprintf(stderr, "Lua warning: %s\n", w->text);
    }
    lua_settop(L, top);
    if (strstr(w->text, "@expected warning") != NULL) {
        if (expected_finalizer_warnings == ULLONG_MAX)
            warning_failure("warning counter overflow", w->text);
        expected_finalizer_warnings++;
    }
    w->length = 0;
    w->text[0] = '\0';
}

static int install_warning(lua_State *L) {
    struct warning_state *w = lua_newuserdatauv(L, sizeof(*w), 0);
    memset(w, 0, sizeof(*w));
    w->L = L;
    expected_finalizer_warnings = 0;
    lua_rawsetp(L, LUA_REGISTRYINDEX, &warning_registry_key);
    lua_setwarnf(L, test_warning, w);
    return 0;
}

static int userdata(lua_State *L) {
    int valid = 1;
    lua_Integer size = 0, values = 0;
    void *p;
    if (!lua_isnoneornil(L, 1)) size = lua_tointegerx(L, 1, &valid);
    if (!valid || size < 0) {
        lua_pushliteral(L, "invalid userdata size");
        return lua_error(L);
    }
    if (!lua_isnoneornil(L, 2)) values = lua_tointegerx(L, 2, &valid);
    if (!valid || values < 0 || values >= 32767) {
        lua_pushliteral(L, "invalid userdata uservalue count");
        return lua_error(L);
    }
    p = lua_newuserdatauv(L, (size_t)size, (int)values);
    if (size != 0) memset(p, 0, (size_t)size);
    return 1;
}

static int inspect(lua_State *L) {
    struct adapter_result result = {0, -1, {0, 0, 0}, {0}};
    int i;
    /* The Ada inspection call returns before any potentially raising C API
     * publication. A Lua error therefore unwinds only the live C guard. */
    lua_ada_test_inspect(lua_touserdata(L, lua_upvalueindex(2)),
        (int)lua_tointeger(L, lua_upvalueindex(1)), &result);
    if (result.count == -2) abort(); /* Internal invariant, never Lua error. */
    if (result.count < 0) {
        lua_pushlstring(L, result.text, (size_t)result.text_length);
        return lua_error(L);
    }
    if (result.text_length >= 0) {
        lua_pushlstring(L, result.text, (size_t)result.text_length);
    } else {
        for (i = 0; i < result.count; ++i)
            lua_pushinteger(L, result.integers[i]);
    }
    return result.count;
}

lua_CFunction lua_ada_test_adapter_callback(int operation) {
    if (operation == 0) return userdata;
    if (operation == 11) return install_warning;
    if (operation >= 14 && operation <= 16)
        return lua_ada_test_platform_callback(operation);
    if (operation >= 17 && operation <= 24)
        return lua_ada_test_api_callback(operation);
    return inspect;
}
