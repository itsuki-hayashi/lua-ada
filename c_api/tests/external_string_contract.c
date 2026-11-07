/* External payload ownership and public short-string identities.
 * Copyright (c) 2026 Lua Ada contributors. MIT; see ../../LICENSE. */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "consumer_allocator.h"

static struct allocation_counts counts;
struct payload { char *bytes; size_t length; unsigned releases; };
static struct payload pending;
static lua_State *refusing_state;
static int refused_release_top;

static void *release_payload(void *data, void *block, size_t old_size,
                              size_t new_size) {
    struct payload *p = (struct payload *)data;
    assert(block == p->bytes && old_size == p->length + 1 && new_size == 0);
    assert(p->releases == 0); p->releases++; free(block); return NULL;
}
static void make_payload(struct payload *p, size_t length, char byte) {
    p->bytes = (char *)malloc(length + 1); assert(p->bytes);
    p->length = length; p->releases = 0;
    memset(p->bytes, byte, length); p->bytes[length] = '\0';
}
static void push_payload(lua_State *L, struct payload *p) {
    const char *actual = lua_pushexternalstring(L, p->bytes, p->length,
                                               release_payload, p);
    assert(actual == p->bytes && lua_tostring(L, -1) == p->bytes);
    assert(lua_rawlen(L, -1) == p->length && p->releases == 0);
}
static void collect(lua_State *L) { lua_gc(L, LUA_GCCOLLECT); }

