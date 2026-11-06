/* Test-only budgets are inherited by CLI children, including those launched
 * by main.lua. They are not product switches or changes to upstream sources. */
#ifndef CONFORMANCE_ALLOCATOR_LIMIT_H
#define CONFORMANCE_ALLOCATOR_LIMIT_H
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static size_t conformance_limit(void) {
  const char *text = getenv("LUA_ADA_CONFORMANCE_ALLOCATOR");
  char *end;
  unsigned long long value;
  if (text == NULL) return (size_t)2147483648ULL;
  /* strtoull accepts signs and leading whitespace. A negative spelling can
   * become SIZE_MAX, accidentally removing the test ceiling. Accept digits
   * only before conversion; the runner itself chooses approved profiles. */
  for (end = (char *)text; *end != '\0'; end++) {
    if (*end < '0' || *end > '9') {
      fputs("invalid LUA_ADA_CONFORMANCE_ALLOCATOR\n", stderr);
      exit(EXIT_FAILURE);
    }
  }
  errno = 0;
  value = strtoull(text, &end, 10);
  if (errno != 0 || *text == '\0' || *end != '\0' || value == 0 ||
      value > (unsigned long long)SIZE_MAX) {
    fputs("invalid LUA_ADA_CONFORMANCE_ALLOCATOR\n", stderr);
    exit(EXIT_FAILURE);
  }
  return (size_t)value;
}
#endif
