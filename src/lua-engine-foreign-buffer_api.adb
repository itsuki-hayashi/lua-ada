separate (Lua.Engine.Foreign)
procedure Buffer_API
  (State : in out World; Context : not null Context_Access;
   Input : Request; Output : in out Response)
is
   use type Memory.Owner_Access;
   Data : Aux_Box_Access;
   --  The C facade passes the address of its userdata's one handle field.
   --  Publishing/clearing it inside this operation closes the ownership gap
   --  before the C dispatcher can drain another callback or propagate error.
   Handle : System.Address with Import, Address => Input.Pointer;

   type Buffer_Head is record
      Bytes : System.Address;
      Capacity : C.size_t;
      Used : C.size_t;
   end record with Convention => C;
   --  This is the public luaL_Buffer prefix, not a private Lua structure.
   --  A successful resize updates it before any possible C transfer, so an
   --  error in a subsequently drained callback cannot leave a stale pointer.

   procedure Charge (Amount : C.size_t);
   procedure Charge (Amount : C.size_t) is
   begin
      if State.Policy = Bounded then
         if Amount > C.size_t (State.Bounds.Instructions - Natural'Min
           (State.Steps, State.Bounds.Instructions))
         then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         State.Steps := State.Steps + Natural (Amount);
      end if;
   end Charge;

begin
   if Input.Pointer = System.Null_Address then
      raise Foreign_Error with "missing auxiliary buffer handle slot";
   end if;
   if Input.Operation = Create_Aux_Box then
      if Handle /= System.Null_Address then
         raise Foreign_Error with "auxiliary buffer already has an owner";
      end if;
      declare
         Box : constant Value := At_Index (State, Context, Input.Index);
      begin
         if Box.Kind /= Userdata_Kind or else
           Userdata_Address (Box) /= Input.Pointer
         then
            raise Foreign_Error with "invalid auxiliary userdata owner";
         end if;
         Attach_Resource
           (Box, System.Null_Address, Cleanup_Aux_Box'Access);
      end;
      Data := new (Memory.Handle (State.Memory)) Aux_Box;
      Data.Owner := Memory.Reference (State.Memory);
      Handle := Data.all'Address;
      return;
   end if;
   if Handle = System.Null_Address then
      if Input.Operation = Release_Aux_Box then return; end if;
      raise Foreign_Error with "auxiliary buffer has no owner";
   end if;
   Data := Aux_Box_Handle (Aux_Box_Views.To_Pointer (Handle));
   if Data.Owner /= Memory.Reference (State.Memory) then
      raise Foreign_Error with "auxiliary buffer belongs to another state";
   end if;
   if Input.Operation = Release_Aux_Box then
      Handle := System.Null_Address;
      Dispose_Aux_Box (Data);
      return;
   end if;
   if Input.Operation = Resize_Aux_Box then
      if Input.Name = System.Null_Address or else
        Input.Integer_Data < 0 or else
        C.size_t (Input.Integer_Data) > Input.Length
      then
         raise Foreign_Error with "invalid public buffer prefix";
      end if;
      declare
         Head : Buffer_Head with Import, Address => Input.Name;
         Original : constant System.Address := Head.Bytes;
         First : constant Boolean := Data.Size = 0;
         Granted : C.size_t := Input.Length;
      begin
         if Head.Used >= C.size_t (Input.Integer_Data) then
            raise Foreign_Error with "buffer space omits its terminator";
         elsif State.Policy = Bounded then
            if C.size_t (Input.Integer_Data) >
              C.size_t (State.Bounds.String_Bytes) + 1
            then
               Fail (State, "string byte limit exceeded", Resource => True);
            end if;
            --  Growth slack is not content. Grant the required bytes while
            --  capping optional capacity, so a valid near-limit string is
            --  not rejected merely by the auxiliary growth heuristic.
            Granted := C.size_t'Min
              (Granted, C.size_t (State.Bounds.String_Bytes) + 1);
         end if;
         if Granted >= C.size_t (Natural'Last) then
            raise Memory.Allocation_Error;
         end if;
         --  Charge the actual owned-copy extent as well as newly appended
         --  C bytes. Direct prep/commit clients must not bypass the budget
         --  by repeatedly resizing a retained allocation without addlstring.
         Charge ((if First then Head.Used else
           C.size_t'Min (C.size_t (Data.Size), Granted)));
         Memory.Reallocate
           (State.Memory, Data.Block, Memory.Byte_Count (Granted));
         Data.Size := Natural (Granted);
         if First and then Head.Used > 0 then
            --  Only the first promotion copies the caller's fixed scratch.
            --  Later resizes preserve bytes through the shared owned pool.
            declare
               Size : constant Natural := Natural (Head.Used);
               Source : constant String (1 .. Size)
                 with Import, Address => Original;
               Target : String (1 .. Size)
                 with Import, Address => Data.Block;
            begin
               Target := Source;
            end;
         end if;
         Head.Bytes := Data.Block;
         Head.Capacity := Granted;
         Output.Pointer := Data.Block;
      end;
   elsif Input.Operation = Publish_Aux_Box then
      if Input.Name = System.Null_Address then
         raise Foreign_Error with "missing public buffer prefix";
      end if;
      if Input.Length >= C.size_t (Natural'Last) then
         raise Memory.Allocation_Error;
      elsif State.Policy = Bounded and then
        Input.Length > C.size_t (State.Bounds.String_Bytes)
      then
         Fail (State, "string byte limit exceeded", Resource => True);
      end if;
      declare
         Size : constant Natural := Natural (Input.Length);
         Item : Value;
         Head : Buffer_Head with Import, Address => Input.Name;
      begin
         Data.Release_Function := Memory.Allocator (State.Memory);
         Data.Release_Data := Memory.Userdata (State.Memory);
         Charge (C.size_t'Min (C.size_t (Data.Size), Input.Length + 1));
         Memory.Reallocate
           (State.Memory, Data.Block, Memory.Byte_Count (Size) + 1);
         Data.Size := Size + 1;
         Head.Bytes := Data.Block;
         Head.Capacity := C.size_t (Data.Size);
         declare
            Terminator : Character with Import,
              Address => Data.Block + Storage_Offset (Size);
         begin
            Terminator := Character'Val (0);
         end;
         --  Match the native buffer's transfer before external publication:
         --  header refusal releases the transferred bytes immediately, even
         --  when an outer C activation catches the error and keeps its box.
         Handle := System.Null_Address;
         begin
            Item := New_External_String
              (State, Data.Block, Size, Release_Aux_Payload'Access,
               Data.all'Address);
         exception
            when others =>
               Dispose_Aux_Box (Data, Captured => True);
               raise;
         end;
         --  The external header now owns descriptor and bytes; a stack-push
         --  refusal cannot return them to the already cleared userdata.
         Push (State, Context, Item);
         Output.Pointer := Item.Reference.C_Bytes;
      end;
   else
      raise Foreign_Error with "invalid auxiliary buffer operation";
   end if;
end Buffer_API;
