-- Match pinned all.lua's observable return check without running its other
-- files. Execute the immutable source exactly once in this measured state.
assert(dofile('events.lua') == 12)
print('events return witness OK')
