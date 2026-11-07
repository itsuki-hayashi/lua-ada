/* Public luaL_loadfilex/luaL_loadfile regressions for C99 consumers.
 * Copyright (c) 2026 Lua Ada contributors. MIT; see ../../LICENSE.
 *
 * Each case below is an independently named file-loading scenario run in its
 * own fresh counted_allocator state. The same source compiles as a standalone
 * C99 consumer (define nothing) or as the reusable bridge target behind
 * lua_ada_test_loadfile(), which is selected by defining
 * LUA_ADA_LOADFILE_CONTRACT_LIBRARY before including this file.
 *
 * Scope: only documented public functions are used: luaL_loadfilex,
 * luaL_loadfile (macro), luaL_loadstring, lua_dump, lua_getinfo, lua_pcall,
 * lua_call, lua_error and the basic stack/value accessors. The only
 * platform-specific glue is the process id used to make temporary names
 * process-unique (_getpid on Windows, getpid elsewhere); it is test-only.
 *
 * Files: every case creates real files in the current directory. Names are
 * relative and contain the process id plus a per-process serial, so repeated
 * or concurrent runs do not collide. Each file is written and closed before
 * it is loaded, and each file is removed before its case returns. Cases never
 * read stdin, because a blocking stdin read would hang the test.
 *
 * Expected messages: the status values and documented message formats come
 * from the pinned lauxlib.c and ldo.c. The missing-file message is computed at
 * run time from a failing fopen on the same host, not hard-coded.
 *
 * Allocation policy: the counted allocator is the only source of truth for
 * heap growth. Tests never assert exact allocation counts or capacities. The
 * only injected fault is a persistent growth refusal (consumer_allocator.h),
 * and an error is accepted as a memory failure only when the allocator
 * actually refused a growth during that call. */
#if !defined(_WIN32)
/* Expose POSIX getpid() under strict -std=c99; must precede every include. */
#define _POSIX_C_SOURCE 200809L
#endif
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <assert.h>
#include <errno.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(_WIN32)
#include <process.h>
#include <fcntl.h>
#include <io.h>
#else
#include <unistd.h>
#endif
#include "consumer_allocator.h"

#ifdef NDEBUG
#error "loadfile_api_contract.c relies on assert(); do not define NDEBUG"
#endif

/* Seed passed to lua_newstate; any value is valid, fixed for repeatability. */
#define LOADFILE_SEED 311U

/* Buffer for one temporary or missing-file name. Names are short so that
 * luaO_chunkid keeps the whole name in short_src (LUA_IDSIZE is 60). */
#define NAME_SIZE 96

/* Capacity for one binary dump; the scenarios here are far below this. */
#define DUMP_CAPACITY 4096

/* Message that the pinned Lua core uses for a refused memory request. */
#define NOMEM_MESSAGE "not enough memory"

/* Per-case allocator state. Each case resets it before lua_newstate. */
static struct allocation_counts counts;

/* Destination for lua_dump. The writer copies into this fixed buffer and
 * flags overflow instead of growing, so the test never allocates for dumps. */
struct dump_buffer {
    char bytes[DUMP_CAPACITY];
    size_t size;
    int overflow;
};

typedef void (*loadfile_case)(lua_State *L);

/* Return the process id used in temporary names. Test-only platform glue. */
static unsigned long process_id(void) {
#if defined(_WIN32)
    return (unsigned long)_getpid();
#else
    return (unsigned long)getpid();
#endif
}

/* Per-process serial, so two temporary names in one process never match. */
static unsigned long name_serial = 0;

/* Build a process-unique relative file name such as
 * "lua_ada_loadfile_<pid>_<serial>_<tag><ext>" in the current directory. */
static void make_name(char *name, const char *tag, const char *ext) {
    int n;
    name_serial++;
    n = snprintf(name, NAME_SIZE, "lua_ada_loadfile_%lu_%lu_%s%s",
                 process_id(), name_serial, tag, ext);
    assert(n > 0 && n < NAME_SIZE);
}

/* Write exactly 'size' bytes with binary mode, so no newline translation
 * changes the bytes that the public loader later sees. The FILE is closed
 * before this function returns. */
static void write_bytes(const char *name, const void *bytes, size_t size) {
    FILE *f = fopen(name, "wb");
    assert(f != NULL);
    if (size != 0) assert(fwrite(bytes, 1, size, f) == size);
    assert(fclose(f) == 0);
}

/* Write a NUL-terminated text, without its terminating NUL. */
static void write_text(const char *name, const char *text) {
    write_bytes(name, text, strlen(text));
}

