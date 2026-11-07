-- First_Stripped_Line: An unknown source line still causes the first real line event.
do
  local f=assert(load(string.dump(function()local x=1;return x end,true)));local n=0;debug.sethook(function(e,l)if debug.getinfo(2,'f').func==f then assert(e=='line' and l==nil);n=n+1 end end,'l');assert(f()==1);debug.sethook();assert(n==1)
end

-- Stripped_Back_Edges: Unknown-line events recur at actual backward control transfers.
do
  local f=assert(load(string.dump(function()for i=1,3 do end;return 9 end,true)));local n=0;debug.sethook(function(e,l)if debug.getinfo(2,'f').func==f then assert(e=='line' and l==nil);n=n+1 end end,'l');assert(f()==9);debug.sethook();assert(n==3)
end

-- Stripped_Vararg_Entry: Vararg setup precedes the single unknown-line user event.
do
  local f=assert(load(string.dump(function(...)return ... end,true)));local n=0;debug.sethook(function(e,l)if debug.getinfo(2,'f').func==f then assert(e=='line' and l==nil);n=n+1 end end,'l');local a,b,c=f(4,nil,6);debug.sethook();assert(a==4 and b==nil and c==6 and n==1)
end

-- Stripped_Frame_Reuse: A reused activation forgets its previous unknown-line check.
do
  local f=assert(load(string.dump(function()return 7 end,true)));local n=0;debug.sethook(function(e,l)if debug.getinfo(2,'f').func==f then assert(e=='line' and l==nil);n=n+1 end end,'l');assert(f()==7);assert(f()==7);assert(f()==7);debug.sethook();assert(n==3)
end

print('stripped line phases OK')
