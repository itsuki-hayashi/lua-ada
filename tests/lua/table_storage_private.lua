-- Ada-only actual storage counterpart, never a native querytab emulation.
assert(T and type(T.ada_check_table_storage)=='function')
collectgarbage('stop')
local a={[{}]=4,[3]=0,alo=1,
         a1234567890123456789012345678901234567890=10}
local weak=setmetatable({},{__mode='v'})
for k in pairs(a)do if type(k)=='table'then weak[1]=k end end
local rows,live=T.ada_check_table_storage(a)
assert(rows==4 and live==4)
for k in pairs(a)do a[k]=nil end
collectgarbage()
local retained,after=T.ada_check_table_storage(a)
assert(retained==rows and after==0 and weak[1]==nil and next(a)==nil)
local fresh={};a[fresh]=42
local reused,inserted=T.ada_check_table_storage(a)
assert(reused==rows and inserted==1 and a[fresh]==42)
collectgarbage('restart')
print('Table storage private OK')
