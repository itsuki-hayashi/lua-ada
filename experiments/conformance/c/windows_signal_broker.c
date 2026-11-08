/* Test-only Windows console broker. It never links Lua or interprets Lua
 * source: the selected UTF-8 file is an opaque -e argument to the real child.
 * Each invocation owns exactly one child, two output pipes and one console
 * attachment. Ctrl-C is allowed only after checking that the attached console
 * contains precisely this broker and the child we just created. */
#define _WIN32_WINNT 0x0601
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#define SOURCE_LIMIT 4096
#define STREAM_LIMIT 1048576
#define CHILD_DEADLINE_MS 25000
#define DRAIN_DEADLINE_MS 1000
#define REQUEST_LIMIT 100
/* A different nonzero status (for example an access violation) is not
 * evidence of Ctrl-C termination, even after successful delivery requests. */
#define EXPECTED_CONTROL_C_EXIT ((DWORD)0xC000013AUL)

typedef struct {
    HANDLE pipe;
    FILE *file;
    unsigned long bytes;
    char prefix[16];
    size_t prefix_size;
    int closed;
} capture;

static FILE *events;
static ULONGLONG started;
static DWORD child_pid;
static int cleanup_ok = 1;
static unsigned long closed_handles;

static void event(const char *name, int ok, DWORD error, ULONGLONG value) {
    fprintf(events,
            "{\"event\":\"%s\",\"elapsed_ms\":%llu,\"broker_pid\":%lu,"
            "\"child_pid\":%lu,\"ok\":%s,\"win32_error\":%lu,\"value\":%llu}\n",
            name, (unsigned long long)(GetTickCount64() - started),
            (unsigned long)GetCurrentProcessId(), (unsigned long)child_pid,
            ok ? "true" : "false", (unsigned long)error,
            (unsigned long long)value);
    fflush(events);
}

static void close_handle(HANDLE *handle) {
    if (*handle != NULL && *handle != INVALID_HANDLE_VALUE) {
        if (!CloseHandle(*handle)) {
            cleanup_ok = 0;
            event("close-owned-handle-failed", 0, GetLastError(), 0);
        } else {
            closed_handles++;
        }
        *handle = NULL;
    }
}

/* Peek before reading keeps both streams progressing without a blocked read
 * thread. Capture is bounded independently of child behavior; overflow makes
 * the probe fail and its subsequent process termination is cleanup only. */
static int drain(capture *stream) {
    DWORD available, count;
    char buffer[4096];
    size_t keep;
    if (stream->closed) return 1;
    if (!PeekNamedPipe(stream->pipe, NULL, 0, NULL, &available, NULL)) {
        DWORD error = GetLastError();
        if (error == ERROR_BROKEN_PIPE) {
            stream->closed = 1;
            close_handle(&stream->pipe);
            return 1;
        }
        event("peek-pipe", 0, error, 0);
        return 0;
    }
    if (available == 0) return 1;
    if (available > sizeof(buffer)) available = sizeof(buffer);
    if (!ReadFile(stream->pipe, buffer, available, &count, NULL)) {
        event("read-pipe", 0, GetLastError(), 0);
        return 0;
    }
    if (count > STREAM_LIMIT - stream->bytes) {
        event("capture-limit", 0, 0, stream->bytes + count);
        return 0;
    }
    if (fwrite(buffer, 1, count, stream->file) != count) {
        event("write-capture", 0, 0, count);
        return 0;
    }
    fflush(stream->file);
    keep = sizeof(stream->prefix) - stream->prefix_size;
    if (keep > count) keep = count;
    memcpy(stream->prefix + stream->prefix_size, buffer, keep);
    stream->prefix_size += keep;
    stream->bytes += count;
    return 1;
}

/* Windows CRT argument quoting is transport, not a shell grammar. No shell
 * is invoked. Backslashes preceding quotes or the final quote are doubled;
 * ordinary backslashes and every source character otherwise retain identity. */
