/* Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE.
 * These wrappers contain ABI/startup/nonlocal-transfer mechanics only. Every
 * stack/value operation executes in Ada and returns an explicit action before
 * C raises it. No reference interpreter object is linked into this library. */
#include "lua_ada_boundary.h"
#include "lauxlib.h"
#include "lualib.h"
#include <setjmp.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void luainit(void);

/* lua.h declares this metadata without LUA_API. Explicitly retain its data
 * export in a Windows DLL, where exporting functions disables auto-export. */
#if defined(LUA_BUILD_AS_DLL)
LUA_API
#endif
const char lua_ident[] =
    "$LuaVersion: " LUA_COPYRIGHT " $"
    "$LuaAuthors: " LUA_AUTHORS " $";

struct lua_ada_guard {
    jmp_buf target;
    struct lua_ada_guard *previous;
    volatile int error_handled;
    volatile int self_closing;
    struct lua_ada_callback_identity callback_token;
};

size_t lua_ada_surface_size(void) { return sizeof(lua_State); }
size_t lua_ada_request_size(void) { return sizeof(struct lua_ada_request); }
size_t lua_ada_response_size(void) { return sizeof(struct lua_ada_response); }
size_t lua_ada_extra_space(void) { return LUA_EXTRASPACE; }

static void initialize(void) {
    /* GNAT's standalone binder entry is idempotent. Calling it from the C
     * constructor entrypoints also pulls the binder object out of a static
     * archive, so a plain C main needs no adainit/binder knowledge. Shared
     * libraries additionally retain GNAT's automatic loader initialization. */
    luainit();
    if (ada_lua_contract(0) != sizeof(struct lua_ada_request) ||
        ada_lua_contract(1) != sizeof(struct lua_ada_response) ||
        ada_lua_contract(2) != sizeof(lua_State) ||
        ada_lua_contract(3) != sizeof(struct lua_ada_debug_information)) {
        fprintf(stderr,
                "Lua Ada: incompatible C dispatch layout: "
                "request C=%zu Ada=%zu; response C=%zu Ada=%zu; "
                "surface C=%zu Ada=%zu\n",
                sizeof(struct lua_ada_request), ada_lua_contract(0),
                sizeof(struct lua_ada_response), ada_lua_contract(1),
                sizeof(lua_State), ada_lua_contract(2));
        abort();
    }
}

static struct lua_ada_request request(enum lua_ada_operation operation) {
    struct lua_ada_request input;
    memset(&input, 0, sizeof input);
    input.operation = operation;
    return input;
}

static void raise_action(lua_State *state, int status,
                         const struct lua_ada_response *output) {
    /* This function is reached only after ada_lua_dispatch has returned.
     * Its checkpoint belongs to C; no abandoned Ada activation is retained. */
    if (status == LUA_OK) return;
    if (status == ADA_ACTION_SELF_CLOSE && state != NULL) {
        struct lua_ada_guard *item;
        /* Mark the live C chain before unwinding its nearest checkpoint.
         * Each parser/writer/formatter guard still runs its own cleanup;
         * jumping directly to the oldest guard could cross waiting Ada. */
        for (item = state->guard; item != NULL; item = item->previous)
            item->self_closing = 1;
    }
    if (state != NULL && state->guard != NULL) {
        state->guard->error_handled = output->error_handled;
        longjmp(state->guard->target, status);
    }
    if (status != ADA_ACTION_ABORT) {
        if (state != NULL && state->main->panic != NULL)
            state->main->panic(state);
        /* A returning (or absent) panic handler completes the public policy.
         * Abort here without inventing a second diagnostic. */
        abort();
    }
    fputs("Lua Ada: unprotected error", stderr);
    fputc('\n', stderr);
    abort();
}

static int self_close_pending(lua_State *state) {
    struct lua_ada_guard *item;
    if (state == NULL) return 0;
    for (item = state->guard; item != NULL; item = item->previous)
        if (item->self_closing) return 1;
    return 0;
}

static int dispatch_raw(lua_State *state,
                         const struct lua_ada_request *input,
                         struct lua_ada_response *output) {
    int action = ada_lua_dispatch(state, input, output);
    /* Completed API results remain on the real stack while release
     * callbacks reenter Lua. Keep every original scalar/status/token field
     * intact; the drainer uses independent transport records. Close frees
     * this surface itself and therefore drains in its pre-teardown phase. */
    if (state && input->operation != ADA_CLOSE_STATE &&
        !self_close_pending(state) &&
        input->operation != ADA_PREPARE_EXTERNAL_RELEASE &&
        input->operation != ADA_COMPLETE_EXTERNAL_RELEASE &&
        action != ADA_ACTION_CALL && action != ADA_ACTION_WARNING &&
        action != ADA_ACTION_EXTERNAL_RELEASE && action != ADA_ACTION_SUSPEND &&
        action != ADA_ACTION_SELF_CLOSE)
        lua_ada_drain_external_releases(state);
    return action;
}

static struct lua_ada_response dispatch(lua_State *state,
                                        struct lua_ada_request input) {
    struct lua_ada_response output;
    int status = dispatch_raw(state, &input, &output);
    raise_action(state, status, &output);
    return output;
}

int lua_ada_debug_dispatch(lua_State *state,
                           const struct lua_ada_request *input,
                           struct lua_ada_response *output) {
    int status = dispatch_raw(state, input, output);
    raise_action(state, status, output);
    return status;
}

