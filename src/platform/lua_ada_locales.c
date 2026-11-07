/* Native locale/ctype mechanics only. All pattern, number and Lua string
 * semantics stay in Ada; the language scanner retains its ASCII policy. */
#include <ctype.h>
#include <locale.h>
#include <stddef.h>

const char *lua_ada_locale_set(int category, const char *name) {
    static const int categories[] = {
        LC_ALL, LC_COLLATE, LC_CTYPE, LC_MONETARY, LC_NUMERIC, LC_TIME
    };
    if (category < 0 || category >= 6) return NULL;
    return setlocale(categories[category], name);
}

unsigned char lua_ada_locale_decimal_point(void) {
    return (unsigned char)localeconv()->decimal_point[0];
}

int lua_ada_locale_class(unsigned char byte, int category) {
    /* Normalized results are bridge booleans, independent of libc's internal
     * classification bit masks. unsigned char satisfies every ctype contract. */
    switch (category) {
    case 0: return !!isalpha(byte);
    case 1: return !!iscntrl(byte);
    case 2: return !!isdigit(byte);
    case 3: return !!isgraph(byte);
    case 4: return !!islower(byte);
    case 5: return !!ispunct(byte);
    case 6: return !!isspace(byte);
    case 7: return !!isupper(byte);
    case 8: return !!isalnum(byte);
    case 9: return !!isxdigit(byte);
    default: return 0;
    }
}

unsigned char lua_ada_locale_lower(unsigned char byte) {
    return (unsigned char)tolower(byte);
}

unsigned char lua_ada_locale_upper(unsigned char byte) {
    return (unsigned char)toupper(byte);
}
