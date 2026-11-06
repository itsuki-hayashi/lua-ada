/* First-party deterministic public IO/OS contract, shared by both runtimes.
 * MIT license; see ../../LICENSE. Uses only the pinned public headers. */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "consumer_allocator.h"
#include "io_contract.h"

int main(void) {
    struct allocation_counts counts = {0};
    lua_State *state = lua_newstate(counted_allocator, &counts, 1);
    assert(state);
    test_io_opener_and_stream_layout(state);
    test_os_opener_without_global_publication(state);
    test_file_payload_closer_callback(state);
    lua_close(state);
    assert(counts.bytes == 0 && counts.blocks == 0);
    puts("PASS: public IO/OS contract");
    return 0;
}
