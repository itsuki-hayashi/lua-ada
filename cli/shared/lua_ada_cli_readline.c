/* Native REPL transport only. Compilation, multiline decisions and execution
 * remain in Ada. Match the pinned platform's readline selection: Linux loads
 * an optional host library, macOS links its system readline, Windows falls
 * back to stdio. A loaded handle stays alive through the process's last use. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "lua.h"
#if defined(LUA_ADA_CLI_LINUX)
#include <dlfcn.h>
#elif defined(LUA_ADA_CLI_MACOS)
#include <readline/readline.h>
#include <readline/history.h>
#endif

typedef char *(*read_line_function)(const char *);
typedef void (*save_line_function)(const char *);
static read_line_function read_line;
static save_line_function save_line;
static char fallback[512];
typedef char function_pointer_size_check[
    sizeof(read_line_function) == sizeof(void *) &&
    sizeof(save_line_function) == sizeof(void *) ? 1 : -1];

static const char *initialize_readline(int ignore_environment) {
#if defined(LUA_ADA_CLI_LINUX)
    const char *name = ignore_environment ? NULL : getenv("LUA_READLINELIB");
    void *library;
    void *symbol;
    const char **application_name;
    if (name == NULL) name = "libreadline.so";
    library = dlopen(name, RTLD_NOW | RTLD_LOCAL);
    read_line = NULL;
    save_line = NULL;
    if (library != NULL) {
        application_name = (const char **)dlsym(library, "rl_readline_name");
        if (application_name != NULL) *application_name = "lua";
        /* POSIX specifies dlsym's function-pointer conversion. Copy its
         * representation without the ISO-C object/function cast warning. */
        symbol = dlsym(library, "readline");
        memcpy(&read_line, &symbol, sizeof(read_line));
        symbol = dlsym(library, "add_history");
        memcpy(&save_line, &symbol, sizeof(save_line));
        if (read_line != NULL) return NULL;
    }
    return name;
#elif defined(LUA_ADA_CLI_MACOS)
    (void)ignore_environment;
    rl_readline_name = "lua";
    read_line = readline;
    save_line = add_history;
    return NULL;
#else
    (void)ignore_environment;
    return NULL;
#endif
}

int lua_ada_cli_initreadline(lua_State *L) {
    const char *failed = initialize_readline(lua_toboolean(L, 1));
    if (failed != NULL) {
        lua_warning(L, "unable to load readline library '", 1);
        lua_warning(L, failed, 1);
        lua_warning(L, "'", 0);
    }
    return 0;
}

char *lua_ada_cli_readline(const char *prompt) {
    if (read_line != NULL) return read_line(prompt);
    fputs(prompt, stdout);
    fflush(stdout);
    return fgets(fallback, sizeof(fallback), stdin);
}

size_t lua_ada_cli_line_length(const char *line) { return strlen(line); }

void lua_ada_cli_freeline(char *line) {
    if (read_line != NULL) free(line);
}

void lua_ada_cli_saveline(const char *line) {
    if (save_line != NULL && line[0] != '\0') save_line(line);
}

int lua_ada_cli_has_history(void) { return save_line != NULL; }

#if defined(LUA_ADA_TEST_BUILD_PROFILE)
/* Test-crate transport injection, absent from the product CLI and runtime
 * library. It observes the actual selected-owner buffer's synchronous borrow
 * and exercises refusal without depending on an optional host installation. */
static save_line_function saved_history;
void lua_ada_cli_test_history(save_line_function observer) {
    saved_history = save_line;
    save_line = observer;
}
void lua_ada_cli_test_restore_history(void) { save_line = saved_history; }
#endif