int lua_ada_guard_probe(lua_State *state, lua_CFunction body) {
    struct lua_ada_guard guard = {0};
    int status;
    guard.previous = state->guard;
    guard.error_handled = 0;
    memset(&guard.callback_token, 0, sizeof guard.callback_token);
    state->guard = &guard;
    status = setjmp(guard.target);
    if (status == 0) body(state);
    state->guard = guard.previous;
    if (status == ADA_ACTION_ABORT || status == ADA_ACTION_SELF_CLOSE) {
        struct lua_ada_response output;
        memset(&output, 0, sizeof output);
        raise_action(state, status, &output);
    }
    return status;
}

int lua_ada_run_protected(lua_State *state,
                         void (*body)(lua_State *, void *), void *data) {
    struct lua_ada_guard guard = {0};
    int status;
    guard.previous = state->guard;
    guard.error_handled = 0;
    memset(&guard.callback_token, 0, sizeof guard.callback_token);
    state->guard = &guard;
    /* An ABI helper can catch a refusal without adding a Lua call frame.
     * Its caller owns data and must release temporary storage on every
     * status before forwarding a host abort to the surrounding C guard. */
    status = setjmp(guard.target);
    if (status == LUA_OK) body(state, data);
    state->guard = guard.previous;
    return status;
}

void lua_ada_propagate_status(lua_State *state, int status) {
    struct lua_ada_response output;
    memset(&output, 0, sizeof output);
    raise_action(state, status, &output);
}

int lua_ada_invoke_borrowed(lua_State *state, enum lua_ada_action action,
                            const struct lua_ada_response *pending,
                            struct lua_ada_response *completion) {
    struct lua_ada_guard guard = {0};
    int status;
    volatile int count = 0;
    memset(completion, 0, sizeof *completion);
    guard.previous = state->guard;
    guard.error_handled = 0;
    guard.callback_token = pending->callback_token;
    state->guard = &guard;
    /* The waiting Ada host frame is below this live C checkpoint. Every
     * longjmp targets C frames above that host; none crosses an active Ada
     * dispatcher, scheduler step or value operation. */
    status = setjmp(guard.target);
    if (status == 0) {
        if (action == ADA_ACTION_EXTERNAL_RELEASE)
            pending->allocator(pending->warning_data,
                (void *)pending->warning_message, pending->length, 0);
        else if (action == ADA_ACTION_WARNING)
            pending->warning_function(pending->warning_data,
                pending->warning_message, pending->warning_continuation);
        else if (pending->continuation != NULL)
            count = pending->continuation(state, pending->kstatus,
                                           pending->kcontext);
        else count = pending->function_data(state);
    }
    state->guard = guard.previous;
    completion->integer_data = count;
    completion->error_handled = guard.error_handled;
    completion->callback_token = guard.callback_token;
    return status;
}

void lua_ada_drain_external_releases(lua_State *state) {
    struct lua_ada_request input = request(ADA_PREPARE_EXTERNAL_RELEASE);
    struct lua_ada_response pending, completion, output;
    int action;
    /* No header/array allocation is needed to free one payload. Detached
     * headers themselves retain the FIFO/LIFO ownership and stack borrow;
     * this guard owns only the live nonlocal-transfer checkpoint. */
    while ((action = ada_lua_dispatch(state, &input, &pending)) ==
           ADA_ACTION_EXTERNAL_RELEASE) {
        int status = lua_ada_invoke_borrowed(state,
            ADA_ACTION_EXTERNAL_RELEASE, &pending, &completion);
        struct lua_ada_request done = request(ADA_COMPLETE_EXTERNAL_RELEASE);
        done.index = status;
        done.callback_token = pending.callback_token;
        done.error_index = state->guard == NULL;
        action = ada_lua_dispatch(state, &done, &output);
        raise_action(state, action, &output);
    }
    raise_action(state, action, &pending);
}

static int pump_callbacks(int action, struct lua_ada_response *pending) {
    struct lua_ada_request input;
    struct lua_ada_response output = *pending;
    while (action == ADA_ACTION_CALL || action == ADA_ACTION_WARNING ||
           action == ADA_ACTION_EXTERNAL_RELEASE) {
        lua_State *callback_state = (lua_State *)output.pointer;
        lua_CFunction callback = output.function_data;
        lua_KFunction pending_k = output.continuation;
        lua_KContext pending_context = output.kcontext;
        int pending_status = output.kstatus;
        lua_WarnFunction warning = output.warning_function;
        int is_warning = action == ADA_ACTION_WARNING;
        int is_release = action == ADA_ACTION_EXTERNAL_RELEASE;
        lua_Alloc allocator = output.allocator;
        size_t release_size = output.length;
        void *warning_data = output.warning_data;
        const char *warning_message = output.warning_message;
        int warning_continuation = output.warning_continuation;
        struct lua_ada_guard guard = {0};
        int status;
        volatile int count = 0;
        /* Every Ada scheduler activation has returned before this checkpoint
         * is installed. A callback may reenter the API and request nested Lua
         * work, but each such call schedules an explicit boundary on the same
         * driver. Only these live C frames are unwound by a callback error. */
        guard.previous = callback_state->guard;
        guard.error_handled = 0;
        guard.callback_token = output.callback_token;
        callback_state->guard = &guard;
        status = setjmp(guard.target);
        if (status == 0) {
            if (is_release)
                allocator(warning_data, (void *)warning_message,
                          release_size, 0);
            else if (is_warning)
                warning(warning_data, warning_message, warning_continuation);
            else if (pending_k != NULL)
                count = pending_k(callback_state, pending_status,
                                  pending_context);
            else count = callback(callback_state);
        }
        callback_state->guard = guard.previous;
        if (status == ADA_ACTION_ABORT && !is_release) {
            /* Host abort is not a protected Lua error. Abandon each live C
             * body until the outer borrowed invoke returns it to Ada; a
             * C-owned outer boundary retains its ordinary abort behavior. */
            raise_action(callback_state, status, &output);
        }
        input = request(is_release ? ADA_COMPLETE_EXTERNAL_RELEASE :
                        is_warning ? ADA_COMPLETE_WARNING :
                        status == ADA_ACTION_SELF_CLOSE ? ADA_COMPLETE_SELF_CLOSE :
                                     ADA_COMPLETE_CALLBACK);
        input.index = status;
        input.count = is_release ? 1 : count;
        input.error_handled = guard.error_handled;
        input.callback_token = guard.callback_token;
        input.error_index = guard.previous == NULL;
        action = dispatch_raw(callback_state, &input, &output);
    }
    *pending = output;
    return action;
}