/* Remove a file that the case created. Callers close every FILE first. */
static void remove_file(const char *name) {
    assert(remove(name) == 0);
}

/* Build the chunk name that luaL_loadfilex gives a file: "@<name>". */
static void chunk_source(char *buf, size_t size, const char *name) {
    int n = snprintf(buf, size, "@%s", name);
    assert(n > 0 && (size_t)n < size);
}

/* Assert that stack index 'idx' is exactly the string 'want'. */
static void check_top_string(lua_State *L, int idx, const char *want) {
    assert(lua_type(L, idx) == LUA_TSTRING);
    assert(strcmp(lua_tostring(L, idx), want) == 0);
}

/* Assert that the error at 'idx' is "<name>:<line>: <text>", the form that
 * the Lua core gives to a runtime or syntax error from a file. */
static void check_error_at(lua_State *L, int idx, const char *name,
                           int line, const char *text) {
    char want[NAME_SIZE + 96];
    int n;
    n = snprintf(want, sizeof want, "%s:%d: %s", name, line, text);
    assert(n > 0 && (size_t)n < sizeof want);
    check_top_string(L, idx, want);
}

/* Assert that the string at 'idx' starts with 'prefix'. */
static void check_prefix(lua_State *L, int idx, const char *prefix) {
    const char *got;
    assert(lua_type(L, idx) == LUA_TSTRING);
    got = lua_tostring(L, idx);
    assert(strncmp(got, prefix, strlen(prefix)) == 0);
}

/* Assert the debug source and short name of the function at 'idx'. The
 * function is copied first, because lua_getinfo with '>' pops its argument.
 * The caller's stack is left unchanged. */
static void check_source(lua_State *L, int idx, const char *source,
                         const char *short_src) {
    lua_Debug ar;
    lua_pushvalue(L, idx);
    assert(lua_getinfo(L, ">S", &ar) != 0);
    assert(strcmp(ar.source, source) == 0);
    assert(strcmp(ar.short_src, short_src) == 0);
}

/* Writer for lua_dump. A NULL terminal call (size 0) is acknowledged without
 * copying. Overflow is a writer failure, which lua_dump returns. */
static int dump_writer(lua_State *L, const void *bytes, size_t size,
                       void *data) {
    struct dump_buffer *dump = (struct dump_buffer *)data;
    (void)L;
    if (bytes == NULL) {
        assert(size == 0);
        return 0;
    }
    if (size > DUMP_CAPACITY - dump->size) {
        dump->overflow = 1;
        return 1;
    }
    memcpy(dump->bytes + dump->size, bytes, size);
    dump->size += size;
    return 0;
}

/* Dump the function at the top of the stack into 'dump', keeping it on the
 * stack. 'strip' is passed unchanged to lua_dump. */
static void dump_top(lua_State *L, int strip, struct dump_buffer *dump) {
    dump->size = 0;
    dump->overflow = 0;
    assert(lua_dump(L, dump_writer, dump, strip) == 0);
    assert(!dump->overflow && dump->size > 0);
}

/* The paired permanent-refusal oracle delivers this exact memory class. */
static void check_memory_error(lua_State *L, int status) {
    assert(status == LUA_ERRMEM);
    assert(lua_type(L, -1) == LUA_TSTRING);
    assert(strcmp(lua_tostring(L, -1), NOMEM_MESSAGE) == 0);
}

/* C function used for protected loading. It loads the file named by its
 * first argument and calls the chunk, returning the chunk's single result.
 * A load failure is re-raised, so the caller's protected call sees it. */
static int protected_loader(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    if (luaL_loadfilex(L, name, NULL) != LUA_OK) return lua_error(L);
    lua_call(L, 0, 1);
    return 1;
}

static int refusing_loader(lua_State *L) {
    /* Exclude outer pcall metadata from the refused operation. */
    counts.refuse = 1;
    return protected_loader(L);
}

/* Case 1. Setup: an empty file (zero bytes). Action: load it, then call the
 * chunk with no arguments and all results. Expected: loading succeeds, the
 * chunk is the only value added, and the call returns no results. */
static void case_empty_file_loads_no_results(lua_State *L) {
    char name[NAME_SIZE];
    make_name(name, "empty", ".lua");
    write_bytes(name, "", 0);
    assert(luaL_loadfile(L, name) == LUA_OK);
    assert(lua_gettop(L) == 1);
    assert(lua_pcall(L, 0, LUA_MULTRET, 0) == LUA_OK);
    assert(lua_gettop(L) == 0);
    remove_file(name);
}

