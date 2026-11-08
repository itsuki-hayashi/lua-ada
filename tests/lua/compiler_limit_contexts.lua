local cases={}
local function names(prefix,n)
 local t={} for i=1,n do t[i]=prefix..i end return table.concat(t,',')
end
local function rejected(source,kind,where)
 local f,e=load(source,'=limit-context')
 assert(f==nil and type(e)=='string')
 assert(e:find('too many '..kind,1,true),e)
 assert(e:find(where,1,true),e)
 assert(assert(load('return 42'))()==42)
end
cases[1]=function()
 rejected('local '..names('a',201),'local variables','in main function')
end
cases[2]=function()
 rejected('\n\n\nreturn function()\nlocal '..names('a',201)..'\nend',
          'local variables','in function at line 4')
end
cases[3]=function()
 rejected('\nreturn function('..names('a',201)..')end',
          'local variables','in function at line 2')
end
cases[4]=function()
 local f=assert(load('local '..names('a',200)..';return a200'))
 assert(select('#',f())==1 and f()==nil)
end
local function captured(n)
 local a,b,values={}, {},{}
 for i=1,127 do a[i]='a'..i end
 for i=1,n do b[i]='b'..i end
 for i=1,math.max(n,127)do values[i]='0' end
 local function zeros(k)return table.concat(values,',',1,k)end
 return 'local '..table.concat(a,',')..'='..zeros(127)..'\n'..
 'return function()\nlocal '..table.concat(b,',')..'='..zeros(n)..'\n'..
 'return function()return '..table.concat(a,'+')..'+'..table.concat(b,'+')..' end\nend'
end
cases[5]=function()
 local maker=assert(load(captured(128)))()
 local f=maker()
 assert(debug.getinfo(f,'u').nups==255 and f()==0)
end
cases[6]=function()
 rejected(captured(129),'upvalues','in function at line 4')
end
cases[7]=function()
 rejected('\nfunction foo()\nlocal '..names('a',200)..',b\n',
          'local variables','in function at line 2')
end
cases[8]=function()
 rejected('\nreturn function('..names('a',201),
          'local variables','in function at line 2')
end
cases[9]=function()
 local source='do local '..names('a',200)..' end; do local '..names('b',200)..' end'
 assert(load(source))()
end
cases[10]=function()
 local source='local '..names('a',200)..';return function()local '..
              names('b',200)..';return a1,b200 end'
 local f=assert(load(source))()
 local result=table.pack(f())
 assert(result.n==2 and result[1]==nil and result[2]==nil)
end
cases[11]=function()
 local parts={}
 for i=1,201 do parts[i]='local k'..i..' <const> = '..i end
 parts[#parts+1]='return k201'
 local f,e=load(table.concat(parts,'\n'))
 assert(f,e);assert(f()==201)
end
cases[12]=function()
 local f,e=load('local '..names('a',200)..';local last<const> = 37;return last')
 assert(f,e);assert(f()==37)
end
cases[13]=function()
 rejected('local '..names('a',200)..';local last<const> = select(1,37)',
          'local variables','in main function')
end
cases[14]=function()
 local f,e=load('local '..names('a',201)..' =')
 assert(f==nil and type(e)=='string' and e:find('<eof>',1,true))
 assert(not e:find('too many local variables',1,true),e)
end
for i=1,#cases do cases[i]();print('compiler context '..i)end
