/* Measured public-header ABI/configuration profile. MIT; see ../../LICENSE.
 *
 * Compile this identical source separately against SDK and pinned C headers.
 * It links no Lua implementation and calls no Lua API. Typed declarations,
 * scalar/aggregate layout, literal constants and active configuration tokens
 * are observations only; actual callback/buffer/debug/API behavior retains
 * its separately named runtime obligations. C and C++ are distinct probes.
 */
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <limits.h>

#ifdef __cplusplus
#include <type_traits>
extern "C" {
#endif
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#ifdef __cplusplus
}
#define ALIGNOF(T) alignof(T)
#define STATIC_ASSERT(c, m) static_assert(c, m)
#define SAME_TYPE(v, T) (std::is_same<decltype(v), T>::value)
#else
#define ALIGNOF(T) _Alignof(T)
#define STATIC_ASSERT(c, m) _Static_assert(c, m)
#define SAME_TYPE(v, T) _Generic((v), T: 1, default: 0)
#endif

/* Independent stable literals from the pinned public contract. These do not
 * infer that an API using the constants actually executed successfully. */
STATIC_ASSERT(LUA_VERSION_MAJOR_N == 5, "major version");
STATIC_ASSERT(LUA_VERSION_MINOR_N == 5, "minor version");
STATIC_ASSERT(LUA_VERSION_RELEASE_N == 1, "release version");
STATIC_ASSERT(LUA_VERSION_NUM == 505, "numeric version");
STATIC_ASSERT(LUA_VERSION_RELEASE_NUM == 50501, "numeric release");
STATIC_ASSERT(LUA_OK == 0 && LUA_YIELD == 1 && LUA_ERRRUN == 2 &&
              LUA_ERRSYNTAX == 3 && LUA_ERRMEM == 4 && LUA_ERRERR == 5,
              "public statuses");
STATIC_ASSERT(LUA_TNONE == -1 && LUA_TNIL == 0 && LUA_TBOOLEAN == 1 &&
              LUA_TLIGHTUSERDATA == 2 && LUA_TNUMBER == 3 &&
              LUA_TSTRING == 4 && LUA_TTABLE == 5 && LUA_TFUNCTION == 6 &&
              LUA_TUSERDATA == 7 && LUA_TTHREAD == 8 && LUA_NUMTYPES == 9,
              "public tags");
STATIC_ASSERT(LUA_MULTRET == -1 && LUA_NOREF == -2 && LUA_REFNIL == -1,
              "public result and reference sentinels");
STATIC_ASSERT(LUA_OPADD == 0 && LUA_OPSUB == 1 && LUA_OPMUL == 2 &&
              LUA_OPMOD == 3 && LUA_OPPOW == 4 && LUA_OPDIV == 5 &&
              LUA_OPIDIV == 6 && LUA_OPBAND == 7 && LUA_OPBOR == 8 &&
              LUA_OPBXOR == 9 && LUA_OPSHL == 10 && LUA_OPSHR == 11 &&
              LUA_OPUNM == 12 && LUA_OPBNOT == 13 && LUA_OPEQ == 0 &&
              LUA_OPLT == 1 && LUA_OPLE == 2, "public operation selectors");
STATIC_ASSERT(sizeof(lua_Integer) == 8 && sizeof(lua_Unsigned) == 8 &&
              sizeof(lua_Number) == 8, "selected primary numeric ABI");
STATIC_ASSERT((lua_Integer)-1 < 0 && (lua_Unsigned)-1 > 0,
              "integer signedness");
STATIC_ASSERT(sizeof(lua_KContext) >= sizeof(void *), "continuation extent");

