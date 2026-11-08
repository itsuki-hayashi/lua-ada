/* Callable standard library identities through the real public C ABI.
 * Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE. */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "consumer_allocator.h"
#include "../../tests/c/argument_registry_callbacks.h"

static struct allocation_counts counts;
static lua_CFunction degrees, direct_pairs, direct_yield, direct_error;
static lua_CFunction direct_pcall;
static lua_CFunction direct_sin;
static lua_CFunction direct_load;
static int after_direct;

static void run(lua_State *L, const char *source) {
    int status = luaL_dostring(L, source);
    if (status != LUA_OK) fprintf(stderr, "%s\n", lua_tostring(L, -1));
    assert(status == LUA_OK);
}

static lua_CFunction field(lua_State *L, const char *module, const char *name) {
    lua_CFunction result;
    if (module) {
        lua_getglobal(L, module); lua_getfield(L, -1, name);
        lua_remove(L, -2);
    } else lua_getglobal(L, name);
    assert(lua_iscfunction(L, -1));
    result = lua_tocfunction(L, -1); assert(result);
    return result;
}

static void exposed_functions(lua_State *L) {
    static const char *const globals[] =
        {"assert", "error", "next", "pcall", "print", "select", "tonumber",
         "tostring", "pairs", "ipairs", "load", "require"};
    static const char *const modules[] =
        {"math", "string", "table", "utf8", "coroutine", "debug", "io", "os",
         "debug"};
    static const char *const names[] =
        {"deg", "format", "concat", "codes", "yield", "getinfo", "open", "time",
         "debug"};
    size_t i;
    lua_Debug ar;
    for (i = 0; i < sizeof globals / sizeof globals[0]; ++i) {
        (void)field(L, NULL, globals[i]); lua_pop(L, 1);
    }
    for (i = 0; i < sizeof modules / sizeof modules[0]; ++i) {
        lua_CFunction function = field(L, modules[i], names[i]);
        lua_pushcfunction(L, function);
        assert(lua_rawequal(L, -1, -2));
        assert(lua_topointer(L, -1) == lua_topointer(L, -2));
        assert(lua_getinfo(L, ">u", &ar));
        assert(ar.nups == 0 && ar.nparams == 0 && ar.isvararg);
        lua_pop(L, 1);
    }
}

static void stateless_roundtrip(lua_State *L) {
    degrees = field(L, "math", "deg");
    lua_pushcfunction(L, degrees); assert(lua_rawequal(L, 1, 2));
    lua_pushnumber(L, 3); lua_call(L, 1, 1);
    assert(fabs(lua_tonumber(L, -1) - 171.88733853924697) < 1e-10);
    lua_settop(L, 0);
}

static void repeated_opener_identity(lua_State *L) {
    lua_CFunction before = field(L, "math", "deg");
    lua_pushcfunction(L, luaopen_math); lua_call(L, 0, 1);
    lua_getfield(L, -1, "deg");
    assert(lua_tocfunction(L, -1) == before && lua_rawequal(L, 1, -1));
    lua_settop(L, 0);
}

static void direct_host_call(lua_State *L) {
    lua_pushnumber(L, 3);
    assert(degrees(L) == 1);
    assert(fabs(lua_tonumber(L, -1) - 171.88733853924697) < 1e-10);
    lua_settop(L, 0);
}

static int forward_degrees(lua_State *L) { return degrees(L); }
static int forward_pairs(lua_State *L) {
    int results = direct_pairs(L);
    ++after_direct;
    return results;
}
static int forward_yield(lua_State *L) {
    int results = direct_yield(L);
    ++after_direct;
    return results;
}
static int forward_error(lua_State *L) { return direct_error(L); }
static int forward_pcall(lua_State *L) { return direct_pcall(L); }

