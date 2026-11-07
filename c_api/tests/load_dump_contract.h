/* Public Lua 5.5 reader/writer regressions, shared with native C Lua.
 * Copyright (c) 2026 Lua Ada contributors. MIT license; see ../../LICENSE. */
#ifndef LUA_ADA_LOAD_DUMP_CONTRACT_H
#define LUA_ADA_LOAD_DUMP_CONTRACT_H

struct chunk_reader {
    const char *bytes;
    size_t size;
    size_t position;
    size_t piece;
    int calls;
    int preserve_values;
    int raise_after_piece;
    int zero_end;
    char scratch[17];
};

static const char *read_chunk(lua_State *state, void *data, size_t *size) {
    struct chunk_reader *reader = (struct chunk_reader *)data;
    size_t amount;
    assert(!lua_isyieldable(state));
    if (reader->preserve_values) {
        if (reader->calls != 0) {
            assert(lua_tointeger(state, -1) == reader->calls);
            lua_pop(state, 1);
        }
        lua_pushinteger(state, reader->calls + 1);
        lua_gc(state, LUA_GCCOLLECT);
    }
    reader->calls++;
    if (reader->raise_after_piece && reader->calls > reader->raise_after_piece) {
        lua_pushvalue(state, 1); /* Preserve a real non-string error object. */
        lua_error(state);
    }
    if (reader->position == reader->size) {
        *size = reader->zero_end ? 0 : 999;
        return reader->zero_end ? reader->scratch : NULL;
    }
    amount = reader->size - reader->position;
    if (amount > reader->piece) amount = reader->piece;
    assert(amount <= sizeof(reader->scratch));
    /* Reuse the same foreign scratch bytes on every read. The implementation
     * must consume/copy each piece before asking for the next one. */
    memcpy(reader->scratch, reader->bytes + reader->position, amount);
    reader->position += amount;
    *size = amount;
    return reader->scratch;
}

struct chunk_writer {
    char *bytes;
    size_t size;
    int calls;
    int terminal_calls;
    int preserve_values;
    int fail_first;
    int fail_terminal;
    int raise_error;
};

static int write_chunk(lua_State *state, const void *bytes, size_t size,
                        void *data) {
    struct chunk_writer *writer = (struct chunk_writer *)data;
    if (writer->preserve_values) {
        if (writer->calls != 0) {
            assert(lua_tointeger(state, -1) == writer->calls);
            lua_pop(state, 1);
        }
        lua_pushinteger(state, writer->calls + 1);
        lua_gc(state, LUA_GCCOLLECT);
    }
    writer->calls++;
    if (writer->raise_error) {
        lua_pushvalue(state, 1);
        lua_error(state);
    }
    if (writer->fail_first) return 73;
    if (bytes == NULL) {
        assert(size == 0);
        writer->terminal_calls++;
        return writer->fail_terminal ? 91 : 0;
    }
    if (size != 0) {
        char *replacement = realloc(writer->bytes, writer->size + size);
        assert(replacement != NULL);
        writer->bytes = replacement;
        memcpy(writer->bytes + writer->size, bytes, size);
        writer->size += size;
    }
    return 0;
}

static void test_reader_piece_lifetime(lua_State *state) {
    /* Load one-byte pieces from reused foreign storage. Compilation must not
     * execute the chunk, and later execution must use the owned source/code. */
    const char source[] = "reader_ran = 29; return 42";
    struct chunk_reader reader = {0};
    lua_settop(state, 0);
    reader.bytes = source;
    reader.size = sizeof(source) - 1;
    reader.piece = 1;
    assert(lua_load(state, read_chunk, &reader, "=reader-pieces", "t") == LUA_OK);
    assert(reader.calls > 2 && lua_gettop(state) == 1);
    lua_getglobal(state, "reader_ran");
    assert(lua_isnil(state, -1));
    lua_pop(state, 1);
    assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 42);
    lua_getglobal(state, "reader_ran");
    assert(lua_tointeger(state, -1) == 29);
    lua_pushnil(state);
    lua_setglobal(state, "reader_ran");
    puts("C API PASS: reader piece lifetime and deferred execution");
}

