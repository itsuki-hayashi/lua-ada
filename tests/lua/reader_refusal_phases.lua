-- Real provider refusal introduced inside the protected Lua reader.
assert(T and type(T.alloccount)=='function')

-- Refused_Cold_Reader: A cold completion preserves load's protected memory tuple.
do
  local control=T.alloccount;control()
  local reader=function()control(0);return 'return 37' end
  local ok,f,e=pcall(load,reader)
  control()
  assert(ok and f==nil and e=='not enough memory')
  assert(assert(load('return 41'))()==41)
end

-- Refused_Warm_Reader: Reusing a reader cannot move refusal outside its parser.
do
  local control=T.alloccount;control()
  local count,inject=0,false
  local reader=function()
    count=count+1
    if count==1 then
      if inject then control(0)end
      return 'return 43'
    end
  end
  assert(assert(load(reader))()==43)
  count=0;inject=true
  local ok,f,e=pcall(load,reader)
  control()
  assert(ok and f==nil and e=='not enough memory')
end

-- Refused_Partial_Source: A retained parser prefix is released after refusal.
do
  local control=T.alloccount;control()
  local count=0
  local reader=function()
    count=count+1
    if count==1 then return 'local value = ' end
    control(0);return '47;return value'
  end
  local ok,f,e=pcall(load,reader)
  control()
  assert(ok and f==nil and e=='not enough memory' and count==2)
end

-- Refused_Binary_Reader: Binary decoding retains the same protected error policy.
do
  local control=T.alloccount;control()
  local source=string.dump(function()return 53 end)
  local reader=function()control(0);return source end
  local ok,f,e=pcall(load,reader,nil,'b')
  control()
  assert(ok and f==nil and e=='not enough memory')
end

print('reader refusal phases OK')
