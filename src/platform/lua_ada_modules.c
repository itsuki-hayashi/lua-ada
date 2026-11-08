/* Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE.
** lua_ada_modules.c -- operating-system loader glue for native Lua modules.
**
** This file is OS mechanics only: open and close a shared library, resolve
** one symbol, report the public default search strings, and find the
** executable's directory on Windows. It does not search package paths,
** substitute LUA_EXEC_DIR, build module names, or call into Lua. The Ada
** loader owns all of that policy.
**
** Platform selection: Windows (_WIN32) uses LoadLibraryExA, GetProcAddress
** and FreeLibrary. Every other target uses the POSIX dlfcn interface.
** Lua's own LUA_USE_DLOPEN and LUA_DL_DLL switches are deliberately not
** consulted, so the platform choice depends only on the compiler target.
**
** Error contract shared by every platform:
**   - *error is set to NULL on entry and on success.
**   - a NULL return reports the platform's failure text. POSIX permits a
**     null diagnostic for a zero-address symbol; that becomes Lua nil.
**   - the text lives in error_buffer on Windows and in the loader's
**     thread-local storage on POSIX. Either way it is valid only until the
**     caller reuses that storage or makes another loader call.
**
** Compilation contract: C99 with -Wall -Wextra -Werror -pedantic. The file
** uses no dynamic allocation and no mutable file-scope state. It is not
** exposed through a header; the Ada imports in lua-platform_modules.ads are
** the ABI declaration.
*/

#if !defined(_WIN32) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#include <stddef.h>
#include <string.h>

/* luaconf.h is the installed public header that defines LUA_PATH_DEFAULT and
** LUA_CPATH_DEFAULT. The defaults are read from it, never copied here. */
#include "lua.h"


/*
** Copies a native function address into a void * carrier.
**
** ISO C forbids converting between function pointers and object pointers,
** so the loader's function address is never cast. Instead its bytes are
** copied with memcpy into an object of the carrier's type. The copy is
** allowed only when both objects have the same size; otherwise the bytes
** would be truncated or read past the source.
*/
static void *carrier_from_bytes (const void *bytes, size_t size,
                                 const char **error) {
  void *carrier = NULL;
  if (size != sizeof carrier) {
    /* A fixed literal has static storage, so it outlives this call. */
    *error = "function pointer size mismatch";
    return NULL;
  }
  memcpy(&carrier, bytes, sizeof carrier);
  return carrier;
}


#if defined(_WIN32)  /* { */

#define WIN32_LEAN_AND_MEAN
#include <stdio.h>
#include <windows.h>

/* Capacity of the caller's error buffer. It matches the 128-byte storage that
** pinned Lua's pusherror uses, and the Ada side declares the same size. */
#define LUA_ADA_MODULES_ERROR_SIZE 128

/* Flags for LoadLibraryExA. Pinned loadlib.c defaults LUA_LLE_FLAGS to 0,
** so the library uses the normal search order with no LOAD_* flags. */
#define LUA_ADA_MODULES_LLE_FLAGS 0


/*
** Translates the thread's most recent Win32 failure into the caller's buffer.
**
** GetLastError must be read first, before any other call, because another
** API call may overwrite the code. FormatMessageA writes at most
** LUA_ADA_MODULES_ERROR_SIZE characters, including the terminator. If it
** cannot produce text, the code is printed as "system error %d" followed by
** a newline, which matches pinned Lua's fallback.
*/
static void windows_error (char error_buffer[LUA_ADA_MODULES_ERROR_SIZE],
                           const char **error) {
  DWORD code = GetLastError();
  DWORD n = FormatMessageA(FORMAT_MESSAGE_IGNORE_INSERTS |
                           FORMAT_MESSAGE_FROM_SYSTEM,
                           NULL, code, 0, error_buffer,
                           LUA_ADA_MODULES_ERROR_SIZE, NULL);
  if (n == 0)  /* no message text: fall back to the numeric code */
    (void)snprintf(error_buffer, LUA_ADA_MODULES_ERROR_SIZE,
                   "system error %d\n", (int)code);
  *error = error_buffer;
}


void *lua_ada_modules_open (const char *path, int global,
                            char error_buffer[LUA_ADA_MODULES_ERROR_SIZE],
                            const char **error) {
  HMODULE lib;
  (void)global;  /* Windows symbols are process-wide, so the flag is unused */
  *error = NULL;
  if (path == NULL) {
    *error = "missing library path";
    return NULL;
  }
  /* The handle is an HMODULE; it is returned as an opaque object pointer. */
  lib = LoadLibraryExA(path, NULL, LUA_ADA_MODULES_LLE_FLAGS);
  if (lib == NULL) {
    windows_error(error_buffer, error);
    return NULL;
  }
  return (void *)lib;
}


