/* Public-API test drivers derived from Lua 5.5.1 ltests.c:1338-1399 and
 * 1496-2144, pinned at 7579fc9d7ed90240487251dfb69168f8e64e9294.
 * Copyright (C) 1994-2026 Lua.org, PUC-Rio. MIT license; see lua.h and
 * conformance_adapter.sources.md for the retained notice and change manifest.
 *
 * This is the test suite's API-command language, not an interpreter backend.
 * Every command below invokes the real exported Lua API. Lua programs,
 * coroutine transfers, hooks and continuations execute in the Ada runtime.
 * No private C Lua structure or reference-interpreter object is linked here.
 */
#include "conformance_api.h"
#include "lauxlib.h"
#include "lualib.h"
#include <limits.h>
#include <stddef.h>
#include <string.h>

static const char delimiters[] = " \t\r\n,;";
static const char *const statuses[] = {
    "OK", "YIELD", "ERRRUN", "ERRSYNTAX", "not enough memory", "ERRERR"
};

static int run_commands(lua_State *, lua_State *, const char *);
static int continue_commands(lua_State *, int, lua_KContext);
static int test_commands(lua_State *);
static int make_function(lua_State *);
static int set_hook(lua_State *);
static int resume_thread(lua_State *);
static int new_state(lua_State *);
static int load_libraries(lua_State *);
static int run_remote(lua_State *);
static int close_state(lua_State *);

/* Argument validation deliberately uses the public core API so this driver
 * does not rely on unimplemented auxiliary convenience functions. Raising
 * happens only after each exported API call has returned to this C frame. */
static int fail(lua_State *L, const char *message) {
    lua_pushstring(L, message);
    return lua_error(L);
}

static const char *string_argument(lua_State *L, int index, size_t *length) {
    const char *result = lua_tolstring(L, index, length);
    if (result == NULL) fail(L, "string expected in C API test driver");
    return result;
}

static int integer_argument(lua_State *L, int index) {
    int valid;
    lua_Integer result = lua_tointegerx(L, index, &valid);
    if (!valid || result < INT_MIN || result > INT_MAX)
        fail(L, "C integer expected in C API test driver");
    return (int)result;
}

static lua_State *state_argument(lua_State *L) {
    lua_State *result = (lua_State *)lua_touserdata(L, 1);
    if (result == NULL) fail(L, "state expected in C API test driver");
    return result;
}

static const char *status_name(lua_State *L, int status) {
    if (status < LUA_OK || status > LUA_ERRERR)
        fail(L, "invalid runtime status in C API test driver");
    return statuses[status];
}

/* Preserve ltests.c's dynamic operands: '.' consumes the stack top, '*'
 * observes its size, !M/!G name actual registry slots and U names a real
 * closure upvalue. Overflow and oversized tokens become test errors rather
 * than allowing the harness itself to execute undefined C arithmetic. */
static void skip(const char **pc) {
    for (;;) {
        if (**pc != '\0' && strchr(delimiters, **pc) != NULL) ++*pc;
        else if (**pc == '#') {
            while (**pc != '\0' && **pc != '\n') ++*pc;
        } else return;
    }
}

static int number(lua_State *L, lua_State *target, const char **pc) {
    unsigned magnitude = 0;
    int negative = 0;
    skip(pc);
    if (**pc == '.') {
        int result = integer_argument(target, -1);
        lua_pop(target, 1);
        ++*pc;
        return result;
    }
    if (**pc == '*') { ++*pc; return lua_gettop(target); }
    if (**pc == '!') {
        int result;
        ++*pc;
        if (**pc == 'M') result = LUA_RIDX_MAINTHREAD;
        else if (**pc == 'G') result = LUA_RIDX_GLOBALS;
        else return fail(L, "unknown C API registry operand");
        ++*pc;
        return result;
    }
    if (**pc == '-') { negative = 1; ++*pc; }
    if (**pc < '0' || **pc > '9') return fail(L, "C API number expected");
    while (**pc >= '0' && **pc <= '9') {
        unsigned digit = (unsigned)(**pc - '0');
        unsigned limit = (unsigned)INT_MAX + (unsigned)negative;
        if (magnitude > (limit - digit) / 10)
            return fail(L, "C API operand overflows int");
        magnitude = magnitude * 10 + digit;
        ++*pc;
    }
    if (negative && magnitude == (unsigned)INT_MAX + 1u) return INT_MIN;
    return negative ? -(int)magnitude : (int)magnitude;
}