static void test_reader_preserves_stack(lua_State *state) {
    /* Callback-added values remain visible until the following read; only
     * the final API return removes scratch values and adds the loaded chunk. */
    const char source[] = "return 83";
    struct chunk_reader reader = {0};
    lua_settop(state, 0);
    lua_pushinteger(state, 404);
    reader.bytes = source;
    reader.size = sizeof(source) - 1;
    reader.piece = 2;
    reader.preserve_values = 1;
    assert(lua_load(state, read_chunk, &reader, NULL, NULL) == LUA_OK);
    assert(lua_gettop(state) == 2 && lua_tointeger(state, 1) == 404);
    assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 83);
    puts("C API PASS: reader stack preservation and result adjustment");
}

static void test_reader_error_identity(lua_State *state) {
    /* Raise after one managed source piece exists. lua_load catches the
     * reader's table error without invoking panic and leaves the state usable. */
    struct chunk_reader reader = {0};
    lua_settop(state, 0);
    lua_newtable(state);
    reader.bytes = "return 1";
    reader.size = 8;
    reader.piece = 3;
    reader.raise_after_piece = 2;
    assert(lua_load(state, read_chunk, &reader, "=reader-error", "t") == LUA_ERRRUN);
    assert(lua_gettop(state) == 2 && lua_rawequal(state, 1, 2));
    lua_settop(state, 0);
    assert(luaL_loadstring(state, "return 19") == LUA_OK);
    assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 19);
    puts("C API PASS: reader protected error identity and recovery");
}

static void test_reader_end_conditions(lua_State *state) {
    /* A non-null zero-sized block and a null pointer with a nonzero size both
     * signal EOF. Neither condition may cause an additional reader call. */
    struct chunk_reader reader = {0};
    lua_settop(state, 0);
    reader.zero_end = 1;
    assert(lua_load(state, read_chunk, &reader, "=empty-zero", "t") == LUA_OK);
    assert(reader.calls == 1);
    assert(lua_pcall(state, 0, 0, 0) == LUA_OK);
    reader.calls = 0;
    reader.zero_end = 0;
    assert(lua_load(state, read_chunk, &reader, "=empty-null", "t") == LUA_OK);
    assert(reader.calls == 1);
    assert(lua_pcall(state, 0, 0, 0) == LUA_OK);
    puts("C API PASS: reader null and zero-sized EOF");
}

static const char *read_yielding_chunk(lua_State *state, void *data,
                                      size_t *size) {
    (void)data;
    *size = 0;
    assert(!lua_isyieldable(state));
    lua_yield(state, 0);
    assert(!"reader yield returned to its C body");
    return NULL;
}

static int load_in_yieldable_callback(lua_State *state) {
    assert(lua_isyieldable(state));
    assert(lua_load(state, read_yielding_chunk, NULL, "=reader-yield", "t") == LUA_ERRRUN);
    assert(strstr(lua_tostring(state, -1), "yield"));
    assert(lua_isyieldable(state));
    lua_settop(state, 0);
    lua_pushinteger(state, 99);
    return 1;
}

static void test_reader_yield_barrier(lua_State *state) {
    /* A resumable C caller remains resumable, but its reader runs inside the
     * protected parser's non-yieldable region and receives a catchable error. */
    lua_State *thread;
    int results = 0;
    lua_settop(state, 0);
    thread = lua_newthread(state);
    lua_pushcfunction(thread, load_in_yieldable_callback);
    assert(lua_resume(thread, state, 0, &results) == LUA_OK);
    assert(results == 1 && lua_tointeger(thread, -1) == 99);
    puts("C API PASS: reader non-yieldable region restores caller policy");
}

static int reader_message_calls;

static const char *read_handler_error(lua_State *state, void *data,
                                      size_t *size) {
    (void)data;
    *size = 0;
    lua_pushliteral(state, "raw reader failure");
    lua_error(state);
    return NULL;
}

static int reader_message_handler(lua_State *state) {
    assert(strcmp(lua_tostring(state, 1), "raw reader failure") == 0);
    reader_message_calls++;
    lua_pushliteral(state, "handled reader failure");
    return 1;
}

static int load_reader_with_handler(lua_State *state) {
    assert(lua_load(state, read_handler_error, NULL, "=reader-handler", "t") == LUA_ERRRUN);
    assert(strcmp(lua_tostring(state, -1), "handled reader failure") == 0);
    return 1;
}