static void direct_c_call(lua_State *L) {
    lua_pushcfunction(L, forward_degrees); lua_pushnumber(L, 3);
    lua_call(L, 1, 1);
    assert(fabs(lua_tonumber(L, -1) - 171.88733853924697) < 1e-10);
    lua_settop(L, 0);
}

static void direct_callback_frame(lua_State *L) {
    direct_pairs = field(L, NULL, "pairs"); lua_pop(L, 1);
    lua_pushcfunction(L, forward_pairs); lua_setglobal(L, "forward_pairs");
    after_direct = 0;
    run(L, "local t=setmetatable({},{__pairs=function(self) "
           "assert(debug.getinfo(2,'f').func==forward_pairs);"
           "return next,{value=91},nil end});"
           "local f,s,v=forward_pairs(t);assert(f==next and s.value==91 "
           "and v==nil)");
    assert(after_direct == 1);
}

static void captured_roundtrip(lua_State *L) {
    lua_CFunction random = field(L, "math", "random");
    lua_CFunction seed = field(L, "math", "randomseed");
    lua_Integer first, repeated;
    const char *name = lua_getupvalue(L, 1, 1);
    assert(name && !*name && lua_isuserdata(L, -1));
    lua_pushcclosure(L, random, 1);
    assert(!lua_rawequal(L, 1, 3) && lua_tocfunction(L, 3) == random);
    assert(lua_upvalueid(L, 1, 1) != lua_upvalueid(L, 3, 1));
    assert(lua_getupvalue(L, 1, 1)); lua_pushcclosure(L, seed, 1);
    lua_pushvalue(L, 4); lua_pushinteger(L, 123); lua_pushinteger(L, 456);
    lua_call(L, 2, 0);
    lua_pushvalue(L, 1); lua_pushinteger(L, 1); lua_pushinteger(L, 100000);
    lua_call(L, 2, 1); first = lua_tointeger(L, -1); lua_pop(L, 1);
    lua_pushvalue(L, 4); lua_pushinteger(L, 123); lua_pushinteger(L, 456);
    lua_call(L, 2, 0);
    lua_pushvalue(L, 3); lua_pushinteger(L, 1); lua_pushinteger(L, 100000);
    lua_call(L, 2, 1); repeated = lua_tointeger(L, -1);
    assert(first == repeated);
    lua_settop(L, 0);
}

static void iterator_identity(lua_State *L) {
    run(L, "local a=ipairs{};local b=ipairs{};assert(a==b);"
           "local a=utf8.codes('a');local b=utf8.codes('b');assert(a==b);"
           "local c=utf8.codes('a',true);local d=utf8.codes('b',true);"
           "assert(c==d and a~=c);"
           "return string.gmatch('a','.'),string.gmatch('b','.')");
    assert(!lua_rawequal(L, 1, 2));
    assert(lua_tocfunction(L, 1) &&
           lua_tocfunction(L, 1) == lua_tocfunction(L, 2));
    lua_settop(L, 0);
}

static void pointer_formats(lua_State *L) {
    run(L, "local p=function(v)return string.format('%p',v)end;"
           "assert(p(print)~='(null)' and p(print)==p(print));"
           "assert(p(assert)~=p(print));"
           "assert(p(coroutine.running())~='(null)');"
           "assert(p(io.stdin)~='(null)' and p(io.stdin)==p(io.stdin));"
           "assert(p(nil)=='(null)' and p(4)=='(null)');"
           "assert(#string.format('%90p',print)==90)");
}

static void direct_error_identity(lua_State *L) {
    direct_error = field(L, NULL, "error"); lua_pop(L, 1);
    lua_pushcfunction(L, forward_error); lua_setglobal(L, "forward_error");
    run(L, "local marker={};local ok,e=pcall(forward_error,marker);"
           "assert(not ok and e==marker)");
}

