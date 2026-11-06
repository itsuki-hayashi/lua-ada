/* Test-only native descriptor observation. Save the witness while FILE is
 * valid, then inspect only the OS descriptor/HANDLE after Lua collection.
 * No freed FILE pointer or dead userdata payload is dereferenced. */
#if !defined(_WIN32)
#define _POSIX_C_SOURCE 200809L
#endif
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#if defined(_WIN32)
#include <io.h>
#include <windows.h>
#else
#include <fcntl.h>
#include <unistd.h>
#endif

void *lua_ada_test_file_witness(FILE *file) {
#if defined(_WIN32)
    return (void *)_get_osfhandle(_fileno(file));
#else
    return (void *)(intptr_t)fileno(file);
#endif
}

int lua_ada_test_file_is_open(void *witness) {
#if defined(_WIN32)
    DWORD flags;
    return GetHandleInformation((HANDLE)witness, &flags) != 0;
#else
    int result;
    errno = 0;
    result = fcntl((int)(intptr_t)witness, F_GETFD);
    return result != -1 || errno != EBADF;
#endif
}