static void test_reader_inherits_message_handler(lua_State *state) {
    /* The surrounding pcall succeeds because the C body catches lua_load's
     * status. Its handler must nevertheless already have transformed the
     * reader's actual lua_error exactly once inside the protected parser. */
    lua_settop(state, 0);
    reader_message_calls = 0;
    lua_pushcfunction(state, reader_message_handler);
    lua_pushcfunction(state, load_reader_with_handler);
    assert(lua_pcall(state, 0, 1, 1) == LUA_OK);
    assert(reader_message_calls == 1);
    assert(strcmp(lua_tostring(state, -1), "handled reader failure") == 0);
    puts("C API PASS: reader inherits surrounding message handler once");
}

static void test_reader_syntax_and_mode_errors(lua_State *state) {
    /* Parser errors and mode rejection are returned statuses with one result,
     * rather than unprotected errors or a successful empty function. */
    struct chunk_reader reader = {0};
    lua_settop(state, 0);
    reader.bytes = "local =";
    reader.size = 7;
    reader.piece = 2;
    assert(lua_load(state, read_chunk, &reader, "=broken-reader", "t") == LUA_ERRSYNTAX);
    assert(lua_gettop(state) == 1 && strstr(lua_tostring(state, -1), "broken-reader"));
    lua_settop(state, 0);
    reader.position = reader.calls = 0;
    reader.bytes = "return 1";
    reader.size = 8;
    reader.raise_after_piece = 1;
    assert(lua_load(state, read_chunk, &reader, "=text-mode", "b") == LUA_ERRSYNTAX);
    assert(reader.calls == 1 && strstr(lua_tostring(state, -1), "text"));
    puts("C API PASS: reader syntax and mode failures");
}