/* Case 2. Setup: a file that begins with the UTF-8 BOM bytes EF BB BF,
 * followed by "return 7". Action: load and call it. Expected: the BOM is
 * skipped, and the chunk returns the integer 7. */
static void case_bom_skipped_returns_value(lua_State *L) {
    char name[NAME_SIZE];
    make_name(name, "bom", ".lua");
    write_text(name, "\xEF\xBB\xBFreturn 7\n");
    assert(luaL_loadfilex(L, name, NULL) == LUA_OK);
    assert(lua_pcall(L, 0, 1, 0) == LUA_OK);
    assert(lua_isinteger(L, -1) && lua_tointeger(L, -1) == 7);
    lua_settop(L, 0);
    remove_file(name);
}

/* Case 3. Setup: a shebang first line, then a call to error() on line 3.
 * Action: load the file, then call it under lua_pcall. Expected: the first
 * line is skipped but still counted, so the error is reported at line 3. */
static void case_shebang_keeps_line_numbers(lua_State *L) {
    char name[NAME_SIZE];
    make_name(name, "shebang", ".lua");
    write_text(name, "#!/usr/bin/env lua\nlocal x = 1\nerror('boom')\n");
    assert(luaL_loadfilex(L, name, NULL) == LUA_OK);
    assert(lua_pcall(L, 0, 0, 0) == LUA_ERRRUN);
    check_error_at(L, -1, name, 3, "boom");
    lua_settop(L, 0);
    remove_file(name);
}

/* Case 4. Setup: CRLF line endings, with an error() call on line 3 after a
 * blank line. Action: load and run under lua_pcall. Expected: each CRLF pair
 * counts as one line break, so the error is at line 3 on every host. */
static void case_crlf_line_numbers(lua_State *L) {
    char name[NAME_SIZE];
    make_name(name, "crlf", ".lua");
    write_text(name, "local a = 1\r\n\r\nerror('crlf')\r\n");
    assert(luaL_loadfilex(L, name, NULL) == LUA_OK);
    assert(lua_pcall(L, 0, 0, 0) == LUA_ERRRUN);
    check_error_at(L, -1, name, 3, "crlf");
    lua_settop(L, 0);
    remove_file(name);
}

/* Case 5. Setup: a file holding only the first two bytes of the BOM (EF BB).
 * Action: load it. Expected: the incomplete BOM is not skipped. The core
 * returns the first byte, so loading fails with a syntax error at line 1
 * and never succeeds. */
static void case_incomplete_bom_syntax_error(lua_State *L) {
    static const char partial[] = { '\xEF', '\xBB' };
    char name[NAME_SIZE];
    make_name(name, "partialbom", ".lua");
    write_bytes(name, partial, sizeof partial);
    assert(luaL_loadfilex(L, name, NULL) == LUA_ERRSYNTAX);
    assert(lua_gettop(L) == 1);
    check_error_at(L, -1, name, 1, "unexpected symbol near '<\\239>'");
    lua_settop(L, 0);
    remove_file(name);
}

/* Case 6. Setup: a text file whose first statement is "x = = 1". Action:
 * load it. Expected: loading fails with LUA_ERRSYNTAX and one message at
 * line 1 that names the file. The chunk is not left on the stack. */
static void case_syntax_error_class_and_position(lua_State *L) {
    char name[NAME_SIZE];
    make_name(name, "syntax", ".lua");
    write_text(name, "x = = 1\n");
    assert(luaL_loadfilex(L, name, NULL) == LUA_ERRSYNTAX);
    assert(lua_gettop(L) == 1);
    check_error_at(L, -1, name, 1, "unexpected symbol near '='");
    lua_settop(L, 0);
    remove_file(name);
}

/* Case 7. Setup: a binary chunk (from luaL_loadstring and lua_dump) written
 * to a file. Action: load with mode "t". Expected: the core rejects it with
 * LUA_ERRSYNTAX and the exact message from ldo.c checkmode, with no position
 * prefix. */
static void case_text_mode_rejects_binary(lua_State *L) {
    struct dump_buffer dump;
    char name[NAME_SIZE];
    make_name(name, "modet", ".luac");
    assert(luaL_loadstring(L, "return 1") == LUA_OK);
    dump_top(L, 0, &dump);
    lua_pop(L, 1);
    write_bytes(name, dump.bytes, dump.size);
    assert(luaL_loadfilex(L, name, "t") == LUA_ERRSYNTAX);
    check_top_string(L, -1,
        "attempt to load a binary chunk (mode is 't')");
    lua_settop(L, 0);
    remove_file(name);
}

