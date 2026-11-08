/* Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE.
 * Public auxiliary C-string composition, using the owned Ada buffer API.
 * This is literal substitution, with no Lua grammar, pattern VM or value
 * representation here. Pinned lauxlib.c supplies the contract: leftmost
 * nonoverlapping matches, replacement bytes never rescanned, and C-string
 * termination for all three input pointers. No reference object is linked.
 */
#include <stddef.h>
#include "lua_ada_runtime_configuration.h"
#include "lauxlib.h"

extern void lua_ada_aux_charge(lua_State *L, size_t amount);

static size_t text_length(lua_State *L, const char *text) {
    size_t size = 0;
    while (text[size] != '\0') {
        ++size;
        if (size % 4096 == 0) lua_ada_aux_charge(L, 4096);
    }
    lua_ada_aux_charge(L, size % 4096);
    return size;
}

void luaL_addgsub(luaL_Buffer *buffer, const char *subject,
                  const char *pattern, const char *replacement) {
    lua_State *L = buffer->L;
    const size_t size = text_length(L, subject);
    const size_t pattern_size = text_length(L, pattern);
    const size_t replacement_size = text_length(L, replacement);
    size_t start = 0, cursor = 0, work = 0;

    /* Keep only scalar offsets into the caller-owned C strings. The public
     * buffer owns every growing output byte and registers its own closer;
     * refusal, errors and host abort use that existing ownership mechanism.
     * Compare bounded prefixes directly rather than hiding unmetered work
     * in strstr/memcmp. A common-prefix adversary pays for actual comparisons.
     */
    while (pattern_size <= size - cursor) {
        size_t matched = 0;
        while (matched < pattern_size) {
            int equal = subject[cursor + matched] == pattern[matched];
            if (++work == 64) {
                lua_ada_aux_charge(L, work);
                work = 0;
            }
            if (!equal) break;
            ++matched;
        }
        if (matched == pattern_size) {
            lua_ada_aux_charge(L, work + 1);
            work = 0;
            luaL_addlstring(buffer, subject + start, cursor - start);
            luaL_addlstring(buffer, replacement, replacement_size);
            cursor += pattern_size;
            start = cursor;
            /* The pinned helper makes no progress for an empty pattern.
             * Retain that behavior; even an empty replacement charges each
             * iteration so a bounded Ada session keeps its execution policy.
             */
        }
        else {
            if (cursor == size) break;
            ++cursor;
        }
        if (cursor == size && pattern_size != 0) break;
    }
    lua_ada_aux_charge(L, work);
    luaL_addlstring(buffer, subject + start, size - start);
}

const char *luaL_gsub(lua_State *L, const char *subject,
                      const char *pattern, const char *replacement) {
    luaL_Buffer buffer;
    luaL_buffinit(L, &buffer);
    luaL_addgsub(&buffer, subject, pattern, replacement);
    luaL_pushresult(&buffer);
    /* The returned pointer is borrowed from the actual result at stack top.
     * Its lifetime follows that rooted Lua string, as for lua_tolstring. */
    return lua_tostring(L, -1);
}