static void test_dump_round_trip(lua_State *state) {
    /* Dump the selected nested closure, not its owning program's main node.
     * Load split binary pieces and the documented fixed-buffer B mode; both
     * must reconstruct executable code without capturing live upvalue values. */
    struct chunk_writer writer = {0};
    struct chunk_reader reader = {0};
    lua_settop(state, 0);
    assert(luaL_loadstring(state, "return function(x) return x + 7 end") == LUA_OK);
    assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
    assert(lua_dump(state, write_chunk, &writer, 0) == 0);
    assert(lua_gettop(state) == 1 && writer.size > 20);
    assert(writer.terminal_calls == 1 && writer.bytes[0] == '\033');
    reader.bytes = writer.bytes;
    reader.size = writer.size;
    reader.piece = 7;
    assert(lua_load(state, read_chunk, &reader, "=dump-roundtrip", "b") == LUA_OK);
    assert(reader.calls == (int)((reader.size + 6) / 7));
    lua_pushinteger(state, 35);
    assert(lua_pcall(state, 1, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 42);
    assert(luaL_loadbufferx(state, writer.bytes, writer.size, "=fixed", "B") == LUA_OK);
    lua_pushinteger(state, 12);
    assert(lua_pcall(state, 1, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 19);
    lua_settop(state, 0);
    lua_gc(state, LUA_GCCOLLECT);
    free(writer.bytes);
    puts("C API PASS: canonical subtree dump and binary reader round trip");
}

static void test_dump_writer_stack_and_terminal(lua_State *state) {
    /* Writer scratch values persist through the terminal NULL/zero callback.
     * lua_dump removes those values on return while preserving the function. */
    struct chunk_writer writer = {0};
    lua_settop(state, 0);
    assert(luaL_loadstring(state, "return 51") == LUA_OK);
    writer.preserve_values = 1;
    assert(lua_dump(state, write_chunk, &writer, 1) == 0);
    assert(writer.calls >= 2 && writer.terminal_calls == 1);
    assert(lua_gettop(state) == 1 && lua_isfunction(state, 1));
    assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 51);
    free(writer.bytes);
    puts("C API PASS: writer stack preservation and terminal callback");
}

static void test_dump_writer_stops_on_status(lua_State *state) {
    /* A nonzero writer result stops all later writes, including the terminal
     * call, and is returned verbatim without changing the original stack. */
    struct chunk_writer writer = {0};
    lua_settop(state, 0);
    assert(luaL_loadstring(state, "return 23") == LUA_OK);
    writer.fail_first = 1;
    assert(lua_dump(state, write_chunk, &writer, 0) == 73);
    assert(writer.calls == 1 && writer.terminal_calls == 0);
    assert(lua_gettop(state) == 1 && lua_isfunction(state, 1));
    puts("C API PASS: writer nonzero status stops further callbacks");
}

static void test_dump_terminal_status(lua_State *state) {
    /* Lua 5.5's extra terminal call can itself fail. Its exact status belongs
     * to lua_dump even after all nonempty output was successfully delivered. */
    struct chunk_writer writer = {0};
    lua_settop(state, 0);
    assert(luaL_loadstring(state, "return 11") == LUA_OK);
    writer.fail_terminal = 1;
    assert(lua_dump(state, write_chunk, &writer, 0) == 91);
    assert(writer.size > 0 && writer.terminal_calls == 1);
    assert(lua_gettop(state) == 1);
    free(writer.bytes);
    puts("C API PASS: writer terminal status is returned verbatim");
}

static int dump_raising_writer(lua_State *state) {
    struct chunk_writer writer = {0};
    assert(luaL_loadstring(state, "return 1") == LUA_OK);
    writer.raise_error = 1;
    lua_dump(state, write_chunk, &writer, 0);
    assert(!"raising writer returned to its C body");
    return 0;
}

static void test_dump_writer_error_identity(lua_State *state) {
    /* Writer errors propagate to the surrounding real protected call. The
     * managed snapshot must be released before that C-owned nonlocal exit. */
    lua_settop(state, 0);
    lua_newtable(state);
    lua_pushcfunction(state, dump_raising_writer);
    lua_pushvalue(state, 1);
    assert(lua_pcall(state, 1, 0, 0) == LUA_ERRRUN);
    assert(lua_gettop(state) == 2 && lua_rawequal(state, 1, 2));
    puts("C API PASS: writer protected error object identity");
}

struct refusing_reader {
    struct allocation_counts *counts;
    int calls;
};

static const char *read_refusing_chunk(lua_State *state, void *data,
                                       size_t *size) {
    struct refusing_reader *reader = (struct refusing_reader *)data;
    static const char source[] = "return ";
    static const char body[8192] = {' '};
    (void)state;
    if (reader->calls++ == 0) {
        *size = sizeof(source) - 1;
        return source;
    }
    assert(reader->calls == 2);
    reader->counts->refuse = 1;
    *size = sizeof(body);
    return body;
}

static void test_reader_allocation_refusal(void) {
    /* Refuse the reader's source storage through the real selected allocator.
     * lua_load must return ERRMEM, release its scratch ownership and recover. */
    struct allocation_counts counts = {0};
    struct refusing_reader reader = {&counts, 0};
    int iteration;
    lua_State *state = lua_newstate(counted_allocator, &counts, 117U);
    assert(state != NULL);
    assert(lua_checkstack(state, 20));
    for (iteration = 0; iteration < 3; iteration++) {
        reader.calls = 0;
        lua_settop(state, 0);
        assert(lua_load(state, read_refusing_chunk, &reader, "=reader-refusal", "t") == LUA_ERRMEM);
        counts.refuse = 0;
        assert(lua_gettop(state) == 1);
        assert(strcmp(lua_tostring(state, -1), "not enough memory") == 0);
        lua_settop(state, 0);
        assert(luaL_loadstring(state, "return 61") == LUA_OK);
        assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
        assert(lua_tointeger(state, -1) == 61);
    }
    lua_close(state);
    assert(counts.bytes == 0 && counts.blocks == 0);
    puts("C API PASS: reader allocation refusal cleanup and recovery");
}

struct fixed_reader {
    const char *bytes;
    size_t size;
    int calls;
};

static const char *read_fixed_chunk(lua_State *state, void *data, size_t *size) {
    struct fixed_reader *reader = (struct fixed_reader *)data;
    (void)state;
    reader->calls++;
    *size = reader->size;
    return reader->calls == 1 ? reader->bytes : NULL;
}

static void test_fixed_binary_reader_count(lua_State *state) {
    /* The documented fixed-buffer reader returns all bytes in one stable
     * piece. Loading a complete binary must not request a redundant EOF read. */
    struct chunk_writer writer = {0};
    struct fixed_reader reader = {0};
    lua_settop(state, 0);
    assert(luaL_loadstring(state, "return 72") == LUA_OK);
    assert(lua_dump(state, write_chunk, &writer, 0) == 0);
    reader.bytes = writer.bytes;
    reader.size = writer.size;
    assert(lua_load(state, read_fixed_chunk, &reader, "=fixed-reader", "B") == LUA_OK);
    assert(reader.calls == 1);
    assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 72);
    lua_settop(state, 0);
    lua_gc(state, LUA_GCCOLLECT);
    free(writer.bytes);
    puts("C API PASS: fixed binary reader consumes one stable block");
}

