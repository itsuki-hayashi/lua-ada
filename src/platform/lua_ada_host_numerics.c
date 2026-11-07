/* Narrow host arithmetic and format-capability adapter. No Lua state lives
 * here: Ada owns conversion, dispatch, numeric rounding and formatting.
 *
 * Ada's checked division rejects a zero divisor, whereas Lua exposes the
 * native binary64 result.  Let the target arithmetic instruction choose NaN
 * sign/payload as well as infinities; synthesizing x86's negative quiet NaN
 * changes observable bytes on AArch64.  Runtime arguments prevent constant
 * folding of an exceptional operation in the source compiler.
 */
#include <locale.h>
#include <stdio.h>
#include <string.h>

double lua_ada_host_divide(double left, double right);
int lua_ada_host_general_carry_zeroes(void);
size_t lua_ada_host_pointer_text(const void *pointer, char *bytes,
                                size_t capacity, int width, int left);

size_t lua_ada_host_pointer_text(const void *pointer, char *bytes,
                                size_t capacity, int width, int left)
{
    char format[8];
    int length;
    /* MinGW's %*p and a literal-width %20p have different default zero
     * padding. Construct the bounded literal field used by Lua instead of
     * replacing it with a star argument. Width is validated in Ada (0..99). */
    if (width == 0)
        strcpy(format, left ? "%-p" : "%p");
    else {
        length = snprintf(format, sizeof format, "%%%s%dp", left ? "-" : "",
                          width);
        if (length < 0 || (size_t)length >= sizeof format) return 0;
    }
    length = snprintf(bytes, capacity, format, (void *)pointer);
    return length < 0 || (size_t)length >= capacity ? 0 : (size_t)length;
}

double lua_ada_host_divide(double left, double right)
{
    return left / right;
}

int lua_ada_host_general_carry_zeroes(void)
{
    char buffer[32];
    int length;
    size_t after_point;
    /* An exact binary quarter provokes the general-format transition without
     * depending on our fixture values or decimal parsing. glibc's old fixed
     * fractional minimum remains zero after this transition; other libcs
     * retain the significant-precision padding. Detect the actual library,
     * including its future changes, rather than assuming every Linux libc
     * has that spelling. Locale can have a multibyte decimal point. */
    length = snprintf(buffer, sizeof buffer, "%#.2g", 99.75);
    after_point = 1 + strlen(localeconv()->decimal_point);
    if (length > 0 && (size_t)length < sizeof buffer &&
        after_point < (size_t)length && buffer[0] == '1' &&
        (buffer[after_point] == 'e' || buffer[after_point] == 'E'))
        return 0;
    return 1;
}