static int index_operand(lua_State *L, lua_State *target, const char **pc) {
    int result;
    skip(pc);
    if (**pc == 'R') { ++*pc; return LUA_REGISTRYINDEX; }
    if (**pc == 'U') {
        ++*pc;
        result = number(L, target, pc);
        if (result < 1 || result > 255)
            return fail(L, "invalid C API upvalue index");
        return lua_upvalueindex(result);
    }
    result = number(L, target, pc);
    return result == 0 ? 0 : lua_absindex(target, result);
}

static const char *token(lua_State *L, char *buffer, size_t capacity,
                         const char **pc) {
    size_t length = 0;
    int quote = 0;
    skip(pc);
    if (**pc == '\'' || **pc == '"') { quote = **pc; ++*pc; }
    while (**pc != '\0' &&
           (quote ? **pc != quote : strchr(delimiters, **pc) == NULL)) {
        if (length + 1 >= capacity) fail(L, "C API token is too long");
        buffer[length++] = **pc;
        ++*pc;
    }
    if (quote) {
        if (**pc == '\0') fail(L, "unfinished string in C API script");
        ++*pc;
    }
    buffer[length] = '\0';
    return buffer;
}

/* A continuation script is retained in its original stack/upvalue slot.
 * The runtime supplies the actual status/context after resumption; neither
 * value is guessed from the requested operation or an expected test result. */
static int continue_commands(lua_State *L, int status, lua_KContext context) {
    lua_pushstring(L, status_name(L, status));
    lua_setglobal(L, "status");
    lua_pushinteger(L, (lua_Integer)context);
    lua_setglobal(L, "ctx");
    return run_commands(L, L, string_argument(L, (int)context, NULL));
}

