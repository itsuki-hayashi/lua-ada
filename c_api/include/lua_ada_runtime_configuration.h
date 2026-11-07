#ifndef LUA_ADA_RUNTIME_CONFIGURATION_H
#define LUA_ADA_RUNTIME_CONFIGURATION_H

/* Keep runtime C facade types consistent with the selected Ada image. The
 * public SDK stays byte-identical to upstream. Only the instrumented buffer
 * extent is overridden here, after luaconf.h's unconditional definition;
 * no private C VM header or lock representation enters the implementation. */
#include "lua.h"
#if defined(LUA_ADA_AUXILIARY_BUFFER_BYTES)
#undef LUAL_BUFFERSIZE
#define LUAL_BUFFERSIZE LUA_ADA_AUXILIARY_BUFFER_BYTES
#endif

#endif
