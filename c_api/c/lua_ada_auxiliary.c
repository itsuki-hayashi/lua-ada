/* Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE.
 * Routines marked "derived" follow pinned Lua 5.5.1 lauxlib.c, which is
 * Copyright (C) 1994-2026 Lua.org, PUC-Rio and released under the MIT license
 * (see the notice at the end of lua.h).
 *
 * This translation unit is an ABI composition layer for the
 * auxiliary-library functions listed below. It contains no interpreter,
 * parser, VM, or standard-library algorithm:
 *
 *  - Every stack, value, string, table, metatable, registry, and error object
 *    is owned by the Ada runtime and is reached only through the public
 *    lua_* functions declared in lua.h.
 *  - Name lookup, option matching, registry walks, and luaL_setfuncs entries
 *    are the only loops. Each one charges the shared runtime budget through
 *    lua_ada_aux_charge before doing its work.
 *  - No setjmp/longjmp, no malloc, and no input-sized unmanaged buffer appear
 *    here. A raw error is raised by lua_error, which returns to C only after
 *    the Ada dispatcher has finished, so no transfer crosses an Ada frame.
 *  - Borrowed const char * results point into a live Lua string. A string
 *    must stay on the stack, unpopped, for as long as the pointer is read.
 *    Each routine notes which stack slot owns the bytes it hands back.
 *
 * Implemented functions (pinned 5.5.1 behavior, not 5.4):
 *   luaL_checkversion_, luaL_getmetafield, luaL_callmeta, luaL_tolstring,
 *   luaL_argerror, luaL_typeerror, luaL_checklstring, luaL_optlstring,
 *   luaL_checknumber, luaL_optnumber, luaL_checkinteger, luaL_optinteger,
 *   luaL_checkstack, luaL_checktype, luaL_checkany, luaL_newmetatable,
 *   luaL_setmetatable, luaL_testudata, luaL_checkudata, luaL_where, luaL_error,
 *   luaL_checkoption, luaL_fileresult, luaL_execresult, luaL_ref, luaL_unref,
 *   luaL_len, luaL_setfuncs.
 *
 * Separate unfinished surface: luaL_traceback, luaL_alloc, the
 * loadfile/loadbuffer family, luaL_makeseed, the buffer API, luaL_gsub and
 * luaL_addgsub, and luaL_getsubtable/luaL_requiref (already in
 * lua_ada_libraries.c).
 */

#include <errno.h>
#include <stddef.h>
#include <string.h>

#include "lua_ada_runtime_configuration.h"
#include "lauxlib.h"

/* Waiting statuses are interpreted only where the platform defines the
 * POSIX wait macros. Elsewhere, luaL_execresult keeps the raw status, as the
 * pinned lauxlib does when LUA_USE_POSIX is not defined. */
#if defined(LUA_USE_POSIX)
#include <sys/wait.h>
#endif

/* Shared-budget charge for one nontrivial loop step (or a bounded group of
 * steps). Implemented by the Ada runtime, not in this file.
 *
 * Contract assumed here: the call either returns normally after recording
 * 'amount' units of primary work, or it raises through the standard boundary
 * (the same route as lua_error), in which case it does not return. Nothing in
 * this file continues past a charge that raised. */
void lua_ada_aux_charge(lua_State *L, size_t amount);

static size_t counted_text(lua_State *L, const char *text) {
    size_t size = 0;
    while (text[size] != '\0') {
        ++size;
        if (size % 4096 == 0) lua_ada_aux_charge(L, 4096);
    }
    lua_ada_aux_charge(L, size % 4096);
    return size;
}

static int same_option(lua_State *L, const char *left, const char *right) {
    size_t index = 0, work = 0;
    /* Foreign option names have no counted extent. Account for their byte
     * comparisons as well as list traversal; a long common prefix cannot
     * hide unlimited runtime work behind one charged option-list entry. */
    for (;;) {
        if (++work == 64) {
            lua_ada_aux_charge(L, work);
            work = 0;
        }
        if (left[index] != right[index]) {
            lua_ada_aux_charge(L, work);
            return 0;
        }
        if (left[index] == '\0') {
            lua_ada_aux_charge(L, work);
            return 1;
        }
        ++index;
    }
}

/* ----------------------------------------------------------------------------
 * Static helpers (derived from pinned lauxlib.c)
 * ------------------------------------------------------------------------- */

