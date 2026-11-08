/* Host stdio mechanics for the Ada IO library. This unit performs no Lua
 * option parsing, value manipulation, callbacks or interpreter execution.
 * All buffers are synchronous borrowed ranges, and errno is captured before
 * returning to code that can allocate or run collector callbacks. */
#if !defined(_WIN32)
#define _POSIX_C_SOURCE 200809L
#endif

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#if !defined(_WIN32)
#include <sys/types.h>
#include <unistd.h>
#else
#include <fcntl.h>
#include <io.h>
#endif

size_t lua_ada_stream_pointer_text(FILE *file, char *bytes, size_t capacity) {
    int length = snprintf(bytes, capacity, "%p", (void *)file);
    if (length < 0 || (size_t)length >= capacity) return 0;
    return (size_t)length;
}

#if defined(_WIN32)
typedef long stream_offset;
#define stream_seek fseek
#define stream_tell ftell
#else
typedef off_t stream_offset;
#define stream_seek fseeko
#define stream_tell ftello
#endif

FILE *lua_ada_stream_standard(int which) {
    switch (which) {
    case 0: return stdin;
    case 1: return stdout;
    case 2: return stderr;
    default: return NULL;
    }
}

FILE *lua_ada_stream_open(const char *name, const char *mode, int *error) {
    FILE *file;
    errno = 0;
    file = fopen(name, mode);
    *error = errno;
    return file;
}

FILE *lua_ada_stream_temporary(int *error) {
    FILE *file;
    errno = 0;
    file = tmpfile();
    *error = errno;
    return file;
}

FILE *lua_ada_stream_pipe(const char *command, const char *mode, int *error) {
    FILE *file;
    errno = 0;
#if defined(_WIN32)
    file = _popen(command, mode);
#else
    /* Pinned POSIX Lua flushes all stdio output before creating the child.
     * This is a host stream operation; captured Ada output is separate. */
    (void)fflush(NULL);
    file = popen(command, mode);
#endif
    *error = errno;
    return file;
}

int lua_ada_stream_close(FILE *file, int *error) {
    int result;
    errno = 0;
    result = fclose(file);
    *error = errno;
    return result;
}

int lua_ada_stream_pclose(FILE *file, int *error) {
    int result;
    errno = 0;
#if defined(_WIN32)
    result = _pclose(file);
#else
    result = pclose(file);
#endif
    *error = errno;
    return result;
}

/* Select untranslated byte mode for a shared standard stream. Windows C
 * text mode would turn CRLF into LF and stop at Ctrl-Z, which is not
 * binary-safe for Lua source or precompiled chunks read from stdin. POSIX
 * streams are already byte streams. Returns zero on success. */
int lua_ada_stream_set_binary(FILE *file) {
#if defined(_WIN32)
    fflush(file);
    return _setmode(_fileno(file), _O_BINARY) == -1 ? -1 : 0;
#else
    (void)file;
    return 0;
#endif
}

/* Report whether a stream is attached to an interactive terminal; used only
 * to choose between batch stdin and the prompt loop. No bytes are consumed. */
int lua_ada_stream_is_terminal(FILE *file) {
#if defined(_WIN32)
    return _isatty(_fileno(file)) != 0;
#else
    return isatty(fileno(file)) != 0;
#endif
}

void lua_ada_stream_begin_read(FILE *file) {
    clearerr(file);
    errno = 0;
}

size_t lua_ada_stream_read(FILE *file, void *bytes, size_t count, int *error) {
    size_t result = count == 0 ? 0 : fread(bytes, 1, count, file);
    *error = errno;
    return result;
}

int lua_ada_stream_get(FILE *file, int *error) {
    int result = fgetc(file);
    *error = errno;
    return result;
}

void lua_ada_stream_unget(FILE *file, int byte) { (void)ungetc(byte, file); }
int lua_ada_stream_eof(FILE *file) { return feof(file); }
int lua_ada_stream_error(FILE *file) { return ferror(file); }
int lua_ada_stream_end_marker(void) { return EOF; }

size_t lua_ada_stream_write(FILE *file, const void *bytes, size_t count,
                            int *error) {
    size_t result;
    errno = 0;
    result = count == 0 ? 0 : fwrite(bytes, 1, count, file);
    *error = errno;
    return result;
}

int lua_ada_stream_flush(FILE *file, int *error) {
    int result;
    errno = 0;
    result = fflush(file);
    *error = errno;
    return result;
}

int lua_ada_stream_buffer(FILE *file, int mode, size_t size, int *error) {
    int native_mode;
    int result;
    switch (mode) {
    case 0: native_mode = _IONBF; break;
    case 1: native_mode = _IOFBF; break;
    case 2: native_mode = _IOLBF; break;
    default: *error = EINVAL; return -1;
    }
    errno = 0;
    result = setvbuf(file, NULL, native_mode, size);
    *error = errno;
    return result;
}

int lua_ada_stream_seek_bits(void) {
    return (int)(sizeof(stream_offset) * CHAR_BIT);
}

int lua_ada_stream_seek(FILE *file, long long offset, int origin, int *error) {
    static const int origins[] = {SEEK_SET, SEEK_CUR, SEEK_END};
    stream_offset narrowed = (stream_offset)offset;
    int result;
    /* Ada validates the exposed width as a Lua argument constraint. Keep a
     * defensive native check too; an accidental narrowing must never seek to
     * a different position silently through this foreign boundary. */
    if ((long long)narrowed != offset || origin < 0 || origin > 2) {
        *error = EINVAL;
        return -1;
    }
    errno = 0;
    result = stream_seek(file, narrowed, origins[origin]);
    *error = errno;
    return result;
}

long long lua_ada_stream_position(FILE *file) {
    return (long long)stream_tell(file);
}
