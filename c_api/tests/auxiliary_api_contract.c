/* Public auxiliary-library contract through the installed C ABI.
 * Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE.
 *
 * This standalone C99 consumer exercises the 28 luaL_* routines implemented by
 * the unbuilt auxiliary draft (c_api/c/lua_ada_auxiliary.c):
 *   luaL_checkversion_, luaL_getmetafield, luaL_callmeta, luaL_tolstring,
 *   luaL_argerror, luaL_typeerror, luaL_checklstring, luaL_optlstring,
 *   luaL_checknumber, luaL_optnumber, luaL_checkinteger, luaL_optinteger,
 *   luaL_checkstack, luaL_checktype, luaL_checkany, luaL_newmetatable,
 *   luaL_setmetatable, luaL_testudata, luaL_checkudata, luaL_where, luaL_error,
 *   luaL_checkoption, luaL_fileresult, luaL_execresult, luaL_ref, luaL_unref,
 *   luaL_len, luaL_setfuncs.
 * It includes only public headers and calls each routine through the same ABI
 * an embedder would use. It never includes or links the draft directly.
 *
 * How raised errors are checked:
 *   - A chunk run under lua_pcall (expect_error or run) puts a real Lua
 *     function on the call stack, so the "aux:LINE: " prefix that luaL_where
 *     (level 1) produces is the caller's position.
 *   - A C function called by the host through lua_pcall has no Lua caller, so
 *     luaL_error adds no position prefix. Global function names are then
 *     recovered from package.loaded, which is what the draft's fallback does.
 *
 * Platform rule: luaL_execresult decodes wait statuses only when LUA_USE_POSIX
 * is defined. This consumer must be compiled with the same LUA_USE_POSIX
 * setting as the library, so the expected values below match its build.
 *
 * Output: each passing test prints "PASS: auxiliary-api-N <name>" in a fixed
 * order. After lua_close the counted allocator must show zero live bytes and
 * zero blocks; then the program prints "PASS: public auxiliary contract". */
#include <assert.h>
#include <errno.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "consumer_allocator.h"

/* Allocator bookkeeping shared with the counted allocator from the header. */
static struct allocation_counts counts;

/* Identity marker for a light userdata argument; only its address matters. */
static int light_marker;

/* Ordinal of the most recent passing test, for deterministic markers. */
static unsigned marker_number;

/* Option list for luaL_checkoption. The array is NULL-terminated, as the
 * routine requires. */
static const char *const option_names[] = {"alpha", "beta", NULL};

/* ----------------------------------------------------------------------------
 * Harness helpers
 * ------------------------------------------------------------------------- */

/* Abort the test (through assert) when a load or call did not succeed. The
 * error message is printed first so that the failure can be diagnosed. */
static void require_ok(lua_State *L, int status) {
    if (status != LUA_OK) {
        const char *msg = lua_tostring(L, -1);
        fprintf(stderr, "%s\n", msg ? msg : "(non-string error)");
    }
    assert(status == LUA_OK);
}

/* Compare a produced string with the expected text. A NULL result fails too,
 * so a missing string can never be mistaken for a match. */
static void expect_str(const char *got, const char *want) {
    int same = got != NULL && strcmp(got, want) == 0;
    if (!same)
        fprintf(stderr, "expected [%s] but got [%s]\n", want,
                got ? got : "(null)");
    assert(same);
}

/* Load and run 'src' under the chunk name 'chunk'. Use "=aux" so that
 * positions read "aux:LINE: ...". The chunk must return no values, so the
 * stack height is unchanged on success. */
static void run(lua_State *L, const char *chunk, const char *src) {
    int status = luaL_loadbufferx(L, src, strlen(src), chunk, NULL);
    if (status == LUA_OK)
        status = lua_pcall(L, 0, 0, 0);
    require_ok(L, status);
}

/* Push a C function and store it as a global, so Lua can call it by name.
 * The global name is also what luaL_argerror reports in messages. */
static void register_fn(lua_State *L, const char *name, lua_CFunction f) {
    lua_pushcfunction(L, f);
    lua_setglobal(L, name);
}

/* Run 'body' inside pcall on source line 1 of chunk "=aux" and require that
 * it raises exactly 'want'. The wrapper is
 *   local ok,e=pcall(function() BODY end) assert(not ok) return e
 * so the error caller is the anonymous function on line 1, which is the
 * source of the "aux:1: " prefix. The body must fit on one line. */
static void expect_error(lua_State *L, const char *body, const char *want) {
    char src[512];
    int status;
    int n = snprintf(src, sizeof src,
                     "local ok,e=pcall(function() %s end) "
                     "assert(not ok) return e", body);
    assert(n > 0 && (size_t)n < sizeof src);
    status = luaL_loadbufferx(L, src, strlen(src), "=aux", NULL);
    require_ok(L, status);
    status = lua_pcall(L, 0, 1, 0);
    require_ok(L, status);
    expect_str(lua_tostring(L, -1), want);
    lua_pop(L, 1);
}

/* Call a C function from the host with no arguments and require that it
 * raises exactly 'want'. The host is not a Lua frame, so no position prefix
 * is expected. */
static void expect_host_error(lua_State *L, lua_CFunction f,
                              const char *want) {
    int status;
    lua_pushcfunction(L, f);
    status = lua_pcall(L, 0, 0, 0);
    assert(status == LUA_ERRRUN);
    expect_str(lua_tostring(L, -1), want);
    lua_pop(L, 1);
}

/* Render the value of the Lua expression 'expr' with luaL_tolstring and
 * compare the result with 'want'. The expression is first stored in the
 * global aux_value, then read back from the stack. With prefix_only set, only
 * the leading bytes of 'want' are compared, which is used for "Name: 0x..."
 * renderings whose address changes from run to run. */
static void tostring_check(lua_State *L, const char *expr, const char *want,
                           int prefix_only) {
    char src[256];
    size_t len = 0;
    const char *got;
    int same;
    int n = snprintf(src, sizeof src, "aux_value = %s", expr);
    assert(n > 0 && (size_t)n < sizeof src);
    run(L, "=aux", src);
    lua_getglobal(L, "aux_value");
    got = luaL_tolstring(L, -1, &len);
    assert(got != NULL && len == strlen(got));
    same = prefix_only ? strncmp(got, want, strlen(want)) == 0
                       : strcmp(got, want) == 0;
    if (!same)
        fprintf(stderr, "expected [%s] but got [%s]\n", want, got);
    assert(same);
    lua_pop(L, 2);  /* the rendered string and the aux_value copy */
}

/* Make sure registry[name] holds a metatable. luaL_newmetatable pushes either
 * the new table or the existing one, so one pop restores the stack in both
 * cases. Repeated calls across tests are therefore harmless. */
static void ensure_metatable(lua_State *L, const char *name) {
    (void)luaL_newmetatable(L, name);
    lua_pop(L, 1);
}

/* Host helper, defined with the userdata tests below: call probe_testud with
 * the value at 'idx' and return the boolean it produced. */
static int testud_matches_box(lua_State *L, int idx);

/* ----------------------------------------------------------------------------
 * C callbacks used by the Lua-side tests. Each one calls exactly one routine
 * under test, so a failure points at a single ABI function.
 * ------------------------------------------------------------------------- */

/* luaL_checkversion succeeds; the callback reports how much the stack grew
 * across the call, which must be zero. */
static int probe_version_ok(lua_State *L) {
    int before = lua_gettop(L);
    luaL_checkversion(L);
    lua_pushinteger(L, lua_gettop(L) - before);
    return 1;
}

