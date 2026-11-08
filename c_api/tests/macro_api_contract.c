/* Executed public SDK macro contracts. MIT; see ../../LICENSE.
 *
 * Compile this identical C99 client against either selected Lua library.
 * These are actual macro invocations, not names counted in a header. Each
 * named case owns a fresh counted state and verifies its stack and physical
 * close. Header-only helpers operate in the client; no Lua API call is
 * invented for stringification, formatting or a C numeric helper.
 *
 * Conditional APIINTCASTS aliases have separate case names and are compiled
 * only when their real source condition is selected. The emitted configuration
 * line identifies that choice; absent aliases are not printed as passes.
 */
#include <assert.h>
#include <float.h>
#include <limits.h>
#include <locale.h>
#include <math.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(_WIN32)
#include <process.h>
#define process_id _getpid
#else
#include <unistd.h>
#define process_id getpid
#endif
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "consumer_allocator.h"

#ifdef NDEBUG
#error "macro_api_contract.c requires its actual assertions"
#endif
#ifdef LUA_USER_H
#error "macro_api_contract.c models an ordinary SDK caller, not a private T header receiver"
#endif

static struct allocation_counts counts;
static unsigned file_serial;
static int effects;

static int seven(lua_State *L) { lua_pushinteger(L, 7); return 1; }
static int eleven(lua_State *L) { lua_pushinteger(L, 11); return 1; }
static int yes(lua_State *L) { effects++; lua_pushboolean(L, 1); return 1; }
static const luaL_Reg functions[] = {
    {"seven", seven}, {"eleven", eleven}, {NULL, NULL}
};

static void expect_integer(lua_State *L, int index, lua_Integer value) {
    assert(lua_isinteger(L, index));
    assert(lua_tointeger(L, index) == value);
}

static void expect_error(lua_State *L, const char *part) {
    assert(lua_type(L, -1) == LUA_TSTRING);
    assert(strstr(lua_tostring(L, -1), part) != NULL);
    lua_pop(L, 1);
}

/* Register the actual zero-upvalue C function, retrieve it through globals
 * and execute it. A table entry alone would not verify the macro's call. */
static void register_function(lua_State *L) {
    lua_register(L, "macro_seven", seven);
    assert(lua_gettop(L) == 0);
    assert(lua_getglobal(L, "macro_seven") == LUA_TFUNCTION);
    assert(lua_tocfunction(L, -1) == seven);
    assert(lua_pcall(L, 0, 1, 0) == LUA_OK);
    expect_integer(L, -1, 7);
    lua_pop(L, 1);
}

/* Predicate macros must distinguish their exact public type, including an
 * absent index; truthiness or numeric conversion is not an equivalent test. */
static void lightuserdata_predicate(lua_State *L) {
    int token;
    lua_pushlightuserdata(L, &token);
    lua_pushnil(L);
    assert(lua_islightuserdata(L, 1));
    assert(!lua_islightuserdata(L, 2));
    assert(!lua_islightuserdata(L, 3));
    lua_settop(L, 0);
}
static void boolean_predicate(lua_State *L) {
    lua_pushboolean(L, 0); lua_pushboolean(L, 1); lua_pushinteger(L, 0);
    assert(lua_isboolean(L, 1) && lua_isboolean(L, 2));
    assert(!lua_isboolean(L, 3) && !lua_isboolean(L, 4));
    lua_settop(L, 0);
}
static void none_predicate(lua_State *L) {
    lua_pushnil(L);
    assert(!lua_isnone(L, 1));
    assert(lua_isnone(L, 2));
    lua_settop(L, 0);
}

/* Insert retains every item while rotating a suffix. Replace copies the
 * previous top and pops it, with both positive and negative destinations. */
static void insert_suffix(lua_State *L) {
    lua_pushinteger(L, 1); lua_pushinteger(L, 2); lua_pushinteger(L, 3);
    lua_insert(L, -2);
    assert(lua_gettop(L) == 3);
    expect_integer(L, 1, 1); expect_integer(L, 2, 3); expect_integer(L, 3, 2);
    lua_settop(L, 0);
}
static void replace_pop(lua_State *L) {
    lua_pushinteger(L, 1); lua_pushinteger(L, 2); lua_pushinteger(L, 3);
    lua_replace(L, 1);
    assert(lua_gettop(L) == 2);
    expect_integer(L, 1, 3); expect_integer(L, 2, 2);
    lua_pushinteger(L, 4); lua_replace(L, -2);
    assert(lua_gettop(L) == 2);
    expect_integer(L, 1, 3); expect_integer(L, 2, 4);
    lua_settop(L, 0);
}

