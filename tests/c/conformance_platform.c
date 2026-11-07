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
#include <windows.h>
#include <io.h>
#include <stdint.h>
#else
#include <unistd.h>
#endif

static luaL_Stream *checked_stream(lua_State *L, int index) {
    luaL_Stream *stream;
    int matched;
    if (lua_type(L, index) != LUA_TUSERDATA ||
        lua_rawlen(L, index) < sizeof(luaL_Stream) ||
        !lua_getmetatable(L, index)) {
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
    stream = (luaL_Stream *)lua_touserdata(L, index);
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
    luaL_Stream *stream = checked_stream(L, 1);
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
    luaL_Stream *stream = checked_stream(L, 1);
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

/* A real byte-mode, nonblocking Windows pipe. Both endpoints replace only
 * descriptors in caller-owned fresh files; neither FILE/closer nor Ada's
 * ownership metadata is replaced. No Lua allocation occurs until all new
 * handles are owned by the existing files or closed on failure. */
static int nonblocking_pair(lua_State *L) {
    luaL_Stream *writer = checked_stream(L, 1);
    luaL_Stream *reader = checked_stream(L, 2);
    static volatile LONG serial = 0;
    HANDLE write_handle = INVALID_HANDLE_VALUE;
    HANDLE read_handle = INVALID_HANDLE_VALUE;
    int write_fd = -1, read_fd = -1;
    const char *failure = NULL;
    char name[128];
    if (writer == reader || writer->f == reader->f) {
        lua_pushliteral(L, "distinct file handles expected");
        return lua_error(L);
    }
    (void)snprintf(name, sizeof name, "\\\\.\\pipe\\lua-ada-test-%lu-%ld",
        (unsigned long)GetCurrentProcessId(),
        (long)InterlockedIncrement(&serial));
    write_handle = CreateNamedPipeA(name,
        PIPE_ACCESS_OUTBOUND | FILE_FLAG_FIRST_PIPE_INSTANCE,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_NOWAIT,
        1, 65536, 0, 0, NULL);
    if (write_handle == INVALID_HANDLE_VALUE) {
        failure = "cannot create nonblocking pipe"; goto cleanup;
    }
    /* PIPE_NOWAIT enters listening state without waiting for the reader. */
    (void)ConnectNamedPipe(write_handle, NULL);
    read_handle = CreateFileA(name, GENERIC_READ, 0, NULL,
                              OPEN_EXISTING, 0, NULL);
    if (read_handle == INVALID_HANDLE_VALUE) {
        failure = "cannot connect pipe reader"; goto cleanup;
    }
    write_fd = _open_osfhandle((intptr_t)write_handle, _O_WRONLY | _O_BINARY);
    if (write_fd < 0) { failure = "cannot adopt pipe writer"; goto cleanup; }
    write_handle = INVALID_HANDLE_VALUE; /* descriptor now owns the handle */
    read_fd = _open_osfhandle((intptr_t)read_handle, _O_RDONLY | _O_BINARY);
    if (read_fd < 0) { failure = "cannot adopt pipe reader"; goto cleanup; }
    read_handle = INVALID_HANDLE_VALUE;
    if (_dup2(write_fd, _fileno(writer->f)) != 0 ||
        _dup2(read_fd, _fileno(reader->f)) != 0)
        failure = "cannot publish pipe descriptors";
cleanup:
    if (write_fd >= 0) _close(write_fd);
    if (read_fd >= 0) _close(read_fd);
    if (write_handle != INVALID_HANDLE_VALUE) CloseHandle(write_handle);
    if (read_handle != INVALID_HANDLE_VALUE) CloseHandle(read_handle);
    if (failure != NULL) {
        lua_pushstring(L, failure);
        return lua_error(L);
    }
    lua_pushvalue(L, 1);
    lua_pushvalue(L, 2);
    return 2;
}
#endif

#if defined(__APPLE__)
/* macOS has no usable /dev/full. A read-only native null descriptor published
 * into a fresh writable FILE preserves the buffering/flush failure sequence
 * without SIGPIPE or process-wide signal changes. Keep the original FILE,
 * closer and Ada ownership metadata; close the temporary descriptor before
 * any Lua operation can allocate or transfer control. */
static int failing_stream(lua_State *L) {
    luaL_Stream *stream = checked_stream(L, 1);
    int descriptor = open("/dev/null", O_RDONLY);
    int status, error;
    if (descriptor < 0) {
        lua_pushstring(L, strerror(errno));
        return lua_error(L);
    }
    status = dup2(descriptor, fileno(stream->f));
    error = errno;
    close(descriptor);
    if (status < 0) {
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
    if (operation == 15) return failing_stream;
    return operation == 16 ? nonblocking_pair : NULL;
#else
#if defined(__APPLE__)
    if (operation == 15) return failing_stream;
#endif
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
    lua_pushcfunction(L, nonblocking_pair);
    lua_setfield(L, -2, "nonblocking_pair");
#else
    lua_pushcfunction(L, nonblock);
    lua_setfield(L, -2, "nonblock");
#if defined(__APPLE__)
    lua_pushcfunction(L, failing_stream);
    lua_setfield(L, -2, "failing_stream");
#endif
#endif
    return 1;
}
#endif
