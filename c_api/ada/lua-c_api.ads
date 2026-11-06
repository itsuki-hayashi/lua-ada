package Lua.C_API with Elaborate_Body is
   --  Standalone-library elaboration root for the public C facade. C hosts
   --  use the pinned lua.h declarations; they never initialize Ada manually.
   --  This unit deliberately introduces no public Ada object handles.
end Lua.C_API;