static void direct_protected_results(lua_State *L) {
    direct_pcall = field(L, NULL, "pcall"); lua_pop(L, 1);
    lua_pushcfunction(L, forward_pcall); lua_setglobal(L, "forward_pcall");
    run(L, "local r=table.pack(forward_pcall(function()return 11,22 end));"
           "assert(r.n==3 and r[1]==true and r[2]==11 and r[3]==22);"
           "local marker={};local r=table.pack(forward_pcall(function()"
           "error(marker)end));assert(r.n==2 and r[1]==false and r[2]==marker)");
}

static void direct_yield_continuation(lua_State *L) {
    lua_State *co;
    int results = -1;
    direct_yield = field(L, "coroutine", "yield"); lua_pop(L, 1);
    lua_pushcfunction(L, forward_yield); lua_setglobal(L, "forward_yield");
    co = lua_newthread(L); after_direct = 0;
    assert(luaL_loadstring(co, "return forward_yield(10,20)") == LUA_OK);
    assert(lua_resume(co, L, 0, &results) == LUA_YIELD && results == 2);
    assert(lua_tointeger(co, -2) == 10 && lua_tointeger(co, -1) == 20);
    lua_pop(co, results); lua_pushinteger(co, 31); lua_pushinteger(co, 32);
    assert(lua_resume(co, L, 2, &results) == LUA_OK && results == 2);
    assert(lua_tointeger(co, -2) == 31 && lua_tointeger(co, -1) == 32);
    assert(after_direct == 0);
    lua_settop(L, 0);
}

static void direct_callback_yield(lua_State *L) {
    lua_State *co = lua_newthread(L);
    int results = -1;
    after_direct = 0;
    assert(luaL_loadstring(co,
        "local t=setmetatable({},{__pairs=function()coroutine.yield(71);"
        "return next,{value=92},nil end});"
        "local f,s,v=forward_pairs(t);assert(f==next and v==nil);"
        "return s.value") == LUA_OK);
    assert(lua_resume(co, L, 0, &results) == LUA_YIELD && results == 1);
    assert(lua_tointeger(co, -1) == 71); lua_pop(co, 1);
    assert(lua_resume(co, L, 0, &results) == LUA_OK && results == 1);
    assert(lua_tointeger(co, -1) == 92 && after_direct == 0);
    lua_settop(L, 0);
}

static void scalar_refusal(lua_State *L) {
    lua_Debug ar;
    assert(lua_checkstack(L, 64));
    counts.refuse = 1;
    lua_pushcfunction(L, degrees);
    assert(lua_tocfunction(L, -1) == degrees && lua_topointer(L, -1));
    assert(lua_getinfo(L, ">u", &ar) && ar.nups == 0);
    counts.refuse = 0;
}

static int push_captured(lua_State *L) {
    lua_pushinteger(L, 11); lua_pushcclosure(L, degrees, 1);
    return 1;
}
static void captured_refusal_recovery(lua_State *L) {
    int status;
    lua_pushcfunction(L, push_captured); counts.refuse = 1;
    status = lua_pcall(L, 0, 1, 0); counts.refuse = 0;
    assert(status == LUA_ERRMEM); lua_pop(L, 1);
    lua_pushcfunction(L, push_captured); assert(lua_pcall(L, 0, 1, 0) == LUA_OK);
    assert(lua_tocfunction(L, -1) == degrees);
    lua_pushnumber(L, 3); lua_call(L, 1, 1);
    assert(fabs(lua_tonumber(L, -1) - 171.88733853924697) < 1e-10);
    lua_settop(L, 0);
}

static int forward_sin(lua_State *L) { return direct_sin(L); }

static void direct_argument_owner(lua_State *L) {
    /* A direct C pointer adds no public CI. Its argument diagnostic belongs
       to this original C function, even when Ada schedules an owned phase. */
    direct_sin = field(L, "math", "sin"); lua_pop(L, 1);
    lua_pushcfunction(L, forward_sin); lua_setglobal(L, "forward_sin");
    run(L, "local ok,e=pcall(forward_sin,{});assert(not ok and e=="
           "\"bad argument #1 to 'forward_sin' (number expected, got table)\","
           "tostring(e))");
}