static int append_quoted(wchar_t *out, size_t *used, const wchar_t *value) {
    size_t slashes = 0, i;
#define PUT(c) do { if (*used >= 32766) return 0; out[(*used)++] = (c); } while (0)
    PUT(L'"');
    for (;;) {
        if (*value == L'\\') { slashes++; value++; continue; }
        if (*value == L'"' || *value == L'\0') {
            for (i = 0; i < slashes * 2; i++) PUT(L'\\');
            if (*value == L'\0') break;
            PUT(L'\\');
        } else {
            for (i = 0; i < slashes; i++) PUT(L'\\');
        }
        slashes = 0;
        PUT(*value++);
    }
    PUT(L'"');
    out[*used] = L'\0';
#undef PUT
    return 1;
}

static int source_argument(const wchar_t *path, wchar_t *source) {
    char bytes[SOURCE_LIMIT + 1];
    HANDLE input = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL,
                               OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    DWORD count;
    int length;
    LARGE_INTEGER size;
    if (input == INVALID_HANDLE_VALUE) return 0;
    if (!GetFileSizeEx(input, &size) || size.QuadPart <= 0 ||
        size.QuadPart > SOURCE_LIMIT ||
        !ReadFile(input, bytes, (DWORD)size.QuadPart, &count, NULL) ||
        count != (DWORD)size.QuadPart) {
        close_handle(&input);
        return 0;
    }
    close_handle(&input);
    if (!cleanup_ok) return 0;
    if (memchr(bytes, '\0', count) != NULL) return 0;
    length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, bytes,
                                (int)count, source, SOURCE_LIMIT);
    if (length == 0) return 0;
    source[length] = L'\0';
    return 1;
}

/* CTRL_C_EVENT group zero broadcasts within the attached console. Never use
 * it in an inherited console. Recheck the complete, bounded process list
 * before every request, not only when the attachment was first established. */
static int isolated_console(void) {
    DWORD ids[8], count, i;
    int own = 0, child = 0;
    count = GetConsoleProcessList(ids, 8);
    if (count != 2) {
        event("console-membership", 0, count == 0 ? GetLastError() : 0, count);
        return 0;
    }
    for (i = 0; i < count; i++) {
        if (ids[i] == GetCurrentProcessId()) own++;
        if (ids[i] == child_pid) child++;
        event("console-member", 1, 0, ids[i]);
    }
    event("console-membership", own == 1 && child == 1, 0, count);
    return own == 1 && child == 1;
}