/* Version argument one step ahead of the core, so the version check fails. */
static int probe_version_bad(lua_State *L) {
    luaL_checkversion_(L, (lua_Number)LUA_VERSION_NUM + 1, LUAL_NUMSIZES);
    return 0;
}

/* Numeric-layout argument one byte off, so the size check fails. */
static int probe_layout_bad(lua_State *L) {
    luaL_checkversion_(L, (lua_Number)LUA_VERSION_NUM, LUAL_NUMSIZES + 1);
    return 0;
}

/* luaL_tolstring on argument 1, discarding the length. */
static int probe_tostring(lua_State *L) {
    (void)luaL_tolstring(L, 1, NULL);
    return 0;
}

/* Argument-error callbacks. probe_custom_one reports argument 1 and
 * probe_custom_two reports argument 2, each with the text "custom". */
static int probe_custom_one(lua_State *L) {
    return luaL_argerror(L, 1, "custom");
}
static int probe_custom_two(lua_State *L) {
    return luaL_argerror(L, 2, "custom");
}

/* An argument-error callback that is never stored in a global or library
 * table. The draft can only fall back to "?" for it. */
static int probe_unregistered_arg(lua_State *L) {
    return luaL_argerror(L, 1, "custom");
}

/* Type-error callbacks for argument 1, expecting a number. probe_number_arg is
 * registered as a global; probe_unregistered_type is not. */
static int probe_number_arg(lua_State *L) {
    luaL_typeerror(L, 1, "number");
    return 0;
}
static int probe_unregistered_type(lua_State *L) {
    luaL_typeerror(L, 1, "number");
    return 0;
}

/* luaL_checklstring returns the bytes and length; the callback pushes both
 * back so the test can compare them. lua_pushlstring keeps embedded zeros. */
static int probe_checklstring(lua_State *L) {
    size_t n = 0;
    const char *s = luaL_checklstring(L, 1, &n);
    lua_pushlstring(L, s, n);
    lua_pushinteger(L, (lua_Integer)n);
    return 2;
}

/* luaL_optlstring with the default "dflt" (length 4). */
static int probe_optlstring(lua_State *L) {
    size_t n = 99;  /* sentinel: the routine must overwrite it */
    const char *s = luaL_optlstring(L, 1, "dflt", &n);
    lua_pushlstring(L, s, n);
    lua_pushinteger(L, (lua_Integer)n);
    return 2;
}

/* luaL_optlstring with a NULL default. The callback reports whether the
 * returned pointer is NULL and what length was stored. */
static int probe_optlstring_null(lua_State *L) {
    size_t n = 99;
    const char *s = luaL_optlstring(L, 1, NULL, &n);
    lua_pushboolean(L, s == NULL);
    lua_pushinteger(L, (lua_Integer)n);
    return 2;
}

/* Number callbacks: checked, optional with default 1.25, and integer
 * callbacks: checked, and optional with default 9. */
static int probe_checknumber(lua_State *L) {
    lua_pushnumber(L, luaL_checknumber(L, 1));
    return 1;
}
static int probe_optnumber(lua_State *L) {
    lua_pushnumber(L, luaL_optnumber(L, 1, 1.25));
    return 1;
}
static int probe_checkinteger(lua_State *L) {
    lua_pushinteger(L, luaL_checkinteger(L, 1));
    return 1;
}
static int probe_optinteger(lua_State *L) {
    lua_pushinteger(L, luaL_optinteger(L, 1, 9));
    return 1;
}

/* luaL_checkstack: reserve ten slots, then push ten results. The second
 * callback requests more slots than LUAI_MAXSTACK allows, with a message. */
static int probe_stack_ten(lua_State *L) {
    int i;
    luaL_checkstack(L, 10, "room");
    for (i = 0; i < 10; i++)
        lua_pushinteger(L, i);
    return 10;
}
static int probe_stack_big(lua_State *L) {
    luaL_checkstack(L, 2000000, "big");
    return 0;
}
static int probe_stack_null(lua_State *L) {
    luaL_checkstack(L, 2000000, NULL);
    return 0;
}

/* luaL_checktype and luaL_checkany. */
static int probe_checktype(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    lua_pushboolean(L, 1);
    return 1;
}
static int probe_checkany(lua_State *L) {
    luaL_checkany(L, 1);
    lua_pushboolean(L, 1);
    return 1;
}

/* luaL_testudata reports whether argument 1 carries the "aux.Box" tag. */
static int probe_testud(lua_State *L) {
    lua_pushboolean(L, luaL_testudata(L, 1, "aux.Box") != NULL);
    return 1;
}

/* luaL_checkudata returns the payload pointer as a light userdata. */
static int probe_checkud(lua_State *L) {
    void *p = luaL_checkudata(L, 1, "aux.Box");
    lua_pushlightuserdata(L, p);
    return 1;
}

/* luaL_where with the level taken from argument 1. */
static int probe_where(lua_State *L) {
    luaL_where(L, (int)luaL_checkinteger(L, 1));
    return 1;
}

/* luaL_error with a formatted message, raised from a Lua caller and from the
 * host respectively. */
static int probe_error(lua_State *L) {
    return luaL_error(L, "value %d of %s", 42, "x");
}
static int probe_host_error(lua_State *L) {
    return luaL_error(L, "value %d of %s", 7, "host");
}

/* luaL_checkoption: with a default of "alpha", and without a default. */
static int probe_option(lua_State *L) {
    lua_pushinteger(L, luaL_checkoption(L, 1, "alpha", option_names));
    return 1;
}
static int probe_option_nodef(lua_State *L) {
    lua_pushinteger(L, luaL_checkoption(L, 1, NULL, option_names));
    return 1;
}

/* luaL_len on argument 1, pushing the integer it returns. */
static int probe_len(lua_State *L) {
    lua_pushinteger(L, luaL_len(L, 1));
    return 1;
}

/* Closure bodies for luaL_setfuncs. captured_pair returns its two upvalues.
 * plain_answer needs no upvalues. setfuncs_too_many asks for more upvalues
 * than the stack can hold, so luaL_setfuncs must fail before storing anything. */
static int captured_pair(lua_State *L) {
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_pushvalue(L, lua_upvalueindex(2));
    return 2;
}
static int plain_answer(lua_State *L) {
    lua_pushinteger(L, 42);
    return 1;
}
static int setfuncs_too_many(lua_State *L) {
    static const luaL_Reg none[] = {{"never", plain_answer}, {NULL, NULL}};
    lua_newtable(L);
    luaL_setfuncs(L, none, 2000000);
    return 0;
}

/* ----------------------------------------------------------------------------
 * Tests: version and metamethod helpers
 * ------------------------------------------------------------------------- */

/* Setup: register probe_version_ok. Action: call it from Lua. Expected: it
 * returns normally, and the stack height it measured is unchanged (0). */
static void checkversion_accepts_matching_core(lua_State *L) {
    register_fn(L, "probe_version_ok", probe_version_ok);
    run(L, "=aux", "assert(probe_version_ok() == 0)");
}

/* Setup: a host lua_pcall of a callback passing LUA_VERSION_NUM + 1. Expected:
 * LUA_ERRRUN with the "version mismatch" text. The text is matched loosely
 * because the %f formatting of the two versions is platform-dependent. */
