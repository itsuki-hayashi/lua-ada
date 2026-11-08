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

/* This is the real public lua_Hook for a Lua-installed hook. Its address can
 * be saved, called directly or restored by C clients. The registry owns the
 * callback; every call below crosses the ordinary C boundary and uses the
 * original scheduler/allocator rather than recursing into an Ada executor. */
static void lua_hook_dispatcher(lua_State *L, lua_Debug *ar) {
    static const char *const names[] =
        {"call", "return", "line", "count", "tail call"};
    lua_getfield(L, LUA_REGISTRYINDEX, "_HOOKKEY");
    lua_pushthread(L);
    if (lua_rawget(L, -2) == LUA_TFUNCTION) {
        lua_pushstring(L, names[ar->event]);
        if (ar->currentline >= 0) lua_pushinteger(L, ar->currentline);
        else lua_pushnil(L);
        (void)lua_getinfo(L, "lS", ar);
        lua_call(L, 2, 0);
    }
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
    /* Lua hooks receive nil when line data is absent; C records use -1.
     * Converting that nil through lua_tointeger would invent line zero. */
    ar.currentline = ar.event == LUA_HOOKLINE && lua_isinteger(L, 2)
        ? (int)lua_tointeger(L, 2) : -1;
    memset(&input, 0, sizeof input);
    input.operation = ADA_GET_DEBUG_FRAME;
    input.index = -1;
    output = debug_request(L, &input);
    ar.i_ci = (struct CallInfo *)output.pointer;
    lua_settop(L, 0);
    lua_ada_hook_view(L, 1);
    hook(L, &ar);
    lua_ada_hook_view(L, 0);
    return 0;
}

void lua_sethook(lua_State *L, lua_Hook hook, int mask, int count) {
    struct lua_ada_request input;
    memset(&input, 0, sizeof input);
    input.operation = ADA_SET_HOOK;
    memcpy(&input.pointer, &hook, sizeof hook);
    input.index = mask;
    input.count = count;
    input.error_index = hook == lua_hook_dispatcher;
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
    if (output.integer_data != 0) return lua_hook_dispatcher;
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
    struct lua_ada_debug_information info;
    static const char *const kinds[] = {"", "local", "upvalue", "constant",
        "global", "field", "method", "for iterator", "metamethod", "hook"};
    if (what == NULL || ar == NULL) return 0;
    memset(&info, 0, sizeof info);
    memset(&input, 0, sizeof input);
    input.operation = ADA_GET_DEBUG_INFO;
    input.pointer = *what == '>' ? NULL : ar->i_ci;
    input.name = what;
    input.debug_information = &info;
    output = debug_request(L, &input);
    if (output.length == 0) return 0;
    if (*what == '>') ++what;
    if (strchr(what, 'S') != NULL) {
        ar->source = info.source;
        ar->srclen = info.source_length;
        ar->what = info.what == 0 ? "C" : info.what == 1 ? "main" : "Lua";
        ar->linedefined = info.first_line;
        ar->lastlinedefined = info.last_line;
        memcpy(ar->short_src, info.short_source, sizeof ar->short_src);
    }
    if (strchr(what, 'l') != NULL) ar->currentline = info.current_line;
    if (strchr(what, 'n') != NULL) {
        ar->name = info.name;
        ar->namewhat = kinds[info.name_kind];
    }
    if (strchr(what, 'u') != NULL) {
        ar->nups = (unsigned char)info.upvalues;
        ar->nparams = (unsigned char)info.parameters;
        ar->isvararg = (char)info.vararg;
    }
    if (strchr(what, 't') != NULL) {
        ar->istailcall = (char)info.tail;
        ar->extraargs = (unsigned char)info.extra_arguments;
    }
    if (strchr(what, 'r') != NULL) {
        ar->ftransfer = info.first_transfer;
        ar->ntransfer = info.transfer_count;
    }
    return (int)output.integer_data;
}

const char *lua_getlocal(lua_State *L, const lua_Debug *ar, int n) {
    struct lua_ada_request input;
    memset(&input, 0, sizeof input);
    input.operation = ADA_GET_LOCAL;
    input.pointer = ar == NULL ? NULL : ar->i_ci;
    input.count = n;
    return debug_request(L, &input).pointer;
}

const char *lua_setlocal(lua_State *L, const lua_Debug *ar, int n) {
    struct lua_ada_request input;
    memset(&input, 0, sizeof input);
    input.operation = ADA_SET_LOCAL;
    input.pointer = ar->i_ci;
    input.count = n;
    return debug_request(L, &input).pointer;
}

const char *lua_getupvalue(lua_State *L, int index, int n) {
    struct lua_ada_request input;
    memset(&input, 0, sizeof input);
    input.operation = ADA_GET_UPVALUE;
    input.index = index;
    input.count = n;
    return debug_request(L, &input).pointer;
}

const char *lua_setupvalue(lua_State *L, int index, int n) {
    struct lua_ada_request input;
    memset(&input, 0, sizeof input);
    input.operation = ADA_SET_UPVALUE;
    input.index = index;
    input.count = n;
    return debug_request(L, &input).pointer;
}

void *lua_upvalueid(lua_State *L, int index, int n) {
    struct lua_ada_request input;
    memset(&input, 0, sizeof input);
    input.operation = ADA_UPVALUE_ID;
    input.index = index;
    input.count = n;
    return debug_request(L, &input).pointer;
}

void lua_upvaluejoin(lua_State *L, int first, int n1, int second, int n2) {
    struct lua_ada_request input;
    memset(&input, 0, sizeof input);
    input.operation = ADA_JOIN_UPVALUES;
    input.index = first;
    input.count = n1;
    input.error_index = second;
    input.integer_data = n2;
    (void)debug_request(L, &input);
}
