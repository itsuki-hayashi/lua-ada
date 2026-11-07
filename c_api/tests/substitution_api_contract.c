/* Public luaL_addgsub and luaL_gsub contract regressions for C99 consumers.
 * Copyright (c) 2026 Lua Ada contributors. MIT; see ../../LICENSE.
 *
 * Each case below is an independently named scenario run in its own fresh
 * counted_allocator state. The same source compiles as a standalone C99
 * consumer (define nothing) or as the reusable bridge target behind
 * lua_ada_test_substitution(), which is selected by defining
 * LUA_ADA_SUBSTITUTION_CONTRACT_LIBRARY before including this file.
 *
 * Public functions used: lua_newstate, luaL_openlibs, lua_pushlstring,
 * lua_pushstring, lua_pushvalue, lua_pushcfunction, lua_pcall, lua_tolstring,
 * lua_tostring, lua_rawlen, lua_gettop, lua_pop, lua_close, luaL_checkstring,
 * luaL_error, luaL_buffinit, luaL_addstring, luaL_pushresult, luaL_addgsub,
 * and luaL_gsub. Only these documented entry points are called.
 *
 * Native contract (pinned Lua 5.5.1, lauxlib.c, luaL_addgsub and luaL_gsub):
 *   - Matching is LITERAL substring search (strstr on the C string 'p'). Lua
 *     pattern syntax such as '%d', '.', '^', '$', '[a]' and '*' has no special
 *     meaning, and the replacement 'r' is copied verbatim (no '%' escapes).
 *   - Scanning resumes after each match, so matches never overlap. The
 *     replacement text is written to the buffer and is never searched again.
 *   - The subject and pattern are C strings, so any bytes after the first NUL
 *     are invisible to these routines. A Lua string with an embedded NUL is
 *     therefore seen only up to that NUL when its lua_tolstring pointer is
 *     passed in.
 *   - luaL_gsub pushes exactly one string and returns lua_tostring of it. The
 *     returned pointer stays valid while that string is on the stack.
 *   - Persistent allocation refusal must deliver LUA_ERRMEM. Calls that may
 *     allocate under a refusing allocator therefore run under lua_pcall.
 *   - An EMPTY pattern is NOT tested. strstr(s, "") returns s at every step
 *     without advancing, so the pinned loop never terminates. No case below
 *     passes an empty pattern, and none may be added.
 *
 * Allocation policy: the counted allocator is the only source of truth for
 * heap use. Tests never assert exact allocation counts or internal buffer
 * capacities. Refusals are injected only into growth requests
 * (consumer_allocator.h), and a memory error is accepted only when it has
 * the form lauxlib raises for a refused growth.
 *
 * Expected stack discipline: every luaL_gsub call leaves exactly one result
 * string above the caller's values, and every case leaves the stack empty
 * before lua_close. run_case checks that the counted allocator reports zero
 * live bytes and zero blocks after lua_close. */
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "consumer_allocator.h"

#ifdef NDEBUG
#error "substitution_api_contract.c relies on assert() checks; do not define NDEBUG"
#endif

/* Per-case allocator state. run_case resets it before lua_newstate. */
static struct allocation_counts counts;

/* Seed passed to lua_newstate; any value is valid, fixed for reproducibility. */
#define SUBST_SEED 419U

/* Length of the large subject. The result of the large-growth case is twice
 * this many bytes after the 4-byte prefix, so the buffer must grow far past
 * LUAL_BUFFERSIZE. */
#define LARGE_LEN ((size_t)30000)


/* ---------------------------------------------------------------------------
 * Helpers
 * ------------------------------------------------------------------------ */

/* Assert that the value at stack index 'idx' is a string whose C view equals
 * 'want'. A NULL or non-string value fails the check. */
static void expect_result(lua_State *L, int idx, const char *want) {
    const char *got;
    assert(lua_type(L, idx) == LUA_TSTRING);
    got = lua_tostring(L, idx);
    assert(got != NULL && strcmp(got, want) == 0);
}

/* Run luaL_gsub on C strings and check the result. The call must leave
 * exactly one new string above the caller's values, which is then popped. */
static void expect_gsub(lua_State *L, const char *s, const char *p,
                        const char *r, const char *want) {
    int base = lua_gettop(L);
    const char *got = luaL_gsub(L, s, p, r);
    assert(got != NULL);
    assert(lua_gettop(L) == base + 1);
    assert(strcmp(got, want) == 0);
    expect_result(L, -1, want);
    lua_pop(L, 1);
}