static int drive_call(lua_State *state, int arguments, int results,
                      int protected_call, int error_function,
                      lua_KContext context, lua_KFunction continuation) {
    struct lua_ada_request input = request(ADA_BEGIN_CALL);
    struct lua_ada_response output;
    int action;
    int function_slot = lua_gettop(state) - arguments;
    input.index = arguments;
    input.count = results;
    input.integer_data = protected_call;
    input.error_index = error_function;
    input.continuation = continuation;
    input.kcontext = context;
    if (state->guard != NULL)
        input.callback_token = state->guard->callback_token;
    action = dispatch_raw(state, &input, &output);
    action = pump_callbacks(action, &output);
    if (protected_call &&
        (action == ADA_ACTION_RAISE || action == ADA_ACTION_MEMORY ||
         action == ADA_ACTION_HANDLING)) {
        /* Setup failure may precede a scheduler boundary (for example driver
         * allocation refusal). Preserve its real error object while dropping
         * the unconsumed callee/arguments, as a protected call must do. */
        lua_copy(state, -1, function_slot);
        lua_settop(state, function_slot);
        return action;
    }
    raise_action(state, action, &output);
    return (int)output.integer_data;
}

static int close_io_primitive(lua_State *state, int kind) {
    struct lua_ada_request input = request(ADA_CLOSE_IO_PRIMITIVE);
    input.count = kind;
    return (int)dispatch(state, input).integer_data;
}

static int builtin_continuation(lua_State *state, int status,
                                 lua_KContext prefix) {
    (void)status;
    /* The VM owns the suspended builtin phase. Its boundary has appended
     * resumed results above the original C argument prefix before requesting
     * this real K callback; returning its tail completes that C activation. */
    return lua_gettop(state) - (int)prefix;
}

int lua_ada_invoke_builtin(lua_State *state, int id) {
    struct lua_ada_request input = request(ADA_BEGIN_BUILTIN);
    struct lua_ada_response output;
    int action;
    input.index = id;
    input.count = LUA_MULTRET;
    input.continuation = builtin_continuation;
    input.kcontext = lua_gettop(state);
    if (state->guard != NULL)
        input.callback_token = state->guard->callback_token;
    action = dispatch_raw(state, &input, &output);
    action = pump_callbacks(action, &output);
    raise_action(state, action, &output);
    return (int)output.length;
}

/* These addresses are real callable lua_CFunction values stored in the public
 * luaL_Stream payload. Lua close validation/results stay Ada-owned; direct C
 * closef invocation deliberately creates no extra interpreter/debug frame. */
int lua_ada_io_close_regular(lua_State *state) {
    return close_io_primitive(state, 0);
}
int lua_ada_io_close_pipe(lua_State *state) {
    return close_io_primitive(state, 1);
}
int lua_ada_io_close_borrowed(lua_State *state) {
    return close_io_primitive(state, 2);
}

void lua_pushcclosure(lua_State *state, lua_CFunction function, int upvalues) {
    struct lua_ada_request input = request(ADA_PUSH_C_CLOSURE);
    input.function_data = function;
    input.count = upvalues;
    dispatch(state, input);
}

lua_CFunction lua_tocfunction(lua_State *state, int index) {
    struct lua_ada_request input = request(ADA_TO_C_FUNCTION);
    input.index = index;
    return dispatch(state, input).function_data;
}

int lua_iscfunction(lua_State *state, int index) {
    return lua_tocfunction(state, index) != NULL;
}

void lua_callk(lua_State *state, int arguments, int results,
               lua_KContext context, lua_KFunction continuation) {
    (void)drive_call(state, arguments, results, 0, 0, context,
                     lua_isyieldable(state) ? continuation : NULL);
}

int lua_pcallk(lua_State *state, int arguments, int results, int error_function,
               lua_KContext context, lua_KFunction continuation) {
    return drive_call(state, arguments, results, 1,
                      error_function == 0 ? 0 :
                      lua_absindex(state, error_function), context,
                      lua_isyieldable(state) ? continuation : NULL);
}

int lua_yieldk(lua_State *state, int results, lua_KContext context,
                lua_KFunction continuation) {
    struct lua_ada_request input = request(ADA_YIELD_CALL);
    input.count = results;
    input.continuation = continuation;
    input.kcontext = context;
    dispatch(state, input);
    return 0;
}

