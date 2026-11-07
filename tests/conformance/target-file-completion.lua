-- Run one remaining primary using the entry operation in pinned all.lua.
-- This wrapper adds completion observations; the original source is immutable.
-- In particular, an OK printed before a return/yield is not a terminal witness.
local name, path = ...
local entries = {
  ['api.lua'] = 'dump', ['attrib.lua'] = 'dump',
  ['big.lua'] = 'coroutine', ['calls.lua'] = 'dump',
  ['code.lua'] = 'strip', ['cstack.lua'] = 'dump',
  ['db.lua'] = 'dump', ['errors.lua'] = 'dump',
  ['literals.lua'] = 'direct', ['locals.lua'] = 'dump',
  ['main.lua'] = 'dump', ['memerr.lua'] = 'dump',
  ['nextvar.lua'] = 'dump', ['sort.lua'] = 'strip',
  ['strings.lua'] = 'direct', ['vararg.lua'] = 'dump',
  ['verybig.lua'] = 'strip',
}
local entry = assert(entries[name], 'unknown target completion source')
assert(type(path) == 'string')
assert(_soft == nil and _port == nil and _U == nil and _nomsg == nil)
-- Retain primitives before source execution: tests deliberately replace globals
-- and debug hooks. Do not install substitute assertions or catch their errors.
local check, emit, pack, kind, numberkind =
  assert, print, table.pack, type, math.type
local absent = T == nil and
  (name == 'api.lua' or name == 'code.lua' or name == 'memerr.lua')
local chunk = check(loadfile(path))
if entry == 'dump' or entry == 'strip' then
  chunk = check(load(string.dump(chunk, entry == 'strip')))
end
if entry == 'coroutine' then
  -- all.lua resumes the large-table test twice. Status and arity distinguish
  -- the intended yield from an early return, and final death from another yield.
  local co = coroutine.create(chunk)
  local first = pack(coroutine.resume(co))
  check(first.n == 2 and first[1] and first[2] == 'b')
  check(coroutine.status(co) == 'suspended')
  emit('target file phase big.lua: yielded b')
  local last = pack(coroutine.resume(co))
  check(last.n == 2 and last[1] and last[2] == 'a')
  check(coroutine.status(co) == 'dead')
  emit('target file phase big.lua: returned a')
else
  local result = pack(chunk())
  if name == 'calls.lua' then
    check(result.n == 1 and kind(result[1]) == 'function')
    check(result[1] == deep and deep)
    _G.deep = nil  -- all.lua clears its exported recursion witness too.
    emit('target file phase calls.lua: returned deep')
  elseif name == 'attrib.lua' then
    check(result.n == 1 and result[1] == 27)
    check(numberkind(result[1]) == 'integer')
    emit('target file phase attrib.lua: returned 27')
  elseif name == 'locals.lua' then
    check(result.n == 2 and result[1] == 5)
    check(numberkind(result[1]) == 'integer' and kind(result[2]) == 'function')
    emit('target file phase locals.lua: returned 5')
  elseif name == 'verybig.lua' then
    check(result.n == 1 and result[1] == 10)
    check(numberkind(result[1]) == 'integer')
    collectgarbage()  -- match all.lua's post-return collection.
    emit('target file phase verybig.lua: returned 10')
  else
    -- An implicit return produces zero values, which differs from one nil.
    -- This also checks the original T-absent early-return branch exactly.
    check(result.n == 0)
  end
end
if absent then
  -- This only observes the original early return. Its omitted body still needs
  -- instrumented evidence or independently reviewed target-only exclusions.
  emit('target file completion ' .. name .. ': T absent')
else
  emit('target file completion ' .. name .. ': complete')
end
