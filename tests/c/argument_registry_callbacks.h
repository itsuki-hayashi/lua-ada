/* Identical actual C direct-builtin/registry protocols for native and AUnit.
 * MIT license; see ../../LICENSE. No private interpreter state is accessed. */
#ifndef LUA_ADA_ARGUMENT_REGISTRY_CALLBACKS_H
#define LUA_ADA_ARGUMENT_REGISTRY_CALLBACKS_H

static unsigned registry_after_direct;

static int registry_forward_sin(lua_State *L) {
    lua_CFunction sine;
    int results;
    lua_getglobal(L, "math");
    lua_getfield(L, -1, "sin");
    sine = lua_tocfunction(L, -1);
    assert(sine != NULL);
    lua_pop(L, 2);
    results = sine(L);
    registry_after_direct++;
    return results;
}

/* This C frame creates the sole argument edge. There is no older Lua caller
 * local to clear: the weak table can observe retirement of the hidden Ada
 * builtin phase's copied inputs separately from its real original C slot. */
static int registry_seed_sin(lua_State *L) {
    assert(lua_gettop(L) == 0);
    lua_newtable(L);
    lua_getglobal(L, "registry_weak");
    lua_pushvalue(L, 1);
    lua_rawseti(L, -2, 1);
    lua_pop(L, 1);
    return registry_forward_sin(L);
}

static const char *const registry_sources[] = {
    "local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r);"
    "local calls=0;r._LOADED=nil;setmetatable(r,{__index=function()"
    "calls=calls+1;assert(debug.getinfo(2,'f').func==registry_forward_sin);"
    "local _,detail=debug.getlocal(2,2);local _,f=debug.getlocal(2,3);"
    "local _,key=debug.getlocal(2,4);assert(detail=='number expected, got table'"
    " and f==registry_forward_sin and key=='_LOADED' and "
    "debug.getlocal(2,5)==nil);return loaded end});"
    "local ok,e=pcall(registry_forward_sin,{});"
    "setmetatable(r,mt);r._LOADED=loaded;assert(not ok and calls==1 and "
    "e==\"bad argument #1 to 'registry_forward_sin' "
    "(number expected, got table)\",tostring(e))",

    "local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r);"
    "registry_weak=setmetatable({},{__mode='v'});"
    "r._LOADED=nil;setmetatable(r,{__index=function()"
    "assert(debug.getinfo(2,'f').func==registry_seed_sin);"
    "assert(debug.setlocal(2,1,nil));collectgarbage();"
    "assert(registry_weak[1]==nil);return loaded end});"
    "local ok,e=pcall(registry_seed_sin);"
    "setmetatable(r,mt);r._LOADED=loaded;assert(not ok and "
    "e==\"bad argument #1 to 'registry_seed_sin' "
    "(number expected, got table)\",tostring(e))",

    "local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r);"
    "local marker={};r._LOADED=nil;"
    "setmetatable(r,{__index=function()error(marker)end});"
    "local ok,e=pcall(registry_forward_sin,{});"
    "setmetatable(r,mt);r._LOADED=loaded;assert(not ok and e==marker)",

    "local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r);"
    "r._LOADED=nil;setmetatable(r,{__index=function()"
    "assert(debug.getinfo(2,'f').func==registry_closure);"
    "assert(debug.setupvalue(registry_closure,1,nil));collectgarbage();"
    "assert(registry_capture_weak[1]==nil);return loaded end});"
    "local ok,e=pcall(registry_closure,{});"
    "setmetatable(r,mt);r._LOADED=loaded;assert(not ok and "
    "e==\"bad argument #1 to 'registry_closure' "
    "(number expected, got table)\",tostring(e))",

    "local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r);"
    "local marker={};r._LOADED=nil;setmetatable(r,{__index=function()"
    "local _,p=debug.getlocal(2,2);local _,m=debug.getlocal(2,3);"
    "local _,n=debug.getlocal(2,4);local _,detail=debug.getlocal(2,5);"
    "local _,f=debug.getlocal(2,6);local _,key=debug.getlocal(2,7);"
    "assert(p=='kept' and m==marker and n==73 and "
    "detail=='number expected, got table' and f==registry_forward_sin "
    "and key=='_LOADED' and debug.getlocal(2,8)==nil);return loaded end});"
    "local ok,e=pcall(registry_forward_sin,{},'kept',marker,73);"
    "setmetatable(r,mt);r._LOADED=loaded;assert(not ok and "
    "e==\"bad argument #1 to 'registry_forward_sin' "
    "(number expected, got table)\",tostring(e))"
};

static void registry_contract(lua_State *L, unsigned which) {
    int status;
    assert(which < sizeof registry_sources / sizeof registry_sources[0]);
    assert(lua_gettop(L) == 0);
    lua_pushcfunction(L, registry_forward_sin);
    lua_setglobal(L, "registry_forward_sin");
    lua_pushcfunction(L, registry_seed_sin);
    lua_setglobal(L, "registry_seed_sin");
    if (which == 3) {
        /* Only the actual closure upvalue initially owns the captured table.
         * Replacing it during the registry callback must not leave a copied
         * hidden builtin capture keeping the old table alive. */
        lua_newtable(L);
        lua_newtable(L);
        lua_newtable(L);
        lua_pushliteral(L, "v"); lua_setfield(L, -2, "__mode");
        lua_setmetatable(L, -2);
        lua_pushvalue(L, -2); lua_rawseti(L, -2, 1);
        lua_setglobal(L, "registry_capture_weak");
        lua_pushcclosure(L, registry_forward_sin, 1);
        lua_setglobal(L, "registry_closure");
    }
    registry_after_direct = 0;
    status = luaL_dostring(L, registry_sources[which]);
    if (status != LUA_OK) fprintf(stderr, "%s\n", lua_tostring(L, -1));
    assert(status == LUA_OK && registry_after_direct == 0);
    assert(lua_gettop(L) == 0);
}
#endif