/* The native persistent-refusal counterpart returns this exact class.
 * A catchable ordinary runtime error must not disguise allocator refusal. */
static void check_memory_error(lua_State *L, int status) {
    assert(status == LUA_ERRMEM);
    assert(lua_type(L, -1) == LUA_TSTRING);
}

/* C function used through lua_pcall: luaL_gsub(subject, pattern, replacement)
 * with all three arguments checked. It returns the one result string. */
static int gsub_callback(lua_State *L) {
    const char *s = luaL_checkstring(L, 1);
    const char *p = luaL_checkstring(L, 2);
    const char *r = luaL_checkstring(L, 3);
    luaL_gsub(L, s, p, r);
    return 1;
}

static int gsub_refusing_callback(lua_State *L) {
    /* Enter the actual callback first: outer pcall metadata allocation must
     * not be mistaken for a refused substitution buffer growth. */
    counts.refuse = 1;
    return gsub_callback(L);
}

/* C function that substitutes first, then raises an error. The substitution
 * result is left on the stack when luaL_error longjmps, so the protected call
 * must discard it. */
static int gsub_then_error(lua_State *L) {
    const char *s = luaL_checkstring(L, 1);
    luaL_gsub(L, s, "x", "y");
    return luaL_error(L, "after gsub: %s", "done");
}

/* ---------------------------------------------------------------------------
 * Cases. Each body runs in a fresh state with the libraries opened. It must
 * leave the stack as it found it, so run_case can verify balance at close.
 * ------------------------------------------------------------------------ */

/* Setup: subjects and patterns containing Lua pattern metacharacters.
 * Action: luaL_gsub with '[a]', '.y*', '%d' and '^$' as patterns.
 * Expected: each pattern is matched literally, so only the exact bytes are
 * replaced and the metacharacters in the subject are kept.
 * Regression: a pattern-engine interpretation of the 'p' argument. */
static void literal_metachars(lua_State *L) {
    expect_gsub(L, "x.y*z[a]^$", "[a]", "-", "x.y*z-^$");
    expect_gsub(L, "x.y*z[a]^$", ".y*", "-", "x-z[a]^$");
    expect_gsub(L, "100%d 100%d", "%d", "#", "100# 100#");
    expect_gsub(L, "x^$y", "^$", "-", "x-y");
}

/* Setup: "aaaaa" and "aaaa" with the pattern "aa". Action: luaL_gsub.
 * Expected: matches are taken left to right without overlap, so "aaaaa"
 * becomes "bba" (two matches and one unmatched 'a').
 * Regression: restarting the search one byte after each match. */
static void nonoverlap_matches(lua_State *L) {
    expect_gsub(L, "aaaaa", "aa", "b", "bba");
    expect_gsub(L, "aaaa", "aa", "b", "bb");
}

/* Setup: replacements that contain the pattern itself.
 * Action: luaL_gsub with pattern "a" and replacement "aaa" in "ab", and
 * pattern "x" and replacement "xx" in "xx".
 * Expected: each match is replaced exactly once. "ab" becomes "aaab", and
 * "xx" becomes "xxxx". The replacement text is never searched again.
 * Regression: re-scanning replacement output, which would loop or over-grow. */
static void replacement_not_rescanned(lua_State *L) {
    expect_gsub(L, "ab", "a", "aaa", "aaab");
    expect_gsub(L, "xx", "x", "xx", "xxxx");
}

/* Setup: subjects where the replacement is shorter than the pattern.
 * Action: luaL_gsub with "long" -> "s", and "abc" -> "" in "abcabc".
 * Expected: "long-marker-long" becomes "s-marker-s", and "abcabc" becomes "".
 * Regression: a buffer or length error when the output is shorter than input. */
static void shrinking_replacement(lua_State *L) {
    expect_gsub(L, "long-marker-long", "long", "s", "s-marker-s");
    expect_gsub(L, "abcabc", "abc", "", "");
}

/* Setup: a one-byte pattern with a replacement much longer than the pattern.
 * Action: luaL_gsub with "-" -> "<<<>>>" and "b" -> ten 'b' characters.
 * Expected: "a-b" becomes "a<<<>>>b", and "ab" becomes "a" followed by ten
 * 'b' characters, so output longer than input is written in full.
 * Regression: truncated output when the replacement grows the result. */