static void checkversion_rejects_version(lua_State *L) {
    int status;
    const char *msg;
    lua_pushcfunction(L, probe_version_bad);
    status = lua_pcall(L, 0, 0, 0);
    assert(status == LUA_ERRRUN);
    msg = lua_tostring(L, -1);
    assert(msg != NULL && strstr(msg, "version mismatch: app. needs") != NULL);
    lua_pop(L, 1);
}

/* Setup: a host lua_pcall with a size argument one larger than the core's
 * LUAL_NUMSIZES. Expected: the literal numeric-layout error text. */
static void checkversion_rejects_numeric_layout(lua_State *L) {
    expect_host_error(L, probe_layout_bad,
                      "core and library have incompatible numeric types");
}

/* Setup: an object whose metatable holds a raw "tag" field of 42, and whose
 * __index table holds tag = 7. Action: luaL_getmetafield for "tag". Expected:
 * the raw metatable value 42 is pushed, and the stack grows by exactly one
 * value. The __index table is not consulted by the lookup itself. */
static void getmetafield_returns_raw_field(lua_State *L) {
    int tt;
    run(L, "=aux",
        "aux_obj = setmetatable({}, {tag = 42, __index = {tag = 7}})");
    lua_getglobal(L, "aux_obj");
    tt = luaL_getmetafield(L, -1, "tag");
    assert(tt == LUA_TNUMBER);
    assert(lua_tointeger(L, -1) == 42);
    assert(lua_gettop(L) == 2);
    lua_settop(L, 0);
}

/* Setup: a table without a metatable and one whose metatable has no "tag".
 * Expected: LUA_TNIL both times, and the stack is unchanged each time. */
static void getmetafield_absent_pushes_nothing(lua_State *L) {
    int tt;
    lua_newtable(L);
    tt = luaL_getmetafield(L, 1, "tag");
    assert(tt == LUA_TNIL);
    assert(lua_gettop(L) == 1);
    run(L, "=aux", "aux_plain = setmetatable({}, {})");
    lua_getglobal(L, "aux_plain");
    tt = luaL_getmetafield(L, -1, "tag");
    assert(tt == LUA_TNIL);
    assert(lua_gettop(L) == 2);
    lua_settop(L, 0);
}

/* Setup: obj's metatable mt has no raw "tag", but mt itself has an __index
 * table containing tag = 7. Expected: the lookup reads mt with a raw get, so
 * the __index fallback is not used and the result is LUA_TNIL. */
static void getmetafield_ignores_index_fallback(lua_State *L) {
    int tt;
    run(L, "=aux",
        "aux_idx = setmetatable({}, setmetatable({}, {__index = {tag = 7}}))");
    lua_getglobal(L, "aux_idx");
    tt = luaL_getmetafield(L, -1, "tag");
    assert(tt == LUA_TNIL);
    assert(lua_gettop(L) == 1);
    lua_settop(L, 0);
}

/* Setup: an object whose metatable has __tostring returning "meta:" followed
 * by type(self). Action: luaL_callmeta on the object. Expected: it returns 1,
 * and the result "meta:table" sits above the object. */
static void callmeta_calls_metamethod_with_object(lua_State *L) {
    int found;
    run(L, "=aux",
        "aux_obj = setmetatable({}, {__tostring = function(s) "
        "return 'meta:' .. type(s) end})");
    lua_getglobal(L, "aux_obj");
    found = luaL_callmeta(L, -1, "__tostring");
    assert(found == 1);
    expect_str(lua_tostring(L, -1), "meta:table");
    assert(lua_gettop(L) == 2);
    lua_settop(L, 0);
}

/* Setup: a table without a metatable. Action: luaL_callmeta for __tostring.
 * Expected: it returns 0 and pushes nothing. */
static void callmeta_absent_pushes_nothing(lua_State *L) {
    int found;
    lua_newtable(L);
    found = luaL_callmeta(L, 1, "__tostring");
    assert(found == 0);
    assert(lua_gettop(L) == 1);
    lua_settop(L, 0);
}

/* Setup: stack [obj, 5], so the object sits at relative index -2. Action:
 * luaL_callmeta with -2. Expected: the relative index is resolved before the
 * call pushes values, so the metamethod still receives obj and its result is
 * pushed on top of the stack. */
static void callmeta_resolves_relative_index(lua_State *L) {
    int found;
    run(L, "=aux",
        "aux_obj = setmetatable({}, {__tostring = function(s) "
        "return 'meta:' .. type(s) end})");
    lua_getglobal(L, "aux_obj");
    lua_pushinteger(L, 5);
    found = luaL_callmeta(L, -2, "__tostring");
    assert(found == 1);
    assert(lua_gettop(L) == 3);
    expect_str(lua_tostring(L, -1), "meta:table");
    assert(lua_tointeger(L, 2) == 5);
    lua_settop(L, 0);
}

/* Tests: luaL_tolstring */

/* Numbers use the core's own format; floats keep a ".0" when integral. */
static void tolstring_renders_numbers(lua_State *L) {
    tostring_check(L, "7", "7", 0);
    tostring_check(L, "2.5", "2.5", 0);
    tostring_check(L, "1.0", "1.0", 0);
}

/* nil and booleans render as their keyword spellings. */
static void tolstring_renders_nil_and_booleans(lua_State *L) {
    tostring_check(L, "nil", "nil", 0);
    tostring_check(L, "true", "true", 0);
    tostring_check(L, "false", "false", 0);
}

/* Setup: a Lua string with an embedded zero (length 3). Action: luaL_tolstring.
 * Expected: the same three bytes and a reported length of 3. The string is
 * compared by memcmp because strcmp would stop at the zero. */
static void tolstring_keeps_string_bytes(lua_State *L) {
    size_t len = 0;
    const char *got;
    lua_pushlstring(L, "a\0b", 3);
    got = luaL_tolstring(L, -1, &len);
    assert(len == 3);
    assert(got != NULL && memcmp(got, "a\0b", 3) == 0);
    lua_settop(L, 0);
}

/* A __tostring metamethod returning a string is used verbatim. */
static void tolstring_uses_tostring_metafield(lua_State *L) {
    tostring_check(L,
        "setmetatable({}, {__tostring = function() return 'custom' end})",
        "custom", 0);
}

/* Setup: __tostring returns a table, which is not a string. Expected: the
 * standard "'__tostring' must return a string" error at the caller's line. */
static void tolstring_rejects_nonstring_tostring(lua_State *L) {
    register_fn(L, "probe_tostring", probe_tostring);
    expect_error(L,
        "probe_tostring(setmetatable({}, {__tostring = function() "
        "return {} end}))",
        "aux:1: '__tostring' must return a string");
}

/* Setup: a table whose metatable has __name = "Point". Expected: the rendering
 * starts with "Point: " (the address after it varies, so only the prefix is
 * compared). */
static void tolstring_uses_name_field(lua_State *L) {
    tostring_check(L, "setmetatable({}, {__name = 'Point'})", "Point: ", 1);
}

/* Setup: __name holds a number, which is not a string. Expected: the basic
 * type name "table" is used instead, so the rendering starts with "table: ". */
static void tolstring_ignores_nonstring_name(lua_State *L) {
    tostring_check(L, "setmetatable({}, {__name = 5})", "table: ", 1);
}

/* Tests: luaL_argerror and luaL_typeerror */

/* Setup: a global callback that reports argument 2. Action: call it with no
 * arguments from line 1. Expected: the caller position, the global name, and
 * the argument number unchanged because this is not a method call. */
static void argerror_names_plain_argument(lua_State *L) {
    register_fn(L, "probe_custom_two", probe_custom_two);
    expect_error(L, "probe_custom_two()",
                 "aux:1: bad argument #2 to 'probe_custom_two' (custom)");
}

