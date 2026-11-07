/* Public traceback rendering over real C/Lua frames and borrowed threads.
 * MIT license; see ../../LICENSE. Run this identical C99 source against
 * the pinned default/T C oracle and both Ada runtime configurations. */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "consumer_allocator.h"

#ifdef NDEBUG
#error "traceback_api_contract.c requires assertions"
#endif

static int trace(lua_State *L) {
    luaL_traceback(L, L, lua_tostring(L, 1), (int)luaL_optinteger(L, 2, 0));
    return 1;
}

static struct allocation_counts *active_counts;
static int refusing_trace(lua_State *L) {
    active_counts->refuse = 1;
    luaL_traceback(L, L, NULL, 0);
    return 1;
}

static void expected(lua_State *L, const char *text) {
    size_t size;
    const char *actual = lua_tolstring(L, -1, &size);
    if (actual == NULL || size != strlen(text) || memcmp(actual, text, size)) {
        fprintf(stderr, "expected [%s], actual [%s]\n", text,
                actual == NULL ? "<nonstring>" : actual);
        assert(0);
    }
    lua_pop(L, 1);
}

static void run(lua_State *L, const char *source, int results) {
    int status = luaL_loadbuffer(L, source, strlen(source), "@traceback");
    if (status == LUA_OK) status = lua_pcall(L, 0, results, 0);
    if (status != LUA_OK) fprintf(stderr, "%s\n", lua_tostring(L, -1));
    assert(status == LUA_OK);
}

static void no_message(lua_State *L) {
    luaL_traceback(L, L, NULL, 0);
    expected(L, "stack traceback:");
}

static void host_message(lua_State *L) {
    luaL_traceback(L, L, "detail", 0);
    expected(L, "detail\nstack traceback:");
}

static void empty_message(lua_State *L) {
    luaL_traceback(L, L, "", 0);
    expected(L, "\nstack traceback:");
}

static void nul_message(lua_State *L) {
    luaL_traceback(L, L, "first\0ignored", 0);
    expected(L, "first\nstack traceback:");
}

static void negative_level(lua_State *L) {
    run(L, "return trace('negative',-1)", 1);
    expected(L, "negative\nstack traceback:");
}

static void nested_frames(lua_State *L) {
    run(L, "local function inner()\n local v=trace('detail',0)\n"
           " return v\nend\nlocal v=inner()\nreturn v", 1);
    expected(L, "detail\nstack traceback:\n\t[C]: in global 'trace'\n"
                "\ttraceback:2: in local 'inner'\n"
                "\ttraceback:5: in main chunk");
}

static void skip_current(lua_State *L) {
    run(L, "local v=trace(nil,1)\nreturn v", 1);
    expected(L, "stack traceback:\n\ttraceback:1: in main chunk");
}

static void out_of_stack(lua_State *L) {
    run(L, "return trace(nil,2147483647)", 1);
    expected(L, "stack traceback:");
}

static void stack_prefix(lua_State *L) {
    const void *identity;
    lua_newtable(L);
    identity = lua_topointer(L, -1);
    lua_pushinteger(L, 19);
    luaL_traceback(L, L, "preserved", 0);
    assert(lua_gettop(L) == 3 && lua_topointer(L, 1) == identity);
    assert(lua_isinteger(L, 2) && lua_tointeger(L, 2) == 19);
    expected(L, "preserved\nstack traceback:");
    lua_pop(L, 2);
}

static void inactive_thread(lua_State *L) {
    lua_State *thread = lua_newthread(L);
    luaL_traceback(L, thread, NULL, 0);
    expected(L, "stack traceback:");
    assert(lua_gettop(thread) == 0);
    lua_pop(L, 1);
}

static void suspended_thread(lua_State *L) {
    lua_State *thread = lua_newthread(L);
    const char *source = "local function wait()\n coroutine.yield()\nend\n"
                         "wait()\nreturn true";
    int results;
    assert(luaL_loadbuffer(thread, source, strlen(source), "@suspended") == 0);
    assert(lua_resume(thread, L, 0, &results) == LUA_YIELD && results == 0);
    luaL_traceback(L, thread, "suspended", 0);
    expected(L, "suspended\nstack traceback:\n\t[C]: in field 'yield'\n"
                "\tsuspended:2: in local 'wait'\n"
                "\tsuspended:4: in main chunk");
    assert(lua_gettop(thread) == 0);
    assert(lua_resume(thread, L, 0, &results) == LUA_OK && results == 1);
    assert(lua_toboolean(thread, -1));
    lua_pop(L, 1);
}

static void independent_destination(lua_State *L) {
    struct allocation_counts counts = {0};
    lua_State *destination = lua_newstate(counted_allocator, &counts, 73U);
    lua_State *thread = lua_newthread(L);
    const char *source = "coroutine.yield()";
    int results;
    assert(destination != NULL);
    assert(luaL_loadbuffer(thread, source, strlen(source), "@other") == 0);
    assert(lua_resume(thread, L, 0, &results) == LUA_YIELD);
    luaL_traceback(destination, thread, NULL, 0);
    /* The destination registry has no libraries. The inferred field name
     * still comes from the addressed thread's actual saved call site. */
    expected(destination, "stack traceback:\n\t[C]: in field 'yield'\n"
                          "\tother:1: in main chunk");
    assert(lua_gettop(thread) == 0);
    lua_close(destination);
    assert(counts.bytes == 0 && counts.blocks == 0);
    lua_pop(L, 1);
}