static void growing_replacement(lua_State *L) {
    expect_gsub(L, "a-b", "-", "<<<>>>", "a<<<>>>b");
    expect_gsub(L, "ab", "b", "bbbbbbbbbb", "abbbbbbbbbb");
}

/* Setup: subjects with separators. Action: luaL_gsub with an empty
 * replacement, the pattern being the separator.
 * Expected: separators are removed, and adjacent separators leave nothing.
 * "a,b,,c" becomes "abc", and ",," becomes "".
 * Regression: treating an empty replacement as "no replacement" or as an
 * error. */
static void empty_replacement(lua_State *L) {
    expect_gsub(L, "a,b,,c", ",", "", "abc");
    expect_gsub(L, ",,", ",", "", "");
}

/* Setup: a subject with no occurrence of the pattern, and a pattern longer
 * than the subject. Action: luaL_gsub.
 * Expected: the result is a copy of the subject, unchanged.
 * Regression: an empty or altered result when nothing matches. */
static void no_match(lua_State *L) {
    expect_gsub(L, "hello", "xyz", "Q", "hello");
    expect_gsub(L, "ab", "abc", "Q", "ab");
}

/* Setup: an empty subject with a non-empty pattern. Action: luaL_gsub.
 * Expected: the result is the empty string. The pattern is non-empty, so
 * the loop terminates after one failed search.
 * Regression: reading past the empty subject. */
static void empty_subject(lua_State *L) {
    expect_gsub(L, "", "x", "y", "");
    expect_gsub(L, "", "longerpattern", "y", "");
}

/* Setup: matches at the start, in the middle, and at the end of the subject.
 * Action: luaL_gsub on "ab-mid-ab", "start-end" and "mid-end".
 * Expected: "ab-mid-ab" becomes "Q-mid-Q", "start-end" becomes "S-end", and
 * "mid-end" becomes "mid-E". Each boundary match is replaced.
 * Regression: skipping a match that touches the subject's first or last byte. */
static void prefix_suffix(lua_State *L) {
    expect_gsub(L, "ab-mid-ab", "ab", "Q", "Q-mid-Q");
    expect_gsub(L, "start-end", "start", "S", "S-end");
    expect_gsub(L, "mid-end", "end", "E", "mid-E");
}

/* Setup: a Lua string "ab\0cd" with an embedded NUL, length 5. Action:
 * luaL_gsub on its lua_tolstring pointer with pattern "a" and replacement
 * "X".
 * Expected: the C API sees only "ab", so the result is "Xb" with C length 2.
 * The bytes "cd" after the NUL are not part of the substituted string, and
 * the original Lua string keeps its length of 5.
 * Regression: reading the Lua length in place of the NUL-terminated C view. */
static void embedded_nul_subject(lua_State *L) {
    const char *s;
    const char *got;
    int base = lua_gettop(L);
    lua_pushlstring(L, "ab\0cd", 5);
    assert(lua_rawlen(L, -1) == 5);
    s = lua_tostring(L, -1);
    got = luaL_gsub(L, s, "a", "X");
    assert(lua_gettop(L) == base + 2);
    assert(strcmp(got, "Xb") == 0);
    assert(lua_rawlen(L, -1) == 2);
    lua_pop(L, 2);
}

/* Setup: a Lua string "a\0Z" with an embedded NUL, length 3. Action:
 * luaL_gsub on "banana" with the NUL-containing string used as the pattern
 * (its C view is "a") and replacement "_".
 * Expected: the pattern is "a", so the result is "b_n_n_".
 * Regression: passing the pattern's full Lua length instead of its C view. */
static void embedded_nul_pattern(lua_State *L) {
    const char *p;
    int base = lua_gettop(L);
    lua_pushlstring(L, "a\0Z", 3);
    p = lua_tostring(L, -1);
    expect_gsub(L, "banana", p, "_", "b_n_n_");
    assert(lua_gettop(L) == base + 1);
    lua_pop(L, 1);
}

/* Setup: a luaL_Buffer that already holds "<" and then receives text.
 * Action: luaL_addgsub on "a-b-c" with "-" -> "+"; luaL_addstring "|";
 * a second luaL_addgsub on the same buffer, "x-y" with "-" -> ""; then
 * luaL_addstring ">"; then luaL_pushresult.
 * Expected: the single result is "<a+b+c|xy>". The buffer is reused across
 * two substitutions without losing its earlier content.
 * Regression: a substitution that resets the buffer or drops appended text.
 * Scratch-buffer placement and capacity are not assumed. */