static void ordinary_short_identity(lua_State *L) {
    char short_text[41], long_text[42]; const char *a, *b;
    memset(short_text, 'k', 40); short_text[40] = 0;
    memset(long_text, 'k', 41); long_text[41] = 0;
    a = lua_pushlstring(L, short_text, 40);
    b = lua_pushlstring(L, short_text, 40); assert(a == b);
    a = lua_pushlstring(L, long_text, 41);
    b = lua_pushlstring(L, long_text, 41); assert(a != b);
    assert(lua_rawequal(L, -1, -2)); lua_settop(L, 0);
}
static void short_lookup_refusal(lua_State *L) {
    const char *a = lua_pushstring(L, "interned-before-refusal");
    assert(lua_checkstack(L, 16)); counts.refuse = 1;
    assert(lua_pushstring(L, "interned-before-refusal") == a);
    counts.refuse = 0; lua_settop(L, 0);
}
static void empty_external(lua_State *L) {
    struct payload p; make_payload(&p, 0, 'e'); push_payload(L, &p);
    assert(lua_pushstring(L, "") != p.bytes);
    assert(lua_rawequal(L, -1, -2)); lua_settop(L, 0); collect(L);
    assert(p.releases == 1);
}
static void short_external(lua_State *L) {
    struct payload p, q; make_payload(&p, 40, 's'); make_payload(&q, 40, 's');
    push_payload(L, &p); push_payload(L, &q);
    assert(lua_rawequal(L, -1, -2) && lua_tostring(L, -1) != p.bytes);
    collect(L); assert(!p.releases && !q.releases);
    lua_settop(L, 0); collect(L); assert(p.releases == 1 && q.releases == 1);
}
static void long_external(lua_State *L) {
    struct payload p; make_payload(&p, 80, 'l'); push_payload(L, &p);
    collect(L); assert(!p.releases); lua_pop(L, 1); collect(L);
    assert(p.releases == 1);
}
static void embedded_zero(lua_State *L) {
    struct payload p; make_payload(&p, 6, 'z'); p.bytes[2] = 0;
    push_payload(L, &p);
    lua_pushlstring(L, "zz\0zzz", 6); assert(lua_rawequal(L, -1, -2));
    lua_settop(L, 0); collect(L); assert(p.releases == 1);
}
static void borrowed_external(lua_State *L) {
    static const char bytes[] = "borrowed-external";
    assert(lua_pushexternalstring(L, bytes, sizeof bytes - 1, NULL, NULL) == bytes);
    assert(lua_tostring(L, -1) == bytes); collect(L);
    assert(lua_tostring(L, -1) == bytes); lua_pop(L, 1); collect(L);
}
static void short_key_normalization(lua_State *L) {
    struct payload p; make_payload(&p, 8, 'q'); lua_newtable(L);
    push_payload(L, &p); lua_pushinteger(L, 17); lua_rawset(L, 1);
    collect(L); assert(p.releases == 1);
    lua_pushnil(L); assert(lua_next(L, 1));
    assert(lua_tostring(L, -2) != p.bytes && lua_tointeger(L, -1) == 17);
    lua_pushstring(L, "qqqqqqqq");
    assert(lua_topointer(L, -1) == lua_topointer(L, -3));
    lua_settop(L, 0); collect(L);
}
static void long_key_retention(lua_State *L) {
    struct payload p; make_payload(&p, 60, 't'); lua_newtable(L);
    push_payload(L, &p); lua_pushboolean(L, 1); lua_rawset(L, 1);
    collect(L); assert(p.releases == 0);
    lua_pushnil(L); assert(lua_next(L, 1));
    assert(lua_tostring(L, -2) == p.bytes); lua_settop(L, 0); collect(L);
    assert(p.releases == 1);
}
static void existing_key_update(lua_State *L) {
    struct payload p; make_payload(&p, 7, 'u'); lua_newtable(L);
    lua_pushstring(L, "uuuuuuu"); lua_pushinteger(L, 1); lua_rawset(L, 1);
    push_payload(L, &p); lua_pushinteger(L, 2); lua_rawset(L, 1);
    collect(L); assert(p.releases == 1);
    lua_getfield(L, 1, "uuuuuuu"); assert(lua_tointeger(L, -1) == 2);
    lua_settop(L, 0); collect(L);
}
static void weak_value_string(lua_State *L) {
    struct payload p; make_payload(&p, 70, 'w'); lua_newtable(L);
    lua_newtable(L); lua_pushstring(L, "v"); lua_setfield(L, -2, "__mode");
    lua_setmetatable(L, 1); push_payload(L, &p); lua_rawseti(L, 1, 1);
    collect(L); assert(p.releases == 0);
    assert(lua_rawgeti(L, 1, 1) == LUA_TSTRING);
    assert(lua_tostring(L, -1) == p.bytes); lua_settop(L, 0); collect(L);
    assert(p.releases == 1);
}
static void *release_refused(void *data, void *block, size_t old_size,
                              size_t new_size) {
    release_payload(data, block, old_size, new_size);
    refused_release_top = lua_gettop(refusing_state); return NULL;
}
static int refusing_push(lua_State *L) {
    counts.refuse = 1;
    lua_pushexternalstring(L, pending.bytes, pending.length,
                           release_refused, &pending);
    return 1;
}
static void allocation_refusal(lua_State *L) {
    static const size_t lengths[] = {0, 9, 90}; size_t i;
    assert(lua_checkstack(L, 64));
    for (i = 0; i < sizeof lengths / sizeof lengths[0]; ++i) {
        int status; make_payload(&pending, lengths[i], 'r');
        refusing_state = L; refused_release_top = -1;
        lua_pushcfunction(L, refusing_push);
        status = lua_pcall(L, 0, 1, 0); counts.refuse = 0;
        assert(status == LUA_ERRMEM && pending.releases == 1);
        assert(refused_release_top == 0); lua_pop(L, 1);
        make_payload(&pending, lengths[i], 'r'); push_payload(L, &pending);
        lua_pop(L, 1); collect(L); assert(pending.releases == 1);
    }
}
static void state_close_lifetime(lua_State *L) {
    struct allocation_counts own = {0}; struct payload p;
    lua_State *other = lua_newstate(counted_allocator, &own, 131U);
    (void)L; assert(other); make_payload(&p, 61, 'c'); push_payload(other, &p);
    lua_setfield(other, LUA_REGISTRYINDEX, "kept-until-close");
    collect(other); assert(p.releases == 0); lua_close(other);
    assert(p.releases == 1 && own.bytes == 0 && own.blocks == 0);
}
struct reentry_payload {
    struct payload p;
    lua_State *state;
    const char *callback;
};
static void *release_reentrant(void *data, void *block, size_t old_size,
                                size_t new_size) {
    struct reentry_payload *p = (struct reentry_payload *)data;
    release_payload(&p->p, block, old_size, new_size);
    lua_getglobal(p->state, p->callback); lua_call(p->state, 0, 0);
    return NULL;
}
static struct reentry_payload recursive_payload;
static int make_recursive(lua_State *L) {
    make_payload(&recursive_payload.p, 77, 'n');
    recursive_payload.state = L; recursive_payload.callback = "inner_release";
    lua_pushexternalstring(L, recursive_payload.p.bytes, recursive_payload.p.length,
                           release_reentrant, &recursive_payload);
    return 0;
}
static void callback_lua_reentry(lua_State *L) {
    struct reentry_payload p;
    assert(luaL_dostring(L, "released=0;function onrelease() "
        "local function f(x)return x+1 end;released=f(released) end") == LUA_OK);
    make_payload(&p.p, 63, 'r'); p.state = L; p.callback = "onrelease";
    lua_pushexternalstring(L, p.p.bytes, p.p.length, release_reentrant, &p);
    lua_pop(L, 1); collect(L); assert(p.p.releases == 1);
    lua_getglobal(L, "released"); assert(lua_tointeger(L, -1) == 1);
    lua_pop(L, 1);
}
static void callback_nested_collection(lua_State *L) {
    struct reentry_payload p;
    lua_pushcfunction(L, make_recursive); lua_setglobal(L, "make_recursive");
    assert(luaL_dostring(L, "nested_released=0;function inner_release() "
        "nested_released=nested_released+1 end;function outer_release() "
        "make_recursive();collectgarbage('collect') end") == LUA_OK);
    make_payload(&p.p, 65, 'o'); p.state = L; p.callback = "outer_release";
    lua_pushexternalstring(L, p.p.bytes, p.p.length, release_reentrant, &p);
    lua_pop(L, 1); collect(L);
    assert(p.p.releases == 1 && recursive_payload.p.releases == 1);
    lua_getglobal(L, "nested_released"); assert(lua_tointeger(L, -1) == 1);
    lua_pop(L, 1);
}
static void callback_interrupted_frame(lua_State *L) {
    struct reentry_payload p;
    assert(luaL_dostring(L, "function inspect_release() "
        "local a=debug.getinfo(2,'f');assert(a and a.func==collectgarbage) end")
        == LUA_OK);
    lua_gc(L, LUA_GCSTOP);
    make_payload(&p.p, 64, 'f'); p.state = L; p.callback = "inspect_release";
    lua_pushexternalstring(L, p.p.bytes, p.p.length, release_reentrant, &p);
    lua_pop(L, 1);
    assert(luaL_dostring(L, "collectgarbage('collect')") == LUA_OK);
    assert(p.p.releases == 1); lua_gc(L, LUA_GCRESTART);
}
static void callback_closure_lifetime(lua_State *L) {
    struct reentry_payload p;
    assert(luaL_dostring(L, "release_weak=setmetatable({},{__mode='v'});"
        "do local captured={value=23};release_weak[1]=captured;"
        "function retained_release()assert(captured.value==23) end end")
        == LUA_OK);
    make_payload(&p.p, 66, 'v'); p.state = L; p.callback = "retained_release";
    lua_pushexternalstring(L, p.p.bytes, p.p.length, release_reentrant, &p);
    lua_pop(L, 1); collect(L); assert(p.p.releases == 1);
    assert(luaL_dostring(L, "retained_release=nil;collectgarbage('collect');"
        "collectgarbage('collect');assert(release_weak[1]==nil)") == LUA_OK);
}
static int close_reentry_count;
static int close_witness(lua_State *L) {
    assert(lua_tointeger(L, 1) == 37); close_reentry_count++; return 0;
}
static void callback_close_reentry(lua_State *L) {
    struct allocation_counts own = {0}; struct reentry_payload p;
    lua_State *other = lua_newstate(counted_allocator, &own, 179U);
    (void)L; assert(other); luaL_openlibs(other);
    lua_pushcfunction(other, close_witness); lua_setglobal(other, "witness");
    assert(luaL_dostring(other, "function close_release()witness(37)end") == LUA_OK);
    make_payload(&p.p, 63, 'c'); p.state = other; p.callback = "close_release";
    lua_pushexternalstring(other, p.p.bytes, p.p.length, release_reentrant, &p);
    lua_setfield(other, LUA_REGISTRYINDEX, "close-reentrant-buffer");
    lua_close(other);
    assert(p.p.releases == 1 && close_reentry_count == 1);
    assert(own.bytes == 0 && own.blocks == 0);
}
static void check(const char *name, void (*body)(lua_State *), lua_State *L) {
    assert(lua_gettop(L) == 0); collect(L); body(L);
    assert(lua_gettop(L) == 0);
    printf("PASS: external-%s\n", name); fflush(stdout);
}
int main(int argc, char **argv) {
    int ownership_only = argc == 2 && strcmp(argv[1], "--ownership-only") == 0;
    lua_State *L = lua_newstate(counted_allocator, &counts, 119U); assert(L);
    assert(argc == 1 || ownership_only);
    luaL_openlibs(L);
    check("ordinary-short-identity", ordinary_short_identity, L);
    check("short-lookup-refusal", short_lookup_refusal, L);
    check("empty-buffer", empty_external, L);
    check("short-buffer", short_external, L);
    check("long-buffer", long_external, L);
    check("embedded-zero", embedded_zero, L);
    check("borrowed-buffer", borrowed_external, L);
    check("short-key-normalization", short_key_normalization, L);
    check("long-key-retention", long_key_retention, L);
    check("existing-key-update", existing_key_update, L);
    check("weak-value-string", weak_value_string, L);
    check("allocation-refusal-recovery", allocation_refusal, L);
    check("state-close-lifetime", state_close_lifetime, L);
    if (ownership_only)
        puts("SKIP: 5 release reentry cases (instrumented C lock rejects reentry)");
    else {
        check("callback-lua-reentry", callback_lua_reentry, L);
        check("callback-nested-collection", callback_nested_collection, L);
        check("callback-interrupted-frame", callback_interrupted_frame, L);
        check("callback-closure-lifetime", callback_closure_lifetime, L);
        check("callback-close-reentry", callback_close_reentry, L);
    }
    lua_close(L); assert(counts.bytes == 0 && counts.blocks == 0);
    puts("PASS: public external string contract"); return 0;
}
