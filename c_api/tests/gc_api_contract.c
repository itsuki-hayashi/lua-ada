/* First-party deterministic public GC contract, shared by both runtimes.
 * MIT license; see ../../LICENSE. No private C or Ada layouts are inspected. */
#include "lua.h"
#include "lauxlib.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "consumer_allocator.h"
#include "gc_contract.h"

int main(void) {
    lua_State *state = luaL_newstate();
    assert(state);
    test_gc_controls_without_allocation();
    test_gc_modes_and_stopped_steps(state);
    test_gc_finalizer_callback_order(state);
    test_gc_finalizer_storage_refusal();
    test_close_drains_c_finalizers();
    test_close_refusal_releases_storage();
    test_gc_and_close_warning_callbacks();
    lua_close(state);
    puts("PASS: public GC contract");
    return 0;
}
