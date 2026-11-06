/* Test-only build identity, derived from the GPR that links this launcher.
 * These constants do not change interpreter behavior or public Lua headers. */
#define TEXT_INNER(value) #value
#define TEXT(value) TEXT_INNER(value)

const char *lua_ada_test_build_profile(void) {
    return TEXT(LUA_ADA_TEST_BUILD_PROFILE);
}

const char *lua_ada_test_link_kind(void) {
    return TEXT(LUA_ADA_TEST_LINK_KIND);
}