/* findfield (derived): search the table at the top of the stack for a field
 * whose value equals the object at absolute index 'objidx'. A string key is
 * matched directly. A nested table is searched recursively with level - 1.
 *
 * Stack on entry: the table to search is at -1. 'level' bounds recursion
 * depth, so C recursion here is bounded and never enters the executor.
 * Stack on success: the matching field's name is at -1, with the table
 * below it. Stack on failure: restored to its entry height. The name pointer
 * the caller reads later is therefore rooted by the stack, not by C. */
static int findfield(lua_State *L, int objidx, int level) {
    if (level == 0 || !lua_istable(L, -1))
        return 0;  /* nothing to search, or the value is not a table */
    lua_pushnil(L);  /* first key for lua_next */
    while (lua_next(L, -2)) {  /* stack: table, key, value */
        /* Charge each traversed entry, including non-string keys, so a huge
         * registry consumes the shared budget even when it finds nothing. */
        lua_ada_aux_charge(L, 1);
        if (lua_type(L, -2) == LUA_TSTRING) {  /* ignore non-string keys */
            if (lua_rawequal(L, objidx, -1)) {  /* direct match */
                lua_pop(L, 1);  /* drop the value, keep the name */
                return 1;
            }
            else if (findfield(L, objidx, level - 1)) {
                /* Stack now: outer table, outer key, nested table, nested
                 * key (top). The recursive success left the nested key on
                 * top. Push '.', overwrite the nested table slot (-3) with
                 * it, and concatenate "outer key" . "." . "nested key" into
                 * one new string that replaces the outer key slot. */
                lua_pushliteral(L, ".");
                lua_replace(L, -3);  /* '.' takes the nested table's slot */
                lua_concat(L, 3);  /* outer key . '.' . nested key */
                return 1;
            }
        }
        lua_pop(L, 1);  /* drop the value; lua_next keeps the key */
    }
    return 0;  /* lua_next popped the final key itself */
}

/* pushglobalfuncname (derived): find a loaded-module name for the function
 * described by 'ar' (a lua_getstack result). Returns 1 with the name at the
 * top, or 0 with the stack restored to its entry height.
 *
 * Phases: (1) push the function being described; (2) push the registry's
 * _LOADED table; (3) search it up to two levels deep. A "_G." prefix is
 * removed so that "_G.print" is reported as "print". The final name is copied
 * into slot top+1 and everything above it is popped, so the name stays on the
 * stack for the caller to read safely. */
static int pushglobalfuncname(lua_State *L, lua_Debug *ar) {
    int top = lua_gettop(L);
    lua_getinfo(L, "f", ar);  /* push the function (slot top+1) */
    lua_getfield(L, LUA_REGISTRYINDEX, LUA_LOADED_TABLE);
    luaL_checkstack(L, 6, "not enough stack");  /* room for findfield */
    if (findfield(L, top + 1, 2)) {
        /* 'name' points into the Lua string at -1. That string stays
         * on the stack until it is copied below, so the bytes stay valid. */
        const char *name = lua_tostring(L, -1);
        if (strncmp(name, LUA_GNAME ".", 3) == 0) {  /* strip "_G." */
            lua_pushstring(L, name + 3);  /* copy: Ada owns the new string */
            lua_remove(L, -2);  /* remove the original, prefixed name */
        }
        lua_copy(L, -1, top + 1);  /* the name goes into the result slot */
        lua_settop(L, top + 1);  /* leave only the name above the entry */
        return 1;
    }
    else {
        lua_settop(L, top);  /* drop the function and the loaded table */
        return 0;
    }
}

/* inspect_termination (derived): interpret a waitpid-style status as
 * luaL_execresult does. With POSIX, a normal exit yields the exit code and a
 * signal yields the signal number with what = "signal". Without POSIX
 * support, the status is left unchanged and what stays "exit". */
static void inspect_termination(int *status, const char **what) {
#if defined(LUA_USE_POSIX)
    if (WIFEXITED(*status)) {
        *status = WEXITSTATUS(*status);
    }
    else if (WIFSIGNALED(*status)) {
        *status = WTERMSIG(*status);
        *what = "signal";
    }
#else
    (void)status;  /* no wait-status macros on this platform */
    (void)what;
#endif
}

/* tag_error (derived): raise a standard "<type> expected, got ..." argument
 * error for an argument whose type is not 'tag'. Never returns normally. */