static void direct_extra_argument_owner(lua_State *L) {
    /* The callable receiver is an actual prepended C argument. Borrow its
       real owner's extra count rather than a hidden phase's zero default. */
    run(L, "local m=setmetatable({},{__call=forward_sin});"
           "local ok,e=pcall(function()m()end);assert(not ok and "
           "e:find(\"bad extra argument #1 to 'm' "
           "(number expected, got table)\",1,true),tostring(e))");
}

static void direct_method_argument_owner(lua_State *L) {
    /* The original C caller was invoked with colon syntax. Its first bad
       value is self and has a distinct spelling, before regular numbering. */
    run(L, "local t={go=forward_sin};"
           "local ok,e=pcall(function()t:go()end);assert(not ok and "
           "e:find(\"calling 'go' on bad self "
           "(number expected, got table)\",1,true),tostring(e))");
}

static void direct_closure_argument_owner(lua_State *L) {
    /* A captured C closure and its zero-upvalue function share code bytes
       but have distinct callable identities in the actual registry search. */
    lua_pushinteger(L, 1); lua_pushcclosure(L, forward_sin, 1);
    lua_setglobal(L, "closure_sin");
    run(L, "local ok,e=pcall(closure_sin,{});assert(not ok and e=="
           "\"bad argument #1 to 'closure_sin' (number expected, got table)\","
           "tostring(e))");
}

static void registry_callback_owner(lua_State *L) {
    registry_contract(L, 0);
}

static void registry_callback_roots(lua_State *L) {
    registry_contract(L, 1);
}

static void registry_callback_guard(lua_State *L) {
    registry_contract(L, 2);
}

static void registry_callback_captures(lua_State *L) {
    registry_contract(L, 3);
}

static void registry_callback_prefix(lua_State *L) {
    registry_contract(L, 4);
}

static int forward_load(lua_State *L) { return direct_load(L); }

static void reader_direct_host(lua_State *L) {
    /* Calling a saved builtin pointer directly adds no public Lua frame.
       Its real host base prefix still receives the returned closure. */
    direct_load = field(L, NULL, "load"); lua_pop(L, 1);
    run(L, "local n=0;return function()"
           "assert(debug.getinfo(2)==nil);n=n+1;"
           "if n==1 then return 'return 37,nil,41' end end");
    assert(lua_gettop(L) == 1 && direct_load(L) == 1);
    assert(lua_gettop(L) == 2 && lua_isfunction(L, -1));
    lua_call(L, 0, 3);
    assert(lua_tointeger(L, -3) == 37 && lua_isnil(L, -2));
    assert(lua_tointeger(L, -1) == 41);
    lua_settop(L, 0);
}

static void reader_direct_owner(lua_State *L) {
    /* The load body is directly borrowed by this actual forward_load C
       activation. The reader observes that owner and its mutable env cell. */
    lua_pushcfunction(L, forward_load); lua_setglobal(L, "forward_load");
    run(L, "local n=0;local f,e=forward_load(function()"
           "local i=debug.getinfo(2,'fSu');"
           "assert(i.func==forward_load and i.what=='C' and i.nparams==0);"
           "n=n+1;if n==1 then assert(debug.setlocal(2,4,{value=47}));"
           "return 'return value' end end,'=direct-reader','t',{value=7});"
           "assert(f and f()==47 and n==2,tostring(e))");
    lua_getglobal(L, "load"); assert(lua_tocfunction(L, -1) == direct_load);
    lua_pop(L, 1);
}

