/* CLI-only SIGINT mechanics. The asynchronous handler never enters Ada/Lua,
 * follows a VM pointer, allocates, or performs a nonlocal transfer. A private
 * Ada execution lease installs this controller only around an actual docall
 * region; its fixed context consumes the request at a safe Lua boundary.
 * Guaranteed lock-free C11 atomics also cover the Windows CRT control thread.
 * Ordinary embedded sessions do not install a process signal disposition. */
#if !defined(_WIN32)
#define _POSIX_C_SOURCE 200809L
#endif
#include <errno.h>
#include <signal.h>
#include <stddef.h>
#include <stdatomic.h>

_Static_assert(ATOMIC_INT_LOCK_FREE == 2,
               "CLI interrupts require always-lock-free int atomics");

enum interrupt_operation { interrupt_arm, interrupt_consume, interrupt_restore };
static _Atomic int pending;
static int active;
#if defined(LUA_ADA_TEST_BUILD_PROFILE)
static unsigned long arm_count;
int lua_ada_cli_interrupt_test_active(void) { return active; }
unsigned long lua_ada_cli_interrupt_test_arm_count(void) { return arm_count; }
#endif
#if defined(_WIN32)
static void (*previous_handler)(int);
#else
static struct sigaction previous_action;
#endif

static void request_interrupt(int number) {
    int saved_errno = errno;
    int reset = signal(number, SIG_DFL) != SIG_ERR;
    /* Reset first, exactly as native laction does. A second interrupt in
     * this protected operation takes the default path, including during a
     * long native operation that has not reached a Lua instruction boundary.
     * Only a lock-free scalar is published; no interpreter hook is touched. */
    /* C atomic assignment is a lock-free store on the required target.
     * Keep generic atomic library/macro operations in the synchronous side. */
    pending = reset ? 1 : -1;
    errno = saved_errno;
}

int lua_ada_cli_interrupt_control(enum interrupt_operation operation) {
    switch (operation) {
    case interrupt_arm:
        /* The CLI serializes protected operations. Refuse an overlapping
         * lease rather than replacing the disposition saved by its owner. */
        if (active) return 0;
        atomic_store_explicit(&pending, 0, memory_order_relaxed);
#if defined(_WIN32)
        previous_handler = signal(SIGINT, request_interrupt);
        if (previous_handler == SIG_ERR) return 0;
#else
        {
            struct sigaction action;
            action.sa_handler = request_interrupt;
            action.sa_flags = 0;  /* native docall does not select SA_RESTART */
            if (sigemptyset(&action.sa_mask) != 0 ||
                sigaction(SIGINT, &action, &previous_action) != 0) return 0;
        }
#endif
        active = 1;
#if defined(LUA_ADA_TEST_BUILD_PROFILE)
        arm_count++;
#endif
        return 1;
    case interrupt_consume:
        if (!active) return 0;
        return atomic_exchange_explicit(&pending, 0, memory_order_relaxed);
    case interrupt_restore:
        if (!active) return 0;
#if defined(_WIN32)
        if (signal(SIGINT, previous_handler) == SIG_ERR) return 0;
#else
        if (sigaction(SIGINT, &previous_action, NULL) != 0) return 0;
#endif
        active = 0;
        atomic_store_explicit(&pending, 0, memory_order_relaxed);
        return 1;
    default:
        return 0;
    }
}