static void shared_lua_renderer(lua_State *L) {
    run(L, "local function f(what) local x=what('same',1);return x end\n"
           "local a=f(trace);local b=f(debug.traceback);assert(a==b)", 0);
}

static void refusal_and_retry(lua_State *L) {
    lua_pushcfunction(L, refusing_trace);
    assert(lua_pcall(L, 0, 1, 0) == LUA_ERRMEM);
    active_counts->refuse = 0;
    expected(L, "not enough memory");
    luaL_traceback(L, L, "healthy", 0);
    expected(L, "healthy\nstack traceback:");
}

static void lua_nul_message(lua_State *L) {
    run(L, "return debug.traceback('first\\0ignored',-1)", 1);
    expected(L, "first\nstack traceback:");
}

static void lua_numeric_message(lua_State *L) {
    run(L, "return debug.traceback(17,-1)", 1);
    expected(L, "17\nstack traceback:");
}

static void lua_message_identity(lua_State *L) {
    run(L, "local t={};assert(debug.traceback(t,{})==t)", 0);
}

static void lua_level_cast(lua_State *L) {
    run(L, "assert(debug.traceback('message',math.maxinteger)=="
           "'message\\nstack traceback:');"
           "assert(debug.traceback(nil,4294967295)=='stack traceback:');"
           "assert(debug.traceback(nil,4294967296)==debug.traceback(nil,0));"
           "assert(debug.traceback(nil,-4294967297)=='stack traceback:')", 0);
}

static void deep_stack(lua_State *L) {
    run(L, "local function f(n) if n==0 then local t=trace(nil,0);return t "
           "else return(f(n-1))end end;local co=coroutine.create(f);"
           "local ok,t=coroutine.resume(co,30);assert(ok);"
           "local _,n=t:gsub('\\n','');assert(n==22);"
           "assert(t:find('(skipping 10 levels)',1,true))", 0);
}

static void shortening_boundary(lua_State *L) {
    run(L, "local function f(n) if n==0 then local t=trace(nil,0);return t "
           "else return(f(n-1))end end;local co=coroutine.create(f);"
           "local ok,t=coroutine.resume(co,20);assert(ok);"
           "local _,n=t:gsub('\\n','');assert(n==22 and not t:find('skipping'));"
           "co=coroutine.create(f);ok,t=coroutine.resume(co,21);assert(ok);"
           "local _,m=t:gsub('\\n','');assert(m==22);"
           "assert(t:find('(skipping 1 levels)',1,true))", 0);
}

static void hook_origin(lua_State *L) {
    run(L, "local n=0;local co=coroutine.create(function()local x=1 end);"
           "debug.sethook(co,function()local t=trace(nil,0);"
           "assert(t:match(\"\\n[^\\n]+: in hook '%?'\"));n=n+1 end,'l');"
           "assert(coroutine.resume(co));assert(n>0)", 0);
}

static void closed_thread(lua_State *L) {
    lua_State *thread = lua_newthread(L);
    const char *source = "coroutine.yield()";
    int results;
    assert(luaL_loadbuffer(thread, source, strlen(source), "@closed") == 0);
    assert(lua_resume(thread, L, 0, &results) == LUA_YIELD);
    assert(lua_closethread(thread, L) == LUA_OK);
    luaL_traceback(L, thread, NULL, 0);
    expected(L, "stack traceback:");
    assert(lua_gettop(thread) == 0);
    lua_pop(L, 1);
}

struct traceback_case { const char *name; void (*body)(lua_State *); };
static const struct traceback_case cases[] = {
    {"no-message", no_message}, {"host-message", host_message},
    {"empty-message", empty_message}, {"nul-message", nul_message},
    {"negative-level", negative_level}, {"nested-frames", nested_frames},
    {"skip-current", skip_current}, {"out-of-stack", out_of_stack},
    {"stack-prefix", stack_prefix}, {"inactive-thread", inactive_thread},
    {"suspended-thread", suspended_thread},
    {"independent-destination", independent_destination},
    {"shared-lua-renderer", shared_lua_renderer},
    {"refusal-and-retry", refusal_and_retry},
    {"lua-nul-message", lua_nul_message},
    {"lua-numeric-message", lua_numeric_message},
    {"lua-message-identity", lua_message_identity},
    {"lua-level-cast", lua_level_cast},
    {"deep-stack", deep_stack},
    {"shortening-boundary", shortening_boundary},
    {"hook-origin", hook_origin}, {"closed-thread", closed_thread}
};

int lua_ada_test_traceback(unsigned which) {
    struct allocation_counts counts = {0};
    lua_State *L = lua_newstate(counted_allocator, &counts, 401U);
    assert(which < sizeof cases / sizeof cases[0] && L != NULL);
    active_counts = &counts;
    luaL_openlibs(L);
    lua_register(L, "trace", trace);
    cases[which].body(L);
    assert(lua_gettop(L) == 0);
    lua_close(L);
    active_counts = NULL;
    assert(counts.bytes == 0 && counts.blocks == 0);
    return 1;
}

#ifndef LUA_ADA_TRACEBACK_CONTRACT_LIBRARY
int main(void) {
    unsigned i;
    for (i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        assert(lua_ada_test_traceback(i));
        printf("PASS: traceback-%s\n", cases[i].name);
        fflush(stdout);
    }
    puts("PASS: public traceback contract");
    return 0;
}
#endif
