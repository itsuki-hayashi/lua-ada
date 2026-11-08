/* The identical public-header program is linked separately to Ada liblua and
 * the isolated pinned C oracle. Cases inspect actual calls and owned state.
 * Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE. */
#include <stdio.h>
#include <string.h>

int lua_ada_test_continuation_contract(int which);
int lua_ada_test_hook_contract(int which);
int lua_ada_test_math_reopen_contract(int which);
int lua_ada_test_library_opener_contract(int which);

static int check(const char *group, int which, int result) {
    if (result != 0) {
        fprintf(stderr, "foreign %s case %d failed: %d\n", group, which,
                result);
        return 0;
    }
    printf("PASS: foreign-%s-%d\n", group, which);
    fflush(stdout);
    return 1;
}

int main(int argc, char **argv) {
    int which;
    int without_release_reentry = argc == 2 &&
        strcmp(argv[1], "--without-release-reentry") == 0;
    for (which = 1; which <= 25; ++which)
        if (!check("continuation", which,
                   lua_ada_test_continuation_contract(which))) return 1;
    for (which = 1; which <= 29; ++which) {
        /* A lua_Debug frame token expires with its activation. The Ada-only
         * stale-token rejection is separately tested by AUnit case6; invoking
         * an expired token is outside the native public lifetime contract. */
        if (which == 6) continue;
        /* The pinned USER_H lock instrumentation aborts public API reentry
         * from a payload allocator. Its native-default witness and both Ada
         * cases remain required; an explicit oracle option records the
         * narrower native-T run without presenting this case as passing. */
        if (which == 24 && without_release_reentry) continue;
        if (!check("hook", which, lua_ada_test_hook_contract(which))) return 1;
    }
    for (which = 1; which <= 5; ++which)
        if (!check("math-reopen", which,
                   lua_ada_test_math_reopen_contract(which))) return 1;
    for (which = 1; which <= 4; ++which)
        if (!check("library-opener", which,
                   lua_ada_test_library_opener_contract(which))) return 1;
    puts("PASS: public foreign contract");
    return 0;
}
