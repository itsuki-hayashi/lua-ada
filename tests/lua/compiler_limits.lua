local shapes = {
 {'local a', ',a', ';', ''},
 {'local a', ',a', '= 1', ',1'},
 {'local a', ',a', '= f()', ''},
 {'local a; a', ',a', '= 1', ',1'},
 {'local a; a=', '{', '0', '}'},
 {'return ', '(', '2', ')', 2},
 {'local function a(x)return x end; return ', 'a(', '2.2', ')', 2.2},
 {'', 'do ', '', ' end'},
 {'', 'while a do ', '', ' end'},
 {'local a; ', 'if a then else ', '', ' end'},
 {'', 'function foo() ', '', ' end'},
 {"local a=''; return ", 'a..', "'a'", '', 'a'},
 {'local a=1; return ', 'a^', 'a', '', 1},
}
local function check(i)
 local p=shapes[i]
 local function code(n)return p[1]..p[2]:rep(n)..p[3]..p[4]:rep(n)end
 local f,e=load(code(100),'=compiler-limit')
 assert(f,e)
 if p[5]~=nil then assert(f()==p[5])end
 local ok,f,e=pcall(load,code(500),'=compiler-limit')
 assert(ok and f==nil and type(e)=='string')
 assert(e:find('too many',1,true) or e:find('overflow',1,true),e)
 assert(assert(load('return 37'))()==37)
end
local cases={}
for i=1,#shapes do local n=i;cases[n]=function()check(n)end end
local source='return '..('('):rep(500)..'1'..(')'):rep(500)
local function reader()
 local sent=false
 return function()if not sent then sent=true;return source end end
end
cases[14]=function()
local ok,f,e=pcall(load,reader(),'=reader-limit')
assert(ok and f==nil and type(e)=='string')
assert(e:find('too many',1,true) or e:find('overflow',1,true))
end
cases[15]=function()
local saved=load
local function invoke(f,...)return f(...)end
local ok,f,e=pcall(invoke,saved,reader(),'=direct-reader-limit')
assert(ok and f==nil and type(e)=='string')
assert(e:find('too many',1,true) or e:find('overflow',1,true))
end
for i=1,#cases do cases[i]();print('compiler limit '..i)end
