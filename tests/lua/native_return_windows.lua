local function capture(fn,...)local record;debug.sethook(function(event)if event=='return' then local info=debug.getinfo(2,'fr');if info.func==fn then local values={n=info.ntransfer};for i=info.ftransfer,info.ftransfer+info.ntransfer-1 do local n,v=debug.getlocal(2,i);assert(n=='(C temporary)');values[i-info.ftransfer+1]=v end;record={first=info.ftransfer,count=info.ntransfer,values=values}end end end,'r');local result=table.pack(fn(...));debug.sethook();assert(record);return record,result end;

-- Math_Appended_Result
do
  local p,r=capture(math.sin,3);assert(p.first==2 and p.count==1 and p.values[1]==r[1] and p.values[1]~=3)
end

-- Equal_Math_Result_Appends
do
  local p,r=capture(math.abs,4);assert(p.first==2 and p.count==1 and p.values[1]==4 and r[1]==4)
end

-- Assert_Existing_Arguments
do
  local p,r=capture(assert,true,12,13);assert(p.first==1 and p.count==3 and p.values[1]==true and p.values[2]==12 and p.values[3]==13 and r.n==3)
end

-- Select_Existing_Suffix
do
  local p,r=capture(select,2,10,20,30,40);assert(p.first==3 and p.count==3 and p.values[1]==20 and p.values[2]==30 and p.values[3]==40 and r.n==3)
end

-- Select_Count_Appends
do
  local p,r=capture(select,'#',10,20);assert(p.first==4 and p.count==1 and p.values[1]==2 and r[1]==2)
end

-- Tonumber_Numeric_Reuse
do
  local p,r=capture(tonumber,12);assert(p.first==1 and p.count==1 and p.values[1]==12 and r[1]==12)
end

-- Tonumber_Text_Appends
do
  local p,r=capture(tonumber,'12');assert(p.first==2 and p.count==1 and type(p.values[1])=='number' and p.values[1]==12 and r[1]==12)
end

-- Rawget_Replaces_Key
do
  local p,r=capture(rawget,{x=41},'x');assert(p.first==2 and p.count==1 and p.values[1]==41 and r[1]==41)
end

-- Rawset_Returns_Table
do
  local t={};local p,r=capture(rawset,t,'x',41);assert(p.first==1 and p.count==1 and p.values[1]==t and r[1]==t and t.x==41)
end

-- Pcall_Success_Prefix
do
  local p,r=capture(pcall,function()return 11,22 end);assert(p.first==1 and p.count==3 and p.values[1]==true and p.values[2]==11 and p.values[3]==22 and r.n==3)
end

-- Pcall_Error_Range
do
  local p,r=capture(pcall,function()error(17)end);assert(p.first==3 and p.count==2 and p.values[1]==false and p.values[2]==17 and r[1]==false and r[2]==17)
end

-- Gmatch_Argument_Replacement
do
  local p,r=capture(string.gmatch,'abc','.');assert(p.first==1 and p.count==1 and type(p.values[1])=='function' and p.values[1]==r[1]);assert(r[1]()=='a')
end

-- Pairs_Four_Results
do
  local t={};local p,r=capture(pairs,t);assert(p.first==2 and p.count==4 and p.values.n==4 and type(p.values[1])=='function' and p.values[2]==t and p.values[3]==nil and p.values[4]==nil and r.n==4)
end

print('native return windows OK')