typedef int (*expected_cfunction)(lua_State *);
typedef int (*expected_kfunction)(lua_State *, int, lua_KContext);
typedef const char *(*expected_reader)(lua_State *, void *, size_t *);
typedef int (*expected_writer)(lua_State *, const void *, size_t, void *);
typedef void *(*expected_allocator)(void *, void *, size_t, size_t);
typedef void (*expected_warning)(void *, const char *, int);
typedef void (*expected_hook)(lua_State *, lua_Debug *);
STATIC_ASSERT(SAME_TYPE((lua_CFunction)0, expected_cfunction), "C callback");
STATIC_ASSERT(SAME_TYPE((lua_KFunction)0, expected_kfunction), "continuation");
STATIC_ASSERT(SAME_TYPE((lua_Reader)0, expected_reader), "reader callback");
STATIC_ASSERT(SAME_TYPE((lua_Writer)0, expected_writer), "writer callback");
STATIC_ASSERT(SAME_TYPE((lua_Alloc)0, expected_allocator), "allocator callback");
STATIC_ASSERT(SAME_TYPE((lua_WarnFunction)0, expected_warning), "warning callback");
STATIC_ASSERT(SAME_TYPE((lua_Hook)0, expected_hook), "debug hook callback");

/* Emit one JSON object with values measured by this compiler. JSON escaping
 * preserves Windows paths and the ESC byte in LUA_SIGNATURE byte for byte;
 * stdout equality is checked only between counterparts on the same host. */
static int first = 1;
static void quoted(const char *s) {
    const unsigned char *p = (const unsigned char *)s;
    putchar('"');
    for (; *p; p++) {
        if (*p == '"' || *p == '\\') printf("\\%c", *p);
        else if (*p < 32 || *p >= 127) printf("\\u%04x", (unsigned)*p);
        else putchar(*p);
    }
    putchar('"');
}
static void key(const char *name) {
    if (!first) putchar(',');
    first = 0;
    quoted(name);
    putchar(':');
}
static void number(const char *name, unsigned long long n) {
    key(name); printf("%llu", n);
}
static void text(const char *name, const char *value) {
    key(name); quoted(value);
}
#define TOKEN_INNER(x) #x
#define TOKEN(x) TOKEN_INNER(x)
#define TYPE(T) number("sizeof." #T, sizeof(T)); number("alignof." #T, ALIGNOF(T))
#define FIELD(T, f) number("offsetof." #T "." #f, offsetof(T, f))
#define VALUE(n) number(#n, (unsigned long long)(n))
#define TEXT(n) text(#n, n)
#define TOKENS(n) text("tokens." #n, TOKEN(n))