/* Setup: a method call o:m() on a callback reporting argument 2. Expected: the
 * implicit self is not counted, so the message names argument #1 and the
 * method name "m". */
static void argerror_method_adjusts_argument(lua_State *L) {
    register_fn(L, "probe_custom_two", probe_custom_two);
    expect_error(L, "local o = {m = probe_custom_two}; o:m()",
                 "aux:1: bad argument #1 to 'm' (custom)");
}

/* Setup: a method call o:m() on a callback reporting argument 1, which is
 * self. Expected: the "bad self" wording, not an argument number. */
static void argerror_method_bad_self(lua_State *L) {
    register_fn(L, "probe_custom_one", probe_custom_one);
    expect_error(L, "local o = {m = probe_custom_one}; o:m()",
                 "aux:1: calling 'm' on bad self (custom)");
}

/* Setup: probe_custom_one is a global, but the host calls it through lua_pcall
 * with no Lua caller, so no call-site name exists. Expected: the draft finds
 * "_G.probe_custom_one" in the loaded modules and strips the "_G." prefix. */
static void argerror_global_name_when_called_from_host(lua_State *L) {
    int status;
    register_fn(L, "probe_custom_one", probe_custom_one);
    lua_getglobal(L, "probe_custom_one");
    status = lua_pcall(L, 0, 0, 0);
    assert(status == LUA_ERRRUN);
    expect_str(lua_tostring(L, -1),
               "bad argument #1 to 'probe_custom_one' (custom)");
    lua_pop(L, 1);
}

/* Setup: an unregistered callback called from the host. Expected: no name is
 * found anywhere, so the fallback name "?" is used. */
static void argerror_unknown_name_uses_question_mark(lua_State *L) {
    expect_host_error(L, probe_unregistered_arg,
                      "bad argument #1 to '?' (custom)");
}

/* Setup: an argument whose metatable has __name = "Point", given to a
 * callback expecting a number. Expected: "got Point", so the __name field is
 * used for the actual type. */
static void typeerror_uses_name_field(lua_State *L) {
    register_fn(L, "probe_number_arg", probe_number_arg);
    expect_error(L,
        "probe_number_arg(setmetatable({}, {__name = 'Point'}))",
        "aux:1: bad argument #1 to 'probe_number_arg' "
        "(number expected, got Point)");
}

/* Setup: a light userdata argument, which has no metatable, given to an
 * unregistered callback from the host. Expected: "got light userdata". */
static void typeerror_light_userdata(lua_State *L) {
    int status;
    lua_pushcfunction(L, probe_unregistered_type);
    lua_pushlightuserdata(L, &light_marker);
    status = lua_pcall(L, 1, 0, 0);
    assert(status == LUA_ERRRUN);
    expect_str(lua_tostring(L, -1),
               "bad argument #1 to '?' (number expected, got light userdata)");
    lua_pop(L, 1);
}

/* Setup: call the number-expecting global with no argument and then with an
 * explicit nil. Expected: "got no value" for the absent case and "got nil"
 * for the explicit nil. */
static void typeerror_absent_and_nil(lua_State *L) {
    register_fn(L, "probe_number_arg", probe_number_arg);
    expect_error(L, "probe_number_arg()",
                 "aux:1: bad argument #1 to 'probe_number_arg' "
                 "(number expected, got no value)");
    expect_error(L, "probe_number_arg(nil)",
                 "aux:1: bad argument #1 to 'probe_number_arg' "
                 "(number expected, got nil)");
}

/* Tests: string, number, and integer argument checks */

/* Setup: an integer argument, which luaL_checklstring converts in place.
 * Action: call with 42. Expected: the bytes "42" and a length of 2. An
 * embedded-zero string keeps its full length of 3. */
static void checklstring_converts_numbers_and_keeps_length(lua_State *L) {
    register_fn(L, "probe_checklstring", probe_checklstring);
    run(L, "=aux",
        "local s, n = probe_checklstring(42); "
        "assert(s == '42' and n == 2); "
        "local t, m = probe_checklstring('a\\0b'); "
        "assert(t == 'a\\0b' and m == 3)");
}

/* Setup: a table argument. Expected: "string expected, got table". */
static void checklstring_rejects_table(lua_State *L) {
    register_fn(L, "probe_checklstring", probe_checklstring);
    expect_error(L, "probe_checklstring({})",
                 "aux:1: bad argument #1 to 'probe_checklstring' "
                 "(string expected, got table)");
}

/* Setup: absent, nil, and present arguments. Expected: absent or nil yields
 * "dflt" with length 4; a present string is returned with its own length. */
static void optlstring_default_and_value(lua_State *L) {
    register_fn(L, "probe_optlstring", probe_optlstring);
    run(L, "=aux",
        "local s, n = probe_optlstring(); assert(s == 'dflt' and n == 4); "
        "s, n = probe_optlstring(nil); assert(s == 'dflt' and n == 4); "
        "s, n = probe_optlstring('xy'); assert(s == 'xy' and n == 2)");
}

/* Setup: a NULL default with no argument. Expected: the routine returns NULL
 * and stores length 0. */
static void optlstring_null_default(lua_State *L) {
    register_fn(L, "probe_optlstring_null", probe_optlstring_null);
    run(L, "=aux",
        "local isnull, n = probe_optlstring_null(); "
        "assert(isnull == true and n == 0)");
}

/* Setup: the string "0x10" is numeric. Expected: luaL_checknumber converts it
 * to 16. */
static void checknumber_converts_numeric_string(lua_State *L) {
    register_fn(L, "probe_checknumber", probe_checknumber);
    run(L, "=aux", "assert(probe_checknumber('0x10') == 16)");
}

/* Setup: a non-numeric string. Expected: "number expected, got string". */
static void checknumber_rejects_nonnumber(lua_State *L) {
    register_fn(L, "probe_checknumber", probe_checknumber);
    expect_error(L, "probe_checknumber('abc')",
                 "aux:1: bad argument #1 to 'probe_checknumber' "
                 "(number expected, got string)");
}

/* Setup: absent, nil, and present arguments. Expected: absent or nil gives
 * the default 1.25; a present number is returned as given. */
static void optnumber_default_and_value(lua_State *L) {
    register_fn(L, "probe_optnumber", probe_optnumber);
    run(L, "=aux",
        "assert(probe_optnumber() == 1.25 and probe_optnumber(nil) == 1.25 "
        "and probe_optnumber(4) == 4)");
}

/* Setup: a table argument. Expected: "number expected, got table". */
static void optnumber_rejects_nonnumber(lua_State *L) {
    register_fn(L, "probe_optnumber", probe_optnumber);
    expect_error(L, "probe_optnumber({})",
                 "aux:1: bad argument #1 to 'probe_optnumber' "
                 "(number expected, got table)");
}

/* Setup: 3.0 has an exact integer value, and '7' converts to an integer.
 * Expected: both return their integer values. */
static void checkinteger_accepts_integral_values(lua_State *L) {
    register_fn(L, "probe_checkinteger", probe_checkinteger);
    run(L, "=aux",
        "assert(probe_checkinteger(3.0) == 3 and probe_checkinteger('7') == 7)");
}

/* Setup: 2.5 is a number with no integer representation. Expected: the
 * precise "number has no integer representation" message. */