int lua_status(lua_State *state) {
    return (int)dispatch(state, request(ADA_GET_STATUS)).integer_data;
}

int lua_resume(lua_State *state, lua_State *from, int arguments, int *results) {
    struct lua_ada_request input = request(ADA_BEGIN_RESUME);
    struct lua_ada_response output;
    int action;
    input.index = arguments;
    input.pointer = from;
    action = dispatch_raw(state, &input, &output);
    action = pump_callbacks(action, &output);
    if (action == ADA_ACTION_RAISE || action == ADA_ACTION_MEMORY ||
        action == ADA_ACTION_HANDLING) {
        /* lua_resume is itself a protected C boundary. Setup refusal and
         * language errors return their real status/object to its caller;
         * host abort remains an uncatchable transfer through the C guard. */
        if (results != NULL) *results = 1;
        return action;
    }
    raise_action(state, action, &output);
    if (results != NULL) *results = (int)output.length;
    return (int)output.integer_data;
}

int lua_closethread(lua_State *state, lua_State *from) {
    struct lua_ada_request input = request(ADA_CLOSE_THREAD);
    struct lua_ada_response output;
    int action;
    input.pointer = from;
    action = dispatch_raw(state, &input, &output);
    if (action == ADA_ACTION_SELF_CLOSE) raise_action(state, action, &output);
    action = pump_callbacks(action, &output);
    /* Like resume, close returns protected language/memory statuses. A self
     * transfer and an embedding abort must abandon the live C body instead. */
    if (action == ADA_ACTION_RAISE || action == ADA_ACTION_MEMORY ||
        action == ADA_ACTION_HANDLING) return action;
    raise_action(state, action, &output);
    return (int)output.integer_data;
}

int lua_error(lua_State *state) {
    dispatch(state, request(ADA_RAISE_ERROR));
    abort(); /* A raise action cannot return through the C guard. */
}

static void release_buffer(lua_State *state, void *buffer) {
    struct lua_ada_request input = request(ADA_RELEASE_BUFFER);
    input.pointer = buffer;
    dispatch(state, input);
}

int lua_ada_read_guarded(lua_State *state, lua_Reader reader, void *data,
                         struct lua_ada_response *completion) {
    struct lua_ada_guard guard = {0};
    int status;
    memset(completion, 0, sizeof *completion);
    guard.previous = state->guard;
    guard.error_handled = 0;
    memset(&guard.callback_token, 0, sizeof guard.callback_token);
    state->guard = &guard;
    /* This checkpoint is ABOVE the suspended shared Ada frontend. A reader
     * can call the public API recursively, but its error/yield jumps only to
     * this live C frame and returns a typed status to that frontend. No saved
     * C stack or nonlocal transfer crosses the waiting Ada parser/decoder. */
    status = setjmp(guard.target);
    if (status == 0) {
        size_t length = 0;
        completion->pointer = (void *)reader(state, data, &length);
        completion->length = length;
    }
    state->guard = guard.previous;
    completion->error_handled = guard.error_handled;
    return status;
}

int lua_load(lua_State *state, lua_Reader reader, void *data,
             const char *name, const char *mode) {
    struct lua_ada_guard guard = {0};
    struct lua_ada_response output;
    volatile int barrier_active = 0;
    int top = lua_gettop(state);
    int status;
    guard.previous = state->guard;
    guard.error_handled = 0;
    memset(&guard.callback_token, 0, sizeof guard.callback_token);
    state->guard = &guard;
    status = setjmp(guard.target);
    if (status == 0) {
        struct lua_ada_request input = request(ADA_READER_BARRIER);
        input.index = 1;
        dispatch(state, input);
        barrier_active = 1;
        input = request(ADA_LOAD_READER);
        input.reader = reader;
        input.pointer = data;
        input.name = name;
        input.mode = mode;
        output = dispatch(state, input);
        status = (int)output.integer_data;
        guard.error_handled = output.error_handled;
    }
    if (status == LUA_ERRRUN && !guard.error_handled) {
        /* lua_error in the reader uses the nearest surrounding message
         * handler even though the parser catches its final status. Re-raise
         * through a hidden phase on the existing VM driver; ordinary pcall
         * applies the real handler (including recursive handler failures). */
        struct lua_ada_request input = request(ADA_PREPARE_READER_ERROR);
        guard.error_handled = 1;
        output = dispatch(state, input);
        if (output.integer_data != 0)
            status = lua_pcall(state, 1, 1, lua_gettop(state) - 2);
    }
    /* The dispatcher has finalized the source and any partial graph before
     * returning. Restore the scalar top directly, without invoking arbitrary
     * lua_settop closing handlers, after removing the parser yield barrier. */
    state->guard = guard.previous;
    if (barrier_active) dispatch(state, request(ADA_READER_BARRIER));
    if (status == ADA_ACTION_ABORT || status == ADA_ACTION_SELF_CLOSE) {
        memset(&output, 0, sizeof output);
        raise_action(state, status, &output);
    }
    {
        struct lua_ada_request restore = request(ADA_RESTORE_LOAD_STACK);
        restore.index = top;
        restore.count = 1;
        dispatch(state, restore);
    }
    return status;
}

