/* First-party public C API regressions. MIT license; see ../../LICENSE. */
#ifndef LUA_ADA_GC_CONTRACT_H
#define LUA_ADA_GC_CONTRACT_H

static void test_gc_controls_without_allocation(void) {
    struct allocation_counts counts = {0};
    lua_State *state = lua_newstate(counted_allocator, &counts, 1);
    size_t calls;
    int parameter;
    assert(state);
    assert(lua_gc(state, LUA_GCSTOP) == 0);
    assert(lua_gc(state, LUA_GCISRUNNING) == 0);
    assert((size_t)lua_gc(state, LUA_GCCOUNT) * 1024 +
           (size_t)lua_gc(state, LUA_GCCOUNTB) == counts.bytes);
    calls = counts.calls;
    counts.refuse = 1;
    for (parameter = 0; parameter < LUA_GCPN; ++parameter) {
        int previous = lua_gc(state, LUA_GCPARAM, parameter, -1);
        assert(previous >= 0);
        assert(lua_gc(state, LUA_GCPARAM, parameter, 200) == previous);
        assert(lua_gc(state, LUA_GCPARAM, parameter, -1) == 200);
        assert(lua_gc(state, LUA_GCPARAM, parameter, INT_MAX) == 200);
        assert(lua_gc(state, LUA_GCPARAM, parameter, -1) >= 0);
        lua_gc(state, LUA_GCPARAM, parameter, previous);
    }
    assert(lua_gc(state, -123) == -1);
    assert(lua_gc(state, LUA_GCRESTART) == 0);
    assert(lua_gc(state, LUA_GCISRUNNING) == 1);
    assert(counts.calls == calls);
    counts.refuse = 0;
    lua_close(state);
    assert(counts.bytes == 0 && counts.blocks == 0);
    puts("C API PASS: GC controls and actual byte counts need no allocation");
}

static void test_gc_modes_and_stopped_steps(lua_State *state) {
    int finished = 0, steps;
    assert(lua_gc(state, LUA_GCINC) == LUA_GCINC);
    assert(lua_gc(state, LUA_GCGEN) == LUA_GCINC);
    assert(lua_gc(state, LUA_GCINC) == LUA_GCGEN);
    lua_gc(state, LUA_GCSTOP);
    lua_newtable(state);
    lua_pop(state, 1);
    for (steps = 0; steps < 10000 && !finished; ++steps)
        finished = lua_gc(state, LUA_GCSTEP, (size_t)0);
    assert(finished && lua_gc(state, LUA_GCISRUNNING) == 0);
    /* Lua 5.5 casts size_t to signed debt: all-bits-one forces a basic step,
     * rather than overflowing a byte-to-debt calculation or looping forever. */
    finished = lua_gc(state, LUA_GCSTEP, (size_t)-1);
    assert((finished == 0 || finished == 1) &&
           lua_gc(state, LUA_GCISRUNNING) == 0);
    lua_gc(state, LUA_GCRESTART);
    puts("C API PASS: GC mode returns and stopped incremental progress");
}

static int gc_order[8], gc_count;
static int gc_record(lua_State *state) {
    int *value = (int *)lua_touserdata(state, 1);
    assert(value && gc_count < 8 && !lua_isyieldable(state));
    assert(lua_gc(state, LUA_GCCOUNT) == -1);
    assert(lua_gc(state, LUA_GCCOLLECT) == -1);
    gc_order[gc_count++] = *value;
    return 0;
}
static void gc_object_with_handler(lua_State *state, int value,
                                  lua_CFunction handler) {
    int *payload = (int *)lua_newuserdatauv(state, sizeof(int), 0);
    *payload = value;
    lua_newtable(state);
    lua_pushliteral(state, "__gc");
    lua_pushcfunction(state, handler);
    lua_rawset(state, -3);
    lua_setmetatable(state, -2);
    lua_pop(state, 1);
}
static void gc_object(lua_State *state, int value) {
    gc_object_with_handler(state, value, gc_record);
}
static void test_gc_finalizer_callback_order(lua_State *state) {
    lua_settop(state, 0);
    lua_gc(state, LUA_GCCOLLECT);
    lua_gc(state, LUA_GCSTOP);
    gc_count = 0;
    gc_object(state, 1);
    gc_object(state, 2);
    gc_object(state, 3);
    assert(lua_gc(state, LUA_GCCOLLECT) == 0);
    assert(lua_gettop(state) == 0 && gc_count == 3);
    assert(gc_order[0] == 3 && gc_order[1] == 2 && gc_order[2] == 1);
    lua_gc(state, LUA_GCCOLLECT);
    assert(gc_count == 3);
    lua_gc(state, LUA_GCRESTART);
    puts("C API PASS: GC drains ordered nonyieldable C finalizers once");
}