static void checkinteger_rejects_fraction(lua_State *L) {
    register_fn(L, "probe_checkinteger", probe_checkinteger);
    expect_error(L, "probe_checkinteger(2.5)",
                 "aux:1: bad argument #1 to 'probe_checkinteger' "
                 "(number has no integer representation)");
}

/* Setup: a table, which is not a number at all. Expected: the ordinary
 * "number expected, got table" message, not the integer-representation one. */
static void checkinteger_rejects_nonnumber(lua_State *L) {
    register_fn(L, "probe_checkinteger", probe_checkinteger);
    expect_error(L, "probe_checkinteger({})",
                 "aux:1: bad argument #1 to 'probe_checkinteger' "
                 "(number expected, got table)");
}

/* Setup: absent, nil, and 2.0 arguments. Expected: absent and nil give the
 * default 9; 2.0 gives 2. */
static void optinteger_default_and_value(lua_State *L) {
    register_fn(L, "probe_optinteger", probe_optinteger);
    run(L, "=aux",
        "assert(probe_optinteger() == 9 and probe_optinteger(nil) == 9 "
        "and probe_optinteger(2.0) == 2)");
}

/* Setup: 2.5 passed to the optional integer. Expected: the same
 * integer-representation error as the required form. */
static void optinteger_rejects_fraction(lua_State *L) {
    register_fn(L, "probe_optinteger", probe_optinteger);
    expect_error(L, "probe_optinteger(2.5)",
                 "aux:1: bad argument #1 to 'probe_optinteger' "
                 "(number has no integer representation)");
}

/* Tests: stack space, type, and any-value checks */

/* Setup: a callback that reserves ten slots, then pushes ten values. Expected:
 * the call succeeds and returns the ten values in order. */
static void checkstack_reserves_requested_slots(lua_State *L) {
    register_fn(L, "probe_stack_ten", probe_stack_ten);
    run(L, "=aux",
        "local a,b,c,d,e,f,g,h,i,j = probe_stack_ten(); "
        "assert(a == 0 and j == 9)");
}

/* Setup: a request for 2000000 slots, above LUAI_MAXSTACK, with a message.
 * Expected: "stack overflow (big)" at the caller's line. */
static void checkstack_overflow_names_message(lua_State *L) {
    register_fn(L, "probe_stack_big", probe_stack_big);
    expect_error(L, "probe_stack_big()",
                 "aux:1: stack overflow (big)");
}

/* Setup: the same overflow with a NULL message. Expected: the bare text
 * "stack overflow" at the caller's line. */
static void checkstack_overflow_without_message(lua_State *L) {
    register_fn(L, "probe_stack_null", probe_stack_null);
    expect_error(L, "probe_stack_null()", "aux:1: stack overflow");
}

/* Setup: a table argument. Expected: the call succeeds. */
static void checktype_accepts_matching_type(lua_State *L) {
    register_fn(L, "probe_checktype", probe_checktype);
    run(L, "=aux", "assert(probe_checktype({}) == true)");
}

/* Setup: an explicit nil where a table is required. Expected: "table
 * expected, got nil" at the caller's line. */
static void checktype_rejects_other_type(lua_State *L) {
    register_fn(L, "probe_checktype", probe_checktype);
    expect_error(L, "probe_checktype(nil)",
                 "aux:1: bad argument #1 to 'probe_checktype' "
                 "(table expected, got nil)");
}

/* Setup: an explicit nil argument. Expected: it counts as a present value,
 * so the call succeeds. */
static void checkany_accepts_nil(lua_State *L) {
    register_fn(L, "probe_checkany", probe_checkany);
    run(L, "=aux", "assert(probe_checkany(nil) == true)");
}

/* Setup: no argument at all. Expected: "value expected" at the caller's
 * line, because an absent argument is not a value. */
static void checkany_rejects_absent(lua_State *L) {
    register_fn(L, "probe_checkany", probe_checkany);
    expect_error(L, "probe_checkany()",
                 "aux:1: bad argument #1 to 'probe_checkany' (value expected)");
}

/* Tests: userdata metatables */

/* Setup: a name not yet in the registry. Action: luaL_newmetatable twice.
 * Expected: the first call returns 1 and leaves a table with __name set,
 * which is also registry[name]. */
static void newmetatable_registers_once(lua_State *L) {
    int created = luaL_newmetatable(L, "aux.Point");
    assert(created == 1);
    lua_getfield(L, -1, "__name");
    expect_str(lua_tostring(L, -1), "aux.Point");
    lua_pop(L, 1);
    lua_getfield(L, LUA_REGISTRYINDEX, "aux.Point");
    assert(lua_rawequal(L, -1, -2));
    lua_settop(L, 0);
}

/* Setup: a metatable already registered under "aux.Existing". Action: call
 * luaL_newmetatable again. Expected: it returns 0 and leaves the existing
 * metatable on top, which is the same object as the one already held. */
static void newmetatable_returns_existing_value(lua_State *L) {
    int created = luaL_newmetatable(L, "aux.Existing");
    assert(created == 1);
    created = luaL_newmetatable(L, "aux.Existing");
    assert(created == 0);
    assert(lua_gettop(L) == 2);
    assert(lua_rawequal(L, -1, -2));
    lua_settop(L, 0);
}

/* Setup: a fresh userdata. Action: luaL_setmetatable with "aux.Box". Expected:
 * the userdata stays on top, its metatable is registry["aux.Box"], and nothing
 * extra remains on the stack. */
static void setmetatable_attaches_registry_metatable(lua_State *L) {
    int has_mt;
    ensure_metatable(L, "aux.Box");
    lua_newuserdatauv(L, 16, 0);
    luaL_setmetatable(L, "aux.Box");
    assert(lua_type(L, -1) == LUA_TUSERDATA);
    has_mt = lua_getmetatable(L, -1);
    assert(has_mt);
    lua_getfield(L, LUA_REGISTRYINDEX, "aux.Box");
    assert(lua_rawequal(L, -1, -2));
    assert(lua_gettop(L) == 3);
    lua_settop(L, 0);
}

/* Host helper implementation for testud_matches_box. */
static int testud_matches_box(lua_State *L, int idx) {
    int result;
    lua_pushcfunction(L, probe_testud);
    lua_pushvalue(L, idx);
    lua_call(L, 1, 1);
    result = lua_toboolean(L, -1);
    lua_pop(L, 1);
    return result;
}

/* Setup: four values: correctly tagged userdata, userdata tagged with a
 * different metatable, a plain table, and an untagged userdata. Expected:
 * only the first matches, and the stack keeps its four values. */
static void testudata_matches_only_tagged_userdata(lua_State *L) {
    ensure_metatable(L, "aux.Box");
    ensure_metatable(L, "aux.Other");
    lua_newuserdatauv(L, 16, 0);
    luaL_setmetatable(L, "aux.Box");        /* index 1 */
    lua_newuserdatauv(L, 16, 0);
    luaL_setmetatable(L, "aux.Other");      /* index 2 */
    lua_newtable(L);                        /* index 3 */
    lua_newuserdatauv(L, 16, 0);            /* index 4: no metatable */
    assert(testud_matches_box(L, 1) == 1);
    assert(testud_matches_box(L, 2) == 0);
    assert(testud_matches_box(L, 3) == 0);
    assert(testud_matches_box(L, 4) == 0);
    assert(lua_gettop(L) == 4);
    lua_settop(L, 0);
}

/* Setup: userdata tagged "aux.Box", registered callback. Action: pass it to
 * luaL_checkudata. Expected: the payload pointer is returned unchanged. */
