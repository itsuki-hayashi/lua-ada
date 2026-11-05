/* Test-only adapter for the unchanged pinned Lua opcode definitions.
 * Copyright Lua Ada contributors. Lua declarations retain their upstream
 * copyright; this program is never linked into the production interpreter. */
#include <stdint.h>
#include <stdio.h>
#include "../../references/lua/lopcodes.h"
#include "../../references/lua/lopnames.h"

int main(void) {
  unsigned int op;
  uint32_t seed = UINT32_C(0xa51c9237);
  printf("BASELINE 5.5.1 7579fc9d7ed90240487251dfb69168f8e64e9294\n");
  for (op = 0; op < NUM_OPCODES; ++op)
    printf("OP %u %s %u\n", op, opnames[op], luaP_opmodes[op]);
  /* Compare every physical field, including signed and variant views,
   * over arbitrary high bits. Constructors/setters must preserve other bits. */
  for (op = 1; op <= 4096; ++op) {
    Instruction i;
    seed = seed * UINT32_C(1664525) + UINT32_C(1013904223);
    i = (seed & UINT32_C(0xffffff80)) | (op % NUM_OPCODES);
    printf("WORD %u %u %u", op, (unsigned)i,
           (unsigned)GET_OPCODE(i));
    printf(" %u %u", (unsigned)GETARG_A(i), (unsigned)GETARG_k(i));
    switch (getOpMode(GET_OPCODE(i))) {
      case iABC:
        printf(" ABC %d %d %d %d", GETARG_B(i), GETARG_C(i),
               GETARG_sB(i), GETARG_sC(i)); break;
      case ivABC:
        printf(" VABC %d %d", GETARG_vB(i), GETARG_vC(i)); break;
      case iABx: printf(" ABX %d", GETARG_Bx(i)); break;
      case iAsBx: printf(" ASBX %d", GETARG_sBx(i)); break;
      case iAx: printf(" AX %d", GETARG_Ax(i)); break;
      case isJ: printf(" SJ %d", GETARG_sJ(i)); break;
    }
    printf(" %d %d\n", !!luaP_isIT(i), !!luaP_isOT(i));
  }
  return 0;
}
