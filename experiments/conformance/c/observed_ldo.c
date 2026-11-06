/* LUAI_MAXSTACK is private to ldo.c in this release. Observe its actual
 * compiled definition without copying the constant into report code. This
 * wrapper replaces that translation unit only in the separate C oracle. */
#include "../../../references/lua/ldo.c"
#include "../../../references/lua/lauxlib.h"

LUA_API unsigned conformance_stack_limit(void) {
  return LUAI_MAXSTACK;
}

LUA_API unsigned conformance_c_call_limit(void) {
  return LUAI_MAXCCALLS;
}

LUA_API unsigned conformance_extra_space(void) {
  return (unsigned)LUA_EXTRASPACE;
}

LUA_API unsigned conformance_aux_buffer(void) {
  return (unsigned)LUAL_BUFFERSIZE;
}