static void checkudata_returns_payload(lua_State *L) {
    void *payload;
    ensure_metatable(L, "aux.Box");
    register_fn(L, "probe_checkud", probe_checkud);
    payload = lua_newuserdatauv(L, 16, 0);
    luaL_setmetatable(L, "aux.Box");
    lua_getglobal(L, "probe_checkud");
    lua_pushvalue(L, 1);
    lua_call(L, 1, 1);
    assert(lua_touserdata(L, -1) == payload);
    lua_settop(L, 0);
}

/* Setup: a table with no __name, and io.stdout, whose metatable name is
 * "FILE*". Expected: "aux.Box expected, got table" and "got FILE*" at the
 * caller's line. */
static void checkudata_rejects_other_metatable(lua_State *L) {
    ensure_metatable(L, "aux.Box");
    register_fn(L, "probe_checkud", probe_checkud);
    expect_error(L, "probe_checkud(setmetatable({}, {}))",
                 "aux:1: bad argument #1 to 'probe_checkud' "
                 "(aux.Box expected, got table)");
    expect_error(L, "probe_checkud(io.stdout)",
                 "aux:1: bad argument #1 to 'probe_checkud' "
                 "(aux.Box expected, got FILE*)");
}

/* Tests: luaL_where, luaL_error */

/* Setup: a chunk whose probe call is on line 3. Action: luaL_where with
 * level 1. Expected: "aux:3: ", the position of the Lua caller. */
static void where_reports_caller_line(lua_State *L) {
    register_fn(L, "probe_where", probe_where);
    run(L, "=aux",
        "local a = 1\n"
        "local b = 2\n"
        "assert(probe_where(1) == 'aux:3: ')");
}

/* Setup: level 0 is the C callback itself, which has no line information.
 * Expected: the empty string. */
static void where_level_zero_is_empty(lua_State *L) {
    register_fn(L, "probe_where", probe_where);
    run(L, "=aux", "assert(probe_where(0) == '')");
}

/* Setup: a level far beyond the call stack. Expected: the empty string, not
 * an error. */
static void where_missing_level_is_empty(lua_State *L) {
    register_fn(L, "probe_where", probe_where);
    run(L, "=aux", "assert(probe_where(500) == '')");
}

/* Setup: a callback calling luaL_error with a number and a string. Expected:
 * the message is "aux:1: value 42 of x", the caller's position first. */
static void error_prefixes_caller_line(lua_State *L) {
    register_fn(L, "probe_error", probe_error);
    expect_error(L, "probe_error()", "aux:1: value 42 of x");
}

/* Setup: the same formatting, called from the host. Expected: no prefix,
 * because the host has no Lua position to report. */
static void error_from_host_has_no_position(lua_State *L) {
    expect_host_error(L, probe_host_error, "value 7 of host");
}

/* Tests: luaL_checkoption */

/* Setup: option list {"alpha", "beta"} and a default of "alpha". Action: call
 * with no argument, nil, "beta", and "alpha". Expected: indices 0, 0, 1, 0. */
static void checkoption_matches_and_defaults(lua_State *L) {
    register_fn(L, "probe_option", probe_option);
    run(L, "=aux",
        "assert(probe_option() == 0 and probe_option(nil) == 0 "
        "and probe_option('beta') == 1 and probe_option('alpha') == 0)");
}

/* Setup: no default, so the argument is required. Action: call with no
 * argument. Expected: "string expected, got no value", the type error the
 * draft raises through luaL_checkstring. */
static void checkoption_requires_argument_without_default(lua_State *L) {
    register_fn(L, "probe_option_nodef", probe_option_nodef);
    expect_error(L, "probe_option_nodef()",
                 "aux:1: bad argument #1 to 'probe_option_nodef' "
                 "(string expected, got no value)");
}

/* Setup: an unknown name "gamma". Expected: "invalid option 'gamma'". */
static void checkoption_rejects_unknown_name(lua_State *L) {
    register_fn(L, "probe_option", probe_option);
    expect_error(L, "probe_option('gamma')",
                 "aux:1: bad argument #1 to 'probe_option' "
                 "(invalid option 'gamma')");
}

/* Tests: luaL_fileresult and luaL_execresult (errno and status reporting) */

/* Setup: errno is cleared, and stat is nonzero. Expected: one value, true, is
 * pushed and 1 is returned. */
static void fileresult_success_pushes_true(lua_State *L) {
    int n;
    errno = 0;
    n = luaL_fileresult(L, 1, "unused.txt");
    assert(n == 1);
    assert(lua_type(L, 1) == LUA_TBOOLEAN && lua_toboolean(L, 1));
    lua_settop(L, 0);
}

/* Setup: errno is ENOENT and the file name is "missing.txt". Expected: the
 * results are fail, "missing.txt: <strerror(ENOENT)>", and ENOENT, and 3 is
 * returned. */
static void fileresult_failure_with_name(lua_State *L) {
    char want[256];
    int n;
    errno = ENOENT;
    n = luaL_fileresult(L, 0, "missing.txt");
    assert(n == 3);
    assert(lua_gettop(L) == 3);
    assert(!lua_toboolean(L, 1));
    (void)snprintf(want, sizeof want, "missing.txt: %s", strerror(ENOENT));
    expect_str(lua_tostring(L, 2), want);
    assert(lua_tointeger(L, 3) == ENOENT);
    lua_settop(L, 0);
}

/* Setup: errno is ENOENT and no file name is given. Expected: the message is
 * only strerror(ENOENT), with no "name: " prefix. */
static void fileresult_failure_without_name(lua_State *L) {
    int n;
    errno = ENOENT;
    n = luaL_fileresult(L, 0, NULL);
    assert(n == 3);
    expect_str(lua_tostring(L, 2), strerror(ENOENT));
    assert(lua_tointeger(L, 3) == ENOENT);
    lua_settop(L, 0);
}

/* Setup: errno is 0. Expected: the fallback text "(no extra info)" and the
 * integer 0. */
static void fileresult_zero_errno_message(lua_State *L) {
    int n;
    errno = 0;
    n = luaL_fileresult(L, 0, NULL);
    assert(n == 3);
    expect_str(lua_tostring(L, 2), "(no extra info)");
    assert(lua_tointeger(L, 3) == 0);
    lua_settop(L, 0);
}

/* Setup: a zero status with errno 0. Expected: true, "exit", and 0. */
static void execresult_clean_exit(lua_State *L) {
    int n;
    errno = 0;
    n = luaL_execresult(L, 0);
    assert(n == 3);
    assert(lua_type(L, 1) == LUA_TBOOLEAN && lua_toboolean(L, 1));
    expect_str(lua_tostring(L, 2), "exit");
    assert(lua_tointeger(L, 3) == 0);
    lua_settop(L, 0);
}

/* Setup: a nonzero status while errno is ENOENT. Expected: the file-error
 * path runs, so the results are fail, strerror(ENOENT), and ENOENT. The
 * status itself is not reported. */
static void execresult_errno_is_file_error(lua_State *L) {
    int n;
    errno = ENOENT;
    n = luaL_execresult(L, 1);
    assert(n == 3);
    assert(!lua_toboolean(L, 1));
    expect_str(lua_tostring(L, 2), strerror(ENOENT));
    assert(lua_tointeger(L, 3) == ENOENT);
    lua_settop(L, 0);
}

/* Setup: a wait-style status for "exited with code 7" (7 << 8), with errno 0.
 * Expected on POSIX: fail, "exit", and code 7 decoded from the status.
 * Without LUA_USE_POSIX: the raw status is reported unchanged. */