static void tag_error(lua_State *L, int arg, int tag) {
    luaL_typeerror(L, arg, lua_typename(L, tag));
}

/* interror (derived): a number that cannot convert to an integer gets a
 * precise "no integer representation" message. Any other value gets the
 * ordinary type error. Never returns normally. */
static void interror(lua_State *L, int arg) {
    if (lua_isnumber(L, arg))
        luaL_argerror(L, arg, "number has no integer representation");
    else
        tag_error(L, arg, LUA_TNUMBER);
}

/* ----------------------------------------------------------------------------
 * Version and metamethod helpers
 * ------------------------------------------------------------------------- */

/* luaL_checkversion_ (derived): verify that the caller's numeric sizes and
 * version number match the core. Leaves the stack unchanged on success. */
void luaL_checkversion_(lua_State *L, lua_Number ver, size_t sz) {
    lua_Number v = lua_version(L);
    if (sz != LUAL_NUMSIZES)  /* numeric type layout differs */
        luaL_error(L, "core and library have incompatible numeric types");
    else if (v != ver)
        luaL_error(L, "version mismatch: app. needs %f, Lua core provides %f",
                   (LUAI_UACNUMBER)ver, (LUAI_UACNUMBER)v);
}

/* luaL_getmetafield (derived): push obj's metafield 'event' and return its
 * type, or push nothing and return LUA_TNIL. The metatable is removed in every
 * case. The raw lookup bypasses __index, as the pinned routine does. */
int luaL_getmetafield(lua_State *L, int obj, const char *event) {
    if (!lua_getmetatable(L, obj))  /* no metatable: push nothing */
        return LUA_TNIL;
    else {
        int tt;
        lua_pushstring(L, event);  /* stack: metatable, event name */
        tt = lua_rawget(L, -2);  /* stack: metatable, field (raw) */
        if (tt == LUA_TNIL)  /* absent: remove both temporaries */
            lua_pop(L, 2);
        else  /* present: keep the field, drop only the metatable */
            lua_remove(L, -2);
        return tt;
    }
}

/* luaL_callmeta (derived): if obj has metafield 'event', call it with obj as
 * its only argument, leave one result on the stack, and return 1. Otherwise
 * return 0 and push nothing. A relative index is resolved first, because the
 * pushes below would otherwise change what it denotes. */
int luaL_callmeta(lua_State *L, int obj, const char *event) {
    obj = lua_absindex(L, obj);
    if (luaL_getmetafield(L, obj, event) == LUA_TNIL)  /* no metafield? */
        return 0;
    lua_pushvalue(L, obj);  /* the one argument */
    lua_call(L, 1, 1);  /* a raised error leaves through the C boundary */
    return 1;
}

/* luaL_len (derived): length of the value at 'idx' through the metamethod
 * path (lua_len), which must produce an integer. Otherwise it raises
 * "object length is not an integer". Leaves the stack unchanged. */
lua_Integer luaL_len(lua_State *L, int idx) {
    lua_Integer l;
    int isnum;
    lua_len(L, idx);  /* pushes the length, honoring __len */
    l = lua_tointegerx(L, -1, &isnum);
    if (luai_unlikely(!isnum))
        luaL_error(L, "object length is not an integer");
    lua_pop(L, 1);  /* remove the length value */
    return l;
}

/* luaL_tolstring (derived): convert the value at 'idx' to a string and push
 * it. Order of precedence: __tostring (which must return a string), then the
 * built-in rendering, then "__name: address" for other values.
 *
 * Ownership: the returned pointer belongs to the string pushed at the top
 * (-1). That string remains on the stack until the caller pops it. */