int lua_dump(lua_State *state, lua_Writer writer, void *data, int strip) {
    struct lua_ada_request input = request(ADA_DUMP_FUNCTION);
    struct lua_ada_response output;
    struct lua_ada_guard guard = {0};
    void *volatile buffer = NULL;
    int top = lua_gettop(state);
    volatile int result = 0;
    int status;
    /* The canonical snapshot is owned bytes, never a live Ada borrow. Writer
     * reentry may mutate its stack and run collection between calls; only its
     * final stack size is restored. Lua 5.5 additionally requires the terminal
     * NULL/zero callback, and a nonzero writer result stops all further calls. */
    guard.previous = state->guard;
    guard.error_handled = 0;
    memset(&guard.callback_token, 0, sizeof guard.callback_token);
    state->guard = &guard;
    status = setjmp(guard.target);
    if (status == 0) {
        input.index = strip;
        output = dispatch(state, input);
        buffer = output.pointer;
        result = writer(state, buffer, output.length, data);
        if (result == 0) result = writer(state, NULL, 0, data);
    }
    state->guard = guard.previous;
    release_buffer(state, buffer);
    if (status != 0) {
        memset(&output, 0, sizeof output);
        output.error_handled = guard.error_handled;
        raise_action(state, status, &output);
    }
    input = request(ADA_RESTORE_LOAD_STACK);
    input.index = top;
    dispatch(state, input);
    return result;
}

int luaL_loadbufferx(lua_State *state, const char *buffer, size_t size,
                     const char *name, const char *mode) {
    struct lua_ada_request input = request(ADA_LOAD_BUFFER);
    input.pointer = (void *)buffer;
    input.length = size;
    input.name = name;
    input.mode = mode;
    return (int)dispatch(state, input).integer_data;
}

int luaL_loadstring(lua_State *state, const char *source) {
    return luaL_loadbufferx(state, source, strlen(source), source, "t");
}

lua_State *lua_newstate(lua_Alloc allocator, void *userdata, unsigned seed) {
    struct lua_ada_request input = request(ADA_CREATE_STATE);
    struct lua_ada_response output;
    initialize();
    input.allocator = allocator;
    input.pointer = userdata;
    input.seed = seed;
    input.length = LUA_EXTRASPACE;
    /* Constructor failure is an ordinary null result, never a panic. */
    if (ada_lua_dispatch(NULL, &input, &output) != LUA_OK) return NULL;
    return (lua_State *)output.pointer;
}

static int default_panic(lua_State *state) {
    const char *message = lua_type(state, -1) == LUA_TSTRING
        ? lua_tostring(state, -1) : "error object is not a string";
    fprintf(stderr, "PANIC: unprotected error in call to Lua API (%s)\n",
            message);
    return 0;
}

lua_State *luaL_newstate(void) {
    struct lua_ada_request input = request(ADA_CREATE_DEFAULT_STATE);
    struct lua_ada_response output;
    initialize();
    input.allocator = luaL_alloc;
    input.seed = luaL_makeseed(NULL);
    input.length = LUA_EXTRASPACE;
    if (ada_lua_dispatch(NULL, &input, &output) != LUA_OK) return NULL;
    /* Keep default warning initialization in Ada, and install the public
     * auxiliary panic policy only after constructor ownership commits. */
    if (output.pointer != NULL)
        lua_atpanic((lua_State *)output.pointer, default_panic);
    return (lua_State *)output.pointer;
}

void lua_close(lua_State *state) { dispatch(state, request(ADA_CLOSE_STATE)); }
lua_State *lua_newthread(lua_State *state) {
    return (lua_State *)dispatch(state, request(ADA_CREATE_THREAD)).pointer;
}
lua_Number lua_version(lua_State *state) { (void)state; return LUA_VERSION_NUM; }
lua_CFunction lua_atpanic(lua_State *state, lua_CFunction panic) {
    lua_CFunction previous = state->main->panic;
    state->main->panic = panic;
    return previous;
}

static struct lua_ada_response indexed(lua_State *state,
                                       enum lua_ada_operation operation,
                                       int index) {
    struct lua_ada_request input = request(operation);
    input.index = index;
    return dispatch(state, input);
}