static void test_binary_reader_failure_boundaries(lua_State *state) {
    /* Retry only genuine binary truncation. A known bad header or a text-only
     * mode must stop after the first piece; missing final bytes remain syntax
     * errors after EOF, and none of these outcomes makes the state unusable. */
    struct chunk_writer writer = {0};
    struct chunk_reader reader = {0};
    lua_settop(state, 0);
    assert(luaL_loadstring(state, "return 37") == LUA_OK);
    assert(lua_dump(state, write_chunk, &writer, 0) == 0);
    reader.bytes = writer.bytes;
    reader.size = writer.size;
    reader.piece = 1;
    reader.raise_after_piece = 1;
    assert(lua_load(state, read_chunk, &reader, "=binary-text-mode", "t") == LUA_ERRSYNTAX);
    assert(reader.calls == 1 && strstr(lua_tostring(state, -1), "binary"));
    lua_pop(state, 1);
    writer.bytes[4] = 0; /* Corrupt the real binary version, not its signature. */
    reader.position = reader.calls = 0;
    reader.piece = 5;
    assert(lua_load(state, read_chunk, &reader, "=binary-version", "b") == LUA_ERRSYNTAX);
    assert(reader.calls == 1 && strstr(lua_tostring(state, -1), "version"));
    lua_pop(state, 1);
    writer.bytes[4] = 0x55;
    reader.position = reader.calls = 0;
    reader.size--;
    reader.piece = 17;
    reader.raise_after_piece = 0;
    assert(lua_load(state, read_chunk, &reader, "=binary-truncated", "b") == LUA_ERRSYNTAX);
    assert(strstr(lua_tostring(state, -1), "truncated"));
    lua_settop(state, 0);
    assert(luaL_loadstring(state, "return 46") == LUA_OK);
    assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 46);
    free(writer.bytes);
    puts("C API PASS: binary reader mode malformed and truncated boundaries");
}

struct scripted_reader {
    const char *pieces[8];
    size_t sizes[8];
    int count;
    int calls;
    int raise_at;
};

static const char *read_scripted_chunk(lua_State *state, void *data,
                                       size_t *size) {
    struct scripted_reader *reader = (struct scripted_reader *)data;
    int index = reader->calls++;
    assert(!lua_isyieldable(state));
    if (reader->raise_at > 0 && index == reader->raise_at) {
        lua_pushliteral(state, "reader should not have been called again");
        lua_error(state);
    }
    if (index >= reader->count) {
        *size = 0;
        return NULL;
    }
    *size = reader->sizes[index];
    return reader->pieces[index];
}

static void test_reader_stops_at_definitive_syntax(lua_State *state) {
    /* A rejected punctuation token is complete in the first piece. Asking
     * for a later piece would run unrelated side effects and replace native
     * syntax rejection with the later reader's runtime error. */
    struct scripted_reader reader = {0};
    lua_settop(state, 0);
    reader.pieces[0] = ") ";
    reader.sizes[0] = 2;
    reader.count = 1;
    reader.raise_at = 1;
    assert(lua_load(state, read_scripted_chunk, &reader, "=early-token", "t") == LUA_ERRSYNTAX);
    assert(reader.calls == 1 && lua_gettop(state) == 1);
    puts("C API PASS: reader stops before unrelated syntax-error side effects");
}

static void test_reader_punctuation_prefetch(lua_State *state) {
    /* Native llex fetches its next current byte before returning a single
     * punctuation token. A reader failure at that exact boundary therefore
     * precedes the parser's later rejection of the punctuation itself. */
    struct scripted_reader reader = {0};
    lua_settop(state, 0);
    reader.pieces[0] = ")"; reader.sizes[0] = 1;
    reader.count = 1;
    reader.raise_at = 1;
    assert(lua_load(state, read_scripted_chunk, &reader, "=punctuation-prefetch", "t") == LUA_ERRRUN);
    assert(reader.calls == 2);
    assert(strstr(lua_tostring(state, -1), "should not have been called"));
    puts("C API PASS: reader preserves native punctuation prefetch errors");
}