const char *luaL_tolstring(lua_State *L, int idx, size_t *len) {
    idx = lua_absindex(L, idx);  /* stable even after the pushes below */
    if (luaL_callmeta(L, idx, "__tostring")) {  /* metafield produced a value */
        if (!lua_isstring(L, -1))
            luaL_error(L, "'__tostring' must return a string");
    }
    else {
        switch (lua_type(L, idx)) {
            case LUA_TNUMBER: {
                /* lua_numbertocstring uses the core's own number format.
                 * lua_pushstring copies the bytes into a Lua string, so the
                 * local buffer does not outlive this block. */
                char buff[LUA_N2SBUFFSZ];
                lua_numbertocstring(L, idx, buff);
                lua_pushstring(L, buff);
                break;
            }
            case LUA_TSTRING:
                lua_pushvalue(L, idx);  /* the string itself, rooted */
                break;
            case LUA_TBOOLEAN:
                lua_pushstring(L, (lua_toboolean(L, idx) ? "true" : "false"));
                break;
            case LUA_TNIL:
                lua_pushliteral(L, "nil");
                break;
            default: {
                /* "__name" supplies the kind; otherwise use the basic type.
                 * The __name value, if any, is rooted at -1 while the result
                 * is formatted and is then removed from beneath it. */
                int tt = luaL_getmetafield(L, idx, "__name");
                const char *kind = (tt == LUA_TSTRING) ? lua_tostring(L, -1) :
                                                         luaL_typename(L, idx);
                lua_pushfstring(L, "%s: %p", kind, lua_topointer(L, idx));
                if (tt != LUA_TNIL)
                    lua_remove(L, -2);  /* drop the __name value */
                break;
            }
        }
    }
    return lua_tolstring(L, -1, len);
}

/* ----------------------------------------------------------------------------
 * Argument checking and error formatting
 * ------------------------------------------------------------------------- */

/* luaL_where (derived): push "source:line: " for the function at 'level', or
 * the empty string if no line information exists. Never raises by itself. */
void luaL_where(lua_State *L, int level) {
    lua_Debug ar;
    if (lua_getstack(L, level, &ar)) {  /* does the level exist? */
        lua_getinfo(L, "Sl", &ar);  /* source and current line */
        if (ar.currentline > 0) {  /* is there line information? */
            lua_pushfstring(L, "%s:%d: ", ar.short_src, ar.currentline);
            return;
        }
    }
    lua_pushfstring(L, "");  /* no information available */
}

/* luaL_error (derived): format a message, prefix it with the current position
 * (luaL_where level 1), and raise it as a runtime error. The lua_error call
 * does not return. The variadic arguments are forwarded to the Ada formatter
 * as a va_list, as the pinned routine does. */
int luaL_error(lua_State *L, const char *fmt, ...) {
    va_list argp;
    va_start(argp, fmt);
    luaL_where(L, 1);  /* position prefix, rooted on the stack */
    lua_pushvfstring(L, fmt, argp);  /* formatted body, rooted */
    va_end(argp);
    lua_concat(L, 2);  /* prefix . body, one new string */
    return lua_error(L);
}

/* luaL_argerror (derived): raise "bad argument #n to 'name' (extramsg)",
 * adjusting for extra arguments and method calls exactly as the pinned
 * routine does. A missing frame reports the bare argument number. The
 * function name is found by a loaded-module search when debug information
 * lacks one.
 *
 * Lifetime: 'ar.name' may come from pushglobalfuncname. That name remains on
 * the stack above the entry height until luaL_error has built the message. */
int luaL_argerror(lua_State *L, int arg, const char *extramsg) {
    lua_Debug ar;
    const char *argword;
    if (!lua_getstack(L, 0, &ar))  /* no frame to describe */
        return luaL_error(L, "bad argument #%d (%s)", arg, extramsg);
    lua_getinfo(L, "nt", &ar);  /* name, namewhat, extraargs */
    if (arg <= ar.extraargs)  /* error in an extra argument */
        argword = "extra argument";
    else {
        arg -= ar.extraargs;  /* extra arguments are not counted */
        if (strcmp(ar.namewhat, "method") == 0) {  /* colon syntax */
            arg--;  /* the implicit self is not counted */
            if (arg == 0)  /* error is in self itself */
                return luaL_error(L, "calling '%s' on bad self (%s)",
                                  ar.name, extramsg);
            /* otherwise an ordinary argument error follows */
        }
        argword = "argument";
    }
    if (ar.name == NULL)  /* no name from debug information */
        ar.name = (pushglobalfuncname(L, &ar)) ? lua_tostring(L, -1) : "?";
    return luaL_error(L, "bad %s #%d to '%s' (%s)",
                      argword, arg, ar.name, extramsg);
}

/* luaL_typeerror (derived): build "<tname> expected, got <actual>" and raise
 * it through luaL_argerror. The actual type prefers a string "__name"
 * metafield, then "light userdata", then the basic type name. The __name
 * string stays rooted while the message is formatted. */
