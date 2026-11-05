/* Test-only evidence for string.pack native layouts. Never linked into the
 * Ada interpreter. C99 alignment is measured through the same offsetof shape
 * used by the pinned Lua string library, including its long-double member. */
#include <limits.h>
#include <stddef.h>
#include <stdio.h>
#include "../../references/lua/lua.h"

#define RECORD_TYPE(name, type) \
  struct align_##name { char prefix; type value; }

RECORD_TYPE(cshort, short);
RECORD_TYPE(cint, int);
RECORD_TYPE(clong, long);
RECORD_TYPE(csize, size_t);
RECORD_TYPE(cfloat, float);
RECORD_TYPE(cdouble, double);
RECORD_TYPE(cldouble, long double);
RECORD_TYPE(linteger, lua_Integer);
RECORD_TYPE(lnumber, lua_Number);
struct maximum_alignment { char prefix; union { LUAI_MAXALIGN; } value; };

#define PRINT_TYPE(name, type) \
  printf(#name ".size=%zu\n" #name ".align=%zu\n", \
         sizeof(type), offsetof(struct align_##name, value))

int main(void) {
  const union { unsigned int word; unsigned char bytes[sizeof(unsigned int)]; }
    endian = { 1u };
  printf("char.bits=%d\n", CHAR_BIT);
  PRINT_TYPE(cshort, short);
  PRINT_TYPE(cint, int);
  PRINT_TYPE(clong, long);
  PRINT_TYPE(csize, size_t);
  PRINT_TYPE(cfloat, float);
  PRINT_TYPE(cdouble, double);
  PRINT_TYPE(cldouble, long double);
  PRINT_TYPE(linteger, lua_Integer);
  PRINT_TYPE(lnumber, lua_Number);
  printf("maximum.align=%zu\n", offsetof(struct maximum_alignment, value));
  printf("endian.little=%d\n", endian.bytes[0] == 1u);
  return 0;
}
