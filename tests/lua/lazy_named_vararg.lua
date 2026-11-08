local cases={
  function()
    local function f(keys,t,...v)
      for _,k in pairs(keys)do assert(t[k]==v[k])end
      assert(t.n==v.n)
      return ...
    end
    local t=table.pack(10,20,30)
    local keys={-1,0,1,3,4,1.0,1.1,'n',print,'k','1'}
    f(keys,t,10,20,30)
    local before=collectgarbage('count')
    f(keys,t,10,20,30)
    assert(before==collectgarbage('count'))
  end,
  function()
    local function f(...v)
      local n,x=debug.getlocal(1,1)
      assert(n=='v' and x==nil)
      return v[1],v.n
    end
    local a,n=f(17,nil,31)
    assert(a==17 and n==3)
  end,
  function()
    local function f(...v)return v end
    local a,b=f(17,nil,31),f(17,nil,31)
    assert(type(a)=='table' and a~=b and a.n==3)
    assert(a[1]==17 and a[2]==nil and a[3]==31)
  end,
  function()
    local function f(...v)v[1]=v[1]+10;v.n=1;return ... end
    local a,b=f(17,31)
    assert(a==27 and b==nil)
  end,
  function()
    local function f(...v)
      return function()return v[1],v.n end
    end
    local g=f(17,nil,31)
    collectgarbage()
    local a,n=g()
    assert(a==17 and n==3)
  end,
  function()
    local count=0
    local function key()count=count+1;return 'n' end
    local function f(...v)return v[key()] end
    assert(f(17,nil,31)==3 and count==1)
  end,
  function()
    local function f(...v)
      assert(debug.setlocal(1,1,{99,n=1})=='v')
      return v[1],v.n
    end
    local a,n=f(17,nil,31)
    assert(a==17 and n==3)
  end,
  function()
    local function f(...v)
      local keys={0,-1,2^63,0/0,1.1,'1',false,print,{}}
      for _,k in ipairs(keys)do assert(v[k]==nil)end
      return v[1],v[2.0],v.n
    end
    local a,b,n=f(17,31)
    assert(a==17 and b==31 and n==2)
  end,
  function()
    local out={}
    local function f(...v)
      out[1]=v[1]
      out[v[2]]=v.n
      v[3][1]=37
      local name,value=debug.getlocal(1,1)
      assert(name=='v' and value==nil)
    end
    local nested={}
    f(17,'count',nested)
    assert(out[1]==17 and out.count==3 and nested[1]==37)
  end,
}
for i,f in ipairs(cases)do f();print('PASS: lazy-named-vararg-'..i)end
print('PASS: lazy named vararg contract')
