/* First-party public IO/OS C API regressions. MIT license; see ../../LICENSE. */
#ifndef LUA_ADA_IO_CONTRACT_H
#define LUA_ADA_IO_CONTRACT_H

static void raw_field(lua_State *state, int index, const char *name) {
    index = lua_absindex(state, index);
    lua_pushstring(state, name);
    lua_rawget(state, index);
}

static void test_io_opener_and_stream_layout(lua_State *state) {
    luaL_Stream *stream;
    lua_settop(state, 0);
    assert(luaopen_io(state) == 1 && lua_gettop(state) == 1);
    raw_field(state, 1, "stdout");
    assert(lua_type(state, 2) == LUA_TUSERDATA);
    assert(lua_rawlen(state, 2) == sizeof(luaL_Stream));
    stream = (luaL_Stream *)lua_touserdata(state, 2);
    assert(stream && stream->f == stdout && stream->closef);
    assert(lua_getmetatable(state, 2));
    /* Reopening creates a module, but old streams retain registry identity. */
    assert(luaopen_io(state) == 1 && lua_gettop(state) == 4);
    assert(!lua_rawequal(state, 1, 4));
    raw_field(state, LUA_REGISTRYINDEX, LUA_FILEHANDLE);
    assert(lua_rawequal(state, 3, 5));
    lua_settop(state, 4);
    raw_field(state, 4, "type");
    lua_pushvalue(state, 2);
    assert(lua_pcall(state, 1, 1, 0) == LUA_OK);
    assert(strcmp(lua_tostring(state, -1), "file") == 0);
    lua_settop(state, 0);
    puts("C API PASS: io opener preserves live FILE payload and metatable");
}

static void test_os_opener_without_global_publication(lua_State *state) {
    lua_settop(state, 0);
    assert(luaopen_os(state) == 1 && lua_gettop(state) == 1);
    raw_field(state, 1, "difftime");
    lua_pushinteger(state, 42);
    lua_pushinteger(state, 17);
    assert(lua_pcall(state, 2, 1, 0) == LUA_OK);
    assert(lua_tonumber(state, -1) == 25);
    lua_rawgeti(state, LUA_REGISTRYINDEX, LUA_RIDX_GLOBALS);
    raw_field(state, -1, "os");
    assert(lua_type(state, -1) == LUA_TNIL);
    lua_settop(state, 0);
    puts("C API PASS: os opener returns callable exports without global write");
}

static void test_file_payload_closer_callback(lua_State *state) {
    luaL_Stream *stream;
    lua_CFunction closer;
    lua_settop(state, 0);
    assert(luaopen_io(state) == 1);
    raw_field(state, 1, "tmpfile");
    assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
    assert(lua_type(state, 2) == LUA_TUSERDATA);
    stream = (luaL_Stream *)lua_touserdata(state, 2);
    assert(stream && stream->f && stream->closef);
    assert(fwrite("native", 1, 6, stream->f) == 6);
    closer = stream->closef;
    /* Follow aux_close's public payload protocol, then invoke the actual
     * exported C trampoline under the C-owned protected-call boundary. */
    stream->closef = NULL;
    lua_pushcfunction(state, closer);
    lua_pushvalue(state, 2);
    assert(lua_pcall(state, 1, LUA_MULTRET, 0) == LUA_OK);
    assert(lua_gettop(state) == 3 && lua_toboolean(state, 3));
    assert(stream->closef == NULL);
    lua_settop(state, 2);
    raw_field(state, 1, "type");
    lua_pushvalue(state, 2);
    assert(lua_pcall(state, 1, 1, 0) == LUA_OK);
    assert(strcmp(lua_tostring(state, -1), "closed file") == 0);
    lua_settop(state, 0);
    puts("C API PASS: public FILE closer callback closes actual native stream");
}

#endif