/* Legacy userdata allocates one real uservalue. Verify the memory remains
 * valid while rooted, and independently exercise each getter/setter alias. */
static void legacy_userdata(lua_State *L) {
    unsigned char *bytes = (unsigned char *)lua_newuserdata(L, 4);
    assert(bytes != NULL && lua_type(L, -1) == LUA_TUSERDATA);
    memcpy(bytes, "a\0bc", 4);
    assert(lua_getiuservalue(L, -1, 1) == LUA_TNIL); lua_pop(L, 1);
    assert(lua_getiuservalue(L, -1, 2) == LUA_TNONE); lua_pop(L, 1);
    lua_gc(L, LUA_GCCOLLECT);
    assert(memcmp(lua_touserdata(L, -1), "a\0bc", 4) == 0);
    lua_settop(L, 0);
}
static void legacy_getuservalue(lua_State *L) {
    assert(lua_newuserdatauv(L, 1, 1) != NULL);
    lua_pushliteral(L, "kept"); assert(lua_setiuservalue(L, 1, 1));
    assert(lua_getuservalue(L, 1) == LUA_TSTRING);
    assert(strcmp(lua_tostring(L, -1), "kept") == 0);
    assert(lua_gettop(L) == 2);
    lua_settop(L, 0);
}
static void legacy_setuservalue(lua_State *L) {
    assert(lua_newuserdatauv(L, 1, 1) != NULL);
    lua_pushinteger(L, 23); assert(lua_setuservalue(L, 1));
    assert(lua_gettop(L) == 1);
    assert(lua_getiuservalue(L, 1, 1) == LUA_TNUMBER);
    expect_integer(L, -1, 23);
    lua_settop(L, 0);
}

/* newlibtable creates only the table. newlib also installs its terminator-
 * bounded registrations and must leave real callable C functions in it. */
static void newlib_empty_table(lua_State *L) {
    lua_pushinteger(L, 19); luaL_newlibtable(L, functions);
    assert(lua_gettop(L) == 2 && lua_istable(L, -1));
    expect_integer(L, 1, 19);
    lua_pushnil(L); assert(lua_next(L, 2) == 0);
    lua_settop(L, 0);
}
static void newlib_calls(lua_State *L) {
    luaL_newlib(L, functions);
    assert(lua_gettop(L) == 1);
    assert(lua_getfield(L, 1, "seven") == LUA_TFUNCTION);
    assert(lua_pcall(L, 0, 1, 0) == LUA_OK); expect_integer(L, -1, 7);
    lua_pop(L, 1);
    assert(lua_getfield(L, 1, "eleven") == LUA_TFUNCTION);
    assert(lua_pcall(L, 0, 1, 0) == LUA_OK); expect_integer(L, -1, 11);
    lua_settop(L, 0);
}

static int unused_argument(void) { effects += 100; return 1; }
static const char *unused_message(void) { effects += 1000; return "unused"; }
static int argcheck_bad(lua_State *L) {
    luaL_argcheck(L, lua_isnumber(L, 1), 1, "must be number"); return 0;
}
static int argexpected_bad(lua_State *L) {
    luaL_argexpected(L, lua_isnumber(L, 1), 1, "widget"); return 0;
}
/* True conditions evaluate once and do not evaluate the error arguments.
 * False conditions enter the actual protected API error, not host assert. */
static void argcheck_short_circuit(lua_State *L) {
    effects = 0;
    luaL_argcheck(L, ++effects, unused_argument(), unused_message());
    assert(effects == 1 && lua_gettop(L) == 0);
}
static void argcheck_failure(lua_State *L) {
    lua_pushcfunction(L, argcheck_bad); lua_pushboolean(L, 0);
    assert(lua_pcall(L, 1, 0, 0) == LUA_ERRRUN);
    assert(strstr(lua_tostring(L, -1), "bad argument #1") != NULL);
    expect_error(L, "must be number");
}
static void argexpected_short_circuit(lua_State *L) {
    effects = 0;
    luaL_argexpected(L, ++effects, unused_argument(), unused_message());
    assert(effects == 1 && lua_gettop(L) == 0);
}
static void argexpected_failure(lua_State *L) {
    lua_pushcfunction(L, argexpected_bad); lua_pushboolean(L, 0);
    assert(lua_pcall(L, 1, 0, 0) == LUA_ERRRUN);
    expect_error(L, "widget expected, got boolean");
}

