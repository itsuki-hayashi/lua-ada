/* Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE.
 *
 * Essential standard-allocation and host-entropy glue for the two public
 * symbols that pinned Lua 5.5.1 defines in lauxlib.c:
 *
 *   void     *luaL_alloc(void *ud, void *ptr, size_t osize, size_t nsize);
 *   unsigned  luaL_makeseed(lua_State *L);
 *
 * Why a C allocator at all: the Ada runtime owns every Lua session, object,
 * and collector record. Those stay in Ada and are reached only through the
 * public lua_* API. The C-ABI side still has to offer the ordinary
 * "lua_Alloc" function that C embedders obtain from luaL_newstate, and that
 * function has to behave exactly like the pinned reference, so that a C
 * consumer comparing lua_getallocf against luaL_alloc, or passing it to
 * lua_newstate, sees the same contract. That contract is a stateless
 * realloc/free pair, which is what this file provides. It holds no Lua
 * values and calls no Lua functions, so it cannot reach interpreter logic.
 *
 * This file contains no interpreter, parser, VM, or library algorithm, and
 * it has no dependency beyond the C99 standard library (stdlib.h, time.h,
 * stddef.h, and the public headers). The C constructor selects this
 * allocator; bounded Ada sessions retain their own provider policy.
 *
 * Compatibility decisions, each traced to the pinned lauxlib.c:
 *
 *  - luaL_alloc ignores 'ud' and 'osize', as the pinned version does, and
 *    never tracks sizes. A 'nsize' of zero means "free": the block is
 *    released and NULL is returned. Any other 'nsize' is a plain realloc.
 *    Lua's contract makes NULL in 'ptr' with a non-zero 'nsize' a fresh
 *    allocation, and realloc gives exactly that.
 *  - On refusal (realloc returns NULL while 'nsize' is non-zero), the old
 *    block is left untouched and still owned by the caller. This file never
 *    frees 'ptr' on that path, because realloc itself keeps the original
 *    block valid when it fails.
 *  - luaL_makeseed does not read or write any lua_State, and it does not
 *    call the allocator in use by any state. It only accepts a state so that
 *    the signature matches the public header. NULL and a live state behave
 *    identically.
 *  - The seed is a mix of three host values: the object representation of a
 *    stack address, the current time(NULL), and the current clock(). It is
 *    only a light source of variation for the hash seed, which the Lua
 *    runtime uses to randomize table hashing. It is NOT a cryptographic
 *    random number, it is not unpredictable to an attacker who can observe
 *    the process, and two calls within the same time or clock tick may
 *    return the same value. Exact seed values are not part of any contract.
 *    The mixing function is FNV-1 over the bytes plus a final avalanche,
 *    which is simple, portable, and cheap.
 */

#include <stddef.h>
#include <stdlib.h>
#include <time.h>

#include "lua_ada_runtime_configuration.h"
#include "lauxlib.h"


/*
** luaL_alloc: the standard Lua allocation function.
**
** 'ud' and 'osize' are part of the lua_Alloc signature but are not needed
** here: realloc and free know the size of their own blocks. Taking them as
** explicit parameters keeps this function interchangeable with any other
** lua_Alloc supplied by an embedder.
**
** Behavior by case:
**   nsize == 0 : free(ptr) and return NULL. 'ptr' may be NULL, and free(NULL)
**                is a no-op, so freeing a NULL block is safe.
**   nsize  > 0 : return realloc(ptr, nsize). A NULL 'ptr' produces a fresh
**                block; a non-NULL 'ptr' is grown or shrunk and its leading
**                bytes are preserved. On failure, realloc returns NULL and
**                leaves 'ptr' valid, which is the refusal case described in
**                the file header.
*/
LUALIB_API void *(luaL_alloc) (void *ud, void *ptr, size_t osize,
                                                    size_t nsize) {
  /* The reference ignores these two parameters too. Casting to void marks
  ** them as intentionally unused so that -Wextra stays quiet. */
  (void)ud;
  (void)osize;
  if (nsize == 0) {
    /* Lua's convention: a zero-size request is a free request. Return NULL
    ** so that a caller which stores the result back into its block pointer
    ** does not keep a dangling address. */
    free(ptr);
    return NULL;
  }
  else {
    /* realloc(NULL, n) is malloc(n). On failure it returns NULL and keeps
    ** 'ptr' allocated; we do not touch 'ptr' on that path, so the caller can
    ** still read and release the original block. */
    return realloc(ptr, nsize);
  }
}


/*
** Hash helper: fold 'n' bytes starting at 'obj' into the running value 'h'.
**
** The bytes are read through an unsigned char pointer, which the C standard
** always allows for object representations. This avoids converting pointers
** or time values to integers, whose width and representation are
** implementation-defined. The FNV-1 step (multiply by the 32-bit FNV prime,
** then XOR the byte) is written with unsigned arithmetic, so wrap-around is
** well defined in C99.
*/
static unsigned int seed_fold(unsigned int h, const void *obj, size_t n) {
  const unsigned char *bytes = (const unsigned char *)obj;
  size_t i;
  for (i = 0; i < n; i++) {
    h *= 16777619u;  /* 32-bit FNV prime */
    h ^= bytes[i];
  }
  return h;
}


/*
** luaL_makeseed: produce an unsigned seed for lua_newstate.
**
** The parameter 'L' is ignored. It is neither dereferenced nor passed to
** any Lua function, so calling this with NULL, or with a live state whose
** allocator is counted, cannot change its stack, call its allocator, or
** touch any table. The contract tests check exactly that.
**
** Steps:
**  1. Start from the 32-bit FNV offset basis.
**  2. Fold in the object bytes of a local variable's address. Its value
**     varies with the stack layout, and typically with address-space layout
**     randomization when the platform enables it.
**  3. Fold in time(NULL) and clock(). Both return a standard type, and their
**     bytes are folded the same way as the address. A value of (time_t)-1 or
**     (clock_t)-1 means the host has no clock; the fold still works, and the
**     seed then depends only on the address.
**  4. Run a final avalanche (xor-shift, multiply, xor-shift) so that small
**     changes in the input spread into all 32 output bits. This is a mixing
**     step, not a cryptographic one.
*/
LUALIB_API unsigned int (luaL_makeseed) (lua_State *L) {
  /* A local whose address provides run-to-run variation. Its value is never
  ** read, only its address, so there is no uninitialized-read hazard. */
  int stack_marker = 0;
  const void *stack_addr = (const void *)&stack_marker;
  time_t now = time(NULL);
  clock_t ticks = clock();
  unsigned int h = 2166136261u;  /* 32-bit FNV offset basis */

  (void)L;  /* The state is intentionally unused; see the comment above. */

  h = seed_fold(h, &stack_addr, sizeof(stack_addr));
  h = seed_fold(h, &now, sizeof(now));
  h = seed_fold(h, &ticks, sizeof(ticks));

  /* Final avalanche: a standard xor-shift/multiply finalizer. */
  h ^= h >> 15;
  h *= 0x2c1b3c6dU;
  h ^= h >> 12;
  return h;
}
