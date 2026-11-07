private package Lua.Engine.Diagnostics is
   Deferred_Argument_Error : exception;
   --  Private typed scheduler request. The failing activation owns its
   --  index/detail before this is raised; no Lua/host failure is published.
   --  Only the existing driver may drive the requested registry lookup.

   procedure Argument_Error
     (State : in out World; Index : Positive; Detail : String);
   --  Raise an auxiliary argument error for the actual current public CI.
   --  Hidden builtin phases borrow their real C owner. Call origin, __call
   --  extra values, colon-call self and an immediate Lua source follow the
   --  pinned luaL_argerror/luaL_where rules. A registry metamethod lookup
   --  raises Deferred_Argument_Error for an explicit driver continuation;
   --  this synchronous formatter never invokes a callback or executor.

   procedure Finish_Argument_Error
     (State : in out World; Origin : not null Frame_Access; Modules : Value);
   --  Finish the retained diagnostic after the actual registry lookup.
   --  Origin remains active below its hidden continuation; Modules is rooted
   --  by that continuation's real returned packet until the error is raised.

   procedure Type_Error
     (State : in out World; Index : Positive; Expected : String;
      Item : Value; Present : Boolean := True);
   --  Render the auxiliary type policy, then raise Argument_Error. Item is
   --  retained by the caller's actual frame/arguments throughout this query.

   function Integer_Argument
     (State : in out World; Index : Positive; Item : Value;
      Present : Boolean := True) return Integer_Value;
   --  Apply luaL_checkinteger conversion without losing its argument index.
   --  Numeric strings use the shared parser; nonintegral/out-of-range values
   --  report representation failure, while wrong types use Type_Error.
end Lua.Engine.Diagnostics;