static int checkstring_bad(lua_State *L) {
    (void)luaL_checkstring(L, 1); return 0;
}
/* The no-length convenience retains binary bytes, performs the documented
 * number conversion in place, and still raises a protected type error. */
static void checkstring_binary(lua_State *L) {
    lua_pushlstring(L, "a\0b", 3);
    assert(memcmp(luaL_checkstring(L, 1), "a\0b", 3) == 0);
    assert(lua_gettop(L) == 1); lua_settop(L, 0);
}
static void checkstring_number(lua_State *L) {
    lua_pushinteger(L, 23);
    assert(strcmp(luaL_checkstring(L, 1), "23") == 0);
    assert(lua_type(L, 1) == LUA_TSTRING && lua_gettop(L) == 1);
    lua_settop(L, 0);
}
static void checkstring_failure(lua_State *L) {
    lua_pushcfunction(L, checkstring_bad); lua_pushboolean(L, 1);
    assert(lua_pcall(L, 1, 0, 0) == LUA_ERRRUN);
    expect_error(L, "string expected, got boolean");
}
static void optstring_default(lua_State *L) {
    const char *fallback = "fallback";
    assert(luaL_optstring(L, 1, fallback) == fallback);
    lua_pushnil(L); assert(luaL_optstring(L, 1, fallback) == fallback);
    assert(lua_gettop(L) == 1); lua_settop(L, 0);
}
static void optstring_present(lua_State *L) {
    lua_pushinteger(L, 31);
    assert(strcmp(luaL_optstring(L, 1, "fallback"), "31") == 0);
    assert(lua_type(L, 1) == LUA_TSTRING); lua_settop(L, 0);
}
static void typename_alias(lua_State *L) {
    lua_pushboolean(L, 0);
    assert(strcmp(luaL_typename(L, 1), "boolean") == 0);
    assert(strcmp(luaL_typename(L, 2), "no value") == 0);
    assert(lua_gettop(L) == 1); lua_settop(L, 0);
}

static void write_script(char *name, size_t capacity, const char *source) {
    FILE *file;
    int size = snprintf(name, capacity, "lua_macro_%ld_%u.lua",
                        (long)process_id(), ++file_serial);
    assert(size > 0 && (size_t)size < capacity);
    file = fopen(name, "wb"); assert(file != NULL);
    assert(fwrite(source, 1, strlen(source), file) == strlen(source));
    assert(fclose(file) == 0);
}
/* The do helpers return Boolean failure, not a particular LUA_ERR* code.
 * Verify successful result cardinality and both compile/runtime failures. */
static void dofile_results(lua_State *L) {
    char name[128]; write_script(name, sizeof name, "return 17, true\n");
    assert(luaL_dofile(L, name) == 0); assert(remove(name) == 0);
    assert(lua_gettop(L) == 2); expect_integer(L, 1, 17);
    assert(lua_type(L, 2) == LUA_TBOOLEAN && lua_toboolean(L, 2));
    lua_settop(L, 0);
}
static void dofile_syntax(lua_State *L) {
    char name[128]; write_script(name, sizeof name, "local =\n");
    assert(luaL_dofile(L, name) == 1); assert(remove(name) == 0);
    assert(lua_gettop(L) == 1); expect_error(L, "<name>");
}
static void dofile_runtime(lua_State *L) {
    char name[128]; write_script(name, sizeof name, "error('macro-file-error')\n");
    assert(luaL_dofile(L, name) == 1); assert(remove(name) == 0);
    assert(lua_gettop(L) == 1); expect_error(L, "macro-file-error");
}
static void dostring_results(lua_State *L) {
    assert(luaL_dostring(L, "return 11, false\0error('unread suffix')") == 0);
    assert(lua_gettop(L) == 2); expect_integer(L, 1, 11);
    assert(lua_type(L, 2) == LUA_TBOOLEAN && !lua_toboolean(L, 2));
    lua_settop(L, 0);
}
static void dostring_syntax(lua_State *L) {
    assert(luaL_dostring(L, "local =") == 1);
    assert(lua_gettop(L) == 1); expect_error(L, "<name>");
}
static void dostring_runtime(lua_State *L) {
    assert(luaL_dostring(L, "error('macro-string-error')") == 1);
    assert(lua_gettop(L) == 1); expect_error(L, "macro-string-error");
}

/* Registry lookup must retrieve the registered table, not create a missing
 * one. Generic opt calls its converter only for a present nonnil argument. */