static void test_reader_stops_at_invalid_escape(lua_State *state) {
    /* The shared lexer must reject an invalid escape in a supplied token
     * without observing artificial EOF or invoking the next failing read. */
    const char source[] = "return '\\q'";
    struct scripted_reader reader = {0};
    lua_settop(state, 0);
    reader.pieces[0] = source;
    reader.sizes[0] = sizeof(source) - 1;
    reader.count = 1;
    reader.raise_at = 1;
    assert(lua_load(state, read_scripted_chunk, &reader, "=early-escape", "t") == LUA_ERRSYNTAX);
    assert(reader.calls == 1);
    assert(strstr(lua_tostring(state, -1), "invalid escape sequence"));
    puts("C API PASS: reader invalid escape precedes later callback errors");
}

static void test_reader_keyword_boundaries(lua_State *state) {
    /* An unfinished keyword is not an actual EOF. Its real next piece must
     * complete the same token before the parser classifies the statement. */
    struct scripted_reader reader = {0};
    lua_settop(state, 0);
    reader.pieces[0] = "ret"; reader.sizes[0] = 3;
    reader.pieces[1] = "urn 23"; reader.sizes[1] = 6;
    reader.count = 2;
    assert(lua_load(state, read_scripted_chunk, &reader, "=split-keyword", "t") == LUA_OK);
    assert(reader.calls == 3);
    assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 23);
    puts("C API PASS: reader preserves split keyword tokens");
}

static void test_reader_number_boundaries(lua_State *state) {
    /* A split hexadecimal exponent must continue scanning the same numeral,
     * preserving its floating classification after the actual final EOF. */
    struct scripted_reader reader = {0};
    lua_settop(state, 0);
    reader.pieces[0] = "ret"; reader.sizes[0] = 3;
    reader.pieces[1] = "urn 0x"; reader.sizes[1] = 6;
    reader.pieces[2] = "1p+"; reader.sizes[2] = 3;
    reader.pieces[3] = "2"; reader.sizes[3] = 1;
    reader.count = 4;
    assert(lua_load(state, read_scripted_chunk, &reader, "=split-number", "t") == LUA_OK);
    assert(reader.calls == 5);
    assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
    assert(lua_tonumber(state, -1) == 4 && !lua_isinteger(state, -1));
    puts("C API PASS: reader preserves split numeral tokens");
}

static void test_reader_escape_boundaries(lua_State *state) {
    /* Refill while decoding escapes. Retained offsets and diagnostic spans
     * must survive managed-buffer relocation without snapshot reparsing. */
    struct scripted_reader reader = {0};
    lua_settop(state, 0);
    reader.pieces[0] = "return \"A\\"; reader.sizes[0] = 10;
    reader.pieces[1] = "x4"; reader.sizes[1] = 2;
    reader.pieces[2] = "2\\u{"; reader.sizes[2] = 4;
    reader.pieces[3] = "43}\""; reader.sizes[3] = 4;
    reader.count = 4;
    assert(lua_load(state, read_scripted_chunk, &reader, "=split-escape", "t") == LUA_OK);
    assert(reader.calls == 5);
    assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
    assert(strcmp(lua_tostring(state, -1), "ABC") == 0);
    puts("C API PASS: reader preserves split escape boundaries");
}

static void test_reader_delimiter_boundaries(lua_State *state) {
    /* Both long-comment delimiters cross a piece boundary. This exercises
     * real scanner lookahead, including the reader lifetime of older bytes. */
    struct scripted_reader reader = {0};
    lua_settop(state, 0);
    reader.pieces[0] = "--["; reader.sizes[0] = 3;
    reader.pieces[1] = "=[ comment ]"; reader.sizes[1] = 12;
    reader.pieces[2] = "=]"; reader.sizes[2] = 2;
    reader.pieces[3] = " return 23"; reader.sizes[3] = 10;
    reader.count = 4;
    assert(lua_load(state, read_scripted_chunk, &reader, "=split-comment", "t") == LUA_OK);
    assert(reader.calls == 5);
    assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 23);
    puts("C API PASS: reader preserves long-delimiter boundaries");
}

struct reentrant_reader {
    struct chunk_reader source;
    int nested_calls;
};

static const char *read_reentrant_chunk(lua_State *state, void *data,
                                        size_t *size) {
    struct reentrant_reader *reader = (struct reentrant_reader *)data;
    int top = lua_gettop(state);
    /* Compile and execute in this same actual universe while the outer
     * frontend waits below the C-owned reader checkpoint. */
    assert(luaL_loadstring(state, "return 37") == LUA_OK);
    assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 37);
    lua_pop(state, 1);
    assert(lua_gettop(state) == top);
    lua_gc(state, LUA_GCCOLLECT);
    reader->nested_calls++;
    return read_chunk(state, &reader->source, size);
}

