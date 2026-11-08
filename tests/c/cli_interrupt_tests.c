/* Focused test transports: real SIGINT and prior-disposition observations.
 * They never install an interpreter handler, inject a pending VM flag or
 * raise a second/default signal in the AUnit host. Product OS delivery is
 * independently exercised by the isolated console/process observers. */
#if !defined(_WIN32)
#define _POSIX_C_SOURCE 200809L
#endif
#include <signal.h>
#include <stddef.h>
#include "lua.h"
#include "lauxlib.h"

extern int lua_ada_cli_interrupt_test_active(void);
extern unsigned long lua_ada_cli_interrupt_test_arm_count(void);
extern int lua_ada_cli_interrupt_control(int operation);
static volatile sig_atomic_t prior_received;
static int prepared;
#if defined(_WIN32)
static void (*original_handler)(int);
#else
static struct sigaction original_action;
#endif

static void prior_handler(int number) {
    if (signal(number, prior_handler) == SIG_ERR) prior_received = -1;
    else prior_received++;
}

int lua_ada_test_interrupt_prepare(void) {
    if (prepared || lua_ada_cli_interrupt_test_active()) return 0;
    prior_received = 0;
#if defined(_WIN32)
    original_handler = signal(SIGINT, prior_handler);
    if (original_handler == SIG_ERR) return 0;
#else
    {
        struct sigaction action;
        action.sa_handler = prior_handler;
        action.sa_flags = 0;
        if (sigemptyset(&action.sa_mask) != 0 ||
            sigaction(SIGINT, &action, &original_action) != 0) return 0;
    }
#endif
    prepared = 1;
    return 1;
}

int lua_ada_test_interrupt_restore(void) {
    if (lua_ada_cli_interrupt_test_active() &&
        lua_ada_cli_interrupt_control(2) != 1) return 0;
    if (!prepared) return 1;
#if defined(_WIN32)
    if (signal(SIGINT, original_handler) == SIG_ERR) return 0;
#else
    if (sigaction(SIGINT, &original_action, NULL) != 0) return 0;
#endif
    prepared = 0;
    return 1;
}

int lua_ada_test_interrupt_previous(void) {
    sig_atomic_t before = prior_received;
    if (!prepared || lua_ada_cli_interrupt_test_active()) return 0;
#if defined(_WIN32)
    {
        void (*observed)(int) = signal(SIGINT, prior_handler);
        if (observed == SIG_ERR) return 0;
        if (signal(SIGINT, observed) == SIG_ERR || observed != prior_handler)
            return 0;
    }
#else
    {
        struct sigaction observed;
        if (sigaction(SIGINT, NULL, &observed) != 0 ||
            observed.sa_handler != prior_handler) return 0;
    }
#endif
    /* Verify the installed handler before raising. A restoration regression
     * must fail this case, never terminate the complete AUnit process. */
    return raise(SIGINT) == 0 && prior_received == before + 1;
}

int lua_ada_test_interrupt_raise(lua_State *L) {
    if (!lua_ada_cli_interrupt_test_active())
        return luaL_error(L, "SIGINT test callback outside CLI docall");
    if (raise(SIGINT) != 0) return luaL_error(L, "SIGINT test raise failed");
    return 0;
}

int lua_ada_test_interrupt_state(lua_State *L) {
    lua_pushboolean(L, lua_ada_cli_interrupt_test_active());
    lua_pushinteger(L, (lua_Integer)lua_ada_cli_interrupt_test_arm_count());
    return 2;
}

int lua_ada_test_interrupt_default(lua_State *L) {
    int is_default;
#if defined(_WIN32)
    void (*observed)(int) = signal(SIGINT, SIG_DFL);
    if (observed == SIG_ERR || signal(SIGINT, observed) == SIG_ERR)
        return luaL_error(L, "cannot inspect SIGINT disposition");
    is_default = observed == SIG_DFL;
#else
    struct sigaction observed;
    if (sigaction(SIGINT, NULL, &observed) != 0)
        return luaL_error(L, "cannot inspect SIGINT disposition");
    is_default = observed.sa_handler == SIG_DFL;
#endif
    lua_pushboolean(L, is_default);
    return 1;
}