/* Case 8. Setup: a text file holding "return 1". Action: load with mode "b".
 * Expected: the core rejects it with LUA_ERRSYNTAX and the exact checkmode
 * message for a text chunk. */
static void case_binary_mode_rejects_text(lua_State *L) {
    char name[NAME_SIZE];
    make_name(name, "modeb", ".lua");
    write_text(name, "return 1\n");
    assert(luaL_loadfilex(L, name, "b") == LUA_ERRSYNTAX);
    check_top_string(L, -1,
        "attempt to load a text chunk (mode is 'b')");
    lua_settop(L, 0);
    remove_file(name);
}

/* Case 9. Setup: a text source file "return 40 + 2" is loaded, then dumped
 * unstripped to a binary file. Action: load the binary file with mode "b"
 * and call it. Expected: the binary loads without a text-mode check, the
 * chunk returns 42, and its debug source is still the original "@<source>"
 * because the dump kept the source name. */
static void case_dump_file_loads_and_runs(lua_State *L) {
    struct dump_buffer dump;
    char source[NAME_SIZE], binary[NAME_SIZE], want[NAME_SIZE + 2];
    make_name(source, "dumpsrc", ".lua");
    make_name(binary, "dumpbin", ".luac");
    write_text(source, "return 40 + 2\n");
    assert(luaL_loadfilex(L, source, NULL) == LUA_OK);
    dump_top(L, 0, &dump);
    lua_pop(L, 1);
    write_bytes(binary, dump.bytes, dump.size);
    assert(luaL_loadfilex(L, binary, "b") == LUA_OK);
    chunk_source(want, sizeof want, source);
    check_source(L, -1, want, source);
    assert(lua_pcall(L, 0, 1, 0) == LUA_OK);
    assert(lua_isinteger(L, -1) && lua_tointeger(L, -1) == 42);
    lua_settop(L, 0);
    remove_file(source);
    remove_file(binary);
}

/* Case 10. Setup: the same source as case 9, dumped with strip set to 1.
 * Action: load the stripped binary file and inspect the function.
 * Expected: the debug source is the stripped marker "=?" (short name "?"),
 * the current line is -1 because there is no line information, and the
 * chunk still returns 42. */
static void case_stripped_dump_has_no_source(lua_State *L) {
    struct dump_buffer dump;
    lua_Debug ar;
    char source[NAME_SIZE], binary[NAME_SIZE];
    make_name(source, "stripsrc", ".lua");
    make_name(binary, "stripbin", ".luac");
    write_text(source, "return 40 + 2\n");
    assert(luaL_loadfilex(L, source, NULL) == LUA_OK);
    dump_top(L, 1, &dump);
    lua_pop(L, 1);
    write_bytes(binary, dump.bytes, dump.size);
    assert(luaL_loadfilex(L, binary, NULL) == LUA_OK);
    check_source(L, -1, "=?", "?");
    lua_pushvalue(L, -1);
    assert(lua_getinfo(L, ">l", &ar) != 0);
    assert(ar.currentline == -1);
    assert(lua_pcall(L, 0, 1, 0) == LUA_OK);
    assert(lua_isinteger(L, -1) && lua_tointeger(L, -1) == 42);
    lua_settop(L, 0);
    remove_file(source);
    remove_file(binary);
}

/* Case 11. Setup: a text file "return 1". Action: load it by name. Expected:
 * the debug info of the main chunk reports the source "@<name>", the short
 * source is the name itself, and the function is the main chunk. */
static void case_source_info_matches_file(lua_State *L) {
    lua_Debug ar;
    char name[NAME_SIZE], want[NAME_SIZE + 2];
    make_name(name, "srcinfo", ".lua");
    write_text(name, "return 1\n");
    assert(luaL_loadfilex(L, name, NULL) == LUA_OK);
    chunk_source(want, sizeof want, name);
    check_source(L, -1, want, name);
    lua_pushvalue(L, -1);
    assert(lua_getinfo(L, ">S", &ar) != 0);
    assert(strcmp(ar.what, "main") == 0);
    assert(ar.linedefined == 0);
    lua_settop(L, 0);
    remove_file(name);
}

/* Case 12. Setup: a name that does not exist (nothing is created). Action:
 * load it. Expected: LUA_ERRFILE, and the message is exactly
 * "cannot open <name>: <strerror(errno)>" as lauxlib.c errfile builds it.
 * The errno value is taken from a failing fopen on this same host, so no
 * platform text is hard-coded. */