static void test_gc_finalizer_storage_refusal(void) {
    struct allocation_counts counts = {0};
    lua_State *state = lua_newstate(counted_allocator, &counts, 1);
    assert(state);
    lua_gc(state, LUA_GCSTOP);
    gc_count = 0;
    gc_object(state, 7);
    /* This state has never allocated a call driver. Refusing growth forces
     * the optional finalizer activation to defer, then a later GC retries. */
    counts.refuse = 1;
    assert(lua_gc(state, LUA_GCCOLLECT) == 0);
    assert(gc_count == 0 && lua_gettop(state) == 0);
    counts.refuse = 0;
    assert(lua_gc(state, LUA_GCCOLLECT) == 0);
    assert(gc_count == 1 && gc_order[0] == 7);
    lua_close(state);
    assert(counts.bytes == 0 && counts.blocks == 0);
    puts("C API PASS: GC defers refused finalizer storage and retries");
}

static void test_close_drains_c_finalizers(void) {
    struct allocation_counts counts = {0};
    lua_State *state = lua_newstate(counted_allocator, &counts, 1);
    assert(state);
    lua_gc(state, LUA_GCSTOP);
    gc_count = 0;
    gc_object(state, 4);
    gc_object(state, 5);
    lua_close(state);
    assert(gc_count == 2 && gc_order[0] == 5 && gc_order[1] == 4);
    assert(counts.bytes == 0 && counts.blocks == 0);
    puts("C API PASS: state close drains C finalizers before allocator release");
}

static void test_close_refusal_releases_storage(void) {
    struct allocation_counts counts = {0};
    lua_State *state = lua_newstate(counted_allocator, &counts, 1);
    assert(state);
    lua_gc(state, LUA_GCSTOP);
    gc_count = 0;
    gc_object(state, 6);
    counts.refuse = 1;
    lua_close(state);
    assert(gc_count == 0 && counts.bytes == 0 && counts.blocks == 0);
    puts("C API PASS: refused close activation still frees all managed storage");
}

struct gc_warning_record {
    char text[128];
    size_t length;
    int fragments, completed;
};
static void gc_warning(void *data, const char *message, int more) {
    struct gc_warning_record *record = (struct gc_warning_record *)data;
    size_t length = strlen(message);
    assert(record->length + length < sizeof(record->text));
    memcpy(record->text + record->length, message, length + 1);
    record->length += length;
    record->fragments++;
    if (!more) record->completed++;
}
static int gc_error(lua_State *state) {
    lua_pushliteral(state, "GC contract error");
    return lua_error(state);
}
static void test_gc_and_close_warning_callbacks(void) {
    struct allocation_counts counts = {0};
    struct gc_warning_record record = {{0}, 0, 0, 0};
    lua_State *state = lua_newstate(counted_allocator, &counts, 1);
    assert(state);
    lua_setwarnf(state, gc_warning, &record);
    lua_gc(state, LUA_GCSTOP);
    gc_object_with_handler(state, 1, gc_error);
    assert(lua_gc(state, LUA_GCCOLLECT) == 0 && lua_gettop(state) == 0);
    assert(record.fragments == 5 && record.completed == 1);
    assert(strcmp(record.text, "error in __gc (GC contract error)") == 0);
    memset(&record, 0, sizeof(record));
    gc_object_with_handler(state, 2, gc_error);
    lua_close(state);
    assert(record.fragments == 5 && record.completed == 1);
    assert(strcmp(record.text, "error in __gc (GC contract error)") == 0);
    assert(counts.bytes == 0 && counts.blocks == 0);
    puts("C API PASS: GC and state close deliver fragmented warning callbacks");
}

#endif