int lua_gettop(lua_State *state) {
    return (int)dispatch(state, request(ADA_GET_TOP)).integer_data;
}
void lua_settop(lua_State *state, int index) {
    struct lua_ada_response output = indexed(state, ADA_SET_TOP, index);
    if (output.length != 0) {
        lua_call(state, 0, 0);
        indexed(state, ADA_SET_TOP, index);
    }
}
int lua_absindex(lua_State *state, int index) {
    return (int)indexed(state, ADA_ABSOLUTE_INDEX, index).integer_data;
}
void lua_pushvalue(lua_State *state, int index) {
    indexed(state, ADA_PUSH_VALUE, index);
}
int lua_checkstack(lua_State *state, int count) {
    struct lua_ada_request input = request(ADA_CHECK_STACK);
    input.count = count;
    return (int)dispatch(state, input).integer_data;
}
void lua_copy(lua_State *state, int from, int to) {
    struct lua_ada_request input = request(ADA_COPY_VALUE);
    input.index = from; input.count = to;
    dispatch(state, input);
}
void lua_rotate(lua_State *state, int index, int count) {
    struct lua_ada_request input = request(ADA_ROTATE_VALUES);
    input.index = index; input.count = count;
    dispatch(state, input);
}
void lua_xmove(lua_State *from, lua_State *to, int count) {
    struct lua_ada_request input = request(ADA_MOVE_VALUES);
    input.pointer = to; input.count = count;
    dispatch(from, input);
}
void lua_setwarnf(lua_State *state, lua_WarnFunction warning, void *data) {
    struct lua_ada_request input = request(ADA_SET_WARNING_FUNCTION);
    input.warning_function = warning;
    input.pointer = data;
    dispatch(state, input);
}
void lua_warning(lua_State *state, const char *message, int to_continue) {
    struct lua_ada_request input = request(ADA_ISSUE_WARNING);
    struct lua_ada_response output;
    int action;
    input.pointer = (void *)message;
    input.length = strlen(message);
    input.count = to_continue;
    action = dispatch_raw(state, &input, &output);
    /* The caller retains its C string, including through nested warnings.
     * No new Lua allocation or logical debug frame is introduced here. */
    if (action == ADA_ACTION_WARNING)
        output.warning_function(output.warning_data, output.warning_message,
                                output.warning_continuation);
    else raise_action(state, action, &output);
}
int lua_isyieldable(lua_State *state) {
    return (int)dispatch(state, request(ADA_GET_YIELDABILITY)).integer_data;
}
int lua_type(lua_State *state, int index) {
    return (int)indexed(state, ADA_GET_TYPE, index).integer_data;
}
const char *lua_typename(lua_State *state, int type) {
    static const char *const names[] = {"nil", "boolean", "userdata",
        "number", "string", "table", "function", "userdata", "thread"};
    (void)state;
    return type >= LUA_TNIL && type < LUA_NUMTYPES ? names[type] : "no value";
}
int lua_isinteger(lua_State *state, int index) {
    return indexed(state, ADA_GET_TYPE, index).length != 0;
}
int lua_isnumber(lua_State *state, int index) {
    return indexed(state, ADA_TO_NUMBER, index).length != 0;
}
int lua_isstring(lua_State *state, int index) {
    int type = lua_type(state, index);
    return type == LUA_TSTRING || type == LUA_TNUMBER;
}
int lua_isuserdata(lua_State *state, int index) {
    int type = lua_type(state, index);
    return type == LUA_TLIGHTUSERDATA || type == LUA_TUSERDATA;
}
int lua_toboolean(lua_State *state, int index) {
    return (int)indexed(state, ADA_TO_BOOLEAN, index).integer_data;
}
lua_Integer lua_tointegerx(lua_State *state, int index, int *valid) {
    struct lua_ada_response output = indexed(state, ADA_TO_INTEGER, index);
    if (valid != NULL) *valid = output.length != 0;
    return (lua_Integer)output.integer_data;
}
lua_Number lua_tonumberx(lua_State *state, int index, int *valid) {
    struct lua_ada_response output = indexed(state, ADA_TO_NUMBER, index);
    if (valid != NULL) *valid = output.length != 0;
    return (lua_Number)output.number_data;
}
size_t lua_stringtonumber(lua_State *state, const char *text) {
    struct lua_ada_request input = request(ADA_STRING_TO_NUMBER);
    input.pointer = (void *)text;
    input.length = strlen(text);
    return dispatch(state, input).length;
}
const char *lua_tolstring(lua_State *state, int index, size_t *length) {
    struct lua_ada_response output = indexed(state, ADA_TO_STRING, index);
    if (length != NULL) *length = output.length;
    return (const char *)output.pointer;
}
lua_Unsigned lua_rawlen(lua_State *state, int index) {
    return (lua_Unsigned)indexed(state, ADA_RAW_LENGTH, index).integer_data;
}
const void *lua_topointer(lua_State *state, int index) {
    return indexed(state, ADA_TO_POINTER, index).pointer;
}
void *lua_touserdata(lua_State *state, int index) {
    return lua_isuserdata(state, index) ?
        indexed(state, ADA_TO_POINTER, index).pointer : NULL;
}
lua_State *lua_tothread(lua_State *state, int index) {
    return (lua_State *)indexed(state, ADA_TO_THREAD, index).pointer;
}
void *lua_newuserdatauv(lua_State *state, size_t size, int uservalues) {
    struct lua_ada_request input = request(ADA_CREATE_USERDATA);
    input.length = size;
    input.count = uservalues;
    return dispatch(state, input).pointer;
}
int lua_getiuservalue(lua_State *state, int index, int number) {
    struct lua_ada_request input = request(ADA_GET_USERVALUE);
    input.index = index;
    input.count = number;
    return (int)dispatch(state, input).integer_data;
}
int lua_setiuservalue(lua_State *state, int index, int number) {
    struct lua_ada_request input = request(ADA_SET_USERVALUE);
    input.index = index;
    input.count = number;
    return (int)dispatch(state, input).integer_data;
}
int lua_getmetatable(lua_State *state, int index) {
    return (int)indexed(state, ADA_GET_METATABLE, index).integer_data;
}
int lua_setmetatable(lua_State *state, int index) {
    return (int)indexed(state, ADA_SET_METATABLE, index).integer_data;
}
void lua_pushnil(lua_State *state) { dispatch(state, request(ADA_PUSH_NIL)); }
void lua_pushboolean(lua_State *state, int value) {
    struct lua_ada_request input = request(ADA_PUSH_BOOLEAN);
    input.count = value; dispatch(state, input);
}
void lua_pushinteger(lua_State *state, lua_Integer value) {
    struct lua_ada_request input = request(ADA_PUSH_INTEGER);
    input.integer_data = value; dispatch(state, input);
}
void lua_pushnumber(lua_State *state, lua_Number value) {
    struct lua_ada_request input = request(ADA_PUSH_NUMBER);
    input.number_data = value; dispatch(state, input);
}
const char *lua_pushlstring(lua_State *state, const char *text, size_t length) {
    struct lua_ada_request input = request(ADA_PUSH_STRING);
    input.pointer = (void *)text; input.length = length;
    return (const char *)dispatch(state, input).pointer;
}
const char *lua_pushstring(lua_State *state, const char *text) {
    if (text == NULL) { lua_pushnil(state); return NULL; }
    return lua_pushlstring(state, text, strlen(text));
}
const char *lua_pushexternalstring(lua_State *state, const char *text,
                                  size_t length, lua_Alloc allocator,
                                  void *data) {
    struct lua_ada_request input = request(ADA_PUSH_EXTERNAL_STRING);
    struct lua_ada_response output;
    int original_top = lua_gettop(state);
    int status;
    input.pointer = (void *)text;
    input.length = length;
    input.allocator = allocator;
    input.warning_data = data;
    status = ada_lua_dispatch(state, &input, &output);
    if (status != LUA_OK && output.integer_data == 0 && allocator) {
        struct lua_ada_response pending, completion;
        int callback_status;
        /* No header was allocated to own the payload. This live C guard
         * retains that sole ownership, including permanent refusal. Native
         * cleanup runs before its memory error is placed on the stack. */
        lua_settop(state, original_top);
        memset(&pending, 0, sizeof pending);
        pending.allocator = allocator;
        pending.warning_data = data;
        pending.warning_message = text;
        pending.length = length + 1;
        callback_status = lua_ada_invoke_borrowed(state,
            ADA_ACTION_EXTERNAL_RELEASE, &pending, &completion);
        if (callback_status != LUA_OK)
            raise_action(state, callback_status, &completion);
        if (status == LUA_ERRMEM) lua_pushliteral(state, "not enough memory");
    }
    lua_ada_drain_external_releases(state);
    raise_action(state, status, &output);
    return (const char *)output.pointer;
}
void lua_pushlightuserdata(lua_State *state, void *pointer) {
    struct lua_ada_request input = request(ADA_PUSH_POINTER);
    input.pointer = pointer; dispatch(state, input);
}
int lua_pushthread(lua_State *state) {
    return (int)dispatch(state, request(ADA_PUSH_THREAD)).integer_data;
}
void lua_createtable(lua_State *state, int array, int records) {
    struct lua_ada_request input = request(ADA_CREATE_TABLE);
    input.index = array; input.count = records; dispatch(state, input);
}
int lua_rawget(lua_State *state, int index) {
    return (int)indexed(state, ADA_RAW_GET, index).integer_data;
}
void lua_rawset(lua_State *state, int index) {
    indexed(state, ADA_RAW_SET, index);
}
int lua_rawgeti(lua_State *state, int index, lua_Integer key) {
    struct lua_ada_request input = request(ADA_RAW_GET_INTEGER);
    input.index = index; input.integer_data = key;
    return (int)dispatch(state, input).integer_data;
}
void lua_rawseti(lua_State *state, int index, lua_Integer key) {
    struct lua_ada_request input = request(ADA_RAW_SET_INTEGER);
    input.index = index; input.integer_data = key; dispatch(state, input);
}
int lua_rawgetp(lua_State *state, int index, const void *key) {
    struct lua_ada_request input = request(ADA_RAW_GET_POINTER);
    input.index = index; input.pointer = (void *)key;
    return (int)dispatch(state, input).integer_data;
}
void lua_rawsetp(lua_State *state, int index, const void *key) {
    struct lua_ada_request input = request(ADA_RAW_SET_POINTER);
    input.index = index; input.pointer = (void *)key; dispatch(state, input);
}
int lua_rawequal(lua_State *state, int first, int second) {
    struct lua_ada_request input = request(ADA_RAW_EQUAL);
    input.index = first; input.count = second;
    return (int)dispatch(state, input).integer_data;
}
void lua_arith(lua_State *state, int operation) {
    struct lua_ada_request input = request(ADA_PREPARE_ARITHMETIC);
    int top = lua_gettop(state);
    int operands = (operation == LUA_OPUNM || operation == LUA_OPBNOT) ? 1 : 2;
    input.index = operation;
    if (dispatch(state, input).length != 0) {
        lua_call(state, 2, 1);
        lua_copy(state, -1, top - operands + 1);
        lua_settop(state, top - operands + 1);
    }
}
int lua_compare(lua_State *state, int first, int second, int operation) {
    struct lua_ada_request input = request(ADA_PREPARE_COMPARISON);
    struct lua_ada_response output;
    int result;
    input.index = first; input.count = second; input.error_index = operation;
    output = dispatch(state, input);
    if (output.length == 0) return (int)output.integer_data;
    lua_call(state, 2, 1);
    result = lua_toboolean(state, -1); lua_pop(state, 1);
    return result;
}
int lua_next(lua_State *state, int index) {
    return (int)indexed(state, ADA_NEXT_ITEM, index).integer_data;
}