static void reader_direct_roots(lua_State *L) {
    /* Replacing argument one changes the next refill and retires the old
       reader root. A private continuation cannot retain an obsolete copy. */
    run(L, "local weak=setmetatable({},{__mode='v'});"
           "local function make_reader() local function old()"
           "assert(debug.setlocal(2,1,function()collectgarbage();"
           "assert(weak[1]==nil);return nil end));return 'return 53' end;"
           "weak[1]=old;return old end;"
           "local f,e=forward_load(make_reader());"
           "assert(f and f()==53,tostring(e))");
}

static void reader_direct_error(lua_State *L) {
    /* Its protected parser preserves the actual reader's error object,
       and a failed streaming call leaves this same C body reusable. */
    run(L, "local marker={};local ok,f,e=pcall(forward_load,function()"
           "error(marker,0)end);assert(ok and f==nil and e==marker);"
           "local n=0;local g=assert(forward_load(function()"
           "n=n+1;if n==1 then return 'return 59' end end));assert(g()==59)");
}

static void reader_direct_extra_root(lua_State *L) {
    /* An unused fifth argument still belongs to the actual C stack. Once
       the reader replaces it, no hidden phase may retain the old object. */
    run(L, "local weak=setmetatable({},{__mode='v'});"
           "local function make_extra()local v={};weak[1]=v;return v end;"
           "local n=0;local f,e=forward_load(function()n=n+1;"
           "if n==1 then assert(debug.setlocal(2,5,nil));collectgarbage();"
           "assert(weak[1]==nil);return 'return 61' end end,"
           "nil,'t',_ENV,make_extra());assert(f and f()==61,tostring(e))");
}

static int reader_self_returned;
static int reader_close_self(lua_State *L) {
    lua_closethread(L, L);
    reader_self_returned++;
    return 0;
}

static void reader_self_close_case(lua_State *L, int partial, int direct) {
    lua_State *co;
    int n;
    /* Native partial-reader self-close leaks parser scratch on this pinned
       host (separate counted diagnostics: 128 bytes/two blocks). Isolate
       these semantic trials from the retained counted state; these trials
       do not establish balanced cleanup. Ada AUnit checks its own selected
       bytes/blocks separately. Never emulate the native scratch leak. */
    (void)L;
    L = luaL_newstate(); assert(L); luaL_openlibs(L);
    lua_pushcfunction(L, forward_load); lua_setglobal(L, "forward_load");
    /* The real reader resets its running thread. Every waiting parser and
       load-portal guard must acknowledge that base-level transfer before
       metadata reuse; neither C nor Lua code after reset may run. */
    reader_self_returned = 0;
    lua_pushcfunction(L, reader_close_self);
    lua_setglobal(L, "reader_close_self");
    lua_pushboolean(L, partial); lua_setglobal(L, "reader_partial");
    lua_pushboolean(L, direct); lua_setglobal(L, "reader_direct");
    run(L, "reader_closed=0;return coroutine.create(function()"
           "local guard<close> = setmetatable({},"
           "{__close=function()reader_closed=reader_closed+1 end});"
           "local n=0;local loader=reader_direct and forward_load or load;"
           "return loader(function()n=n+1;"
           "if reader_partial and n==1 then return 'local value = ' end;"
           "reader_close_self();error('self-closed reader resumed')end)end)");
    co = lua_tothread(L, -1); assert(co);
    assert(lua_resume(co, L, 0, &n) == LUA_OK && n == 0);
    assert(!reader_self_returned && lua_gettop(co) == 0);
    assert(lua_status(co) == LUA_OK);
    lua_getglobal(L, "reader_closed");
    assert(lua_tointeger(L, -1) == 1);
    lua_settop(L, 0);
    run(L, "assert(assert(load('return 67'))()==67)");
    puts("OBSERVED: reader self-close semantics; teardown follows");
    fflush(stdout);
    lua_close(L);
}

static void reader_self_close(lua_State *L) {
    reader_self_close_case(L, 0, 0);
}

static void reader_partial_self_close(lua_State *L) {
    reader_self_close_case(L, 1, 0);
}

static void reader_direct_self_close(lua_State *L) {
    reader_self_close_case(L, 1, 1);
}

