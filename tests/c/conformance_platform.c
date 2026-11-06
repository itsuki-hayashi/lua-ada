/* First-party test-only native platform counterparts. This unit uses only
 * public Lua APIs and native descriptors, so the same driver can be linked
 * independently to the pinned C oracle and to the actual Ada runtime.
 * POSIX nonblock is derived from ltests.c:2154; see the extraction manifest. */
#if !defined(_WIN32)
#define _POSIX_C_SOURCE 200809L
#endif
#include "lua.h"
#include "lauxlib.h"
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <errno.h>
#if defined(_WIN32)
#include <io.h>
#else
#include <unistd.h>
#endif

static luaL_Stream *checked_stream(lua_State *L) {
    luaL_Stream *stream;
    int matched;
    if (lua_type(L, 1) != LUA_TUSERDATA ||
        lua_rawlen(L, 1) < sizeof(luaL_Stream) || !lua_getmetatable(L, 1)) {
        lua_pushliteral(L, "file handle expected");
        lua_error(L);
        return NULL;
    }
    lua_pushliteral(L, LUA_FILEHANDLE);
    lua_rawget(L, LUA_REGISTRYINDEX);
    matched = lua_rawequal(L, -1, -2);
    lua_pop(L, 2);
    if (!matched) {
        lua_pushliteral(L, "file handle expected");
        lua_error(L);
        return NULL;
    }
    stream = (luaL_Stream *)lua_touserdata(L, 1);
    if (stream->f == NULL || stream->closef == NULL) {
        lua_pushliteral(L, "closed file handle");
        lua_error(L);
        return NULL;
    }
    return stream;
}

#if !defined(_WIN32)
/* ltests.c:2154, using the public luaL_Stream payload and real descriptor.
 * Errors are checked rather than silently leaving the stream blocking. */
static int nonblock(lua_State *L) {
    luaL_Stream *stream = checked_stream(L);
    int descriptor, flags;
    descriptor = fileno(stream->f);
    flags = fcntl(descriptor, F_GETFL, 0);
    if (flags < 0 || fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) < 0) {
        lua_pushstring(L, strerror(errno));
        return lua_error(L);
    }
    return 0;
}
#else
/* Native Windows counterpart for /dev/full's buffered write/failed flush
 * sequence. Replace the descriptor, not the FILE pointer: the original public
 * closer and Ada ownership metadata remain authoritative, including abort
 * cleanup. The caller supplies a fresh ordinary temporary file. No Lua call
 * occurs while an unowned pipe descriptor is live. */
static int failing_stream(lua_State *L) {
    luaL_Stream *stream = checked_stream(L);
    int descriptors[2], status, error;
    if (_pipe(descriptors, 4096, _O_BINARY) != 0) {
        lua_pushstring(L, strerror(errno));
        return lua_error(L);
    }
    _close(descriptors[0]);
    status = _dup2(descriptors[1], _fileno(stream->f));
    error = errno;
    _close(descriptors[1]);
    if (status != 0) {
        lua_pushstring(L, strerror(error));
        return lua_error(L);
    }
    if (setvbuf(stream->f, NULL, _IOFBF, 4096) != 0) {
        lua_pushliteral(L, "cannot buffer failure stream");
        return lua_error(L);
    }
    lua_pushvalue(L, 1);
    return 1;
}
#endif

lua_CFunction lua_ada_test_platform_callback(int operation) {
#if defined(_WIN32)
    return operation == 15 ? failing_stream : NULL;
#else
    return operation == 14 ? nonblock : NULL;
#endif
}

/* Only the independently built oracle module exports a loader. The ordinary
 * test crate calls the same driver through its guarded native dispatcher. */
#if defined(LUA_ADA_PLATFORM_MODULE)
#if defined(_WIN32)
__declspec(dllexport)
#endif
int luaopen_conformance_platform(lua_State *L) {
    lua_createtable(L, 0, 1);
#if defined(_WIN32)
    lua_pushcfunction(L, failing_stream);
    lua_setfield(L, -2, "failing_stream");
#else
    lua_pushcfunction(L, nonblock);
    lua_setfield(L, -2, "nonblock");
#endif
    return 1;
}
#endif
