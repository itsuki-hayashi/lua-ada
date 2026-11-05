/* Compile the unchanged reference CLI as a separate test executable.
 * Keeping this translation unit outside the reference project's source
 * directory avoids duplicate-source ownership across GPRbuild versions. */
#include "../../../references/lua/lua.c"