static void test_reader_recursive_api_reentry(lua_State *state) {
    /* Each reader call reenters loading and the iterative execution portal.
     * The waiting frontend retains its own tokens/input and shared roots. */
    const char source[] = "return function(x) return x + 9 end";
    struct reentrant_reader reader = {0};
    lua_settop(state, 0);
    reader.source.bytes = source;
    reader.source.size = sizeof(source) - 1;
    reader.source.piece = 3;
    assert(lua_load(state, read_reentrant_chunk, &reader, "=recursive-reader", "t") == LUA_OK);
    assert(reader.nested_calls == reader.source.calls && reader.nested_calls > 2);
    assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
    lua_pushinteger(state, 33);
    assert(lua_pcall(state, 1, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 42);
    puts("C API PASS: reader recursive loading execution and collection");
}

struct recursive_source_reader {
    int depth;
    int phase;
    int *calls;
};

static const char *read_recursive_source(lua_State *state, void *data,
                                         size_t *size) {
    struct recursive_source_reader *reader =
        (struct recursive_source_reader *)data;
    (*reader->calls)++;
    if (reader->phase++ != 0) {
        *size = 0;
        return NULL;
    }
    if (reader->depth > 0) {
        struct recursive_source_reader child =
            {reader->depth - 1, 0, reader->calls};
        assert(lua_load(state, read_recursive_source, &child, "=nested-source", "t") == LUA_OK);
        assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
        assert(lua_tointeger(state, -1) == 31);
        lua_pop(state, 1);
    }
    *size = 9;
    return "return 31";
}

static void test_reader_nested_guarded_sources(lua_State *state) {
    /* Explicit C-host recursion creates distinct source owners and live
     * reader checkpoints. Each one must finish its own parser and preserve
     * its parent's retained bytes, stack window and caller-owned context. */
    int calls = 0;
    struct recursive_source_reader reader = {8, 0, &calls};
    lua_settop(state, 0);
    assert(lua_load(state, read_recursive_source, &reader, "=nested-source-root", "t") == LUA_OK);
    assert(calls == 18);
    assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 31);
    puts("C API PASS: nested guarded readers retain independent source owners");
}

static void test_binary_reader_every_split(lua_State *state) {
    /* Execute the same actual binary after every possible two-piece split.
     * One decoder must consume both pieces exactly once, without an EOF read
     * or repeated prefix reconstruction of partial canonical graphs. */
    struct chunk_writer writer = {0};
    size_t split;
    lua_settop(state, 0);
    assert(luaL_loadstring(state, "return 64") == LUA_OK);
    assert(lua_dump(state, write_chunk, &writer, 0) == 0);
    for (split = 1; split < writer.size; split++) {
        struct scripted_reader reader = {0};
        lua_settop(state, 1);
        reader.pieces[0] = writer.bytes; reader.sizes[0] = split;
        reader.pieces[1] = writer.bytes + split;
        reader.sizes[1] = writer.size - split;
        reader.count = 2;
        assert(lua_load(state, read_scripted_chunk, &reader, "=binary-split", "b") == LUA_OK);
        assert(reader.calls == 2);
        assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
        assert(lua_tointeger(state, -1) == 64);
    }
    free(writer.bytes);
    puts("C API PASS: binary reader preserves every split and exact end count");
}

static void test_fixed_binary_piece_requirements(lua_State *state) {
    /* B mode permits ordinary header reads across pieces but cannot assemble
     * a fixed code array from separate tiny blocks. Reject that split at the
     * actual block request instead of consuming the entire later stream. */
    struct chunk_writer writer = {0};
    struct scripted_reader reader = {0};
    struct chunk_reader tiny = {0};
    lua_settop(state, 0);
    assert(luaL_loadstring(state, "return 86") == LUA_OK);
    assert(lua_dump(state, write_chunk, &writer, 0) == 0);
    reader.pieces[0] = writer.bytes; reader.sizes[0] = 1;
    reader.pieces[1] = writer.bytes + 1;
    reader.sizes[1] = writer.size - 1;
    reader.count = 2;
    assert(lua_load(state, read_scripted_chunk, &reader, "=fixed-header-split", "B") == LUA_OK);
    assert(reader.calls == 2);
    assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 86);
    tiny.bytes = writer.bytes; tiny.size = writer.size; tiny.piece = 1;
    assert(lua_load(state, read_chunk, &tiny, "=fixed-code-split", "B") == LUA_ERRSYNTAX);
    assert(tiny.calls > 1 && tiny.calls < (int)writer.size);
    assert(strstr(lua_tostring(state, -1), "truncated fixed buffer"));
    lua_settop(state, 0);
    lua_gc(state, LUA_GCCOLLECT);
    free(writer.bytes);
    puts("C API PASS: fixed binary reader enforces actual piece boundaries");
}

