/* Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE.
 * C debug records and callback signatures belong here; hook state and frame
 * inspection remain Ada-owned. All dispatches return through Ada before the
 * common C boundary may raise an error or yield from an actual hook callback. */
#include "lua_ada_boundary.h"
#include <string.h>

typedef char lua_ada_hook_pointer_size[
    sizeof(lua_Hook) == sizeof(void *) ? 1 : -1];

static struct lua_ada_response debug_request(lua_State *L,
        struct lua_ada_request *input) {
    struct lua_ada_response output;
    memset(&output, 0, sizeof output);
    lua_ada_debug_dispatch(L, input, &output);
    return output;
}

/* The scheduler passes event/line as rooted callback arguments. Consume only
 * that transport packet before entering the user's real hook; the callback's
 * lua_Debug names the interrupted frame, never this trampoline activation. */
static int hook_dispatch(lua_State *L) {
    struct lua_ada_request input;
    struct lua_ada_response output;
    lua_Debug ar;
    lua_Hook hook = lua_gethook(L);
    const char *event = lua_tostring(L, 1);
    memset(&ar, 0, sizeof ar);
    if (hook == NULL || event == NULL) return 0;
    if (strcmp(event, "call") == 0) ar.event = LUA_HOOKCALL;
    else if (strcmp(event, "return") == 0) ar.event = LUA_HOOKRET;
    else if (strcmp(event, "line") == 0) ar.event = LUA_HOOKLINE;
    else if (strcmp(event, "count") == 0) ar.event = LUA_HOOKCOUNT;
    else ar.event = LUA_HOOKTAILCALL;
    ar.currentline = ar.event == LUA_HOOKLINE ? (int)lua_tointeger(L, 2) : -1;
    memset(&input, 0, sizeof input);
    input.operation = ADA_GET_DEBUG_FRAME;
    input.index = -1;
    output = debug_request(L, &input);
    ar.i_ci = (struct CallInfo *)output.pointer;
    lua_settop(L, 0);
    hook(L, &ar);
    return 0;
}

void lua_sethook(lua_State *L, lua_Hook hook, int mask, int count) {
    struct lua_ada_request input;
    memset(&input, 0, sizeof input);
    input.operation = ADA_SET_HOOK;
    memcpy(&input.pointer, &hook, sizeof hook);
    input.index = mask;
    input.count = count;
    input.function_data = hook_dispatch;
    (void)debug_request(L, &input);
}

lua_Hook lua_gethook(lua_State *L) {
    struct lua_ada_request input;
    struct lua_ada_response output;
    lua_Hook hook;
    memset(&input, 0, sizeof input);
    input.operation = ADA_GET_HOOK;
    output = debug_request(L, &input);
    memcpy(&hook, &output.pointer, sizeof hook);
    return hook;
}

int lua_gethookmask(lua_State *L) {
    struct lua_ada_request input;
    memset(&input, 0, sizeof input);
    input.operation = ADA_GET_HOOK_MASK;
    return (int)debug_request(L, &input).integer_data;
}

int lua_gethookcount(lua_State *L) {
    struct lua_ada_request input;
    memset(&input, 0, sizeof input);
    input.operation = ADA_GET_HOOK_COUNT;
    return (int)debug_request(L, &input).integer_data;
}

int lua_getstack(lua_State *L, int level, lua_Debug *ar) {
    struct lua_ada_request input;
    struct lua_ada_response output;
    if (level < 0 || ar == NULL) return 0;
    memset(&input, 0, sizeof input);
    input.operation = ADA_GET_DEBUG_FRAME;
    input.index = level;
    output = debug_request(L, &input);
    if (output.integer_data == 0) return 0;
    ar->i_ci = (struct CallInfo *)output.pointer;
    return 1;
}

int lua_getinfo(lua_State *L, const char *what, lua_Debug *ar) {
    struct lua_ada_request input;
    struct lua_ada_response output;
    const char *option;
    if (what == NULL || ar == NULL) return 0;
    /* This delivery implements line inspection over actual active frames.
     * Other public C debug selectors remain an explicit later ABI gate; do
     * not populate apparently successful source/name/layout metadata. */
    for (option = what; *option != '\0'; option++)
        if (*option != 'l') return 0;
    memset(&input, 0, sizeof input);
    input.operation = ADA_GET_DEBUG_LINE;
    input.pointer = ar->i_ci;
    output = debug_request(L, &input);
    if (output.length == 0) return 0;
    if (strchr(what, 'l') != NULL) ar->currentline = (int)output.integer_data;
    return 1;
}
