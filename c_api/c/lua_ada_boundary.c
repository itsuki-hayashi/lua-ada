/* Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE.
 * These wrappers contain ABI/startup/nonlocal-transfer mechanics only. Every
 * stack/value operation executes in Ada and returns an explicit action before
 * C raises it. No reference interpreter object is linked into this library. */
#include "lua_ada_boundary.h"
#include "lauxlib.h"
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void luainit(void);

struct lua_ada_guard {
    jmp_buf target;
    struct lua_ada_guard *previous;
};

size_t lua_ada_surface_size(void) { return sizeof(lua_State); }
size_t lua_ada_request_size(void) { return sizeof(struct lua_ada_request); }
size_t lua_ada_response_size(void) { return sizeof(struct lua_ada_response); }
size_t lua_ada_extra_space(void) { return LUA_EXTRASPACE; }

static void initialize(void) {
    /* GNAT's standalone binder entry is idempotent. Calling it from the C
     * constructor entrypoints also pulls the binder object out of a static
     * archive, so a plain C main needs no adainit/binder knowledge. Shared
     * libraries additionally retain GNAT's automatic loader initialization. */
    luainit();
    if (ada_lua_contract(0) != sizeof(struct lua_ada_request) ||
        ada_lua_contract(1) != sizeof(struct lua_ada_response) ||
        ada_lua_contract(2) != sizeof(lua_State)) {
        fprintf(stderr,
                "Lua Ada: incompatible C dispatch layout: "
                "request C=%zu Ada=%zu; response C=%zu Ada=%zu; "
                "surface C=%zu Ada=%zu\n",
                sizeof(struct lua_ada_request), ada_lua_contract(0),
                sizeof(struct lua_ada_response), ada_lua_contract(1),
                sizeof(lua_State), ada_lua_contract(2));
        abort();
    }
}

static struct lua_ada_request request(enum lua_ada_operation operation) {
    struct lua_ada_request input;
    memset(&input, 0, sizeof input);
    input.operation = operation;
    return input;
}

static void raise_action(lua_State *state, int status,
                         const struct lua_ada_response *output) {
    /* This function is reached only after ada_lua_dispatch has returned.
     * Its checkpoint belongs to C; no abandoned Ada activation is retained. */
    if (status == LUA_OK) return;
    if (status != ADA_ACTION_ABORT && state != NULL && state->guard != NULL)
        longjmp(state->guard->target, status);
    if (status != ADA_ACTION_ABORT && state != NULL && state->main->panic != NULL)
        state->main->panic(state);
    fputs("Lua Ada: unprotected error", stderr);
    if (output->pointer != NULL) {
        fputs(": ", stderr);
        fputs((const char *)output->pointer, stderr);
    }
    fputc('\n', stderr);
    abort();
}

static struct lua_ada_response dispatch(lua_State *state,
                                        struct lua_ada_request input) {
    struct lua_ada_response output;
    int status = ada_lua_dispatch(state, &input, &output);
    raise_action(state, status, &output);
    return output;
}

int lua_ada_guard_probe(lua_State *state, lua_CFunction body) {
    struct lua_ada_guard guard;
    int status;
    guard.previous = state->guard;
    state->guard = &guard;
    status = setjmp(guard.target);
    if (status == 0) body(state);
    state->guard = guard.previous;
    return status;
}

lua_State *lua_newstate(lua_Alloc allocator, void *userdata, unsigned seed) {
    struct lua_ada_request input = request(ADA_CREATE_STATE);
    struct lua_ada_response output;
    initialize();
    input.allocator = allocator;
    input.pointer = userdata;
    input.seed = seed;
    input.length = LUA_EXTRASPACE;
    /* Constructor failure is an ordinary null result, never a panic. */
    if (ada_lua_dispatch(NULL, &input, &output) != LUA_OK) return NULL;
    return (lua_State *)output.pointer;
}

lua_State *luaL_newstate(void) {
    struct lua_ada_request input = request(ADA_CREATE_DEFAULT_STATE);
    struct lua_ada_response output;
    initialize();
    input.length = LUA_EXTRASPACE;
    if (ada_lua_dispatch(NULL, &input, &output) != LUA_OK) return NULL;
    return (lua_State *)output.pointer;
}