static void buffer_append_reuse(lua_State *L) {
    luaL_Buffer B;
    int base = lua_gettop(L);
    luaL_buffinit(L, &B);
    luaL_addstring(&B, "<");
    luaL_addgsub(&B, "a-b-c", "-", "+");
    luaL_addstring(&B, "|");
    luaL_addgsub(&B, "x-y", "-", "");
    luaL_addstring(&B, ">");
    luaL_pushresult(&B);
    assert(lua_gettop(L) == base + 1);
    expect_result(L, -1, "<a+b+c|xy>");
    lua_pop(L, 1);
}

/* Setup: "HEAD" followed by LARGE_LEN bytes of 'a', as a C string. Action:
 * luaL_gsub with pattern "a" and replacement "bb".
 * Expected: the result is 4 + 2 * LARGE_LEN bytes long. Its first eight bytes
 * are "HEADbbbb", and every 'a' from the subject appears as "bb" in order.
 * Regression: a truncated or misplaced prefix when the internal buffer grows
 * far beyond its initial storage. */
static void large_growth_prefix(lua_State *L) {
    char *subject;
    const char *got;
    size_t got_len = 0;
    size_t i;
    int base = lua_gettop(L);
    subject = malloc(LARGE_LEN + 5);
    assert(subject != NULL);
    memcpy(subject, "HEAD", 4);
    memset(subject + 4, 'a', LARGE_LEN);
    subject[4 + LARGE_LEN] = '\0';
    got = luaL_gsub(L, subject, "a", "bb");
    assert(lua_gettop(L) == base + 1);
    got_len = lua_rawlen(L, -1);
    assert(got_len == 4 + 2 * LARGE_LEN);
    assert(strncmp(got, "HEADbbbb", 8) == 0);
    for (i = 0; i < LARGE_LEN; i++) {
        assert(got[4 + 2 * i] == 'b');
        assert(got[5 + 2 * i] == 'b');
    }
    lua_pop(L, 1);
    free(subject);
}

/* Setup: a C function gsub_callback is pushed with three string arguments.
 * Action: call it under lua_pcall with 3 arguments and 1 result.
 * Expected: status LUA_OK, and the stack holds exactly the result "a+b+c"
 * above the base. The caller's arguments are consumed.
 * Regression: an extra or missing value after a protected C call. */
static void callback_result(lua_State *L) {
    int base = lua_gettop(L);
    int status;
    lua_pushcfunction(L, gsub_callback);
    lua_pushstring(L, "a-b-c");
    lua_pushstring(L, "-");
    lua_pushstring(L, "+");
    status = lua_pcall(L, 3, 1, 0);
    assert(status == LUA_OK);
    assert(lua_gettop(L) == base + 1);
    expect_result(L, -1, "a+b+c");
    lua_pop(L, 1);
}

/* Setup: gsub_then_error runs luaL_gsub on "xax", then calls luaL_error.
 * Action: call it under lua_pcall with 1 argument and 1 result.
 * Expected: status LUA_ERRRUN. The error string contains "after gsub: done".
 * The discarded substitution result is removed, so only the error object
 * remains above the base. The error text is checked with strstr because
 * luaL_error may prefix a location.
 * Regression: a substitution result left on the stack after a longjmp. */
static void callback_error_cleanup(lua_State *L) {
    int base = lua_gettop(L);
    int status;
    lua_pushcfunction(L, gsub_then_error);
    lua_pushstring(L, "xax");
    status = lua_pcall(L, 1, 1, 0);
    assert(status == LUA_ERRRUN);
    assert(lua_gettop(L) == base + 1);
    assert(lua_type(L, -1) == LUA_TSTRING);
    assert(strstr(lua_tostring(L, -1), "after gsub: done") != NULL);
    lua_pop(L, 1);
}

/* Setup: a 30000-byte subject of 'a' characters is pushed as a Lua string
 * before allocation is refused. Action: with growth refused, call
 * gsub_callback under lua_pcall to substitute "a" with "bb". Then allow
 * growth again and repeat the identical call.
 * Expected: the refused call returns LUA_ERRMEM, the allocator
 * was asked for growth during that call, and the stack keeps only the error
 * object. The recovery call then succeeds with 2 * LARGE_LEN bytes of 'b'.
 * Regression: a memory failure that leaves the state unusable or leaves
 * stale values on the stack. */