int lua_gettable(lua_State *state, int index) {
    struct lua_ada_request input = request(ADA_PREPARE_INDEX);
    struct lua_ada_response output;
    input.index = index;
    output = dispatch(state, input);
    if (output.length != 0) lua_call(state, 2, 1);
    return lua_type(state, -1);
}

void lua_len(lua_State *state, int index) {
    struct lua_ada_request input = request(ADA_PREPARE_LENGTH);
    input.index = index;
    if (dispatch(state, input).length != 0) lua_call(state, 1, 1);
}

void lua_concat(lua_State *state, int count) {
    struct lua_ada_request input = request(ADA_PREPARE_CONCATENATION);
    input.count = count;
    if (dispatch(state, input).length != 0) lua_call(state, count, 1);
}

unsigned lua_numbertocstring(lua_State *state, int index, char *buffer) {
    struct lua_ada_request input = request(ADA_NUMBER_TO_C_STRING);
    input.index = index;
    input.pointer = buffer;
    return (unsigned)dispatch(state, input).length;
}

void lua_settable(lua_State *state, int index) {
    struct lua_ada_request input = request(ADA_PREPARE_INDEX);
    struct lua_ada_response output;
    input.index = index;
    input.count = 1;
    output = dispatch(state, input);
    if (output.length != 0) lua_call(state, 3, 0);
}