int wmain(int argc, wchar_t **argv) {
    SECURITY_ATTRIBUTES security = {sizeof(SECURITY_ATTRIBUTES), NULL, TRUE};
    STARTUPINFOEXW startup;
    PROCESS_INFORMATION process;
    HANDLE out_write = NULL, err_write = NULL, in_read = NULL, in_write = NULL;
    HANDLE inherited[3];
    SIZE_T attribute_bytes = 0;
    capture output = {0}, errors = {0};
    wchar_t command[32768], source[SOURCE_LIMIT + 1];
    size_t used = 0;
    DWORD status = STILL_ACTIVE, result, request_error, attach_error;
    ULONGLONG ready_at = 0, sent_at = 0, exited_at = 0;
    int search, ready = 0, requests = 0, attached = 0, success = 0, forced = 0;
    int created = 0, attributes_ready = 0;
    const char *expected;

    if (argc != 8) return 2;
    search = wcscmp(argv[7], L"search") == 0;
    if (!search && wcscmp(argv[7], L"protected") != 0) return 2;
    events = _wfopen(argv[6], L"wb");
    if (events == NULL) return 2;
    started = GetTickCount64();
    memset(&startup, 0, sizeof(startup));
    memset(&process, 0, sizeof(process));
    startup.StartupInfo.cb = sizeof(startup);
    output.file = _wfopen(argv[4], L"wb");
    errors.file = _wfopen(argv[5], L"wb");
    if (output.file == NULL || errors.file == NULL ||
        !source_argument(argv[2], source) ||
        !append_quoted(command, &used, argv[1])) {
        event("prepare-input", 0, GetLastError(), 0);
        goto cleanup;
    }
    if (used + 4 >= 32766) goto cleanup;
    memcpy(command + used, L" -e ", 4 * sizeof(wchar_t));
    used += 4;
    if (!append_quoted(command, &used, source)) goto cleanup;
    if (!CreatePipe(&output.pipe, &out_write, &security, 0) ||
        !CreatePipe(&errors.pipe, &err_write, &security, 0) ||
        !CreatePipe(&in_read, &in_write, &security, 0) ||
        !SetHandleInformation(output.pipe, HANDLE_FLAG_INHERIT, 0) ||
        !SetHandleInformation(errors.pipe, HANDLE_FLAG_INHERIT, 0) ||
        !SetHandleInformation(in_write, HANDLE_FLAG_INHERIT, 0)) {
        event("create-pipes", 0, GetLastError(), 0);
        goto cleanup;
    }
    inherited[0] = in_read;
    inherited[1] = out_write;
    inherited[2] = err_write;
    InitializeProcThreadAttributeList(NULL, 1, 0, &attribute_bytes);
    if (attribute_bytes == 0 || attribute_bytes > 65536) goto cleanup;
    startup.lpAttributeList = HeapAlloc(GetProcessHeap(), 0, attribute_bytes);
    if (startup.lpAttributeList == NULL ||
        !InitializeProcThreadAttributeList(startup.lpAttributeList, 1, 0,
                                           &attribute_bytes)) {
        event("create-attribute-list", 0, GetLastError(), 0);
        goto cleanup;
    }
    attributes_ready = 1;
    if (!UpdateProcThreadAttribute(startup.lpAttributeList, 0,
            PROC_THREAD_ATTRIBUTE_HANDLE_LIST, inherited, sizeof(inherited),
            NULL, NULL)) {
        event("inherit-pipe-list", 0, GetLastError(), 0);
        goto cleanup;
    }
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    startup.StartupInfo.wShowWindow = SW_HIDE;
    startup.StartupInfo.hStdInput = in_read;
    startup.StartupInfo.hStdOutput = out_write;
    startup.StartupInfo.hStdError = err_write;
    if (!CreateProcessW(argv[1], command, NULL, NULL, TRUE,
            CREATE_NEW_CONSOLE | EXTENDED_STARTUPINFO_PRESENT, NULL, argv[3],
            &startup.StartupInfo, &process)) {
        event("create-child", 0, GetLastError(), 0);
        goto cleanup;
    }
    created = 1;
    child_pid = process.dwProcessId;
    event("create-child-new-console-hidden", 1, 0, child_pid);
    close_handle(&process.hThread);
    close_handle(&in_read);
    close_handle(&in_write);  /* real EOF; -e does not read input */
    close_handle(&out_write);
    close_handle(&err_write);

    /* Only this subprocess detaches. Its parent is never attached/detached
     * or signalled. The new child console exists independently of stdio. */
    result = FreeConsole();
    attach_error = result ? 0 : GetLastError();
    event("detach-broker", result != 0, attach_error, 0);
    if (!result && attach_error != ERROR_INVALID_HANDLE) goto cleanup;
    expected = search ? "15\r\n" : "12\r\n";
    while (GetTickCount64() - started < CHILD_DEADLINE_MS) {
        if (!drain(&output) || !drain(&errors)) goto cleanup;
        result = WaitForSingleObject(process.hProcess, 0);
        if (result == WAIT_OBJECT_0) {
            if (exited_at == 0) {
                exited_at = GetTickCount64();
                if (!GetExitCodeProcess(process.hProcess, &status)) goto cleanup;
                event("child-exited", 1, 0, status);
            }
            if (output.closed && errors.closed) break;
            if (GetTickCount64() - exited_at > DRAIN_DEADLINE_MS) {
                event("pipe-drain-deadline", 0, 0, 0);
                goto cleanup;
            }
        } else if (result != WAIT_TIMEOUT) {
            event("wait-child", 0, GetLastError(), result);
            goto cleanup;
        }
        if (!ready && output.prefix_size >= 4) {
            if (memcmp(output.prefix, expected, 4) != 0) {
                event("wrong-readiness", 0, 0, output.prefix_size);
                goto cleanup;
            }
            ready = 1;
            ready_at = GetTickCount64();
            event("actual-stdout-readiness", 1, 0, search ? 15 : 12);

            /* CreateProcess can return before the child's console is ready.
             * The first failed observation attempted attachment at 0 ms.
             * First require actual workload output, then retry only the
             * documented no-console error for at most two seconds. Every
             * attempt and liveness result is retained; all other errors fail.
             * No console attachment or event targets the broker's parent. */
            while (!attached) {
                if (WaitForSingleObject(process.hProcess, 0) != WAIT_TIMEOUT) {
                    event("child-not-alive-before-attach", 0, 0, 0);
                    goto cleanup;
                }
                result = AttachConsole(child_pid);
                attach_error = result ? 0 : GetLastError();
                event("attach-child-console-attempt", result != 0,
                      attach_error, GetTickCount64() - ready_at);
                if (result) {
                    attached = 1;
                } else if (attach_error != ERROR_INVALID_HANDLE ||
                           GetTickCount64() - ready_at >= 2000) {
                    goto cleanup;
                } else {
                    if (!drain(&output) || !drain(&errors)) goto cleanup;
                    Sleep(10);
                }
            }
            if (!SetConsoleCtrlHandler(NULL, TRUE) || !isolated_console()) {
                event("guard-broker-console", 0, GetLastError(), 0);
                goto cleanup;
            }
            event("attach-isolated-child-console", 1, 0, child_pid);
        }
        if (exited_at == 0 && ready && requests < REQUEST_LIMIT &&
            ((!search && requests == 0) ||
             (search && GetTickCount64() - ready_at >= 1000 &&
              (requests == 0 || GetTickCount64() - sent_at >= 100)))) {
            if (!isolated_console()) goto cleanup;
            result = GenerateConsoleCtrlEvent(CTRL_C_EVENT, 0);
            request_error = result ? 0 : GetLastError();
            event("request-real-ctrl-c-group-zero", result != 0,
                  request_error, (ULONGLONG)(requests + 1));
            if (!result) goto cleanup;
            requests++;
            sent_at = GetTickCount64();
        }
        Sleep(5);
    }
    if (exited_at == 0 || !output.closed || !errors.closed) {
        event("child-deadline", 0, 0, CHILD_DEADLINE_MS);
        goto cleanup;
    }
    if (search) {
        success = ready && requests >= 2 && status == EXPECTED_CONTROL_C_EXIT &&
                  output.bytes == 4 && errors.bytes == 0;
    } else {
        success = ready && requests == 1 && status == 0 && errors.bytes == 0 &&
                  output.bytes == 8 && memcmp(output.prefix, "12\r\n42\r\n", 8) == 0;
    }

cleanup:
    /* Termination here never produces a passing result. It only prevents a
     * failed probe from leaving an infinite loop or native search behind. */
    if (created && WaitForSingleObject(process.hProcess, 0) == WAIT_TIMEOUT) {
        forced = 1;
        success = 0;
        result = TerminateProcess(process.hProcess, 125);
        event("failed-probe-timeout-cleanup-only", result != 0,
              result ? 0 : GetLastError(), 125);
        result = WaitForSingleObject(process.hProcess, 2000);
        event("cleanup-child-wait", result == WAIT_OBJECT_0,
              result == WAIT_FAILED ? GetLastError() : 0, result);
    }
    if (attached && !FreeConsole()) {
        cleanup_ok = 0;
        event("detach-child-console-failed", 0, GetLastError(), 0);
    }
    close_handle(&process.hThread);
    close_handle(&process.hProcess);
    close_handle(&out_write);
    close_handle(&err_write);
    close_handle(&in_read);
    close_handle(&in_write);
    close_handle(&output.pipe);
    close_handle(&errors.pipe);
    if (attributes_ready) DeleteProcThreadAttributeList(startup.lpAttributeList);
    if (startup.lpAttributeList != NULL &&
        !HeapFree(GetProcessHeap(), 0, startup.lpAttributeList)) {
        cleanup_ok = 0;
        event("free-attribute-storage-failed", 0, GetLastError(), 0);
    }
    if (output.file != NULL && fclose(output.file) != 0) success = 0;
    if (errors.file != NULL && fclose(errors.file) != 0) success = 0;
    event("cleanup-complete", cleanup_ok, 0, closed_handles);
    if (!cleanup_ok || ferror(events)) success = 0;
    event("final-result", success && !forced, 0, requests);
    if (fclose(events) != 0) success = 0;
    return success && !forced ? 0 : 1;
}