void *lua_ada_modules_symbol (void *handle, const char *name,
                              char error_buffer[LUA_ADA_MODULES_ERROR_SIZE],
                              const char **error) {
  FARPROC proc;
  *error = NULL;
  if (handle == NULL || name == NULL) {
    *error = "missing library or symbol";
    return NULL;
  }
  proc = GetProcAddress((HMODULE)handle, name);
  if (proc == NULL) {
    windows_error(error_buffer, error);
    return NULL;
  }
  /* Copy the FARPROC's bytes into a void * carrier. Its size is checked. */
  return carrier_from_bytes(&proc, sizeof proc, error);
}


void lua_ada_modules_close (void *handle) {
  if (handle != NULL)
    (void)FreeLibrary((HMODULE)handle);
}

void *lua_ada_modules_keep_code (void *address) {
  HMODULE module = NULL;
  /* A selected allocator can itself be code in a loaded module. Hold that
  ** one image while releasing the cache's last provider-owned records. */
  if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
                        (LPCSTR)address, &module))
    return (void *)module;
  return NULL;
}


int lua_ada_modules_program_directory (char *buffer, size_t capacity) {
  DWORD n;
  char *sep;
  /* Reject capacities that cannot be passed to GetModuleFileNameA as DWORD. */
  if (buffer == NULL || capacity == 0 || capacity > (size_t)MAXDWORD)
    return 0;
  n = GetModuleFileNameA(NULL, buffer, (DWORD)capacity);
  /* n == 0 is failure. n >= capacity means the path was truncated, so it is
  ** not trustworthy either. Both return 0 and leave the buffer unspecified. */
  if (n == 0 || (size_t)n >= capacity)
    return 0;
  /* Keep the directory: cut the path at its final backslash. */
  sep = strrchr(buffer, '\\');
  if (sep == NULL)
    return 0;
  *sep = '\0';
  return 1;
}


#else  /* }{ POSIX */

#include <dlfcn.h>


/*
** Copies the loader's most recent failure text into *error.
**
** dlerror() returns text owned by the loader, valid only until the next dl*
** call on this thread. The caller reads it at once and does not keep it.
** Preserve NULL too: pinned pusherror uses lua_pushstring(dlerror()), and
** therefore exposes nil for a zero-address symbol with no loader error.
*/
static void posix_error (const char **error) {
  *error = dlerror();
}


void *lua_ada_modules_open (const char *path, int global,
                            char error_buffer[128], const char **error) {
  int mode = RTLD_NOW | (global ? RTLD_GLOBAL : RTLD_LOCAL);
  void *lib;
  (void)error_buffer;  /* POSIX returns loader text, so this is not used */
  *error = NULL;
  if (path == NULL) {
    *error = "missing library path";
    return NULL;
  }
  /* Clear stale loader text, so a failure reports only this call's error. */
  (void)dlerror();
  lib = dlopen(path, mode);
  if (lib == NULL)
    posix_error(error);
  return lib;
}


void *lua_ada_modules_symbol (void *handle, const char *name,
                              char error_buffer[128], const char **error) {
  void *sym;
  (void)error_buffer;  /* POSIX returns loader text, so this is not used */
  *error = NULL;
  if (handle == NULL || name == NULL) {
    *error = "missing library or symbol";
    return NULL;
  }
  /* A symbol whose address is NULL is an error only if dlerror reports one,
  ** so the stale text is cleared before the lookup. */
  (void)dlerror();
  sym = dlsym(handle, name);
  if (sym == NULL) {
    posix_error(error);
    return NULL;
  }
  /* The address is already an object pointer here. Its copy is still checked
  ** against the carrier size, so both platforms share one validation path. */
  return carrier_from_bytes(&sym, sizeof sym, error);
}


void lua_ada_modules_close (void *handle) {
  if (handle != NULL)
    (void)dlclose(handle);
}

void *lua_ada_modules_keep_code (void *address) {
  Dl_info info;
  if (dladdr(address, &info) != 0 && info.dli_fname != NULL)
    return dlopen(info.dli_fname, RTLD_NOW | RTLD_LOCAL | RTLD_NOLOAD);
  /* Main-executable code cannot be unloaded by a module cache. Some
  ** loaders refuse dlopen on an executable; no extra hold is needed there. */
  return NULL;
}


int lua_ada_modules_program_directory (char *buffer, size_t capacity) {
  /* POSIX has no LUA_EXEC_DIR expansion, so no directory is reported. The
  ** buffer is left untouched and the result is always 0. */
  (void)buffer;
  (void)capacity;
  return 0;
}

#endif  /* } */


/*
** Default search strings. These come from the installed luaconf.h, so they
** follow the same configuration as the rest of the interpreter build. They
** are unexpanded: ';;' and LUA_EXEC_DIR are left for the Ada loader's policy.
** Each returns static storage that the caller must not modify or free.
*/
const char *lua_ada_modules_default_path (void) {
  return LUA_PATH_DEFAULT;
}


const char *lua_ada_modules_default_cpath (void) {
  return LUA_CPATH_DEFAULT;
}