int lua_getfield(lua_State *state, int index, const char *key) {
    index = lua_absindex(state, index);
    lua_pushstring(state, key);
    return lua_gettable(state, index);
}

void lua_setfield(lua_State *state, int index, const char *key) {
    index = lua_absindex(state, index);
    lua_pushstring(state, key);
    lua_insert(state, -2);
    lua_settable(state, index);
}

int lua_geti(lua_State *state, int index, lua_Integer key) {
    index = lua_absindex(state, index);
    lua_pushinteger(state, key);
    return lua_gettable(state, index);
}

void lua_seti(lua_State *state, int index, lua_Integer key) {
    index = lua_absindex(state, index);
    lua_pushinteger(state, key);
    lua_insert(state, -2);
    lua_settable(state, index);
}

int lua_getglobal(lua_State *state, const char *name) {
    int type;
    lua_pushglobaltable(state);
    type = lua_getfield(state, -1, name);
    lua_remove(state, -2);
    return type;
}

void lua_setglobal(lua_State *state, const char *name) {
    lua_pushglobaltable(state);
    lua_insert(state, -2);
    lua_setfield(state, -2, name);
    lua_pop(state, 1);
}

void lua_toclose(lua_State *state, int index) {
    indexed(state, ADA_MARK_CLOSE, index);
}

void lua_closeslot(lua_State *state, int index) {
    struct lua_ada_request input = request(ADA_CLOSE_SLOT);
    struct lua_ada_response output;
    input.index = lua_absindex(state, index);
    output = dispatch(state, input);
    if (output.length != 0) {
        lua_call(state, 0, 0);
        input.count = 1;
        dispatch(state, input);
    }
}
lua_Alloc lua_getallocf(lua_State *state, void **userdata) {
    struct lua_ada_response output = dispatch(state, request(ADA_GET_ALLOCATOR));
    if (userdata != NULL) *userdata = output.pointer;
    return output.allocator;
}
void lua_setallocf(lua_State *state, lua_Alloc allocator, void *userdata) {
    struct lua_ada_request input = request(ADA_SET_ALLOCATOR);
    input.allocator = allocator; input.pointer = userdata; dispatch(state, input);
}

int luaopen_io(lua_State *state) {
    return (int)dispatch(state, request(ADA_OPEN_IO_MODULE)).integer_data;
}
int luaopen_os(lua_State *state) {
    return (int)dispatch(state, request(ADA_OPEN_OS_MODULE)).integer_data;
}

static int drain_collector(lua_State *state) {
    dispatch(state, request(ADA_PUSH_COLLECTOR_DRAIN));
    lua_call(state, 0, 0);
    return 0;
}

void *lua_ada_collector_drain_address(void) {
    typedef char pointer_sizes_match[
        sizeof(lua_CFunction) == sizeof(void *) ? 1 : -1];
    lua_CFunction function = drain_collector;
    void *address;
    (void)sizeof(pointer_sizes_match);
    /* Ada classifies this actual private C guard transport before scheduling
     * it. It is not a Lua call and must not add a public frame or hook event.
     * The callback still executes through its ordinary protected C pump. */
    memcpy(&address, &function, sizeof address);
    return address;
}

int lua_gc(lua_State *state, int what, ...) {
    struct lua_ada_request input = request(ADA_COLLECTOR_CONTROL);
    struct lua_ada_response output;
    va_list arguments;
    int status;
    input.index = what;
    va_start(arguments, what);
    if (what == LUA_GCSTEP) input.length = va_arg(arguments, size_t);
    else if (what == LUA_GCPARAM) {
        input.count = va_arg(arguments, int);
        input.error_index = va_arg(arguments, int);
    }
    va_end(arguments);
    output = dispatch(state, input);
    /* Lua finalizers run only after the Ada control call has returned. The
     * ordinary protected C pump owns every callback and nonlocal transfer.
     * Failure to obtain optional frame/stack storage defers the intact queue;
     * host-abort transfers retain their existing uncatchable boundary. */
    if (output.length && lua_checkstack(state, 1)) {
        lua_pushcfunction(state, drain_collector);
        status = lua_pcall(state, 0, 0, 0);
        if (status == LUA_ERRMEM) lua_pop(state, 1);
        else if (status != LUA_OK) lua_error(state);
    }
    return (int)output.integer_data;
}
