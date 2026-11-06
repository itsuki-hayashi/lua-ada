#ifndef LUA_ADA_CORE_IMAGE_SUPPORT_H
#define LUA_ADA_CORE_IMAGE_SUPPORT_H

#include "lua.h"

void *lua_ada_image_make(void);
int lua_ada_image_check(void *address, void *pool, lua_Alloc allocator);
void lua_ada_image_close(void *address);
void lua_ada_image_check_elaboration(void);

#endif
