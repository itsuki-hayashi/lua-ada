/* Public luaL_Buffer layout and caller-owned scratch stay on the C side.
 * Dynamic bytes, ownership transfer and cleanup are Ada-owned operations.
 * Copyright (c) 2026 Lua Ada contributors. MIT; see ../../LICENSE. */
#include "lua_ada_boundary.h"
#include "lauxlib.h"
#include <assert.h>
#include <stdint.h>
#include <string.h>

extern void lua_ada_aux_charge(lua_State *L, size_t amount);

struct buffer_box { void *handle; };

/* The private Ada operation views only the first two public fields. Keep
 * their actual SDK layout checked rather than copying a private C layout. */
typedef char buffer_pointer_first[(offsetof(luaL_Buffer, b) == 0) ? 1 : -1];
typedef char buffer_capacity_second[
    (offsetof(luaL_Buffer, size) == sizeof(char *)) ? 1 : -1];
typedef char buffer_length_third[
    (offsetof(luaL_Buffer, n) == sizeof(char *) + sizeof(size_t)) ? 1 : -1];

static void box_request(lua_State *L, enum lua_ada_operation operation,
                        struct buffer_box *box, luaL_Buffer *B, size_t size,
                        int index, size_t minimum) {
    struct lua_ada_request input;
    struct lua_ada_response output;
    memset(&input, 0, sizeof input);
    memset(&output, 0, sizeof output);
    input.operation = operation;
    input.pointer = &box->handle;
    input.name = (const char *)B;
    input.length = size;
    input.index = index;
    input.integer_data = (lua_Integer)minimum;
    lua_ada_debug_dispatch(L, &input, &output);
}

static int close_box(lua_State *L) {
    struct buffer_box *box = (struct buffer_box *)lua_touserdata(L, 1);
    assert(box != NULL);
    box_request(L, ADA_RELEASE_AUX_BOX, box, NULL, 0, 1, 0);
    return 0;
}

static struct buffer_box *new_box(lua_State *L) {
    static const luaL_Reg methods[] = {
        {"__gc", close_box}, {"__close", close_box}, {NULL, NULL}
    };
    struct buffer_box *box = (struct buffer_box *)
        lua_newuserdatauv(L, sizeof *box, 0);
    box->handle = NULL;
    if (luaL_newmetatable(L, "_UBOX*")) luaL_setfuncs(L, methods, 0);
    lua_setmetatable(L, -2);
    return box;
}

static int heap_buffer(const luaL_Buffer *B) {
    return B->b != B->init.b;
}

static void check_level(luaL_Buffer *B, int index) {
    assert(heap_buffer(B) ? lua_touserdata(B->L, index) != NULL :
                           lua_touserdata(B->L, index) == (void *)B);
}

static size_t capacity_for(luaL_Buffer *B, size_t extra) {
    const size_t maximum = sizeof(size_t) < sizeof(lua_Integer) ?
        SIZE_MAX : (size_t)LUA_MAXINTEGER;
    size_t size = B->size;
    if (extra >= maximum - B->n)
        luaL_error(B->L, "resulting string too large");
    if (size <= maximum / 3 * 2) size += size >> 1;
    if (size < B->n + extra + 1) size = B->n + extra + 1;
    return size;
}

static char *prepare(luaL_Buffer *B, size_t extra, int index) {
    lua_State *L = B->L;
    struct buffer_box *box;
    size_t capacity;
    check_level(B, index);
    if (B->size - B->n >= extra) return B->b + B->n;
    capacity = capacity_for(B, extra);
    if (heap_buffer(B)) box = (struct buffer_box *)lua_touserdata(L, index);
    else {
        /* Keep an addvalue operand rooted while replacing its placeholder.
         * Registration is on the actual C slot, before any owned allocation
         * can fail, so ordinary C error unwinding releases this box. */
        lua_remove(L, index);
        box = new_box(L);
        lua_insert(L, index);
        lua_toclose(L, index);
        box_request(L, ADA_CREATE_AUX_BOX, box, NULL, 0, index, 0);
    }
    box_request(L, ADA_RESIZE_AUX_BOX, box, B, capacity, 0,
                B->n + extra + 1);
    return B->b + B->n;
}

void luaL_buffinit(lua_State *L, luaL_Buffer *B) {
    B->L = L;
    B->b = B->init.b;
    B->n = 0;
    B->size = LUAL_BUFFERSIZE;
    lua_pushlightuserdata(L, B);
}

char *luaL_prepbuffsize(luaL_Buffer *B, size_t size) {
    return prepare(B, size, -1);
}

char *luaL_buffinitsize(lua_State *L, luaL_Buffer *B, size_t size) {
    luaL_buffinit(L, B);
    return prepare(B, size, -1);
}

void luaL_addlstring(luaL_Buffer *B, const char *text, size_t size) {
    if (size != 0) {
        char *target;
        lua_ada_aux_charge(B->L, size);
        target = prepare(B, size, -1);
        memcpy(target, text, size);
        luaL_addsize(B, size);
    }
}

void luaL_addstring(luaL_Buffer *B, const char *text) {
    size_t size = 0;
    while (text[size] != '\0') {
        ++size;
        /* This foreign scan and the subsequent owned copy are distinct
         * work. Charge completed scan blocks before proceeding farther. */
        if (size % 4096 == 0) lua_ada_aux_charge(B->L, 4096);
    }
    luaL_addlstring(B, text, size);
}

void luaL_addvalue(luaL_Buffer *B) {
    size_t size;
    const char *text = lua_tolstring(B->L, -1, &size);
    char *target;
    lua_ada_aux_charge(B->L, size);
    target = prepare(B, size, -2);
    if (size != 0) memcpy(target, text, size);
    luaL_addsize(B, size);
    lua_pop(B->L, 1);
}

void luaL_pushresult(luaL_Buffer *B) {
    lua_State *L = B->L;
    check_level(B, -1);
    if (!heap_buffer(B)) lua_pushlstring(L, B->b, B->n);
    else {
        struct buffer_box *box = (struct buffer_box *)lua_touserdata(L, -1);
        /* Ada atomically clears this userdata's handle when the external
         * string adopts the actual allocation. Its package-level deallocator
         * outlives this C activation; no buffer record address is retained. */
        box_request(L, ADA_PUBLISH_AUX_BOX, box, B, B->n, 0, 0);
        lua_closeslot(L, -2);
        lua_gc(L, LUA_GCSTEP, (int)B->n);
    }
    lua_remove(L, -2);
}

void luaL_pushresultsize(luaL_Buffer *B, size_t size) {
    luaL_addsize(B, size);
    luaL_pushresult(B);
}