static void case_missing_file_errno_message(lua_State *L) {
    char name[NAME_SIZE], want[NAME_SIZE + 96];
    FILE *probe;
    int err, n;
    make_name(name, "missing", ".lua");
    errno = 0;
    probe = fopen(name, "r");
    assert(probe == NULL);
    err = errno;
    if (err != 0) n = snprintf(want, sizeof want, "cannot open %s: %s",
                               name, strerror(err));
    else n = snprintf(want, sizeof want, "cannot open %s", name);
    assert(n > 0 && (size_t)n < sizeof want);
    assert(luaL_loadfilex(L, name, NULL) == LUA_ERRFILE);
    assert(lua_gettop(L) == 1);
    check_top_string(L, -1, want);
    lua_settop(L, 0);
}

/* Case 13. Setup: a real file "return 5", and a C buffer whose bytes are the
 * file name, a NUL, then the text "ignored". Action: pass the buffer to
 * luaL_loadfilex. Expected: the C string ends at the NUL, so the file named
 * before it loads, the debug source is "@<name>" with no suffix, and the
 * chunk returns 5. */
static void case_filename_nul_suffix_ignored(lua_State *L) {
    char name[NAME_SIZE], want[NAME_SIZE + 2], arg[NAME_SIZE + 16];
    size_t len;
    make_name(name, "nul", ".lua");
    write_text(name, "return 5\n");
    len = strlen(name);
    memcpy(arg, name, len);
    arg[len] = '\0';
    memcpy(arg + len + 1, "ignored", 8);
    assert(luaL_loadfilex(L, arg, NULL) == LUA_OK);
    chunk_source(want, sizeof want, name);
    check_source(L, -1, want, name);
    assert(lua_pcall(L, 0, 1, 0) == LUA_OK);
    assert(lua_isinteger(L, -1) && lua_tointeger(L, -1) == 5);
    lua_settop(L, 0);
    remove_file(name);
}

/* Case 14. Setup: two values, "left" and 42, are on the stack before the
 * call. A file returns 3. Action: load the file, then call it. Expected:
 * the chunk lands above the existing values, which stay unchanged, and the
 * result is pushed above them. */
static void case_success_preserves_caller_stack(lua_State *L) {
    char name[NAME_SIZE];
    make_name(name, "stackok", ".lua");
    write_text(name, "return 3\n");
    lua_pushstring(L, "left");
    lua_pushinteger(L, 42);
    assert(luaL_loadfilex(L, name, NULL) == LUA_OK);
    assert(lua_gettop(L) == 3);
    check_top_string(L, 1, "left");
    assert(lua_isinteger(L, 2) && lua_tointeger(L, 2) == 42);
    assert(lua_type(L, 3) == LUA_TFUNCTION);
    assert(lua_pcall(L, 0, 1, 0) == LUA_OK);
    assert(lua_gettop(L) == 3);
    check_top_string(L, 1, "left");
    assert(lua_isinteger(L, 2) && lua_tointeger(L, 2) == 42);
    assert(lua_isinteger(L, 3) && lua_tointeger(L, 3) == 3);
    lua_settop(L, 0);
    remove_file(name);
}

/* Case 15. Setup: two values on the stack, then a missing file. Action: load
 * it. Expected: LUA_ERRFILE, the two caller values are unchanged, and the
 * only addition is the error message on top (the filename is removed). */
static void case_missing_file_preserves_caller_stack(lua_State *L) {
    char name[NAME_SIZE];
    make_name(name, "stackmiss", ".lua");
    lua_pushstring(L, "left");
    lua_pushinteger(L, 42);
    assert(luaL_loadfilex(L, name, NULL) == LUA_ERRFILE);
    assert(lua_gettop(L) == 3);
    check_top_string(L, 1, "left");
    assert(lua_isinteger(L, 2) && lua_tointeger(L, 2) == 42);
    check_prefix(L, 3, "cannot open ");
    lua_settop(L, 0);
}

/* Case 16. Setup: a file that is a syntax error, with two values already on
 * the stack. Action: load it. Expected: LUA_ERRSYNTAX, the caller values are
 * unchanged, and the error message is the only addition. This is the lua_load
 * failure path, which differs from the missing-file path in case 15. */