static int reader_refuse_growth(lua_State *L) {
    void *data;
    (void)lua_getallocf(L, &data);
    ((struct allocation_counts *)data)->refuse = 1;
    lua_pushvalue(L, lua_upvalueindex(1));
    return 1;
}

static void reader_injected_refusal(lua_State *L) {
    struct allocation_counts local_counts = {0};
    lua_State *trial = lua_newstate(counted_allocator, &local_counts, 977U);
    int status;
    (void)L;
    assert(trial); luaL_openlibs(trial);
    /* Inject only after the actual reader C body has entered. A cold load
       completion must retain its protected nil/error tuple under permanent
       refusal, rather than failing a later private result allocation. */
    lua_getglobal(trial, "load");
    lua_pushliteral(trial, "return 71");
    lua_pushcclosure(trial, reader_refuse_growth, 1);
    status = lua_pcall(trial, 1, 2, 0);
    local_counts.refuse = 0;
    assert(status == LUA_OK && lua_gettop(trial) == 2);
    assert(lua_isnil(trial, 1));
    assert(strcmp(lua_tostring(trial, 2), "not enough memory") == 0);
    lua_settop(trial, 0);
    run(trial, "assert(assert(load('return 73'))()==73)");
    lua_close(trial);
    assert(local_counts.bytes == 0 && local_counts.blocks == 0);
}

static void check(const char *name, void (*body)(lua_State *), lua_State *L) {
    assert(lua_gettop(L) == 0); body(L); assert(lua_gettop(L) == 0);
    printf("PASS: builtin-%s\n", name); fflush(stdout);
}

static void debug_console_host_body(lua_State *L, int closing) {
    lua_CFunction console = field(L, "debug", "debug");
    lua_pop(L, 1);
    run(L, "watch=setmetatable({},{__mode='v'})");
    if (closing) {
        run(L, closing == 2 ?
            "closed=0;console_object=setmetatable({},"
            "{__close=function(self,...)assert(select('#',...)==0);"
            "closed=closed+1;error('CLOSE',0) end})" :
            "closed=0;console_object=setmetatable({},"
            "{__close=function(self,...)assert(select('#',...)==0);"
            "closed=closed+1 end})");
        lua_getglobal(L, "console_object");
        lua_pushnil(L); lua_setglobal(L, "console_object");
    } else lua_newtable(L);
    lua_getglobal(L, "watch");
    lua_pushvalue(L, 1); lua_rawseti(L, -2, 1); lua_pop(L, 1);
    if (closing) lua_toclose(L, 1);
    /* stdin supplies two commands, then cont. The first sees this initial
       argument; the second must see it collected after lua_settop(L,0). */
    assert(console(L) == 0 && lua_gettop(L) == 0);
    run(L, "assert(watch[1]==nil)");
    if (closing) run(L, "assert(closed==1)");
}

static void debug_console_host(lua_State *L) {
    debug_console_host_body(L, 0);
}

static void debug_console_host_close(lua_State *L) {
    debug_console_host_body(L, 1);
}

static int debug_console_callback(lua_State *L) {
    debug_console_host_body(L, 1);
    return 0;
}

static int debug_console_failing_callback(lua_State *L) {
    debug_console_host_body(L, 2);
    assert(!"a failing closer cannot return to debug.debug");
    return 0;
}

static void debug_console_callback_close(lua_State *L) {
    lua_pushcfunction(L, debug_console_callback);
    assert(lua_pcall(L, 0, 0, 0) == LUA_OK);
    run(L, "assert(closed==1)");
}

static void debug_console_callback_error(lua_State *L) {
    lua_pushcfunction(L, debug_console_failing_callback);
    assert(lua_pcall(L, 0, 0, 0) == LUA_ERRRUN);
    assert(strcmp(lua_tostring(L, -1), "CLOSE") == 0);
    lua_pop(L, 1);
    run(L, "assert(closed==1)");
}

