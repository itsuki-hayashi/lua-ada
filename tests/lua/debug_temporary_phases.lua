-- Pending_Arithmetic_Value
do
  local f,g;f=function()local n,v=debug.getlocal(2,3);assert(n=='(temporary)' and v==1);return 20 end;g=function(a,b)return(a+1)+f()end;assert(g(0,0)==21)
end

-- Pending_Arithmetic_Write
do
  local f,g;f=function()assert(debug.setlocal(2,3,10)=='(temporary)');return 20 end;g=function(a,b)return(a+1)+f()end;assert(g(0,0)==30)
end

-- Child_Callee_Excluded
do
  local f,g;f=function(x)assert(x==9);assert(debug.getlocal(2,4)==nil);assert(debug.setlocal(2,4,99)==nil);assert(debug.getlocal(2,5)==nil);return 20 end;g=function(a,b)return(a+1)+f(9)end;assert(g(0,0)==21)
end

-- Nested_Computed_Value
do
  local f,g;f=function()local n,v=debug.getlocal(2,3);assert(n=='(temporary)' and v==2);debug.setlocal(2,3,7);return 20 end;g=function(a,b)return((a+1)*2)+f()end;assert(g(0,0)==27)
end

-- Direct_Local_No_Hole
do
  local f,g;f=function()assert(debug.getlocal(2,3)==nil);assert(debug.setlocal(2,1,7)=='a');return 20 end;g=function(a,b)return a+f()end;assert(g(0,0)==27)
end

-- Unary_Call_No_Hole
do
  local f,g;f=function()assert(debug.getlocal(2,3)==nil);return 20 end;g=function(a,b)return -f()end;assert(g(0,0)==-20)
end

-- Indexed_Pending_Value
do
  local f,g;f=function()local n,v=debug.getlocal(2,3);assert(n=='(temporary)' and v==1);debug.setlocal(2,3,10);return 20 end;g=function(a,b)return a[1]+f()end;assert(g({1},0)==30)
end

-- Earlier_Result_Preserved
do
  local f,g;f=function()local n,v=debug.getlocal(2,3);assert(n=='(temporary)' and v==99);local n,v=debug.getlocal(2,4);assert(n=='(temporary)' and v==1);assert(debug.getlocal(2,5)==nil);debug.setlocal(2,4,10);return 20 end;g=function(a,b)return 99,(a+1)+f()end;local x,y=g(0,0);assert(x==99 and y==30)
end

-- Suspended_Pending_Value
do
  local function f()coroutine.yield();return 20 end;local co=coroutine.create(function(a,b)return(a+1)+f()end);assert(coroutine.resume(co,0,0));collectgarbage();local n,v=debug.getlocal(co,2,3);assert(n=='(temporary)' and v==1);assert(debug.getlocal(co,2,4)==nil);assert(debug.setlocal(co,2,3,10)=='(temporary)');local ok,v=coroutine.resume(co);assert(ok and v==30)
end

-- Vararg_Shifted_Window
do
  local f,g;f=function()local n,v=debug.getlocal(2,2);assert(n=='(vararg table)' and v==nil);local n,v=debug.getlocal(2,3);assert(n=='(temporary)' and v==1);assert(debug.getlocal(2,4)==nil);debug.setlocal(2,3,10);return 20 end;g=function(a,...)return(a+1)+f()end;assert(g(0,7,8)==30)
end

-- Managed_Pending_Value
do
  local new=setmetatable({},{__add=function()return'new'end});local f,g;f=function()local n,v=debug.getlocal(2,3);assert(n=='(temporary)' and type(v)=='table');debug.setlocal(2,3,new);collectgarbage();return 20 end;g=function(a,b)return a[1]+f()end;local old=setmetatable({},{__add=function()return'old'end});assert(g({old},0)=='new')
end

print('debug temporary phases OK')