static void case_syntax_failure_preserves_caller_stack(lua_State *L) {
    char name[NAME_SIZE];
    make_name(name, "stacksyntax", ".lua");
    write_text(name, "x = = 1\n");
    lua_pushstring(L, "left");
    lua_pushinteger(L, 42);
    assert(luaL_loadfilex(L, name, NULL) == LUA_ERRSYNTAX);
    assert(lua_gettop(L) == 3);
    check_top_string(L, 1, "left");
    assert(lua_isinteger(L, 2) && lua_tointeger(L, 2) == 42);
    check_prefix(L, 3, name);
    lua_settop(L, 0);
    remove_file(name);
}

/* Case 17. Setup: a file "return 9" loaded through protected_loader, which
 * runs under lua_pcall. Action: call it once for the success path, then with
 * a missing name for the failure path. Expected: the success returns 9 and
 * the failure is a protected LUA_ERRRUN whose message starts with
 * "cannot open ". Both paths leave the protected state usable. */
static void case_protected_callback_loads_and_reports(lua_State *L) {
    char name[NAME_SIZE], missing[NAME_SIZE];
    make_name(name, "protect", ".lua");
    make_name(missing, "protectmiss", ".lua");
    write_text(name, "return 9\n");
    lua_pushcfunction(L, protected_loader);
    lua_pushstring(L, name);
    assert(lua_pcall(L, 1, 1, 0) == LUA_OK);
    assert(lua_isinteger(L, -1) && lua_tointeger(L, -1) == 9);
    lua_settop(L, 0);
    lua_pushcfunction(L, protected_loader);
    lua_pushstring(L, missing);
    assert(lua_pcall(L, 1, 1, 0) == LUA_ERRRUN);
    check_prefix(L, -1, "cannot open ");
    lua_settop(L, 0);
    remove_file(name);
}

/* Case 18. Setup: a file "return 5" loaded through protected_loader. Action:
 * with the allocator refusing every growth for the whole protected call,
 * call the loader; then, with refusal cleared, call it again on the same
 * file. Expected: the refused call fails with the memory error (the allocator
 * really refused at least one growth), the second call succeeds with 5, and
 * the state closes with every counted byte and block released. */
static void case_persistent_refusal_recovers(lua_State *L) {
    char name[NAME_SIZE];
    size_t before;
    int status;
    make_name(name, "refuse", ".lua");
    write_text(name, "return 5\n");
    lua_pushcfunction(L, refusing_loader);
    lua_pushstring(L, name);
    before = counts.growths;
    status = lua_pcall(L, 1, 1, 0);
    counts.refuse = 0;
    assert(counts.growths > before);
    check_memory_error(L, status);
    lua_settop(L, 0);
    lua_pushcfunction(L, protected_loader);
    lua_pushstring(L, name);
    assert(lua_pcall(L, 1, 1, 0) == LUA_OK);
    assert(lua_isinteger(L, -1) && lua_tointeger(L, -1) == 5);
    lua_settop(L, 0);
    remove_file(name);
}

/* Prefix a real dump with BOM/shebang bytes. The reopened binary input must
 * discard them without shifting canonical alignment or losing payload bytes. */
static void case_prefixed_binary(lua_State *L) {
    struct dump_buffer dump;
    char name[NAME_SIZE];
    const char prefix[] = "\xEF\xBB\xBF#!/usr/bin/lua\r\n";
    FILE *file;
    make_name(name, "prefixbin", ".luac");
    assert(luaL_loadstring(L, "return 42") == LUA_OK);
    dump_top(L, 0, &dump);
    lua_pop(L, 1);
    file = fopen(name, "wb");
    assert(file != NULL);
    assert(fwrite(prefix, 1, sizeof prefix - 1, file) == sizeof prefix - 1);
    assert(fwrite(dump.bytes, 1, dump.size, file) == dump.size);
    assert(fclose(file) == 0);
    assert(luaL_loadfilex(L, name, "b") == LUA_OK);
    assert(lua_pcall(L, 0, 1, 0) == LUA_OK);
    assert(lua_tointeger(L, -1) == 42);
    lua_settop(L, 0);
    remove_file(name);
}

static size_t requested_fault, started_growth;

static int faulted_loader(lua_State *L) {
    void *userdata = NULL;
    struct allocation_counts *local;
    (void)lua_getallocf(L, &userdata);
    local = (struct allocation_counts *)userdata;
    started_growth = local->growths;
    if (requested_fault != 0)
        local->fail_after = local->growths + requested_fault;
    return protected_loader(L);
}

/* Every round uses a fresh identically configured state and refuses one
 * measured actual growth, persisting through emergency retry. The failed
 * state must then load the same file successfully, and close in balance.
 * Private allocation counts are measured independently in each runtime. */