int luaL_typeerror(lua_State *L, int arg, const char *tname) {
    const char *msg;
    const char *typearg;  /* name for the type of the actual argument */
    if (luaL_getmetafield(L, arg, "__name") == LUA_TSTRING)
        typearg = lua_tostring(L, -1);  /* the __name string, on the stack */
    else if (lua_type(L, arg) == LUA_TLIGHTUSERDATA)
        typearg = "light userdata";  /* special name for messages */
    else
        typearg = luaL_typename(L, arg);  /* standard name */
    msg = lua_pushfstring(L, "%s expected, got %s", tname, typearg);
    return luaL_argerror(L, arg, msg);
}

/* luaL_checklstring (derived): return the string value of argument 'arg'
 * (numbers are converted in place, as lua_tolstring does), and store its
 * length in *len if len is not NULL. Raises a type error otherwise. The
 * pointer is owned by that stack slot. */
const char *luaL_checklstring(lua_State *L, int arg, size_t *len) {
    const char *s = lua_tolstring(L, arg, len);
    if (luai_unlikely(!s))
        tag_error(L, arg, LUA_TSTRING);
    return s;
}

/* luaL_optlstring (derived): as luaL_checklstring, but an absent or nil
 * argument yields 'def'. In that case *len, if requested, is strlen(def), or
 * 0 for a NULL default. 'def' is the caller's string and is not copied. */
const char *luaL_optlstring(lua_State *L, int arg, const char *def,
                            size_t *len) {
    if (lua_isnoneornil(L, arg)) {
        if (len)
            *len = (def ? counted_text(L, def) : 0);
        return def;
    }
    else return luaL_checklstring(L, arg, len);
}

/* luaL_checknumber (derived): return argument 'arg' as a number, converting a
 * numeric string if needed. Raises a type error for anything else. */
lua_Number luaL_checknumber(lua_State *L, int arg) {
    int isnum;
    lua_Number d = lua_tonumberx(L, arg, &isnum);
    if (luai_unlikely(!isnum))
        tag_error(L, arg, LUA_TNUMBER);
    return d;
}

/* luaL_optnumber (derived): luaL_checknumber, or 'def' for absent/nil. */
lua_Number luaL_optnumber(lua_State *L, int arg, lua_Number def) {
    return luaL_opt(L, luaL_checknumber, arg, def);
}

/* luaL_checkinteger (derived): return argument 'arg' as an integer. A number
 * without an exact integer representation raises the "no integer
 * representation" message. Any other type gets the ordinary type error. */
lua_Integer luaL_checkinteger(lua_State *L, int arg) {
    int isnum;
    lua_Integer d = lua_tointegerx(L, arg, &isnum);
    if (luai_unlikely(!isnum)) {
        interror(L, arg);
    }
    return d;
}

/* luaL_optinteger (derived): luaL_checkinteger, or 'def' for absent/nil. */
lua_Integer luaL_optinteger(lua_State *L, int arg, lua_Integer def) {
    return luaL_opt(L, luaL_checkinteger, arg, def);
}

/* luaL_checkstack (derived): guarantee 'space' extra stack slots, or raise
 * "stack overflow (msg)". The failure path needs slots to format its own
 * message, so the error is not raised before lua_checkstack succeeds. */
void luaL_checkstack(lua_State *L, int space, const char *msg) {
    if (luai_unlikely(!lua_checkstack(L, space))) {
        if (msg)
            luaL_error(L, "stack overflow (%s)", msg);
        else
            luaL_error(L, "stack overflow");
    }
}

/* luaL_checktype (derived): raise a type error unless argument 'arg' has the
 * basic type 't'. */
void luaL_checktype(lua_State *L, int arg, int t) {
    if (luai_unlikely(lua_type(L, arg) != t))
        tag_error(L, arg, t);
}

/* luaL_checkany (derived): raise "value expected" if argument 'arg' is absent.
 * A nil argument is present and passes. */
void luaL_checkany(lua_State *L, int arg) {
    if (luai_unlikely(lua_type(L, arg) == LUA_TNONE))
        luaL_argerror(L, arg, "value expected");
}

/* luaL_checkoption (derived): match argument 'arg' (or 'def' if absent and a
 * default is given) against the NULL-terminated list 'lst', and return its
 * index. An unknown name raises "invalid option". Each comparison is charged
 * to the budget, so an oversized list cannot run unaccounted.
 *
 * Lifetime: 'name' borrows the stack slot for 'arg', or 'def'. The message
 * string made by lua_pushfstring stays on the stack for luaL_argerror. */