static void test_partial_binary_reader_error_cleanup(lua_State *state) {
    /* Fail after almost the whole real graph has been decoded. Repeating
     * the failure must release partial code/input and preserve the actual
     * reader error instead of converting it to a truncation observation. */
    struct chunk_writer writer = {0};
    int attempt;
    lua_settop(state, 0);
    assert(luaL_loadstring(state, "return function(x) return x+1 end") == LUA_OK);
    assert(lua_dump(state, write_chunk, &writer, 0) == 0);
    for (attempt = 0; attempt < 3; attempt++) {
        struct scripted_reader reader = {0};
        lua_settop(state, 1);
        reader.pieces[0] = writer.bytes;
        reader.sizes[0] = writer.size - 1;
        reader.count = 1;
        reader.raise_at = 1;
        assert(lua_load(state, read_scripted_chunk, &reader, "=partial-binary-error", "b") == LUA_ERRRUN);
        assert(reader.calls == 2);
        assert(strstr(lua_tostring(state, -1), "should not have been called"));
    }
    free(writer.bytes);
    puts("C API PASS: partial binary reader errors preserve cleanup and recovery");
}

static const char *read_many_single_bytes(lua_State *state, void *data,
                                         size_t *size) {
    size_t *position = (size_t *)data;
    static const char space = ' ';
    (void)state;
    if ((*position)++ < 16384) {
        *size = 1;
        return &space;
    }
    if (*position == 16385) {
        *size = 9;
        return "return 57";
    }
    *size = 0;
    return NULL;
}

static void test_reader_avoids_prefix_reconstruction(void) {
    /* Thousands of pieces still describe one simple chunk. A broad measured
     * allocation bound rejects recreating a parser/model for each prefix;
     * it does not require C and Ada to share layouts or exact byte counts. */
    struct allocation_counts counts = {0};
    lua_State *state = lua_newstate(counted_allocator, &counts, 733U);
    size_t position = 0, before;
    assert(state != NULL);
    before = counts.growths;
    assert(lua_load(state, read_many_single_bytes, &position, "=many-pieces", "t") == LUA_OK);
    assert(position == 16386);
    assert(counts.growths - before < 512);
    assert(lua_pcall(state, 0, 1, 0) == LUA_OK);
    assert(lua_tointeger(state, -1) == 57);
    lua_close(state);
    assert(counts.bytes == 0 && counts.blocks == 0);
    puts("C API PASS: many reader pieces avoid prefix reconstruction");
}

static void test_load_dump_contract(lua_State *state) {
    test_reader_piece_lifetime(state);
    test_reader_preserves_stack(state);
    test_reader_error_identity(state);
    test_reader_end_conditions(state);
    test_reader_yield_barrier(state);
    test_reader_inherits_message_handler(state);
    test_reader_syntax_and_mode_errors(state);
    test_dump_round_trip(state);
    test_dump_writer_stack_and_terminal(state);
    test_dump_writer_stops_on_status(state);
    test_dump_terminal_status(state);
    test_dump_writer_error_identity(state);
    test_reader_allocation_refusal();
    test_fixed_binary_reader_count(state);
    test_binary_reader_failure_boundaries(state);
    test_reader_stops_at_definitive_syntax(state);
    test_reader_punctuation_prefetch(state);
    test_reader_stops_at_invalid_escape(state);
    test_reader_keyword_boundaries(state);
    test_reader_number_boundaries(state);
    test_reader_escape_boundaries(state);
    test_reader_delimiter_boundaries(state);
    test_reader_recursive_api_reentry(state);
    test_reader_nested_guarded_sources(state);
    test_binary_reader_every_split(state);
    test_fixed_binary_piece_requirements(state);
    test_partial_binary_reader_error_cleanup(state);
    test_reader_avoids_prefix_reconstruction();
}

#endif