static void execresult_exit_status_platform(lua_State *L) {
    int stat = 7 << 8;
    int n;
    int want_code;
#if defined(LUA_USE_POSIX)
    want_code = 7;
#else
    want_code = stat;
#endif
    errno = 0;
    n = luaL_execresult(L, stat);
    assert(n == 3);
    assert(!lua_toboolean(L, 1));
    expect_str(lua_tostring(L, 2), "exit");
    assert(lua_tointeger(L, 3) == want_code);
    lua_settop(L, 0);
}

/* Setup: a wait-style status whose low seven bits hold signal 9 (SIGKILL),
 * with errno 0. Expected on POSIX: fail, "signal", and 9. Without
 * LUA_USE_POSIX: the raw status 9 is reported as an ordinary exit. */
static void execresult_signal_platform(lua_State *L) {
    int stat = 9;
    int n;
    const char *want_what;
    int want_code;
#if defined(LUA_USE_POSIX)
    want_what = "signal";
    want_code = 9;
#else
    want_what = "exit";
    want_code = stat;
#endif
    errno = 0;
    n = luaL_execresult(L, stat);
    assert(n == 3);
    assert(!lua_toboolean(L, 1));
    expect_str(lua_tostring(L, 2), want_what);
    assert(lua_tointeger(L, 3) == want_code);
    lua_settop(L, 0);
}

/* Tests: luaL_ref and luaL_unref */

/* Setup: an empty table at index 1 and a nil value on top. Expected: the
 * value is not stored, LUA_REFNIL is returned, and the nil is popped. */
static void ref_nil_returns_refnil(lua_State *L) {
    int r;
    lua_newtable(L);
    lua_pushnil(L);
    r = luaL_ref(L, 1);
    assert(r == LUA_REFNIL);
    assert(lua_gettop(L) == 1);
    lua_settop(L, 0);
}

/* Setup: a string on top of an empty table. Action: luaL_ref. Expected: the
 * value is popped, a positive key is returned, and t[key] holds the string.
 * The exact key value is not asserted. */
static void ref_stores_value_and_pops(lua_State *L) {
    int r;
    lua_newtable(L);
    lua_pushstring(L, "kept");
    r = luaL_ref(L, 1);
    assert(r > 0);
    assert(lua_gettop(L) == 1);
    lua_rawgeti(L, 1, r);
    expect_str(lua_tostring(L, -1), "kept");
    lua_settop(L, 0);
}

/* Setup: store "first", release its key, then store "second". Expected: the
 * released key is handed out again, so the second reference equals the first
 * and holds "second". This is the observable reuse of a released reference;
 * the private free-list layout is not inspected. */
static void unref_reuses_released_reference(lua_State *L) {
    int r1, r2;
    lua_newtable(L);
    lua_pushstring(L, "first");
    r1 = luaL_ref(L, 1);
    luaL_unref(L, 1, r1);
    lua_pushstring(L, "second");
    r2 = luaL_ref(L, 1);
    assert(r2 == r1);
    lua_rawgeti(L, 1, r2);
    expect_str(lua_tostring(L, -1), "second");
    lua_settop(L, 0);
}

/* Setup: one live reference "live", then luaL_unref with LUA_REFNIL and with
 * LUA_NOREF. Expected: both calls are ignored, the live value stays, and a
 * new reference gets a different key. */
static void unref_ignores_sentinels(lua_State *L) {
    int r, r2;
    lua_newtable(L);
    lua_pushstring(L, "live");
    r = luaL_ref(L, 1);
    luaL_unref(L, 1, LUA_REFNIL);
    luaL_unref(L, 1, LUA_NOREF);
    assert(lua_gettop(L) == 1);
    lua_rawgeti(L, 1, r);
    expect_str(lua_tostring(L, -1), "live");
    lua_settop(L, 1);
    lua_pushstring(L, "next");
    r2 = luaL_ref(L, 1);
    assert(r2 > 0 && r2 != r);
    lua_rawgeti(L, 1, r);
    expect_str(lua_tostring(L, -1), "live");
    lua_settop(L, 0);
}

/* Tests: luaL_len */

/* Setup: a 3-byte string and a 4-element table. Expected: lengths 3 and 4,
 * with the stack unchanged. */
static void len_string_and_table(lua_State *L) {
    lua_Integer n;
    lua_pushstring(L, "abc");
    n = luaL_len(L, 1);
    assert(n == 3);
    assert(lua_gettop(L) == 1);
    lua_settop(L, 0);
    run(L, "=aux", "aux_t = {1, 2, 3, 4}");
    lua_getglobal(L, "aux_t");
    n = luaL_len(L, -1);
    assert(n == 4);
    assert(lua_gettop(L) == 1);
    lua_settop(L, 0);
}

/* Setup: an object whose __len returns 9. Expected: luaL_len honors __len and
 * returns 9. */
static void len_uses_len_metamethod(lua_State *L) {
    lua_Integer n;
    run(L, "=aux", "aux_m = setmetatable({}, {__len = function() return 9 end})");
    lua_getglobal(L, "aux_m");
    n = luaL_len(L, -1);
    assert(n == 9);
    lua_settop(L, 0);
}

/* Setup: __len returns the non-numeric string 'x'. Expected: "object length is
 * not an integer" at the caller's line. */
static void len_rejects_non_integer(lua_State *L) {
    register_fn(L, "probe_len", probe_len);
    expect_error(L,
        "probe_len(setmetatable({}, {__len = function() return 'x' end}))",
        "aux:1: object length is not an integer");
}

/* Tests: luaL_setfuncs */

/* Setup: a table, plus two upvalues "u1" and 5 on the stack above it.
 * Entries: "pair" and "again" are closures over the upvalues, and "hole" is a
 * NULL placeholder. Expected: both closures return "u1" and 5; the placeholder
 * is false; the upvalues are popped, leaving only the table. */
static void setfuncs_captures_upvalues_and_placeholders(lua_State *L) {
    static const luaL_Reg funcs[] = {
        {"pair", captured_pair},
        {"hole", NULL},
        {"again", captured_pair},
        {NULL, NULL}
    };
    lua_newtable(L);
    lua_pushstring(L, "u1");
    lua_pushinteger(L, 5);
    luaL_setfuncs(L, funcs, 2);
    assert(lua_gettop(L) == 1);
    lua_setglobal(L, "aux_funcs");
    run(L, "=aux",
        "local a, b = aux_funcs.pair(); assert(a == 'u1' and b == 5); "
        "a, b = aux_funcs.again(); assert(a == 'u1' and b == 5); "
        "assert(aux_funcs.hole == false)");
}

/* Setup: nup = 0, with one plain function entry. Expected: the table remains
 * as the only stack value, and the function is callable. */
static void setfuncs_zero_upvalues(lua_State *L) {
    static const luaL_Reg funcs[] = {{"answer", plain_answer}, {NULL, NULL}};
    lua_newtable(L);
    luaL_setfuncs(L, funcs, 0);
    assert(lua_gettop(L) == 1);
    lua_setglobal(L, "aux_plain");
    run(L, "=aux", "assert(aux_plain.answer() == 42)");
}

/* Setup: a callback asks luaL_setfuncs for 2000000 upvalues. Expected: the
 * stack-space check fails before any entry is stored, with the message
 * "stack overflow (too many upvalues)" at the caller's line. */
static void setfuncs_rejects_excess_upvalues(lua_State *L) {
    register_fn(L, "probe_setfuncs_many", setfuncs_too_many);
    expect_error(L, "probe_setfuncs_many()",
                 "aux:1: stack overflow (too many upvalues)");
}