static void getmetatable_alias(lua_State *L) {
    assert(luaL_newmetatable(L, "macro.meta") == 1);
    assert(luaL_getmetatable(L, "macro.meta") == LUA_TTABLE);
    assert(lua_rawequal(L, 1, 2)); lua_pop(L, 1);
    assert(luaL_getmetatable(L, "macro.absent") == LUA_TNIL);
    lua_settop(L, 0);
}
static lua_Integer opt_converter(lua_State *L, int index) {
    effects++; return luaL_checkinteger(L, index);
}
static void generic_opt(lua_State *L) {
    effects = 0;
    assert(luaL_opt(L, opt_converter, 1, 7) == 7 && effects == 0);
    lua_pushnil(L);
    assert(luaL_opt(L, opt_converter, 1, 9) == 9 && effects == 0);
    lua_pushinteger(L, 11); lua_replace(L, 1);
    assert(luaL_opt(L, opt_converter, 1, 9) == 11 && effects == 1);
    lua_settop(L, 0);
}
static void loadbuffer_extent(lua_State *L) {
    static const char bytes[] = "return 17 invalid suffix";
    lua_Debug info;
    assert(luaL_loadbuffer(L, bytes, 9, "=macro-buffer") == LUA_OK);
    lua_pushvalue(L, -1); assert(lua_getinfo(L, ">S", &info));
    assert(strcmp(info.source, "=macro-buffer") == 0);
    assert(lua_pcall(L, 0, 1, 0) == LUA_OK);
    expect_integer(L, -1, 17); lua_settop(L, 0);
}
static void integer_wrap(lua_State *L) {
    (void)L;
    assert(luaL_intop(+, LUA_MAXINTEGER, 1) == LUA_MININTEGER);
    assert(luaL_intop(-, LUA_MININTEGER, 1) == LUA_MAXINTEGER);
    assert(luaL_intop(*, LUA_MAXINTEGER, 2) == -2);
}
static void selected_failure_value(lua_State *L) {
    luaL_pushfail(L); assert(lua_gettop(L) == 1);
#if defined(LUA_FAILISFALSE)
    assert(lua_type(L, 1) == LUA_TBOOLEAN && !lua_toboolean(L, 1));
#else
    assert(lua_type(L, 1) == LUA_TNIL);
#endif
    lua_settop(L, 0);
}

/* Older length aliases retain raw behavior; comparison aliases execute the
 * actual metamethod rather than replacing equality/order with raw checks. */
static void legacy_strlen(lua_State *L) {
    lua_pushlstring(L, "a\0b", 3); assert(lua_strlen(L, 1) == 3);
    lua_settop(L, 0);
}
static void legacy_objlen(lua_State *L) {
    lua_newtable(L); lua_pushinteger(L, 7); lua_rawseti(L, 1, 1);
    lua_pushinteger(L, 9); lua_rawseti(L, 1, 2);
    lua_newtable(L); lua_pushcfunction(L, seven); lua_setfield(L, -2, "__len");
    lua_setmetatable(L, 1); assert(lua_objlen(L, 1) == 2);
    lua_settop(L, 0);
}
static void compare_tables(lua_State *L, const char *event) {
    lua_newtable(L); lua_pushcfunction(L, yes); lua_setfield(L, 1, event);
    lua_newtable(L); lua_pushvalue(L, 1); lua_setmetatable(L, 2);
    lua_newtable(L); lua_pushvalue(L, 1); lua_setmetatable(L, 3);
    effects = 0;
}
static void legacy_equal(lua_State *L) {
    compare_tables(L, "__eq");
    assert(lua_equal(L, 2, 3) == 1 && effects == 1);
    assert(!lua_rawequal(L, 2, 3)); lua_settop(L, 0);
}
static void legacy_lessthan(lua_State *L) {
    compare_tables(L, "__lt");
    assert(lua_lessthan(L, 2, 3) == 1 && effects == 1);
    lua_settop(L, 0);
}

/* These helpers execute client-side C operations. They make no claim that
 * the Lua implementation ran a C preprocessor or implemented libc math. */