int main(int argc, char **argv) {
    int console_trial = argc == 2 &&
        strncmp(argv[1], "--debug-console-", 16) == 0;
    /* The native T library requires its own default debug allocator when
       opening T. These console-only modes use the ordinary public state
       constructor on both runtimes; counts is not their allocator witness. */
    lua_State *L = console_trial ? luaL_newstate() :
        lua_newstate(counted_allocator, &counts, 971U);
    assert(L); luaL_openlibs(L);
    if (argc == 2) {
        /* Keep known-failing native T partial-parser teardown isolated.
           These modes still call lua_close: a failed oracle is recorded as
           failed, never transformed into a passing balanced consumer. */
        direct_load = field(L, NULL, "load"); lua_pop(L, 1);
        if (strcmp(argv[1], "--reader-self-close") == 0)
            check("reader-self-close", reader_self_close, L);
        else if (strcmp(argv[1], "--reader-partial-self-close") == 0)
            check("reader-partial-self-close", reader_partial_self_close, L);
        else if (strcmp(argv[1], "--reader-direct-self-close") == 0)
            check("reader-direct-self-close", reader_direct_self_close, L);
        else if (strcmp(argv[1], "--debug-console-host") == 0)
            check("debug-console-host", debug_console_host, L);
        else if (strcmp(argv[1], "--debug-console-host-close") == 0)
            check("debug-console-host-close", debug_console_host_close, L);
        else if (strcmp(argv[1], "--debug-console-callback-close") == 0)
            check("debug-console-callback-close", debug_console_callback_close, L);
        else if (strcmp(argv[1], "--debug-console-callback-error") == 0)
            check("debug-console-callback-error", debug_console_callback_error, L);
        else assert(!"unknown reader lifecycle trial");
    } else {
    assert(argc == 1);
    check("exposed-functions", exposed_functions, L);
    check("stateless-roundtrip", stateless_roundtrip, L);
    check("repeated-opener-identity", repeated_opener_identity, L);
    check("direct-host-call", direct_host_call, L);
    check("direct-c-call", direct_c_call, L);
    check("direct-callback-frame", direct_callback_frame, L);
    check("captured-roundtrip", captured_roundtrip, L);
    check("iterator-identity", iterator_identity, L);
    check("pointer-formats", pointer_formats, L);
    check("direct-error-identity", direct_error_identity, L);
    check("direct-protected-results", direct_protected_results, L);
    check("direct-yield-continuation", direct_yield_continuation, L);
    check("direct-callback-yield", direct_callback_yield, L);
    check("scalar-refusal", scalar_refusal, L);
    check("captured-refusal-recovery", captured_refusal_recovery, L);
    check("direct-argument-owner", direct_argument_owner, L);
    check("direct-extra-argument-owner", direct_extra_argument_owner, L);
    check("direct-method-argument-owner", direct_method_argument_owner, L);
    check("direct-closure-argument-owner", direct_closure_argument_owner, L);
    check("registry-callback-original-owner", registry_callback_owner, L);
    check("registry-callback-original-roots", registry_callback_roots, L);
    check("registry-callback-error-guard", registry_callback_guard, L);
    check("registry-callback-original-captures", registry_callback_captures, L);
    check("registry-callback-extra-temporaries", registry_callback_prefix, L);
    check("reader-direct-host", reader_direct_host, L);
    check("reader-direct-owner", reader_direct_owner, L);
    check("reader-direct-roots", reader_direct_roots, L);
    check("reader-direct-error", reader_direct_error, L);
    check("reader-direct-extra-root", reader_direct_extra_root, L);
    check("reader-injected-refusal", reader_injected_refusal, L);
    }
    lua_close(L);
    if (!console_trial) assert(counts.bytes == 0 && counts.blocks == 0);
    puts("PASS: public builtin contract");
    return 0;
}