/* ----------------------------------------------------------------------------
 * Driver: each test runs with an empty stack and must leave it empty. The
 * marker is printed only after the test returns, so a failed assertion stops
 * the run without printing a false PASS line.
 * ------------------------------------------------------------------------- */
static void check(const char *name, void (*body)(lua_State *), lua_State *L) {
    assert(lua_gettop(L) == 0);
    body(L);
    assert(lua_gettop(L) == 0);
    ++marker_number;
    printf("PASS: auxiliary-api-%u %s\n", marker_number, name);
    fflush(stdout);
}

int main(void) {
    lua_State *L = lua_newstate(counted_allocator, &counts, 1103U);
    assert(L != NULL);
    luaL_openlibs(L);

    check("checkversion-accepts-matching-core",
          checkversion_accepts_matching_core, L);
    check("checkversion-rejects-version", checkversion_rejects_version, L);
    check("checkversion-rejects-numeric-layout",
          checkversion_rejects_numeric_layout, L);
    check("getmetafield-returns-raw-field", getmetafield_returns_raw_field, L);
    check("getmetafield-absent-pushes-nothing",
          getmetafield_absent_pushes_nothing, L);
    check("getmetafield-ignores-index-fallback",
          getmetafield_ignores_index_fallback, L);
    check("callmeta-calls-metamethod-with-object",
          callmeta_calls_metamethod_with_object, L);
    check("callmeta-absent-pushes-nothing", callmeta_absent_pushes_nothing, L);
    check("callmeta-resolves-relative-index",
          callmeta_resolves_relative_index, L);
    check("tolstring-renders-numbers", tolstring_renders_numbers, L);
    check("tolstring-renders-nil-and-booleans",
          tolstring_renders_nil_and_booleans, L);
    check("tolstring-keeps-string-bytes", tolstring_keeps_string_bytes, L);
    check("tolstring-uses-tostring-metafield",
          tolstring_uses_tostring_metafield, L);
    check("tolstring-rejects-nonstring-tostring",
          tolstring_rejects_nonstring_tostring, L);
    check("tolstring-uses-name-field", tolstring_uses_name_field, L);
    check("tolstring-ignores-nonstring-name",
          tolstring_ignores_nonstring_name, L);
    check("argerror-names-plain-argument", argerror_names_plain_argument, L);
    check("argerror-method-adjusts-argument",
          argerror_method_adjusts_argument, L);
    check("argerror-method-bad-self", argerror_method_bad_self, L);
    check("argerror-global-name-from-host",
          argerror_global_name_when_called_from_host, L);
    check("argerror-unknown-name-question-mark",
          argerror_unknown_name_uses_question_mark, L);
    check("typeerror-uses-name-field", typeerror_uses_name_field, L);
    check("typeerror-light-userdata", typeerror_light_userdata, L);
    check("typeerror-absent-and-nil", typeerror_absent_and_nil, L);
    check("checklstring-converts-and-keeps-length",
          checklstring_converts_numbers_and_keeps_length, L);
    check("checklstring-rejects-table", checklstring_rejects_table, L);
    check("optlstring-default-and-value", optlstring_default_and_value, L);
    check("optlstring-null-default", optlstring_null_default, L);
    check("checknumber-converts-numeric-string",
          checknumber_converts_numeric_string, L);
    check("checknumber-rejects-nonnumber", checknumber_rejects_nonnumber, L);
    check("optnumber-default-and-value", optnumber_default_and_value, L);
    check("optnumber-rejects-nonnumber", optnumber_rejects_nonnumber, L);
    check("checkinteger-accepts-integral-values",
          checkinteger_accepts_integral_values, L);
    check("checkinteger-rejects-fraction", checkinteger_rejects_fraction, L);
    check("checkinteger-rejects-nonnumber",
          checkinteger_rejects_nonnumber, L);
    check("optinteger-default-and-value", optinteger_default_and_value, L);
    check("optinteger-rejects-fraction", optinteger_rejects_fraction, L);
    check("checkstack-reserves-requested-slots",
          checkstack_reserves_requested_slots, L);
    check("checkstack-overflow-names-message",
          checkstack_overflow_names_message, L);
    check("checkstack-overflow-without-message",
          checkstack_overflow_without_message, L);
    check("checktype-accepts-matching-type",
          checktype_accepts_matching_type, L);
    check("checktype-rejects-other-type", checktype_rejects_other_type, L);
    check("checkany-accepts-nil", checkany_accepts_nil, L);
    check("checkany-rejects-absent", checkany_rejects_absent, L);
    check("newmetatable-registers-once", newmetatable_registers_once, L);
    check("newmetatable-returns-existing-value",
          newmetatable_returns_existing_value, L);
    check("setmetatable-attaches-registry-metatable",
          setmetatable_attaches_registry_metatable, L);
    check("testudata-matches-only-tagged-userdata",
          testudata_matches_only_tagged_userdata, L);
    check("checkudata-returns-payload", checkudata_returns_payload, L);
    check("checkudata-rejects-other-metatable",
          checkudata_rejects_other_metatable, L);
    check("where-reports-caller-line", where_reports_caller_line, L);
    check("where-level-zero-is-empty", where_level_zero_is_empty, L);
    check("where-missing-level-is-empty", where_missing_level_is_empty, L);
    check("error-prefixes-caller-line", error_prefixes_caller_line, L);
    check("error-from-host-has-no-position",
          error_from_host_has_no_position, L);
    check("checkoption-matches-and-defaults",
          checkoption_matches_and_defaults, L);
    check("checkoption-requires-argument-without-default",
          checkoption_requires_argument_without_default, L);
    check("checkoption-rejects-unknown-name",
          checkoption_rejects_unknown_name, L);
    check("fileresult-success-pushes-true", fileresult_success_pushes_true, L);
    check("fileresult-failure-with-name", fileresult_failure_with_name, L);
    check("fileresult-failure-without-name",
          fileresult_failure_without_name, L);
    check("fileresult-zero-errno-message", fileresult_zero_errno_message, L);
    check("execresult-clean-exit", execresult_clean_exit, L);
    check("execresult-errno-is-file-error",
          execresult_errno_is_file_error, L);
    check("execresult-exit-status-platform",
          execresult_exit_status_platform, L);
    check("execresult-signal-platform", execresult_signal_platform, L);
    check("ref-nil-returns-refnil", ref_nil_returns_refnil, L);
    check("ref-stores-value-and-pops", ref_stores_value_and_pops, L);
    check("unref-reuses-released-reference",
          unref_reuses_released_reference, L);
    check("unref-ignores-sentinels", unref_ignores_sentinels, L);
    check("len-string-and-table", len_string_and_table, L);
    check("len-uses-len-metamethod", len_uses_len_metamethod, L);
    check("len-rejects-non-integer", len_rejects_non_integer, L);
    check("setfuncs-captures-upvalues-and-placeholders",
          setfuncs_captures_upvalues_and_placeholders, L);
    check("setfuncs-zero-upvalues", setfuncs_zero_upvalues, L);
    check("setfuncs-rejects-excess-upvalues",
          setfuncs_rejects_excess_upvalues, L);

    lua_close(L);
    /* Every allocation made through the counted allocator must have been
     * released by lua_close: no live bytes and no live blocks remain. */
    assert(counts.bytes == 0 && counts.blocks == 0);
    puts("PASS: public auxiliary contract");
    return 0;
}