void lua_close(lua_State *state) { dispatch(state, request(ADA_CLOSE_STATE)); }
lua_State *lua_newthread(lua_State *state) {
    return (lua_State *)dispatch(state, request(ADA_CREATE_THREAD)).pointer;
}
lua_Number lua_version(lua_State *state) { (void)state; return LUA_VERSION_NUM; }
lua_CFunction lua_atpanic(lua_State *state, lua_CFunction panic) {
    lua_CFunction previous = state->main->panic;
    state->main->panic = panic;
    return previous;
}

static struct lua_ada_response indexed(lua_State *state,
                                       enum lua_ada_operation operation,
                                       int index) {
    struct lua_ada_request input = request(operation);
    input.index = index;
    return dispatch(state, input);
}

int lua_gettop(lua_State *state) {
    return (int)dispatch(state, request(ADA_GET_TOP)).integer_data;
}
void lua_settop(lua_State *state, int index) {
    indexed(state, ADA_SET_TOP, index);
}
int lua_absindex(lua_State *state, int index) {
    return (int)indexed(state, ADA_ABSOLUTE_INDEX, index).integer_data;
}
void lua_pushvalue(lua_State *state, int index) {
    indexed(state, ADA_PUSH_VALUE, index);
}
int lua_checkstack(lua_State *state, int count) {
    struct lua_ada_request input = request(ADA_CHECK_STACK);
    input.count = count;
    return (int)dispatch(state, input).integer_data;
}
void lua_copy(lua_State *state, int from, int to) {
    struct lua_ada_request input = request(ADA_COPY_VALUE);
    input.index = from; input.count = to;
    dispatch(state, input);
}
void lua_rotate(lua_State *state, int index, int count) {
    struct lua_ada_request input = request(ADA_ROTATE_VALUES);
    input.index = index; input.count = count;
    dispatch(state, input);
}
void lua_xmove(lua_State *from, lua_State *to, int count) {
    struct lua_ada_request input = request(ADA_MOVE_VALUES);
    input.pointer = to; input.count = count;
    dispatch(from, input);
}
int lua_type(lua_State *state, int index) {
    return (int)indexed(state, ADA_GET_TYPE, index).integer_data;
}
const char *lua_typename(lua_State *state, int type) {
    static const char *const names[] = {"nil", "boolean", "userdata",
        "number", "string", "table", "function", "userdata", "thread"};
    (void)state;
    return type >= LUA_TNIL && type < LUA_NUMTYPES ? names[type] : "no value";
}
int lua_isinteger(lua_State *state, int index) {
    return indexed(state, ADA_GET_TYPE, index).length != 0;
}
int lua_isnumber(lua_State *state, int index) {
    return indexed(state, ADA_TO_NUMBER, index).length != 0;
}
int lua_isstring(lua_State *state, int index) {
    int type = lua_type(state, index);
    return type == LUA_TSTRING || type == LUA_TNUMBER;
}
int lua_isuserdata(lua_State *state, int index) {
    int type = lua_type(state, index);
    return type == LUA_TLIGHTUSERDATA || type == LUA_TUSERDATA;
}
int lua_toboolean(lua_State *state, int index) {
    return (int)indexed(state, ADA_TO_BOOLEAN, index).integer_data;
}
lua_Integer lua_tointegerx(lua_State *state, int index, int *valid) {
    struct lua_ada_response output = indexed(state, ADA_TO_INTEGER, index);
    if (valid != NULL) *valid = output.length != 0;
    return (lua_Integer)output.integer_data;
}
lua_Number lua_tonumberx(lua_State *state, int index, int *valid) {
    struct lua_ada_response output = indexed(state, ADA_TO_NUMBER, index);
    if (valid != NULL) *valid = output.length != 0;
    return (lua_Number)output.number_data;
}
const char *lua_tolstring(lua_State *state, int index, size_t *length) {
    struct lua_ada_response output = indexed(state, ADA_TO_STRING, index);
    if (length != NULL) *length = output.length;
    return (const char *)output.pointer;
}
lua_Unsigned lua_rawlen(lua_State *state, int index) {
    return (lua_Unsigned)indexed(state, ADA_RAW_LENGTH, index).integer_data;
}
const void *lua_topointer(lua_State *state, int index) {
    return indexed(state, ADA_TO_POINTER, index).pointer;
}
void *lua_touserdata(lua_State *state, int index) {
    return lua_isuserdata(state, index) ?
        indexed(state, ADA_TO_POINTER, index).pointer : NULL;
}
lua_State *lua_tothread(lua_State *state, int index) {
    return (lua_State *)indexed(state, ADA_TO_THREAD, index).pointer;
}
void lua_pushnil(lua_State *state) { dispatch(state, request(ADA_PUSH_NIL)); }
void lua_pushboolean(lua_State *state, int value) {
    struct lua_ada_request input = request(ADA_PUSH_BOOLEAN);
    input.count = value; dispatch(state, input);
}
void lua_pushinteger(lua_State *state, lua_Integer value) {
    struct lua_ada_request input = request(ADA_PUSH_INTEGER);
    input.integer_data = value; dispatch(state, input);
}
void lua_pushnumber(lua_State *state, lua_Number value) {
    struct lua_ada_request input = request(ADA_PUSH_NUMBER);
    input.number_data = value; dispatch(state, input);
}
const char *lua_pushlstring(lua_State *state, const char *text, size_t length) {
    struct lua_ada_request input = request(ADA_PUSH_STRING);
    input.pointer = (void *)text; input.length = length;
    return (const char *)dispatch(state, input).pointer;
}
const char *lua_pushstring(lua_State *state, const char *text) {
    if (text == NULL) { lua_pushnil(state); return NULL; }
    return lua_pushlstring(state, text, strlen(text));
}
void lua_pushlightuserdata(lua_State *state, void *pointer) {
    struct lua_ada_request input = request(ADA_PUSH_POINTER);
    input.pointer = pointer; dispatch(state, input);
}
int lua_pushthread(lua_State *state) {
    return (int)dispatch(state, request(ADA_PUSH_THREAD)).integer_data;
}
void lua_createtable(lua_State *state, int array, int records) {
    struct lua_ada_request input = request(ADA_CREATE_TABLE);
    input.index = array; input.count = records; dispatch(state, input);
}
int lua_rawget(lua_State *state, int index) {
    return (int)indexed(state, ADA_RAW_GET, index).integer_data;
}
void lua_rawset(lua_State *state, int index) {
    indexed(state, ADA_RAW_SET, index);
}
int lua_rawgeti(lua_State *state, int index, lua_Integer key) {
    struct lua_ada_request input = request(ADA_RAW_GET_INTEGER);
    input.index = index; input.integer_data = key;
    return (int)dispatch(state, input).integer_data;
}
void lua_rawseti(lua_State *state, int index, lua_Integer key) {
    struct lua_ada_request input = request(ADA_RAW_SET_INTEGER);
    input.index = index; input.integer_data = key; dispatch(state, input);
}
int lua_rawgetp(lua_State *state, int index, const void *key) {
    struct lua_ada_request input = request(ADA_RAW_GET_POINTER);
    input.index = index; input.pointer = (void *)key;
    return (int)dispatch(state, input).integer_data;
}
void lua_rawsetp(lua_State *state, int index, const void *key) {
    struct lua_ada_request input = request(ADA_RAW_SET_POINTER);
    input.index = index; input.pointer = (void *)key; dispatch(state, input);
}
int lua_rawequal(lua_State *state, int first, int second) {
    struct lua_ada_request input = request(ADA_RAW_EQUAL);
    input.index = first; input.count = second;
    return (int)dispatch(state, input).integer_data;
}
int lua_next(lua_State *state, int index) {
    return (int)indexed(state, ADA_NEXT_ITEM, index).integer_data;
}
lua_Alloc lua_getallocf(lua_State *state, void **userdata) {
    struct lua_ada_response output = dispatch(state, request(ADA_GET_ALLOCATOR));
    if (userdata != NULL) *userdata = output.pointer;
    return output.allocator;
}
void lua_setallocf(lua_State *state, lua_Alloc allocator, void *userdata) {
    struct lua_ada_request input = request(ADA_SET_ALLOCATOR);
    input.allocator = allocator; input.pointer = userdata; dispatch(state, input);
}
