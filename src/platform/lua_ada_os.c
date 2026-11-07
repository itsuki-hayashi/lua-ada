/* OS/time mechanics for Ada's standard library. This unit knows no Lua
 * values, stacks, source, callbacks or library option grammar. The small tm
 * carrier transfers only public fields; it does not reproduce native layout.
 */
#if !defined(_WIN32)
#define _POSIX_C_SOURCE 200809L
#endif

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#if !defined(_WIN32)
#include <sys/wait.h>
#include <unistd.h>
#endif

struct lua_ada_broken_down_time {
    int second, minute, hour, day, month, year, weekday, yearday, daylight;
};

static void copy_from_tm(struct lua_ada_broken_down_time *out,
                         const struct tm *in) {
    out->second = in->tm_sec;
    out->minute = in->tm_min;
    out->hour = in->tm_hour;
    out->day = in->tm_mday;
    out->month = in->tm_mon;
    out->year = in->tm_year;
    out->weekday = in->tm_wday;
    out->yearday = in->tm_yday;
    out->daylight = in->tm_isdst;
}

static void copy_to_tm(struct tm *out,
                       const struct lua_ada_broken_down_time *in) {
    /* Initialize platform extensions, such as tm_gmtoff/tm_zone, without
     * ever naming or assuming their presence in the public Ada carrier. */
    memset(out, 0, sizeof *out);
    out->tm_sec = in->second;
    out->tm_min = in->minute;
    out->tm_hour = in->hour;
    out->tm_mday = in->day;
    out->tm_mon = in->month;
    out->tm_year = in->year;
    out->tm_wday = in->weekday;
    out->tm_yday = in->yearday;
    out->tm_isdst = in->daylight;
}

double lua_ada_os_clock(void) {
    return (double)clock() / (double)CLOCKS_PER_SEC;
}

int lua_ada_os_execute(const char *command, int *error) {
    int status;
    errno = 0;
    status = system(command);
    *error = errno;
    return status;
}

int lua_ada_os_exit_success(void) { return EXIT_SUCCESS; }
int lua_ada_os_exit_failure(void) { return EXIT_FAILURE; }
void lua_ada_os_exit(int code) { exit(code); }

void lua_ada_os_status(int status, int *code, int *signaled) {
    *code = status;
    *signaled = 0;
#if !defined(_WIN32)
    if (WIFEXITED(status)) {
        *code = WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        *code = WTERMSIG(status);
        *signaled = 1;
    }
#endif
}

int lua_ada_os_remove(const char *name, int *error) {
    int status;
    errno = 0;
    status = remove(name);
    *error = errno;
    return status;
}

int lua_ada_os_rename(const char *old_name, const char *new_name, int *error) {
    int status;
    errno = 0;
    status = rename(old_name, new_name);
    *error = errno;
    return status;
}

size_t lua_ada_os_tmpname_size(void) {
#if defined(_WIN32)
    return L_tmpnam;
#else
    return sizeof "/tmp/lua_XXXXXX";
#endif
}

int lua_ada_os_tmpname(char *bytes, int *error) {
    int status;
    errno = 0;
#if defined(_WIN32)
    status = tmpnam(bytes) == NULL;
#else
    int descriptor;
    memcpy(bytes, "/tmp/lua_XXXXXX", sizeof "/tmp/lua_XXXXXX");
    descriptor = mkstemp(bytes);
    status = descriptor == -1;
    if (descriptor != -1) (void)close(descriptor);
#endif
    *error = errno;
    return status;
}

long long lua_ada_os_time(int *valid) {
    time_t value = time(NULL);
    *valid = value != (time_t)-1;
    return (long long)value;
}

int lua_ada_os_time_range(long long stamp) {
    time_t value = (time_t)stamp;
    return (long long)value == stamp;
}

int lua_ada_os_calendar(long long stamp, int universal,
                         struct lua_ada_broken_down_time *result) {
    time_t value = (time_t)stamp;
    struct tm *date;
#if !defined(_WIN32)
    struct tm storage;
#endif
    if ((long long)value != stamp) return 0;
#if defined(_WIN32)
    date = universal ? gmtime(&value) : localtime(&value);
#else
    date = universal ? gmtime_r(&value, &storage) : localtime_r(&value, &storage);
#endif
    if (date == NULL) return 0;
    copy_from_tm(result, date);
    return 1;
}

long long lua_ada_os_normalize(struct lua_ada_broken_down_time *date,
                              int *valid) {
    struct tm native;
    time_t value;
    copy_to_tm(&native, date);
    value = mktime(&native);
    copy_from_tm(date, &native);
    *valid = value != (time_t)-1 && (time_t)(long long)value == value;
    return (long long)value;
}

double lua_ada_os_difftime(long long left, long long right) {
    return difftime((time_t)left, (time_t)right);
}

size_t lua_ada_os_strftime(char *bytes, size_t capacity, const char *format,
                          long long stamp, int universal) {
    time_t value = (time_t)stamp;
    struct tm *date;
#if !defined(_WIN32)
    struct tm storage;
#endif
    /* The nine public fields are sufficient for Lua's *t carrier, but not
     * for strftime: native tm extensions retain timezone offsets/names.
     * Recompute from the unchanged timestamp instead of assuming a private
     * struct layout or incorrectly formatting local timestamps as UTC. */
    if ((long long)value != stamp) return 0;
#if defined(_WIN32)
    date = universal ? gmtime(&value) : localtime(&value);
#else
    date = universal ? gmtime_r(&value, &storage) : localtime_r(&value, &storage);
#endif
    if (date == NULL) return 0;
    return strftime(bytes, capacity, format, date);
}
