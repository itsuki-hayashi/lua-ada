/* C varargs are consumed here; formatting storage, numbers and UTF-8 remain
 * Ada-owned. The raw C guard distinguishes nonthrowing va_list formatting
 * from its throwing variadic counterpart. No reference VM is linked.
 * Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE. */
#include "lua_ada_boundary.h"
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

struct format_call {
    const char *format;
    va_list arguments;
    void *temporary;
    const char *result;
};

static struct lua_ada_response format_request(lua_State *L,
        enum lua_ada_operation operation, void *temporary,
        const char *bytes, size_t length, int kind,
        lua_Integer integer, lua_Number number) {
    struct lua_ada_request input;
    struct lua_ada_response output;
    memset(&input, 0, sizeof input);
    memset(&output, 0, sizeof output);
    input.operation = operation;
    input.pointer = temporary;
    input.name = bytes;
    input.length = length;
    input.count = kind;
    input.integer_data = integer;
    input.number_data = number;
    lua_ada_debug_dispatch(L, &input, &output);
    return output;
}

void lua_ada_aux_charge(lua_State *L, size_t amount) {
    (void)format_request(L, ADA_CHARGE_AUX_WORK, NULL, NULL, amount, 0, 0, 0);
}

static void append_bytes(lua_State *L, struct format_call *call,
                         const char *bytes, size_t length) {
    (void)format_request(L, ADA_APPEND_FORMAT_VALUE, call->temporary,
                        bytes, length, 0, 0, 0);
}

static size_t span_to(lua_State *L, const char *text, char delimiter) {
    size_t length = 0;
    /* Foreign text has no counted length. Charge bounded scanning blocks
     * before moving farther, so a long C string cannot bypass the owning
     * session's work policy merely by deferring its first buffer append. */
    while (text[length] != '\0' && text[length] != delimiter) {
        ++length;
        if (length % 4096 == 0) lua_ada_aux_charge(L, 4096);
    }
    return length;
}

static void format_body(lua_State *L, void *opaque) {
    struct format_call *call = (struct format_call *)opaque;
    const char *cursor = call->format;
    size_t length;
    call->temporary = format_request(L, ADA_CREATE_FORMATTER,
                                    NULL, NULL, 0, 0, 0, 0).pointer;
    /* The only persistent temporary is the selected owner's buffer. No Lua
     * arguments, call frames or stack slots are added while consuming varargs.
     * Each source span/scalar charges shared work in its Ada operation. */
    for (;;) {
        const char *percent;
        length = span_to(L, cursor, '%');
        append_bytes(L, call, cursor, length);
        if (cursor[length] == '\0') break;
        percent = cursor + length;
        char specifier = percent[1];
        lua_ada_aux_charge(L, 2);
        switch (specifier) {
        case 's': {
            const char *text = va_arg(call->arguments, const char *);
            if (text == NULL) text = "(null)";
            append_bytes(L, call, text, span_to(L, text, '\0'));
            break;
        }
        case 'c': {
            char byte = (char)va_arg(call->arguments, int);
            append_bytes(L, call, &byte, 1);
            break;
        }
        case 'd':
            (void)format_request(L, ADA_APPEND_FORMAT_VALUE, call->temporary,
                NULL, 0, 1, (lua_Integer)va_arg(call->arguments, int), 0);
            break;
        case 'I':
            (void)format_request(L, ADA_APPEND_FORMAT_VALUE, call->temporary,
                NULL, 0, 1, va_arg(call->arguments, lua_Integer), 0);
            break;
        case 'f':
            (void)format_request(L, ADA_APPEND_FORMAT_VALUE, call->temporary,
                NULL, 0, 2, 0, (lua_Number)va_arg(call->arguments, double));
            break;
        case 'p': {
            char text[2 * sizeof(void *) + 8];
            int written = snprintf(text, sizeof text, "%p",
                                   va_arg(call->arguments, void *));
            if (written < 0 || (size_t)written >= sizeof text) {
                lua_ada_propagate_status(L, ADA_ACTION_ABORT);
            }
            append_bytes(L, call, text, (size_t)written);
            break;
        }
        case 'U':
            (void)format_request(L, ADA_APPEND_FORMAT_UTF8, call->temporary,
                NULL, 0, 0,
                (lua_Integer)(uint32_t)va_arg(call->arguments, unsigned long),
                0);
            break;
        case '%':
            append_bytes(L, call, "%", 1);
            break;
        default:
            /* Lua 5.5 keeps an unknown conversion verbatim and consumes no
             * argument. A terminal '%' also keeps its NUL byte; do not read
             * beyond the counted C format after that terminator. */
            append_bytes(L, call, percent, 2);
            break;
        }
        if (specifier == '\0') {
            cursor = percent + 1;
            break;
        }
        cursor = percent + 2;
    }
    call->result = format_request(L, ADA_FINISH_FORMATTER,
                                  call->temporary, NULL, 0, 0, 0, 0).pointer;
}

static const char *execute_format(lua_State *L, const char *format,
                                 va_list args, int raise_memory, int *failure) {
    struct format_call call;
    int status;
    int top = lua_gettop(L);
    memset(&call, 0, sizeof call);
    call.format = format;
    va_copy(call.arguments, args);
    status = lua_ada_run_protected(L, format_body, &call);
    va_end(call.arguments);
    /* Cleanup follows every status, including refusal before construction.
     * Pinned clearbuff catches memory failure without setting an error slot;
     * retain that measured stack behavior for the nonthrowing va_list API.
     * The variadic API forwards the genuine refusal to its surrounding guard. */
    (void)format_request(L, ADA_RELEASE_FORMATTER, call.temporary,
                        NULL, 0, status == LUA_ERRMEM && !raise_memory, top, 0);
    *failure = status;
    if (status != LUA_OK) return NULL;
    return call.result;
}

const char *lua_pushvfstring(lua_State *L, const char *format, va_list args) {
    int status;
    const char *result = execute_format(L, format, args, 0, &status);
    if (status != LUA_OK && status != LUA_ERRMEM)
        lua_ada_propagate_status(L, status);
    return result;
}

const char *lua_pushfstring(lua_State *L, const char *format, ...) {
    const char *result;
    va_list args;
    int status;
    va_start(args, format);
    result = execute_format(L, format, args, 1, &status);
    va_end(args);
    if (status != LUA_OK) lua_ada_propagate_status(L, status);
    return result;
}
