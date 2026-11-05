/* Reference-only experiments. This is not part of the Ada interpreter. */
#include <assert.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../../../references/lua/lua.h"
#include "../../../references/lua/lauxlib.h"

extern void abi_bridgeinit(void);
extern void abi_bridgefinal(void);
extern int ada_probe_invoke(int (*handler)(int), int value);

struct allocator_state {
    size_t blocks;
    int reject_growth;
};

static void *tracked_alloc(void *context, void *old, size_t old_size,
                           size_t new_size)
{
    struct allocator_state *state = context;
    void *result;
    int fresh = old == NULL;
    if (new_size == 0) {
        if (old != NULL) {
            --state->blocks;
        }
        free(old);
        return NULL;
    }
    if (state->reject_growth && (old == NULL || new_size > old_size)) {
        return NULL;
    }
    result = realloc(old, new_size);
    if (result != NULL && fresh) {
        ++state->blocks;
    }
    return result;
}

static int echo_status(int value)
{
    return value;
}

/* Probe-local context only: a production design needs per-execution storage. */
struct guard_context {
    jmp_buf jump;
    struct guard_context *previous;
};
static struct guard_context *active_guard;
static int guarded_callback(int value);

static int foreign_leaf(int value)
{
    if (value < 0) {
        assert(active_guard != NULL);
        longjmp(active_guard->jump, 17);
    }
    if (value == 100) {
        return ada_probe_invoke(guarded_callback, -1);
    }
    return value;
}

static int guarded_callback(int value)
{
    struct guard_context guard;
    int status;
    guard.previous = active_guard;
    active_guard = &guard;
    status = setjmp(guard.jump);
    if (status == 0) {
        status = foreign_leaf(value);
    }
    active_guard = guard.previous;
    return status;
}

static const char *push_format(lua_State *state, const char *format, ...)
{
    const char *result;
    va_list arguments;
    va_start(arguments, format);
    result = lua_pushvfstring(state, format, arguments);
    va_end(arguments);
    return result;
}

static int protected_failure(lua_State *state)
{
    /* The Ada frame has returned before C initiates the nonlocal jump. */
    int status = ada_probe_invoke(echo_status, 17);
    assert(status == 17);
    lua_pushliteral(state, "probe failure");
    return lua_error(state);
}

static int allocate_userdata(lua_State *state)
{
    (void)lua_newuserdatauv(state, 4096, 0);
    return 1;
}

static int yielding_callback(lua_State *state)
{
    /* Ada returns normally before Lua suspends this reference C callback. */
    int value = ada_probe_invoke(echo_status, 42);
    lua_pushinteger(state, value);
    return lua_yield(state, 1);
}

int main(void)
{
    struct allocator_state allocation = {0, 0};
    lua_State *state;
    void *marker = &allocation;
    void *recovered = NULL;

    abi_bridgeinit();
    assert(ada_probe_invoke(NULL, 0) == -1);
    assert(ada_probe_invoke(echo_status, 42) == 42);
    /* Ada remains active below the C checkpoint, never inside the jump. */
    assert(ada_probe_invoke(guarded_callback, -1) == 17);
    assert(ada_probe_invoke(guarded_callback, 100) == 17);
    assert(active_guard == NULL);

    allocation.reject_growth = 1;
    assert(lua_newstate(tracked_alloc, &allocation, 0) == NULL);
    assert(allocation.blocks == 0);
    allocation.reject_growth = 0;
    state = lua_newstate(tracked_alloc, &allocation, 0);
    assert(state != NULL);
    assert(LUA_EXTRASPACE >= sizeof marker);
    memcpy(lua_getextraspace(state), &marker, sizeof marker);
    memcpy(&recovered, lua_getextraspace(state), sizeof recovered);
    assert(recovered == marker);

    assert(strcmp(push_format(state, "%s:%d", "value", 42), "value:42") == 0);
    lua_pop(state, 1);
    lua_pushcfunction(state, allocate_userdata);
    allocation.reject_growth = 1;
    assert(lua_pcall(state, 0, 1, 0) == LUA_ERRMEM);
    allocation.reject_growth = 0;
    lua_pop(state, 1);
    lua_pushcfunction(state, protected_failure);
    assert(lua_pcall(state, 0, 0, 0) == LUA_ERRRUN);
    assert(strcmp(lua_tostring(state, -1), "probe failure") == 0);
    lua_pop(state, 1);
    lua_pushinteger(state, 42);
    assert(lua_tointeger(state, -1) == 42);
    lua_pop(state, 1);

    {
        int count = 0;
        lua_State *thread = lua_newthread(state);
        memcpy(&recovered, lua_getextraspace(thread), sizeof recovered);
        assert(recovered == marker);
        lua_pushcfunction(thread, yielding_callback);
        assert(lua_resume(thread, state, 0, &count) == LUA_YIELD);
        assert(count == 1 && lua_tointeger(thread, -1) == 42);
        assert(lua_resume(thread, state, 0, &count) == LUA_OK);
        lua_pop(state, 1); /* release the coroutine's main-state root */
    }
    assert(lua_gc(state, LUA_GCCOUNT) >= 0);
    lua_close(state);
    assert(allocation.blocks == 0);

    printf("integer=%zu number=%zu debug=%zu extraspace=%zu\n",
           sizeof(lua_Integer), sizeof(lua_Number), sizeof(lua_Debug),
           (size_t)LUA_EXTRASPACE);
    printf("debug.currentline.offset=%zu\n", offsetof(lua_Debug, currentline));
    abi_bridgefinal();
    puts("PASS: reference allocation, varargs, extraspace, Ada callback, protected error");
    return 0;
}