static int run_commands(lua_State *L, lua_State *target, const char *pc) {
    char instruction[300], argument[300];
    int status = LUA_OK;
    if (pc == NULL) return fail(L, "null C API script");
    for (;;) {
        token(L, instruction, sizeof(instruction), &pc);
        if (instruction[0] == '\0') return 0;
        if (strcmp(instruction, "pushint") == 0)
            lua_pushinteger(target, number(L, target, &pc));
        else if (strcmp(instruction, "pushnum") == 0)
            lua_pushnumber(target, (lua_Number)number(L, target, &pc));
        else if (strcmp(instruction, "pushstring") == 0)
            lua_pushstring(target, token(L, argument, sizeof(argument), &pc));
        else if (strcmp(instruction, "pushvalue") == 0)
            lua_pushvalue(target, index_operand(L, target, &pc));
        else if (strcmp(instruction, "pushupvalueindex") == 0) {
            int upvalue = number(L, target, &pc);
            if (upvalue < 1 || upvalue > 255)
                return fail(L, "invalid C API upvalue index");
            lua_pushinteger(target, lua_upvalueindex(upvalue));
        } else if (strcmp(instruction, "pushnil") == 0) lua_pushnil(target);
        else if (strcmp(instruction, "pushbool") == 0)
            lua_pushboolean(target, number(L, target, &pc));
        else if (strcmp(instruction, "pushstatus") == 0)
            lua_pushstring(target, status_name(L, status));
        else if (strcmp(instruction, "newthread") == 0) lua_newthread(target);
        else if (strcmp(instruction, "rawgeti") == 0) {
            int index = index_operand(L, target, &pc);
            lua_rawgeti(target, index, number(L, target, &pc));
        } else if (strcmp(instruction, "gettop") == 0)
            lua_pushinteger(target, lua_gettop(target));
        else if (strcmp(instruction, "settop") == 0)
            lua_settop(target, number(L, target, &pc));
        else if (strcmp(instruction, "pop") == 0)
            lua_pop(target, number(L, target, &pc));
        else if (strcmp(instruction, "remove") == 0)
            lua_remove(target, number(L, target, &pc));
        else if (strcmp(instruction, "getglobal") == 0)
            lua_getglobal(target, token(L, argument, sizeof(argument), &pc));
        else if (strcmp(instruction, "setglobal") == 0)
            lua_setglobal(target, token(L, argument, sizeof(argument), &pc));
        else if (strcmp(instruction, "isyieldable") == 0) {
            lua_State *thread = lua_tothread(target,
                index_operand(L, target, &pc));
            if (thread == NULL) return fail(L, "C API thread expected");
            lua_pushboolean(target, lua_isyieldable(thread));
        } else if (strcmp(instruction, "resume") == 0) {
            int index = index_operand(L, target, &pc), results;
            lua_State *thread = lua_tothread(target, index);
            int arguments = number(L, target, &pc);
            if (thread == NULL) return fail(L, "C API thread expected");
            status = lua_resume(thread, L, arguments, &results);
        } else if (strcmp(instruction, "xmove") == 0) {
            int from = index_operand(L, target, &pc);
            int to = index_operand(L, target, &pc);
            lua_State *source = from == 0 ? target : lua_tothread(target, from);
            lua_State *destination = to == 0 ? target : lua_tothread(target, to);
            int count = number(L, target, &pc);
            if (source == NULL || destination == NULL)
                return fail(L, "C API thread expected");
            if (count == 0) count = lua_gettop(source);
            lua_xmove(source, destination, count);
        } else if (strcmp(instruction, "call") == 0 ||
                   strcmp(instruction, "callk") == 0 ||
                   strcmp(instruction, "pcall") == 0 ||
                   strcmp(instruction, "pcallk") == 0) {
            int arguments = number(L, target, &pc);
            int results = number(L, target, &pc);
            if (strcmp(instruction, "call") == 0)
                lua_call(target, arguments, results);
            else if (strcmp(instruction, "callk") == 0) {
                int context = index_operand(L, target, &pc);
                lua_callk(target, arguments, results, context, continue_commands);
            } else if (strcmp(instruction, "pcall") == 0)
                status = lua_pcall(target, arguments, results,
                                   number(L, target, &pc));
            else {
                int context = index_operand(L, target, &pc);
                status = lua_pcallk(target, arguments, results, 0,
                                    context, continue_commands);
            }
        } else if (strcmp(instruction, "yield") == 0)
            return lua_yield(target, number(L, target, &pc));
        else if (strcmp(instruction, "yieldk") == 0) {
            int results = number(L, target, &pc);
            int context = index_operand(L, target, &pc);
            return lua_yieldk(target, results, context, continue_commands);
        } else if (strcmp(instruction, "toclose") == 0)
            lua_toclose(target, number(L, target, &pc));
        else if (strcmp(instruction, "return") == 0) {
            int count = number(L, target, &pc);
            if (target != L) {
                int i;
                /* Independent universes cannot use xmove. The pinned driver
                 * transfers booleans directly and textual scalar results by
                 * value; numeric remote results intentionally become strings. */
                for (i = 0; i < count; ++i) {
                    int index = -(count - i);
                    if (lua_type(target, index) == LUA_TBOOLEAN)
                        lua_pushboolean(L, lua_toboolean(target, index));
                    else lua_pushstring(L, lua_tostring(target, index));
                }
            }
            return count;
        } else return fail(L, "unknown instruction in C API script");
    }
}

static int test_commands(lua_State *L) {
    lua_State *target = L;
    int script = 1;
    if (lua_isuserdata(L, 1)) { target = state_argument(L); script = 2; }
    else if (lua_isthread(L, 1)) { target = lua_tothread(L, 1); script = 2; }
    return run_commands(L, target, string_argument(L, script, NULL));
}

static int closure_commands(lua_State *L) {
    return run_commands(L, L, string_argument(L, lua_upvalueindex(1), NULL));
}

static int make_function(lua_State *L) {
    (void)string_argument(L, 1, NULL);
    lua_pushcclosure(L, closure_commands, lua_gettop(L));
    return 1;
}

/* Registry ownership keeps each coroutine's script alive through collection
 * and suspension. Hook scripts run under the runtime's real C hook guard;
 * yielding from them must preserve the interrupted activation and its top. */
static void command_hook(lua_State *L, lua_Debug *record) {
    static const char *const events[] = {"call", "ret", "line", "count",
                                         "tailcall"};
    const char *script;
    lua_getfield(L, LUA_REGISTRYINDEX, "C_HOOK");
    lua_pushlightuserdata(L, L);
    lua_gettable(L, -2);
    script = string_argument(L, -1, NULL);
    lua_pop(L, 2);
    if (record->event < LUA_HOOKCALL || record->event > LUA_HOOKTAILCALL) {
        fail(L, "unknown C hook event");
        return;
    }
    lua_pushstring(L, events[record->event]);
    lua_pushinteger(L, record->currentline);
    (void)run_commands(L, L, script);
}

