#ifndef LUA_ADA_BOUNDARY_H
#define LUA_ADA_BOUNDARY_H

/* First-party ABI glue. Interpreter state and all value operations remain
 * Ada-owned. Keep these operation IDs synchronized with Engine.Foreign and
 * validate this ordinary C layout during standalone-library elaboration. */
#include "lua.h"

enum lua_ada_operation {
    ADA_CREATE_STATE, ADA_CREATE_DEFAULT_STATE, ADA_CLOSE_STATE,
    ADA_CREATE_THREAD, ADA_GET_TOP, ADA_SET_TOP, ADA_ABSOLUTE_INDEX,
    ADA_CHECK_STACK, ADA_PUSH_VALUE, ADA_COPY_VALUE, ADA_ROTATE_VALUES,
    ADA_MOVE_VALUES, ADA_GET_TYPE, ADA_TO_BOOLEAN, ADA_TO_INTEGER,
    ADA_TO_NUMBER, ADA_TO_STRING, ADA_RAW_LENGTH, ADA_TO_POINTER,
    ADA_TO_THREAD, ADA_PUSH_NIL, ADA_PUSH_BOOLEAN, ADA_PUSH_INTEGER,
    ADA_PUSH_NUMBER, ADA_PUSH_STRING, ADA_PUSH_POINTER, ADA_PUSH_THREAD,
    ADA_CREATE_TABLE, ADA_RAW_GET, ADA_RAW_SET, ADA_RAW_GET_INTEGER,
    ADA_RAW_SET_INTEGER, ADA_RAW_GET_POINTER, ADA_RAW_SET_POINTER,
    ADA_RAW_EQUAL, ADA_NEXT_ITEM, ADA_GET_ALLOCATOR, ADA_SET_ALLOCATOR,
    ADA_PUSH_C_CLOSURE, ADA_TO_C_FUNCTION, ADA_BEGIN_CALL,
    ADA_COMPLETE_CALLBACK, ADA_RAISE_ERROR, ADA_LOAD_BUFFER
};

struct lua_ada_request {
    enum lua_ada_operation operation;
    int index;
    int count;
    long long integer_data;
    double number_data;
    void *pointer;
    size_t length;
    lua_Alloc allocator;
    unsigned seed;
    lua_CFunction function_data;
    const char *name;
    const char *mode;
};

struct lua_ada_response {
    long long integer_data;
    double number_data;
    void *pointer;
    size_t length;
    lua_Alloc allocator;
    lua_CFunction function_data;
};

enum lua_ada_action {
    ADA_ACTION_DONE = LUA_OK,
    ADA_ACTION_CALL = LUA_YIELD,
    ADA_ACTION_RAISE = LUA_ERRRUN,
    ADA_ACTION_MEMORY = LUA_ERRMEM,
    ADA_ACTION_ABORT = 6
};

/* This is an opaque state surface, not C Lua's private lua_State layout.
 * Pinned lua_getextraspace only relies on the exact prefix preceding it.
 * A guard is always a live C-owned checkpoint, never a saved Ada frame. */
struct lua_ada_guard;
struct lua_State {
    void *control;
    struct lua_ada_guard *guard;
    lua_State *main;
    lua_CFunction panic;
};

enum lua_ada_action ada_lua_dispatch(lua_State *state,
                                    const struct lua_ada_request *input,
                                    struct lua_ada_response *output);
size_t ada_lua_contract(int part);
size_t lua_ada_surface_size(void);
size_t lua_ada_request_size(void);
size_t lua_ada_response_size(void);
size_t lua_ada_extra_space(void);

/* Test-only C guard probe. It demonstrates that a failing exported operation
 * returned through Ada before C unwinds. It is not a lua_pcall replacement. */
LUA_API int lua_ada_guard_probe(lua_State *state, lua_CFunction body);

#endif