int luaL_checkoption(lua_State *L, int arg, const char *def,
                     const char *const lst[]) {
    const char *name = (def) ? luaL_optstring(L, arg, def) :
                               luaL_checkstring(L, arg);
    int i;
    for (i = 0; lst[i]; i++) {
        lua_ada_aux_charge(L, 1);  /* one option comparison */
        if (same_option(L, lst[i], name))
            return i;
    }
    return luaL_argerror(L, arg,
                         lua_pushfstring(L, "invalid option '%s'", name));
}

/* ----------------------------------------------------------------------------
 * Userdata metatables and type testing
 * ------------------------------------------------------------------------- */

/* luaL_newmetatable (derived): create a metatable with __name = tname and
 * register it as registry[tname]. If that registry key is already in use,
 * leave the existing value on the stack and return 0. Otherwise leave the
 * new metatable on the stack and return 1. */
int luaL_newmetatable(lua_State *L, const char *tname) {
    if (luaL_getmetatable(L, tname) != LUA_TNIL)  /* name already in use? */
        return 0;  /* leave the previous value on top */
    lua_pop(L, 1);
    lua_createtable(L, 0, 2);  /* the metatable, sized for two fields */
    lua_pushstring(L, tname);
    lua_setfield(L, -2, "__name");  /* metatable.__name = tname */
    lua_pushvalue(L, -1);  /* keep one copy on the stack as the result */
    lua_setfield(L, LUA_REGISTRYINDEX, tname);  /* registry[tname] = mt */
    return 1;
}

/* luaL_setmetatable (derived): set the metatable for the value at the top of
 * the stack to registry[tname]. The value stays on the stack, and
 * lua_setmetatable consumes the metatable pushed here. */
void luaL_setmetatable(lua_State *L, const char *tname) {
    luaL_getmetatable(L, tname);  /* metatable above the value */
    lua_setmetatable(L, -2);  /* consumes the metatable */
}

/* luaL_testudata (derived): return the userdata payload pointer if argument
 * 'ud' is a userdata whose metatable is registry[tname], otherwise NULL. Both
 * metatables are removed from the stack on every path that pushed them. */
void *luaL_testudata(lua_State *L, int ud, const char *tname) {
    void *p = lua_touserdata(L, ud);
    if (p != NULL) {  /* value is a userdata (or light userdata) */
        if (lua_getmetatable(L, ud)) {  /* it has a metatable */
            luaL_getmetatable(L, tname);  /* the expected metatable */
            if (!lua_rawequal(L, -1, -2))  /* different metatables */
                p = NULL;
            lua_pop(L, 2);  /* remove both metatables */
            return p;
        }
    }
    return NULL;  /* not a userdata with a metatable */
}

/* luaL_checkudata (derived): luaL_testudata, but a mismatch raises the
 * standard "<tname> expected" type error through luaL_argerror. */
void *luaL_checkudata(lua_State *L, int ud, const char *tname) {
    void *p = luaL_testudata(L, ud, tname);
    luaL_argexpected(L, p != NULL, ud, tname);
    return p;
}

/* ----------------------------------------------------------------------------
 * System-result helpers
 * ------------------------------------------------------------------------- */

/* luaL_fileresult (derived): report a file-operation outcome. Success pushes
 * true and returns 1. Failure pushes fail, "fname: strerror" (or the message
 * alone with no fname), and errno, then returns 3. errno is captured first,
 * because the Lua calls below may change it.
 *
 * Lifetime: 'msg' comes from strerror, whose storage is not a Lua value. It
 * is used at once, and lua_pushstring/lua_pushfstring copy it into Ada. */
int luaL_fileresult(lua_State *L, int stat, const char *fname) {
    int en = errno;  /* save before any API call can change it */
    if (stat) {
        lua_pushboolean(L, 1);
        return 1;
    }
    else {
        const char *msg;
        luaL_pushfail(L);
        msg = (en != 0) ? strerror(en) : "(no extra info)";
        if (fname)
            lua_pushfstring(L, "%s: %s", fname, msg);
        else
            lua_pushstring(L, msg);
        lua_pushinteger(L, en);
        return 3;
    }
}

/* luaL_execresult (derived): report the outcome of a process. If the status
 * is a failure and errno is set, this is treated as a file error. Otherwise
 * it pushes true or fail, the termination kind ("exit" or "signal"), and the
 * code. Returns 3. On platforms without POSIX status macros, the raw status
 * is pushed unchanged, as the pinned routine does. */