static void floor_helper(lua_State *L) {
    (void)L; assert(l_floor((lua_Number)-1.25) == (lua_Number)-2);
}
static void float_attribute(lua_State *L) {
    (void)L;
#if LUA_FLOAT_TYPE == LUA_FLOAT_DOUBLE
    assert(l_floatatt(MANT_DIG) == DBL_MANT_DIG);
#elif LUA_FLOAT_TYPE == LUA_FLOAT_FLOAT
    assert(l_floatatt(MANT_DIG) == FLT_MANT_DIG);
#else
    assert(l_floatatt(MANT_DIG) == LDBL_MANT_DIG);
#endif
}
static void math_helper(lua_State *L) {
    (void)L; assert(l_mathop(sqrt)((lua_Number)9) == (lua_Number)3);
}
static void decimal_helper(lua_State *L) {
    const char *source = "12.5tail"; char *end;
    (void)L; assert(lua_str2number(source, &end) == (lua_Number)12.5);
    assert(end == source + 4);
}
static void integer_format(lua_State *L) {
    char text[96]; int count;
    (void)L; count = lua_integer2str(text, sizeof text, LUA_MININTEGER);
    assert(count == (int)strlen(text));
    assert(strcmp(text, "-9223372036854775808") == 0);
}
static void sprintf_helper(lua_State *L) {
    char text[16]; (void)L;
    assert(l_sprintf(text, sizeof text, "%s", "bounded") == 7);
    assert(strcmp(text, "bounded") == 0);
}
#if !defined(LUA_USE_C89)
static void hex_parse(lua_State *L) {
    const char *source = "0x1.8p+1tail"; char *end;
    (void)L; assert(lua_strx2number(source, &end) == (lua_Number)3);
    assert(strcmp(end, "tail") == 0);
}
static void hex_format(lua_State *L) {
    char expected[80], actual[80]; int want, got;
    want = snprintf(expected, sizeof expected, "%.3a", (double)1.5);
    got = lua_number2strx(L, actual, sizeof actual, "%.3a", (lua_Number)1.5);
    assert(want == got && strcmp(actual, expected) == 0);
}
#endif
static void pointer_format(lua_State *L) {
    int token; char expected[80], actual[80]; int want, got;
    (void)L;
    want = snprintf(expected, sizeof expected, "%p", (void *)&token);
    got = lua_pointer2str(actual, sizeof actual, (void *)&token);
    assert(want == got && strcmp(actual, expected) == 0);
}
static void decimal_locale(lua_State *L) {
    (void)L; assert(setlocale(LC_NUMERIC, "C") != NULL);
    assert(lua_getlocaledecpoint() == '.');
}
static void branch_hints(lua_State *L) {
    int value; (void)L;
    effects = 0; value = luai_likely(++effects);
    assert(value != 0 && effects == 1);
    effects = 0; value = luai_unlikely(++effects);
    assert(value != 0 && effects == 1);
    assert(!luai_likely(0) && !luai_unlikely(0));
}
#define MACRO_CONTRACT_TOKEN 41
static void stringify_raw(lua_State *L) {
    const char *actual = LUAI_TOSTRAUX(MACRO_CONTRACT_TOKEN); (void)L;
    assert(strcmp(actual, "MACRO_CONTRACT_TOKEN") == 0);
    printf("MACRO-TOKEN-RAW: %s\n", actual);
}
static void stringify_expanded(lua_State *L) {
    const char *actual = LUAI_TOSTR(MACRO_CONTRACT_TOKEN); (void)L;
    assert(strcmp(actual, "41") == 0);
    printf("MACRO-TOKEN-EXPANDED: %s\n", actual);
}

#if defined(LUA_COMPAT_APIINTCASTS)
/* These aliases exist only under the real opt-in source condition. Their
 * optional execution cannot stand in for an inactive ordinary-context row. */
static void compat_checkunsigned(lua_State *L) {
    lua_pushinteger(L, -1); assert(luaL_checkunsigned(L, 1) == LUA_MAXUNSIGNED);
    lua_settop(L, 0);
}
static void compat_optunsigned(lua_State *L) {
    assert(luaL_optunsigned(L, 1, 17) == (lua_Unsigned)17);
    lua_pushinteger(L, 23); assert(luaL_optunsigned(L, 1, 17) == (lua_Unsigned)23);
    lua_settop(L, 0);
}
static void compat_checkint(lua_State *L) {
    lua_pushinteger(L, -23); assert(luaL_checkint(L, 1) == -23); lua_settop(L, 0);
}
static void compat_optint(lua_State *L) {
    assert(luaL_optint(L, 1, -7) == -7);
    lua_pushinteger(L, 29); assert(luaL_optint(L, 1, -7) == 29); lua_settop(L, 0);
}
static void compat_checklong(lua_State *L) {
    lua_pushinteger(L, 31); assert(luaL_checklong(L, 1) == 31L); lua_settop(L, 0);
}
static void compat_optlong(lua_State *L) {
    assert(luaL_optlong(L, 1, 13L) == 13L);
    lua_pushinteger(L, -37); assert(luaL_optlong(L, 1, 13L) == -37L); lua_settop(L, 0);
}
#endif