static size_t file_fault_attempt(const char *name, size_t point) {
    struct allocation_counts local;
    lua_State *child;
    size_t observed;
    int status;
    memset(&local, 0, sizeof local);
    child = lua_newstate(counted_allocator, &local, LOADFILE_SEED);
    assert(child != NULL);
    luaL_openlibs(child);
    assert(lua_checkstack(child, 16));
    lua_pushcfunction(child, faulted_loader);
    lua_pushstring(child, name);
    requested_fault = point;
    status = lua_pcall(child, 1, 1, 0);
    observed = local.growths - started_growth;
    local.fail_after = 0;
    if (point == 0) {
        assert(status == LUA_OK && lua_tointeger(child, -1) == 5);
    }
    else {
        assert(observed >= point);
        check_memory_error(child, status);
    }
    lua_settop(child, 0);
    requested_fault = 0;
    lua_pushcfunction(child, faulted_loader);
    lua_pushstring(child, name);
    assert(lua_pcall(child, 1, 1, 0) == LUA_OK);
    assert(lua_tointeger(child, -1) == 5);
    lua_close(child);
    assert(local.bytes == 0 && local.blocks == 0);
    return observed;
}

static void case_file_growth_sweep(lua_State *L) {
    char name[NAME_SIZE], block[1024];
    FILE *file;
    size_t measured, point;
    unsigned i;
    (void)L;
    make_name(name, "faults", ".lua");
    file = fopen(name, "wb");
    assert(file != NULL);
    assert(fputs("--[=[", file) >= 0);
    memset(block, 'x', sizeof block);
    for (i = 0; i < 64; ++i)
        assert(fwrite(block, 1, sizeof block, file) == sizeof block);
    assert(fputs("]=]\nreturn 5\n", file) >= 0);
    assert(fclose(file) == 0);
    measured = file_fault_attempt(name, 0);
    assert(measured > 0);
    for (point = 1; point <= measured; ++point)
        (void)file_fault_attempt(name, point);
    remove_file(name);
}

/* LF, rather than a lone CR, terminates the ignored interpreter line. */
static void case_shebang_lone_cr(lua_State *L) {
    char name[NAME_SIZE];
    make_name(name, "hashcr", ".lua");
    write_text(name, "#!ignored\rerror('must be skipped')\nreturn 23\n");
    assert(luaL_loadfilex(L, name, "t") == LUA_OK);
    assert(lua_pcall(L, 0, 1, 0) == LUA_OK);
    assert(lua_tointeger(L, -1) == 23);
    lua_settop(L, 0);
    remove_file(name);
}

/* Table of independently named cases, in run order. */
static const struct {
    const char *name;
    loadfile_case body;
} cases[] = {
    {"empty-file-no-results", case_empty_file_loads_no_results},
    {"bom-skipped", case_bom_skipped_returns_value},
    {"shebang-line-numbers", case_shebang_keeps_line_numbers},
    {"crlf-line-numbers", case_crlf_line_numbers},
    {"incomplete-bom-syntax", case_incomplete_bom_syntax_error},
    {"syntax-error-class", case_syntax_error_class_and_position},
    {"text-mode-rejects-binary", case_text_mode_rejects_binary},
    {"binary-mode-rejects-text", case_binary_mode_rejects_text},
    {"dump-file-loads-runs", case_dump_file_loads_and_runs},
    {"stripped-dump-no-source", case_stripped_dump_has_no_source},
    {"source-info-matches-file", case_source_info_matches_file},
    {"missing-file-errno", case_missing_file_errno_message},
    {"filename-nul-suffix", case_filename_nul_suffix_ignored},
    {"success-keeps-stack", case_success_preserves_caller_stack},
    {"missing-keeps-stack", case_missing_file_preserves_caller_stack},
    {"syntax-failure-keeps-stack", case_syntax_failure_preserves_caller_stack},
    {"protected-callback", case_protected_callback_loads_and_reports},
    {"persistent-refusal-recovers", case_persistent_refusal_recovers},
    {"prefixed-binary-alignment", case_prefixed_binary},
    {"actual-file-growth-sweep", case_file_growth_sweep},
    {"shebang-lone-CR", case_shebang_lone_cr}
};

#define LOADFILE_CASE_COUNT (sizeof cases / sizeof cases[0])

/* Run one case in a fresh counted state. The state is opened, the body runs
 * with an empty stack, and the state is closed. The byte and block counts
 * must return to zero only after lua_close, so any leak fails the case. */