static int set_hook(lua_State *L) {
    const char *script, *mask_text;
    int mask = 0, count = 0;
    if (lua_isnoneornil(L, 1)) { lua_sethook(L, NULL, 0, 0); return 0; }
    script = string_argument(L, 1, NULL);
    mask_text = string_argument(L, 2, NULL);
    if (!lua_isnoneornil(L, 3)) count = integer_argument(L, 3);
    if (strchr(mask_text, 'c') != NULL) mask |= LUA_MASKCALL;
    if (strchr(mask_text, 'r') != NULL) mask |= LUA_MASKRET;
    if (strchr(mask_text, 'l') != NULL) mask |= LUA_MASKLINE;
    if (count > 0) mask |= LUA_MASKCOUNT;
    if (script[0] == '\0') { lua_sethook(L, NULL, 0, 0); return 0; }
    lua_getfield(L, LUA_REGISTRYINDEX, "C_HOOK");
    if (!lua_istable(L, -1)) {
        lua_pop(L, 1);
        lua_newtable(L);
        lua_pushvalue(L, -1);
        lua_setfield(L, LUA_REGISTRYINDEX, "C_HOOK");
    }
    lua_pushlightuserdata(L, L);
    lua_pushvalue(L, 1);
    lua_settable(L, -3);
    lua_sethook(L, command_hook, mask, count);
    return 0;
}

static int resume_thread(lua_State *L) {
    lua_State *thread = lua_tothread(L, 1);
    int count, status;
    if (thread == NULL) return fail(L, "coroutine expected");
    status = lua_resume(thread, L, 0, &count);
    if (status != LUA_OK && status != LUA_YIELD) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, lua_tostring(thread, -1));
        return 2;
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int new_state(lua_State *L) {
    void *data;
    lua_Alloc allocator = lua_getallocf(L, &data);
    lua_State *other = lua_newstate(allocator, data, 0);
    if (other == NULL) lua_pushnil(L);
    else lua_pushlightuserdata(L, other);
    return 1;
}

static int open_api(lua_State *L) {
    static const char *const names[] = {"testC", "makeCfunc", "sethook",
        "resume", "newstate", "loadlib", "doremote", "closestate"};
    int i;
    lua_newtable(L);
    for (i = 0; i < 8; ++i) {
        lua_pushcfunction(L, lua_ada_test_api_callback(17 + i));
        lua_setfield(L, -2, names[i]);
    }
    return 1;
}

static int load_libraries(lua_State *L) {
    lua_State *other = state_argument(L);
    luaL_openselectedlibs(other, integer_argument(L, 2),
                         integer_argument(L, 3));
    luaL_requiref(other, "T", open_api, 0);
    if (!lua_istable(other, -1)) return fail(L, "T did not return a table");
    luaL_requiref(other, "T", NULL, 1);
    if (!lua_rawequal(other, -1, -2))
        return fail(L, "requiref reloaded the T module");
    return 0;
}

static int run_remote(lua_State *L) {
    lua_State *other = state_argument(L);
    size_t length;
    const char *script = string_argument(L, 2, &length);
    int status, i, count;
    lua_settop(other, 0);
    status = luaL_loadbufferx(other, script, length, script, "t");
    if (status == LUA_OK) status = lua_pcall(other, 0, LUA_MULTRET, 0);
    if (status != LUA_OK) {
        lua_pushnil(L);
        lua_pushstring(L, lua_tostring(other, -1));
        lua_pushinteger(L, status);
        return 3;
    }
    count = lua_gettop(other);
    for (i = 1; i <= count; ++i) lua_pushstring(L, lua_tostring(other, i));
    lua_pop(other, count);
    return count;
}

static int close_state(lua_State *L) {
    lua_close(state_argument(L));
    return 0;
}

lua_CFunction lua_ada_test_api_callback(int operation) {
    static lua_CFunction const callbacks[] = {test_commands, make_function,
        set_hook, resume_thread, new_state, load_libraries, run_remote,
        close_state};
    if (operation < 17 || operation > 24) return NULL;
    return callbacks[operation - 17];
}
