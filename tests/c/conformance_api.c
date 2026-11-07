/* Public-API test drivers derived from Lua 5.5.1 ltests.c:1223-1399 and
 * 1469-2144, pinned at 7579fc9d7ed90240487251dfb69168f8e64e9294.
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
#include <assert.h>
#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
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
static void set_hook_script(lua_State *, int, int, const char *);
static int check_panic(lua_State *);

/* The test host binds a real zero-upvalue C leaf in the registry. Calling it
 * directly does not allocate a Lua call boundary while growth is disabled.
 * Its only argument is temporarily placed in slot 1; the actual old value is
 * rooted in a spare C slot and restored before another command observes it.
 * Native oracle modules bind the original native T.alloccount C function. */
static void allocation_count(lua_State *L, int limit) {
    int top = lua_gettop(L), results;
    lua_CFunction control;
    luaL_checkstack(L, 2, "allocation control");
    lua_getfield(L, LUA_REGISTRYINDEX, LUA_ADA_T_COUNT_KEY);
    control = lua_tocfunction(L, -1);
    lua_pop(L, 1);
    if (control == NULL) {
        lua_pushliteral(L, "allocation control is not installed");
        lua_error(L);
        return;
    }
    if (top > 0) lua_pushvalue(L, 1);
    lua_pushinteger(L, limit);
    if (top > 0) lua_replace(L, 1);
    results = control(L);
    assert(results == 0 && lua_gettop(L) == (top ? top + 1 : 1));
    if (top > 0) lua_copy(L, top + 1, 1);
    lua_settop(L, top);
}

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
        /* U0 is the registry and U256 is the acceptable absent-upvalue
         * query used by api.lua. Neither denotes an extra closure capture. */
        if (result < 0 || result > 256)
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
        /* These commands contain only operand decoding and exported API
         * calls. All lookup, handler, arithmetic, lifetime and error behavior
         * belongs to the selected runtime, including commands on other states. */
        if (strcmp(instruction, "alloccount") == 0)
            allocation_count(L, number(L, target, &pc));
        else if (strcmp(instruction, "absindex") == 0)
            lua_pushinteger(target, index_operand(L, target, &pc));
        else if (strcmp(instruction, "append") == 0) {
            int index = index_operand(L, target, &pc);
            lua_rawseti(target, index, (lua_Integer)lua_rawlen(target, index) + 1);
        } else if (strcmp(instruction, "arith") == 0) {
            static const char operations[] = "+-*%^/\\&|~<>_!";
            const char *operation;
            skip(&pc);
            operation = *pc ? strchr(operations, *pc++) : NULL;
            if (operation == NULL) return fail(L, "C API arithmetic expected");
            lua_arith(target, (int)(operation - operations));
        } else if (strcmp(instruction, "checkstack") == 0) {
            int space = number(L, target, &pc);
            const char *message = token(L, argument, sizeof(argument), &pc);
            luaL_checkstack(target, space, message[0] ? message : NULL);
        } else if (strcmp(instruction, "rawcheckstack") == 0)
            lua_pushboolean(target, lua_checkstack(target,
                number(L, target, &pc)));
        else if (strcmp(instruction, "compare") == 0) {
            const char *option = token(L, argument, sizeof(argument), &pc);
            int operation;
            if (strcmp(option, "EQ") == 0) operation = LUA_OPEQ;
            else if (strcmp(option, "LT") == 0) operation = LUA_OPLT;
            else if (strcmp(option, "LE") == 0) operation = LUA_OPLE;
            else return fail(L, "C API comparison expected");
            int left = index_operand(L, target, &pc);
            int right = index_operand(L, target, &pc);
            lua_pushboolean(target, lua_compare(target, left, right, operation));
        } else if (strcmp(instruction, "concat") == 0)
            lua_concat(target, number(L, target, &pc));
        else if (strcmp(instruction, "copy") == 0) {
            int from = index_operand(L, target, &pc);
            lua_copy(target, from, index_operand(L, target, &pc));
        } else if (strcmp(instruction, "func2num") == 0) {
            lua_CFunction function = lua_tocfunction(target,
                index_operand(L, target, &pc));
            uintptr_t bits = 0;
            typedef char function_bits_fit[
                sizeof(function) <= sizeof(bits) ? 1 : -1];
            (void)sizeof(function_bits_fit);
            memcpy(&bits, &function, sizeof(function));
            lua_pushinteger(target, (lua_Integer)bits);
        } else if (strcmp(instruction, "getfield") == 0) {
            int index = index_operand(L, target, &pc);
            int type = lua_getfield(target, index,
                token(L, argument, sizeof(argument), &pc));
            assert(type == lua_type(target, -1));
        } else if (strcmp(instruction, "getmetatable") == 0) {
            if (!lua_getmetatable(target, index_operand(L, target, &pc)))
                lua_pushnil(target);
        } else if (strcmp(instruction, "gettable") == 0) {
            int type = lua_gettable(target, index_operand(L, target, &pc));
            assert(type == lua_type(target, -1));
        } else if (strcmp(instruction, "gsub") == 0) {
            int subject = number(L, target, &pc);
            int pattern = number(L, target, &pc);
            int replacement = number(L, target, &pc);
            luaL_gsub(target, lua_tostring(target, subject),
                lua_tostring(target, pattern), lua_tostring(target, replacement));
        } else if (strcmp(instruction, "insert") == 0)
            lua_insert(target, number(L, target, &pc));
        else if (strcmp(instruction, "iscfunction") == 0)
            lua_pushboolean(target, lua_iscfunction(target,
                index_operand(L, target, &pc)));
        else if (strcmp(instruction, "isfunction") == 0)
            lua_pushboolean(target, lua_isfunction(target,
                index_operand(L, target, &pc)));
        else if (strcmp(instruction, "isnil") == 0)
            lua_pushboolean(target, lua_isnil(target,
                index_operand(L, target, &pc)));
        else if (strcmp(instruction, "isnull") == 0)
            lua_pushboolean(target, lua_isnone(target,
                index_operand(L, target, &pc)));
        else if (strcmp(instruction, "isnumber") == 0)
            lua_pushboolean(target, lua_isnumber(target,
                index_operand(L, target, &pc)));
        else if (strcmp(instruction, "isstring") == 0)
            lua_pushboolean(target, lua_isstring(target,
                index_operand(L, target, &pc)));
        else if (strcmp(instruction, "istable") == 0)
            lua_pushboolean(target, lua_istable(target,
                index_operand(L, target, &pc)));
        else if (strcmp(instruction, "isudataval") == 0)
            lua_pushboolean(target, lua_islightuserdata(target,
                index_operand(L, target, &pc)));
        else if (strcmp(instruction, "isuserdata") == 0)
            lua_pushboolean(target, lua_isuserdata(target,
                index_operand(L, target, &pc)));
        else if (strcmp(instruction, "len") == 0)
            lua_len(target, index_operand(L, target, &pc));
        else if (strcmp(instruction, "Llen") == 0)
            lua_pushinteger(target, luaL_len(target,
                index_operand(L, target, &pc)));
        else if (strcmp(instruction, "loadfile") == 0)
            luaL_loadfilex(target, luaL_checkstring(target,
                number(L, target, &pc)), "t");
        else if (strcmp(instruction, "loadstring") == 0) {
            size_t length;
            const char *source = luaL_checklstring(target,
                number(L, target, &pc), &length);
            char name[300];
            token(L, name, sizeof(name), &pc);
            luaL_loadbufferx(target, source, length, name,
                token(L, argument, sizeof(argument), &pc));
        } else if (strcmp(instruction, "newmetatable") == 0)
            lua_pushboolean(target, luaL_newmetatable(target,
                token(L, argument, sizeof(argument), &pc)));
        else if (strcmp(instruction, "newtable") == 0) lua_newtable(target);
        else if (strcmp(instruction, "resetthread") == 0)
            lua_pushinteger(target, lua_resetthread(target));
        else if (strcmp(instruction, "newuserdata") == 0)
            lua_newuserdata(target, (size_t)number(L, target, &pc));
        else if (strcmp(instruction, "next") == 0) lua_next(target, -2);
        else if (strcmp(instruction, "objsize") == 0)
            lua_pushinteger(target, (lua_Integer)lua_rawlen(target,
                index_operand(L, target, &pc)));
        else if (strcmp(instruction, "print") == 0)
            printf("%s\n", token(L, argument, sizeof(argument), &pc));
        else if (strcmp(instruction, "warning") == 0 ||
                 strcmp(instruction, "warningC") == 0)
            lua_warning(target, token(L, argument, sizeof(argument), &pc),
                strcmp(instruction, "warningC") == 0);
        else if (strcmp(instruction, "pushcclosure") == 0)
            lua_pushcclosure(target, test_commands, number(L, target, &pc));
        else if (strcmp(instruction, "pushfstringI") == 0)
            lua_pushfstring(target, lua_tostring(L, -2),
                (int)lua_tointeger(L, -1));
        else if (strcmp(instruction, "pushfstringS") == 0)
            lua_pushfstring(target, lua_tostring(L, -2), lua_tostring(L, -1));
        else if (strcmp(instruction, "pushfstringP") == 0)
            lua_pushfstring(target, lua_tostring(L, -2), lua_topointer(L, -1));
        else if (strcmp(instruction, "rawget") == 0)
            lua_rawget(target, index_operand(L, target, &pc));
        else if (strcmp(instruction, "rawgetp") == 0) {
            int index = index_operand(L, target, &pc);
            lua_rawgetp(target, index, (void *)(uintptr_t)
                number(L, target, &pc));
        } else if (strcmp(instruction, "rawset") == 0)
            lua_rawset(target, index_operand(L, target, &pc));
        else if (strcmp(instruction, "rawseti") == 0) {
            int index = index_operand(L, target, &pc);
            lua_rawseti(target, index, number(L, target, &pc));
        } else if (strcmp(instruction, "rawsetp") == 0) {
            int index = index_operand(L, target, &pc);
            lua_rawsetp(target, index, (void *)(uintptr_t)
                number(L, target, &pc));
        } else if (strcmp(instruction, "replace") == 0)
            lua_replace(target, index_operand(L, target, &pc));
        else if (strcmp(instruction, "rotate") == 0) {
            int index = index_operand(L, target, &pc);
            lua_rotate(target, index, number(L, target, &pc));
        } else if (strcmp(instruction, "setfield") == 0) {
            int index = index_operand(L, target, &pc);
            lua_setfield(target, index,
                token(L, argument, sizeof(argument), &pc));
        } else if (strcmp(instruction, "seti") == 0) {
            int index = index_operand(L, target, &pc);
            lua_seti(target, index, number(L, target, &pc));
        } else if (strcmp(instruction, "sethook") == 0) {
            int mask = number(L, target, &pc);
            int count = number(L, target, &pc);
            set_hook_script(target, mask, count,
                token(L, argument, sizeof(argument), &pc));
        } else if (strcmp(instruction, "setmetatable") == 0)
            lua_setmetatable(target, index_operand(L, target, &pc));
        else if (strcmp(instruction, "settable") == 0)
            lua_settable(target, index_operand(L, target, &pc));
        else if (strcmp(instruction, "testudata") == 0) {
            int index = index_operand(L, target, &pc);
            lua_pushboolean(target, luaL_testudata(target, index,
                token(L, argument, sizeof(argument), &pc)) != NULL);
        } else if (strcmp(instruction, "threadstatus") == 0)
            lua_pushstring(target, status_name(L, lua_status(target)));
        else if (strcmp(instruction, "error") == 0) return lua_error(target);
        else if (strcmp(instruction, "abort") == 0) abort();
        else if (strcmp(instruction, "throw") == 0)
            return luaL_error(target, "C++");
        else if (strcmp(instruction, "tobool") == 0)
            lua_pushboolean(target, lua_toboolean(target,
                index_operand(L, target, &pc)));
        else if (strcmp(instruction, "tocfunction") == 0)
            lua_pushcfunction(target, lua_tocfunction(target,
                index_operand(L, target, &pc)));
        else if (strcmp(instruction, "tointeger") == 0)
            lua_pushinteger(target, lua_tointeger(target,
                index_operand(L, target, &pc)));
        else if (strcmp(instruction, "tonumber") == 0)
            lua_pushnumber(target, lua_tonumber(target,
                index_operand(L, target, &pc)));
        else if (strcmp(instruction, "topointer") == 0)
            lua_pushlightuserdata(target, (void *)lua_topointer(target,
                index_operand(L, target, &pc)));
        else if (strcmp(instruction, "touserdata") == 0)
            lua_pushlightuserdata(target, lua_touserdata(target,
                index_operand(L, target, &pc)));
        else if (strcmp(instruction, "tostring") == 0) {
            const char *text = lua_tostring(target,
                index_operand(L, target, &pc));
            const char *copy = lua_pushstring(target, text);
            assert((text == NULL && copy == NULL) || strcmp(text, copy) == 0);
        } else if (strcmp(instruction, "Ltolstring") == 0)
            luaL_tolstring(target, index_operand(L, target, &pc), NULL);
        else if (strcmp(instruction, "type") == 0)
            lua_pushstring(target, luaL_typename(target,
                number(L, target, &pc)));
        else if (strcmp(instruction, "argerror") == 0) {
            int index = number(L, target, &pc);
            return luaL_argerror(target, index,
                token(L, argument, sizeof(argument), &pc));
        } else if (strcmp(instruction, "closeslot") == 0)
            lua_closeslot(target, number(L, target, &pc));
        else if (strcmp(instruction, "pushint") == 0)
            lua_pushinteger(target, number(L, target, &pc));
        else if (strcmp(instruction, "pushnum") == 0)
            lua_pushnumber(target, (lua_Number)number(L, target, &pc));
        else if (strcmp(instruction, "pushstring") == 0)
            lua_pushstring(target, token(L, argument, sizeof(argument), &pc));
        else if (strcmp(instruction, "pushvalue") == 0)
            lua_pushvalue(target, index_operand(L, target, &pc));
        else if (strcmp(instruction, "pushupvalueindex") == 0) {
            int upvalue = number(L, target, &pc);
            if (upvalue < 0 || upvalue > 256)
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

static void set_hook_script(lua_State *L, int mask, int count,
                             const char *script) {
    if (script[0] == '\0') { lua_sethook(L, NULL, 0, 0); return; }
    lua_getfield(L, LUA_REGISTRYINDEX, "C_HOOK");
    if (!lua_istable(L, -1)) {
        lua_pop(L, 1);
        lua_newtable(L);
        lua_pushvalue(L, -1);
        lua_setfield(L, LUA_REGISTRYINDEX, "C_HOOK");
    }
    lua_pushlightuserdata(L, L);
    lua_pushstring(L, script);
    lua_settable(L, -3);
    lua_sethook(L, command_hook, mask, count);
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
    set_hook_script(L, mask, count, script);
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

/* Copy only genuine callback/pointer scalars between independent worlds;
 * lua_xmove would be invalid across universes. The controlling test provider
 * remains the inherited one, while normal Lua values keep separate owners. */
static void copy_allocation_control(lua_State *L, lua_State *other) {
    lua_CFunction control;
    void *owner;
    lua_getfield(L, LUA_REGISTRYINDEX, LUA_ADA_T_COUNT_KEY);
    control = lua_tocfunction(L, -1);
    lua_pop(L, 1);
    if (control == NULL) return;
    lua_pushcfunction(other, control);
    lua_setfield(other, LUA_REGISTRYINDEX, LUA_ADA_T_COUNT_KEY);
    lua_getfield(L, LUA_REGISTRYINDEX, LUA_ADA_T_OWNER_KEY);
    owner = lua_touserdata(L, -1);
    lua_pop(L, 1);
    lua_pushlightuserdata(other, owner);
    lua_setfield(other, LUA_REGISTRYINDEX, LUA_ADA_T_OWNER_KEY);
}

struct panic_context {
    jmp_buf jump;
    lua_State *caller;
    const char *panic_code;
    const char *result;
};

static int panic_setup(lua_State *L) {
    lua_pushvalue(L, 1);
    lua_setfield(L, LUA_REGISTRYINDEX, "_jmpbuf");
    return 0;
}

static int panic_back(lua_State *L) {
    struct panic_context *context;
    luaL_checkstack(L, 1, "panic context");
    lua_getfield(L, LUA_REGISTRYINDEX, "_jmpbuf");
    context = (struct panic_context *)lua_touserdata(L, -1);
    lua_pop(L, 1);
    assert(context != NULL);
    (void)run_commands(context->caller, L, context->panic_code);
    /* Every exported operation and every Ada dispatch has returned. This
     * jump targets only the actual live C check_panic frame below it. */
    longjmp(context->jump, 1);
    return 0;
}

static int copy_panic_result(lua_State *L) {
    struct panic_context *context =
        (struct panic_context *)lua_touserdata(L, 1);
    lua_pushstring(L, context->result);
    return 1;
}

static int check_panic(lua_State *L) {
    struct panic_context context;
    void *data;
    lua_Alloc allocator;
    lua_State *other;
    const char *code = luaL_checkstring(L, 1);
    int status;
    context.caller = L;
    context.panic_code = luaL_optstring(L, 2, "");
    allocator = lua_getallocf(L, &data);
    other = lua_newstate(allocator, data, 0);
    if (other == NULL) {
        lua_pushliteral(L, "not enough memory");
        return 1;
    }
    /* Register the real C context under an ordinary protected call before
     * installing panic. Unlike the source's unguarded setup, refusal here
     * cannot jump through an uninitialized jmp_buf or strand the new state. */
    lua_pushcfunction(other, panic_setup);
    lua_pushlightuserdata(other, &context);
    status = lua_pcall(other, 1, 0, 0);
    if (status == LUA_OK) {
        lua_atpanic(other, panic_back);
        if (setjmp(context.jump) == 0) {
            (void)run_commands(L, other, code);
            context.result = "no errors";
        } else context.result = lua_tostring(other, -1);
    } else context.result = lua_tostring(other, -1);
    /* The borrowed child string stays alive until this protected publication
     * finishes. Release the child even if parent result creation refuses,
     * then propagate the parent's actual error through its original guard. */
    lua_pushcfunction(L, copy_panic_result);
    lua_pushlightuserdata(L, &context);
    status = lua_pcall(L, 1, 1, 0);
    lua_close(other);
    if (status != LUA_OK) return lua_error(L);
    return 1;
}

/* These helpers retain ltests.c's public API behavior. memcpy implements the
 * byte probe without the source's potentially unaligned double dereference;
 * the bytes still come from an actual host double and an actual Lua string. */
static int double_to_string(lua_State *L) {
    double value = (double)luaL_checknumber(L, 1);
    lua_pushlstring(L, (const char *)&value, sizeof(value));
    return 1;
}

static int string_to_double(lua_State *L) {
    size_t length;
    const char *bytes = luaL_checklstring(L, 1, &length);
    double value;
    if (length < sizeof(value))
        return luaL_argerror(L, 1, "double byte string is too short");
    memcpy(&value, bytes, sizeof(value));
    lua_pushnumber(L, (lua_Number)value);
    return 1;
}

static int push_userdata_address(lua_State *L) {
    lua_pushlightuserdata(L, (void *)(uintptr_t)luaL_checkinteger(L, 1));
    return 1;
}

static int userdata_address(lua_State *L) {
    lua_pushinteger(L, (lua_Integer)(uintptr_t)lua_touserdata(L, 1));
    return 1;
}

static int reference_table(lua_State *L) {
    return lua_istable(L, 2) ? 2 : LUA_REGISTRYINDEX;
}

static int create_reference(lua_State *L) {
    int table = reference_table(L), level = lua_gettop(L);
    luaL_checkany(L, 1);
    lua_pushvalue(L, 1);
    lua_pushinteger(L, luaL_ref(L, table));
    assert(lua_gettop(L) == level + 1);
    return 1;
}

static int get_reference(lua_State *L) {
    int table = reference_table(L), level = lua_gettop(L);
    lua_rawgeti(L, table, luaL_checkinteger(L, 1));
    assert(lua_gettop(L) == level + 1);
    return 1;
}

static int release_reference(lua_State *L) {
    int table = reference_table(L), level = lua_gettop(L);
    luaL_unref(L, table, (int)luaL_checkinteger(L, 1));
    assert(lua_gettop(L) == level);
    return 0;
}

static int inspect_upvalue(lua_State *L) {
    int index = (int)luaL_checkinteger(L, 2);
    const char *name;
    luaL_checktype(L, 1, LUA_TFUNCTION);
    if (lua_isnone(L, 3)) {
        name = lua_getupvalue(L, 1, index);
        if (name == NULL) return 0;
        lua_pushstring(L, name);
        return 2;
    }
    name = lua_setupvalue(L, 1, index);
    lua_pushstring(L, name);
    return 1;
}

static int run_new_stack(lua_State *L) {
    lua_State *thread = lua_newthread(L);
    size_t length;
    const char *source = luaL_checklstring(L, 1, &length);
    int status = luaL_loadbufferx(thread, source, length, source, "t");
    if (status == LUA_OK) status = lua_pcall(thread, 0, 0, 0);
    lua_pushinteger(L, status);
    return 1;
}

static int external_string(lua_State *L) {
    size_t length;
    const char *source = luaL_checklstring(L, 1, &length);
    void *data;
    lua_Alloc allocator = lua_getallocf(L, &data);
    char *buffer;
    if (length == SIZE_MAX) return fail(L, "external string size overflow");
    buffer = (char *)allocator(data, NULL, 0, length + 1);
    if (buffer == NULL) return fail(L, "not enough memory");
    memcpy(buffer, source, length + 1);
    /* Ownership transfers even if header creation fails; the public API
     * calls the original allocator exactly once. There is no shadow buffer. */
    lua_pushexternalstring(L, buffer, length, allocator, data);
    return 1;
}

static int open_api(lua_State *L) {
    static const char *const names[] = {"testC", "makeCfunc", "sethook",
        "resume", "newstate", "loadlib", "doremote", "closestate",
        "d2s", "s2d", "pushuserdata", "udataval", "ref", "getref",
        "unref", "upvalue", "doonnewstack", "externstr", "checkpanic"};
    unsigned i;
    lua_newtable(L);
    for (i = 0; i < sizeof(names) / sizeof(names[0]); ++i) {
        lua_pushcfunction(L, lua_ada_test_api_callback(17 + (int)i));
        lua_setfield(L, -2, names[i]);
    }
    return 1;
}

static int load_libraries(lua_State *L) {
    lua_State *other = state_argument(L);
    copy_allocation_control(L, other);
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
        close_state, double_to_string, string_to_double, push_userdata_address,
        userdata_address, create_reference, get_reference, release_reference,
        inspect_upvalue, run_new_stack, external_string, check_panic};
    if (operation < 17 || operation > 35) return NULL;
    return callbacks[operation - 17];
}
