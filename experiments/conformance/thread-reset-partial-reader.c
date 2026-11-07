/* Diagnostic reproducer, deliberately outside the passing contract. Pinned
 * native Lua skips parser scratch cleanup when a second reader refill resets
 * its running thread. Default trips the final provider-balance assertion;
 * native T aborts on its internal total-byte assertion during lua_close.
 * The Ada-owned AUnit callback regression requires balanced cleanup instead.
 * Compile/link this separately against the selected runtime, never reference
 * interpreter objects inside the Ada implementation. */
#define LUA_ADA_RESET_CONTRACT_LIBRARY
#include "../../c_api/tests/thread_reset_api_contract.c"

int main(void) {
    int n;
    lua_State *L, *co;
    memset(&counts, 0, sizeof counts);
    reader_calls = 0;
    self_returned = 0;
    L = lua_newstate(counted_allocator, &counts, 223U);
    assert(L != NULL);
    luaL_openlibs(L);
    co = lua_newthread(L);
    lua_pushcfunction(co, lua_ada_test_reset_reader());
    assert(lua_resume(co, L, 0, &n) == LUA_OK && n == 0);
    assert(reader_calls == 2 && self_returned == 0);
    puts("Observed: partial reader self transfer completed");
    fflush(stdout);
    lua_close(L);
    assert(counts.bytes == 0 && counts.blocks == 0);
    puts("PASS: partial reader reset released parser ownership");
    return 0;
}
