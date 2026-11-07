/* Private-T caller of the unchanged public buffer operation witness.
 * MIT; see ../../LICENSE.
 *
 * This is a separate T-only executable. Its actual pinned ltests.h receiver
 * declares a 23-byte scratch buffer; it must never run against a default
 * 1024-byte implementation. The ordinary SDK consumer remains separate.
 * The emitted extraspace value describes this header role only. These buffer
 * operations do not access private native lock/extraspace storage.
 */
#ifdef LUA_USER_H
#error "the private buffer receiver selects its own pinned user header"
#endif
#define LUA_USER_H <ltests.h>
#define LUA_ADA_BUFFER_CONTRACT_LIBRARY
#include "buffer_api_contract.c"

int main(void) {
    unsigned i;
    assert(LUAL_BUFFERSIZE == 23);
    assert(sizeof(((luaL_Buffer *)0)->init.b) == 23);
    printf("BUFFER-RECEIVER: private-t-c LUAL_BUFFERSIZE=%u "
           "SIZEOF_BUFFER=%u LUA_EXTRASPACE=%u\n",
           (unsigned)LUAL_BUFFERSIZE, (unsigned)sizeof(luaL_Buffer),
           (unsigned)LUA_EXTRASPACE);
    for (i = 0; i < BUFFER_CASE_COUNT; i++) {
        assert(lua_ada_test_buffer(i));
        printf("PASS: buffer-%s\n", cases[i].name);
        fflush(stdout);
    }
    puts("PASS: public luaL_Buffer contract");
    return 0;
}
