/* Protected frontend adapter: test-only use of pinned Lua internals.
 * No source is executed, and no change to the upstream tree is required. */
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../../references/lua/lua.h"
#include "../../references/lua/lauxlib.h"
#include "../../references/lua/llex.h"
#include "../../references/lua/lstate.h"
#include "../../references/lua/lstring.h"
#include "../../references/lua/lzio.h"

typedef struct {
  const char *bytes;
  size_t size;
  Mbuffer buffer;
  LexState lexer;
} Input;

static const char *reader(lua_State *L, void *ud, size_t *size) {
  Input *input = (Input *)ud;
  (void)L;
  *size = input->size;
  input->size = 0;
  return input->bytes;
}
static void hex(const char *text, size_t size) {
  size_t i;
  for (i = 0; i < size; ++i) printf("%02X", (unsigned char)text[i]);
}
static int scan(lua_State *L) {
  Input *input = (Input *)lua_touserdata(L, 1);
  LexState *ls = &input->lexer;
  ZIO stream;
  int token;
  lua_newtable(L); /* Keep the anchor table live throughout scanning. */
  ls->h = hvalue(s2v(L->top.p - 1));
  ls->buff = &input->buffer;
  luaZ_init(L, &stream, reader, input);
  /* The source label must survive collections triggered by string scanning.
   * Keep it on the C frame's Lua stack, just like the anchor table. */
  lua_pushliteral(L, "=oracle");
  luaX_setinput(L, ls, &stream, tsvalue(s2v(L->top.p - 1)),
                zgetc(&stream));
  do {
    luaX_next(ls);
    token = ls->t.token;
    printf("TOKEN %d %d", token, ls->linenumber);
    if (token == TK_NAME || token == TK_STRING) {
      putchar(' ');
      hex(getstr(ls->t.seminfo.ts), tsslen(ls->t.seminfo.ts));
    } else if (token == TK_INT) {
      printf(" %" PRId64, (int64_t)ls->t.seminfo.i);
    } else if (token == TK_FLT) {
      uint64_t bits;
      memcpy(&bits, &ls->t.seminfo.r, sizeof(bits));
      printf(" %016" PRIX64, bits);
    }
    putchar('\n');
  } while (token != TK_EOS);
  return 0;
}
/* Each batch case owns a fresh C state; scanner errors are caught before
 * buffer cleanup. This keeps arbitrary-byte campaigns cheap and isolated. */
static void run(const char *mode, const char *bytes, size_t length) {
  Input input;
  lua_State *L = luaL_newstate();
  int status;
  if (!L) { puts("RESOURCE"); return; }
  memset(&input, 0, sizeof(input));
  input.bytes = bytes;
  input.size = length;
  luaZ_initbuffer(L, &input.buffer);
  if (strcmp(mode, "lex") == 0) {
    lua_pushcfunction(L, scan);
    lua_pushlightuserdata(L, &input);
    status = lua_pcall(L, 1, 0, 0);
    if (status == LUA_ERRSYNTAX)
      printf("ERROR %d\n", input.lexer.linenumber);
    else if (status) puts("RESOURCE");
    luaZ_freebuffer(L, &input.buffer);
  } else {
    status = luaL_loadbufferx(L, bytes, length, "=oracle", "t");
    if (status) { const char *message = lua_tostring(L, -1); const char *colon = strchr(message, ':' ); if (status != LUA_ERRSYNTAX) puts("RESOURCE"); else printf("ERROR %ld\n", colon ? strtol(colon + 1, NULL, 10) : 0); }
    else puts("ACCEPT");
  }
  lua_close(L);
}
int main(int argc, char **argv) {
  FILE *file;
  long length;
  char *bytes;
  if (argc != 3) return 2;
  if (sizeof(lua_Integer) != 8 || sizeof(lua_Number) != 8) return 2;
  file = fopen(argv[2], "rb");
  if (!file) return 2;
  if (strcmp(argv[1], "batch") == 0 || strcmp(argv[1], "parse-batch") == 0) {
    char line[8192], decoded[4096];
    while (fgets(line, sizeof(line), file)) {
      size_t i, count = strcspn(line, "\r\n");
      if (count % 2) return 2;
      for (i = 0; i < count / 2; ++i) {
        unsigned byte;
        if (sscanf(line + 2 * i, "%2x", &byte) != 1) return 2;
        decoded[i] = (char)byte;
      }
      run(strcmp(argv[1], "batch") == 0 ? "lex" : "parse", decoded, count / 2);
      puts("END");
    }
    fclose(file);
    return 0;
  }
  if (fseek(file, 0, SEEK_END) || (length = ftell(file)) < 0 ||
      length > 1000000 || fseek(file, 0, SEEK_SET)) return 2;
  bytes = (char *)malloc((size_t)length + 1);
  if (!bytes || fread(bytes, 1, (size_t)length, file) != (size_t)length)
    return 2;
  fclose(file);
  if (strcmp(argv[1], "lex") != 0 && strcmp(argv[1], "parse") != 0)
    return 2;
  run(argv[1], bytes, (size_t)length);
  free(bytes);
  return 0;
}