int luaL_execresult(lua_State *L, int stat) {
    if (stat != 0 && errno != 0)  /* failure with an errno: a file error */
        return luaL_fileresult(L, 0, NULL);
    else {
        const char *what = "exit";  /* kind of termination */
        inspect_termination(&stat, &what);  /* may change both outputs */
        if (*what == 'e' && stat == 0)  /* clean exit with status 0 */
            lua_pushboolean(L, 1);
        else
            luaL_pushfail(L);
        lua_pushstring(L, what);
        lua_pushinteger(L, stat);
        return 3;  /* true/fail, what, code */
    }
}

/* ----------------------------------------------------------------------------
 * References
 * ------------------------------------------------------------------------- */

/* luaL_ref (derived): store the value at the top of the stack in table 't'
 * under a fresh integer key, pop it, and return that key. A nil value gives
 * LUA_REFNIL and stores nothing.
 *
 * Free-list invariant (pinned 5.5.1): t[1] holds the head of the free list,
 * where each freed key stores the next freed key. Index 1 is reserved for that
 * list and is never handed out. A zero head means the list is empty. On an
 * empty table the first reference is therefore 2, not 1. The table must be
 * the registry or another table owned by the caller. The stored value is
 * rooted by the table, so it need not stay on the stack after this returns. */
int luaL_ref(lua_State *L, int t) {
    int ref;
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);  /* nil is never stored */
        return LUA_REFNIL;  /* the fixed nil reference */
    }
    t = lua_absindex(L, t);  /* resolve before pushes change relative slots */
    if (lua_rawgeti(L, t, 1) == LUA_TNUMBER)  /* free list already exists? */
        ref = (int)lua_tointeger(L, -1);  /* ref = t[1], the free-list head */
    else {  /* first use: initialize the list head */
        ref = 0;  /* list is empty */
        lua_pushinteger(L, 0);
        lua_rawseti(L, t, 1);  /* t[1] = 0 */
    }
    lua_pop(L, 1);  /* drop the head value pushed above */
    if (ref != 0) {  /* reuse the first free key */
        lua_rawgeti(L, t, ref);  /* the next free key after 'ref' */
        lua_rawseti(L, t, 1);  /* t[1] = that next key */
    }
    else  /* no free key: take the next index past the sequence */
        ref = (int)lua_rawlen(L, t) + 1;
    lua_rawseti(L, t, ref);  /* t[ref] = the value at the top */
    return ref;
}

/* luaL_unref (derived): release reference 'ref' in table 't' by pushing it
 * onto the free list. Negative references (LUA_REFNIL, LUA_NOREF) are
 * ignored. The caller must release each live nonnegative reference once. */
void luaL_unref(lua_State *L, int t, int ref) {
    if (ref >= 0) {
        t = lua_absindex(L, t);
        lua_rawgeti(L, t, 1);  /* the current free-list head */
        lua_rawseti(L, t, ref);  /* t[ref] = old head (the new link) */
        lua_pushinteger(L, ref);
        lua_rawseti(L, t, 1);  /* t[1] = ref, the new head */
    }
}

/* ----------------------------------------------------------------------------
 * Function-table registration
 * ------------------------------------------------------------------------- */

/* luaL_setfuncs (derived): for each entry of the NULL-terminated list 'l',
 * store a C closure (or false for a NULL placeholder) in the table below the
 * 'nup' upvalues at the top of the stack. Each closure receives copies of
 * those upvalues. On return the upvalues are popped and the table remains.
 *
 * Charging: each list entry is charged with its upvalue copies, so a huge
 * registration list is accounted against the shared budget. */
void luaL_setfuncs(lua_State *L, const luaL_Reg *l, int nup) {
    luaL_checkstack(L, nup, "too many upvalues");  /* room for copies */
    for (; l->name != NULL; l++) {
        lua_ada_aux_charge(L, (size_t)nup + 1);  /* this entry and its copies */
        if (l->func == NULL)  /* placeholder entry */
            lua_pushboolean(L, 0);
        else {
            int i;
            for (i = 0; i < nup; i++)  /* copy the upvalues to the top */
                lua_pushvalue(L, -nup);
            lua_pushcclosure(L, l->func, nup);  /* closure with the copies */
        }
        lua_setfield(L, -(nup + 2), l->name);  /* table[name] = value */
    }
    lua_pop(L, nup);  /* remove the upvalues, leaving the table */
}