static int run_case(loadfile_case body) {
    lua_State *L;
    memset(&counts, 0, sizeof counts);
    L = lua_newstate(counted_allocator, &counts, LOADFILE_SEED);
    assert(L != NULL);
    luaL_openlibs(L);
    assert(lua_checkstack(L, 16));
    body(L);
    assert(lua_gettop(L) == 0);
    counts.refuse = 0;
    counts.fail_after = 0;
    lua_close(L);
    assert(counts.bytes == 0 && counts.blocks == 0);
    return 1;
}

/* Reusable AUnit entry point. Pass an index below LOADFILE_CASE_COUNT and the
 * function returns 1 on success; any failed check aborts via assert. An index
 * past the table returns 0 without running anything. */
int lua_ada_test_loadfile(unsigned which) {
    if (which >= LOADFILE_CASE_COUNT) return 0;
    return run_case(cases[which].body);
}

static char budget_filename[NAME_SIZE];

static int budget_loader(lua_State *L) {
    if (luaL_loadfilex(L, budget_filename, "t") != LUA_OK) return lua_error(L);
    lua_call(L, 0, 1);
    return 1;
}

lua_CFunction lua_ada_test_loadfile_budget(void) {
    char bytes[2056];
    make_name(budget_filename, "quota", ".lua");
    memset(bytes, ' ', sizeof bytes);
    memcpy(bytes, "return 5", 8);
    write_bytes(budget_filename, bytes, sizeof bytes);
    return budget_loader;
}

int lua_ada_test_loadfile_cleanup(void) {
    int result = remove(budget_filename);
    budget_filename[0] = '\0';
    return result;
}

#ifndef LUA_ADA_LOADFILE_CONTRACT_LIBRARY
static int emit_writer(lua_State *L, const void *bytes, size_t size, void *ud) {
    (void)L;
    (void)ud;
    return size != 0 && fwrite(bytes, 1, size, stdout) != size;
}

int main(int argc, char **argv) {
    unsigned i;
    if (argc == 2 && strcmp(argv[1], "--emit-stdin-chunk") == 0) {
        lua_State *L = luaL_newstate();
        static const char source[] = "return 17, 'input\\0payload', true\n";
        assert(L != NULL);
#if defined(_WIN32)
        assert(_setmode(_fileno(stdout), _O_BINARY) != -1);
#endif
        assert(luaL_loadbufferx(L, source, sizeof source - 1,
                               "=stdin", "t") == LUA_OK);
        assert(lua_dump(L, emit_writer, NULL, 0) == 0);
        lua_close(L);
        return 0;
    }
    if (argc == 2 && (strcmp(argv[1], "--stdin-text") == 0 ||
                      strcmp(argv[1], "--stdin-binary") == 0)) {
        lua_State *L;
        size_t size;
        const char *bytes;
        memset(&counts, 0, sizeof counts);
#if defined(_WIN32)
        /* Match the explicitly binary standard-stream configuration in the
         * oracle and implementation; ordinary text input keeps native mode. */
        if (strcmp(argv[1], "--stdin-binary") == 0)
            assert(_setmode(_fileno(stdin), _O_BINARY) != -1);
#endif
        L = lua_newstate(counted_allocator, &counts, LOADFILE_SEED);
        assert(L != NULL);
        assert(luaL_loadfilex(L, NULL, "bt") == LUA_OK);
        check_source(L, -1, "=stdin", "stdin");
        assert(lua_pcall(L, 0, LUA_MULTRET, 0) == LUA_OK);
        assert(lua_gettop(L) == 3 && lua_isinteger(L, 1));
        assert(lua_tointeger(L, 1) == 17);
        assert(lua_type(L, 2) == LUA_TSTRING);
        bytes = lua_tolstring(L, 2, &size);
        assert(size == 13 && memcmp(bytes, "input\0payload", size) == 0);
        assert(lua_type(L, 3) == LUA_TBOOLEAN && lua_toboolean(L, 3));
        lua_close(L);
        assert(counts.bytes == 0 && counts.blocks == 0);
        puts("PASS: public loadfile stdin");
        return 0;
    }
    if (argc != 1) return EXIT_FAILURE;
    for (i = 0; i < LOADFILE_CASE_COUNT; i++) {
        assert(lua_ada_test_loadfile(i));
        printf("PASS: loadfile-%s\n", cases[i].name);
        fflush(stdout);
    }
    puts("PASS: public luaL_loadfilex contract");
    return 0;
}
#endif