struct macro_case { const char *name; void (*body)(lua_State *); };
static const struct macro_case cases[] = {
    {"register-cfunction", register_function},
    {"islightuserdata", lightuserdata_predicate},
    {"isboolean", boolean_predicate},
    {"isnone", none_predicate},
    {"insert-suffix", insert_suffix},
    {"replace-pop", replace_pop},
    {"newuserdata-one-uservalue", legacy_userdata},
    {"getuservalue-alias", legacy_getuservalue},
    {"setuservalue-alias", legacy_setuservalue},
    {"newlibtable-empty", newlib_empty_table},
    {"newlib-calls", newlib_calls},
    {"argcheck-short-circuit", argcheck_short_circuit},
    {"argcheck-protected-error", argcheck_failure},
    {"argexpected-short-circuit", argexpected_short_circuit},
    {"argexpected-protected-error", argexpected_failure},
    {"checkstring-binary", checkstring_binary},
    {"checkstring-number", checkstring_number},
    {"checkstring-protected-error", checkstring_failure},
    {"optstring-default", optstring_default},
    {"optstring-present", optstring_present},
    {"typename-alias", typename_alias},
    {"dofile-results", dofile_results},
    {"dofile-syntax", dofile_syntax},
    {"dofile-runtime", dofile_runtime},
    {"dostring-results", dostring_results},
    {"dostring-syntax", dostring_syntax},
    {"dostring-runtime", dostring_runtime},
    {"getmetatable-registry", getmetatable_alias},
    {"opt-short-circuit", generic_opt},
    {"loadbuffer-extent", loadbuffer_extent},
    {"intop-wrap", integer_wrap},
    {"pushfail-selected", selected_failure_value},
    {"legacy-strlen", legacy_strlen},
    {"legacy-objlen", legacy_objlen},
    {"legacy-equal-metamethod", legacy_equal},
    {"legacy-lessthan-metamethod", legacy_lessthan},
    {"floor-helper", floor_helper},
    {"float-attribute", float_attribute},
    {"math-helper", math_helper},
    {"decimal-helper", decimal_helper},
    {"integer-format", integer_format},
    {"sprintf-helper", sprintf_helper},
#if !defined(LUA_USE_C89)
    {"hex-parse", hex_parse},
    {"hex-format", hex_format},
#endif
    {"pointer-format", pointer_format},
    {"locale-decimal", decimal_locale},
    {"branch-hints", branch_hints},
    {"stringify-raw-bytes", stringify_raw},
    {"stringify-expanded-bytes", stringify_expanded},
#if defined(LUA_COMPAT_APIINTCASTS)
    {"compat-checkunsigned", compat_checkunsigned},
    {"compat-optunsigned", compat_optunsigned},
    {"compat-checkint", compat_checkint},
    {"compat-optint", compat_optint},
    {"compat-checklong", compat_checklong},
    {"compat-optlong", compat_optlong},
#endif
};

int lua_ada_test_macro(unsigned which) {
    lua_State *L;
    if (which >= sizeof cases / sizeof cases[0]) return 0;
    memset(&counts, 0, sizeof counts);
    L = lua_newstate(counted_allocator, &counts, 0x713U);
    assert(L != NULL); luaL_openlibs(L); assert(lua_checkstack(L, 24));
    cases[which].body(L);
    assert(lua_gettop(L) == 0);
    lua_close(L); assert(counts.bytes == 0 && counts.blocks == 0);
    return 1;
}

#ifndef LUA_ADA_MACRO_CONTRACT_LIBRARY
int main(void) {
    unsigned i;
    printf("MACRO-CONFIG: APIINTCASTS=%u FAILISFALSE=%u C89=%u\n",
#if defined(LUA_COMPAT_APIINTCASTS)
           1U,
#else
           0U,
#endif
#if defined(LUA_FAILISFALSE)
           1U,
#else
           0U,
#endif
#if defined(LUA_USE_C89)
           1U);
#else
           0U);
#endif
    for (i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        assert(lua_ada_test_macro(i));
        printf("PASS: macro-%s\n", cases[i].name); fflush(stdout);
    }
    puts("PASS: public SDK macro contract");
    return 0;
}
#endif
