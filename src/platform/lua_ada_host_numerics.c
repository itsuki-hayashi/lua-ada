/* Narrow host arithmetic adapter.  No Lua state or language behavior lives
 * here: Ada owns conversion, dispatch, floor division and modulo correction.
 *
 * Ada's checked division rejects a zero divisor, whereas Lua exposes the
 * native binary64 result.  Let the target arithmetic instruction choose NaN
 * sign/payload as well as infinities; synthesizing x86's negative quiet NaN
 * changes observable bytes on AArch64.  Runtime arguments prevent constant
 * folding of an exceptional operation in the source compiler.
 */
double lua_ada_host_divide(double left, double right);

double lua_ada_host_divide(double left, double right)
{
    return left / right;
}