int main(void) {
    if (memcmp(LUA_SIGNATURE, "\033Lua", 4) != 0 ||
        strcmp(LUA_VERSION, "Lua 5.5") != 0 ||
        strcmp(LUA_RELEASE, "Lua 5.5.1") != 0) return 1;
    fputs("HEADER-PROFILE-V1 {", stdout);
#ifdef __cplusplus
    number("cplusplus", __cplusplus);
#else
    number("cplusplus", 0);
#endif
#ifdef __STDC_VERSION__
    number("stdc_version", __STDC_VERSION__);
#else
    number("stdc_version", 0);
#endif
#ifdef LUA_USER_H
    number("user_header", 1);
#else
    number("user_header", 0);
#endif
    TYPE(lua_State *); TYPE(lua_Number); TYPE(lua_Integer); TYPE(lua_Unsigned);
    TYPE(lua_KContext); TYPE(lua_CFunction); TYPE(lua_KFunction); TYPE(lua_Reader);
    TYPE(lua_Writer); TYPE(lua_Alloc); TYPE(lua_WarnFunction); TYPE(lua_Hook);
    TYPE(lua_Debug); TYPE(luaL_Reg); TYPE(luaL_Buffer); TYPE(luaL_Stream);
    FIELD(lua_Debug, event); FIELD(lua_Debug, name); FIELD(lua_Debug, namewhat);
    FIELD(lua_Debug, what); FIELD(lua_Debug, source); FIELD(lua_Debug, srclen);
    FIELD(lua_Debug, currentline); FIELD(lua_Debug, linedefined);
    FIELD(lua_Debug, lastlinedefined); FIELD(lua_Debug, nups);
    FIELD(lua_Debug, nparams); FIELD(lua_Debug, isvararg);
    FIELD(lua_Debug, extraargs); FIELD(lua_Debug, istailcall);
    FIELD(lua_Debug, ftransfer); FIELD(lua_Debug, ntransfer);
    FIELD(lua_Debug, short_src); FIELD(lua_Debug, i_ci);
    FIELD(luaL_Reg, name); FIELD(luaL_Reg, func);
    FIELD(luaL_Buffer, b); FIELD(luaL_Buffer, size); FIELD(luaL_Buffer, n);
    FIELD(luaL_Buffer, L); FIELD(luaL_Buffer, init);
    FIELD(luaL_Stream, f); FIELD(luaL_Stream, closef);
    VALUE(LUA_VERSION_NUM); VALUE(LUA_VERSION_RELEASE_NUM); VALUE(LUA_MINSTACK);
    VALUE(LUA_EXTRASPACE); VALUE(LUA_IDSIZE); VALUE(LUAL_BUFFERSIZE);
    VALUE(LUA_INT_TYPE); VALUE(LUA_FLOAT_TYPE); VALUE(LUAI_IS32INT);
    VALUE(LUA_MAXINTEGER); VALUE(LUA_MAXUNSIGNED); VALUE(LUAL_NUMSIZES);
    VALUE(LUA_RIDX_GLOBALS); VALUE(LUA_RIDX_MAINTHREAD); VALUE(LUA_RIDX_LAST);
    VALUE(LUA_GCSTOP); VALUE(LUA_GCRESTART); VALUE(LUA_GCCOLLECT);
    VALUE(LUA_GCCOUNT); VALUE(LUA_GCCOUNTB); VALUE(LUA_GCSTEP);
    VALUE(LUA_GCISRUNNING); VALUE(LUA_GCGEN); VALUE(LUA_GCINC);
    VALUE(LUA_HOOKCALL); VALUE(LUA_HOOKRET); VALUE(LUA_HOOKLINE);
    VALUE(LUA_HOOKCOUNT); VALUE(LUA_HOOKTAILCALL);
    VALUE(LUA_MASKCALL); VALUE(LUA_MASKRET); VALUE(LUA_MASKLINE); VALUE(LUA_MASKCOUNT);
    VALUE(LUA_GLIBK); VALUE(LUA_LOADLIBK); VALUE(LUA_COLIBK); VALUE(LUA_DBLIBK);
    VALUE(LUA_IOLIBK); VALUE(LUA_MATHLIBK); VALUE(LUA_OSLIBK); VALUE(LUA_STRLIBK);
    VALUE(LUA_TABLIBK); VALUE(LUA_UTF8LIBK);
    TEXT(LUA_SIGNATURE); TEXT(LUA_VERSION); TEXT(LUA_RELEASE);
    TEXT(LUA_COPYRIGHT); TEXT(LUA_AUTHORS); TEXT(LUA_VERSUFFIX);
    TEXT(LUA_GNAME); TEXT(LUA_LOADED_TABLE); TEXT(LUA_PRELOAD_TABLE);
    TEXT(LUA_LOADLIBNAME); TEXT(LUA_COLIBNAME); TEXT(LUA_DBLIBNAME);
    TEXT(LUA_IOLIBNAME); TEXT(LUA_MATHLIBNAME); TEXT(LUA_OSLIBNAME);
    TEXT(LUA_STRLIBNAME); TEXT(LUA_TABLIBNAME); TEXT(LUA_UTF8LIBNAME);
    TEXT(LUA_PATH_SEP); TEXT(LUA_PATH_MARK); TEXT(LUA_EXEC_DIR);
    TEXT(LUA_PATH_DEFAULT); TEXT(LUA_CPATH_DEFAULT); TEXT(LUA_DIRSEP); TEXT(LUA_IGMARK);
    TEXT(LUA_NUMBER_FMT); TEXT(LUA_NUMBER_FMT_N); TEXT(LUA_NUMBER_FRMLEN);
    TEXT(LUA_INTEGER_FMT); TEXT(LUA_INTEGER_FRMLEN);
    TOKENS(LUA_NUMBER); TOKENS(LUA_INTEGER); TOKENS(LUA_UNSIGNED);
    TOKENS(LUA_KCONTEXT); TOKENS(LUAI_UACNUMBER); TOKENS(LUAI_UACINT);
    TOKENS(LUA_API); TOKENS(LUALIB_API); TOKENS(LUAMOD_API); TOKENS(LUAI_MAXALIGN);
    puts("}");
    return ferror(stdout) ? 1 : 0;
}
