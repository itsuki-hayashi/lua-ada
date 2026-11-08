-- These public refusal cases require an actual native/Ada T allocator driver.
-- Initialize the real C control surface before warming the measured producer;
-- a fresh Ada-host world may reserve its C reset metadata on that first entry.
assert(T and type(T.alloccount)=='function','real allocation control required')

-- Refused_Find: The unchanged memerr scalar pattern succeeds under permanent refusal.
do
  collectgarbage('stop')
  local s,p='not enough memory','not enough memory'
  local f,control=string.find,T.alloccount
  control();assert(pcall(f,s,p));control(0)
  local ok,a,b=pcall(f,s,p);control()
  assert(ok and a==1 and b==#s)
end

-- Refused_Length: A warmed one-integer producer needs no fresh output container.
do
  collectgarbage('stop')
  local f,s,control=string.len,'existing subject',T.alloccount
  control();assert(pcall(f,s));control(0)
  local ok,n=pcall(f,s);control();assert(ok and n==#s)
end

-- Refused_Zero: A warmed zero-result producer still returns its protected true status.
do
  collectgarbage('stop')
  local f,s,control=string.byte,'',T.alloccount
  control();assert(pcall(f,s));control(0)
  local ok,extra=pcall(f,s);control();assert(ok and extra==nil)
end

-- Refused_Error: The preexisting protected error owner remains usable with no growth.
do
  collectgarbage('stop')
  local marker={};local f,control=error,T.alloccount
  control();assert(not pcall(f,marker,0));control(0)
  local ok,e=pcall(f,marker,0);control();assert(not ok and e==marker)
end

print('string refusal phases OK')