static void allocator_refusal_recovery(lua_State *L) {
    int base = lua_gettop(L);
    int status;
    size_t grown_before;
    char *subject = malloc(LARGE_LEN);
    size_t i;
    assert(subject != NULL);
    memset(subject, 'a', LARGE_LEN);
    lua_pushlstring(L, subject, LARGE_LEN);
    free(subject);
    lua_pushcfunction(L, gsub_refusing_callback);
    lua_pushvalue(L, base + 1);
    lua_pushstring(L, "a");
    lua_pushstring(L, "bb");

    grown_before = counts.growths;
    status = lua_pcall(L, 3, 1, 0);
    counts.refuse = 0;
    assert(status != LUA_OK);
    assert(counts.growths > grown_before);
    check_memory_error(L, status);
    assert(lua_gettop(L) == base + 2);
    lua_pop(L, 1);

    lua_pushcfunction(L, gsub_callback);
    lua_pushvalue(L, base + 1);
    lua_pushstring(L, "a");
    lua_pushstring(L, "bb");
    status = lua_pcall(L, 3, 1, 0);
    assert(status == LUA_OK);
    assert(lua_gettop(L) == base + 2);
    assert(lua_rawlen(L, -1) == 2 * LARGE_LEN);
    {
        const char *got = lua_tostring(L, -1);
        for (i = 0; i < 2 * LARGE_LEN; i++) assert(got[i] == 'b');
    }
    lua_pop(L, 2);
}

/* ---------------------------------------------------------------------------
 * Driver. The table below is the only list of cases; the bridge and the
 * standalone main both iterate over it.
 * ------------------------------------------------------------------------ */

typedef void (*substitution_case)(lua_State *L);

static const struct {
    const char *name;
    substitution_case body;
} cases[] = {
    {"literal-metachars", literal_metachars},
    {"nonoverlap-matches", nonoverlap_matches},
    {"replacement-not-rescanned", replacement_not_rescanned},
    {"shrinking-replacement", shrinking_replacement},
    {"growing-replacement", growing_replacement},
    {"empty-replacement", empty_replacement},
    {"no-match", no_match},
    {"empty-subject", empty_subject},
    {"prefix-suffix", prefix_suffix},
    {"embedded-nul-subject", embedded_nul_subject},
    {"embedded-nul-pattern", embedded_nul_pattern},
    {"buffer-append-reuse", buffer_append_reuse},
    {"large-growth-prefix", large_growth_prefix},
    {"callback-result", callback_result},
    {"callback-error-cleanup", callback_error_cleanup},
    {"allocator-refusal-recovery", allocator_refusal_recovery}
};

#define SUBSTITUTION_CASE_COUNT (sizeof cases / sizeof cases[0])

/* Create a fresh counted state, open the libraries, run one case, verify that
 * the stack is empty, then close the state and verify the counted allocator
 * reports no live bytes or blocks. Returns 1 when all checks pass. */
static int run_case(substitution_case body) {
    lua_State *L;
    memset(&counts, 0, sizeof counts);
    L = lua_newstate(counted_allocator, &counts, SUBST_SEED);
    assert(L != NULL);
    luaL_openlibs(L);
    assert(lua_checkstack(L, 16));
    body(L);
    assert(lua_gettop(L) == 0);
    counts.refuse = 0;
    counts.fail_after = 0;
    lua_close(L);
    assert(counts.bytes == 0 && counts.blocks == 0);
    return 1;
}

/* Reusable AUnit entry point. Pass an index below SUBSTITUTION_CASE_COUNT and
 * the function returns 1 on success; any failed check aborts via assert. */
int lua_ada_test_substitution(unsigned which) {
    assert(which < SUBSTITUTION_CASE_COUNT);
    return run_case(cases[which].body);
}

#ifndef LUA_ADA_SUBSTITUTION_CONTRACT_LIBRARY
int main(void) {
    unsigned i;
    for (i = 0; i < SUBSTITUTION_CASE_COUNT; i++) {
        assert(lua_ada_test_substitution(i));
        printf("PASS: substitution-%s\n", cases[i].name);
        fflush(stdout);
    }
    puts("PASS: public luaL_addgsub and luaL_gsub contract");
    return 0;
}
#endif
