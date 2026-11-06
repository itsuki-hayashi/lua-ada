/* First-party native counterpart for POSIX signal termination in files.lua.
 * Windows reports a process exit code instead of a waitpid signal number.
 * TerminateProcess actually terminates this process; this is not a normal
 * return or a Lua os.exit stand-in. The surrounding C/Ada Lua code must still
 * observe matching popen and system status and preserve subprocess cleanup. */
#include <windows.h>
#include <errno.h>
#include <limits.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    char *end;
    unsigned long code;
    if (argc != 2) return 2;
    errno = 0;
    code = strtoul(argv[1], &end, 10);
    if (errno != 0 || *argv[1] == '\0' || *end != '\0' ||
        code == 0 || code > INT_MAX) return 2;
    if (!TerminateProcess(GetCurrentProcess(), (UINT)code)) return 3;
    /* The successful native call terminates the calling process. If delivery
     * is pending, do not manufacture an ordinary main-return status. */
    Sleep(INFINITE);
    return 3;
}
