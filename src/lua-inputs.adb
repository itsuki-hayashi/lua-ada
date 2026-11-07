with System.Storage_Elements;

package body Lua.Inputs is
   use System.Storage_Elements;
   use type System.Address;

   function Available (Self : Source) return Natural is
     (if Self.Is_Stream then Self.Data.Length else Self.View_Length);

   function Streaming (Self : Source) return Boolean is (Self.Is_Stream);

   procedure Borrow
     (Self : in out Source; Address : System.Address; Length : Natural) is
   begin
      if Self.Is_Stream or else Self.Borrows /= 0 or else
        (Length /= 0 and then Address = System.Null_Address)
      then
         raise Program_Error with "invalid fixed input borrow";
      end if;
      Self.View := Address;
      Self.View_Length := Length;
      Self.Piece_Last := Length;
   end Borrow;

   procedure Open
     (Self : in out Source; Memory : not null Lua.Storage.Owner_Access;
      Refill : not null Refill_Function; Context : System.Address;
      Maximum_Bytes : Positive; Retry : Retry_Function := null) is
   begin
      if Self.Is_Stream or else Self.View_Length /= 0 or else
        Self.Borrows /= 0
      then
         raise Program_Error with "input is already open";
      end if;
      Self.Data.Set_Owner (Memory);
      Self.Is_Stream := True;
      Self.Ended := False;
      Self.Refill := Refill;
      Self.Retry := Retry;
      Self.Context := Context;
      Self.Maximum := Maximum_Bytes;
   end Open;

   function Ensure (Self : in out Source; Last : Natural) return Boolean is
   begin
      if Last <= Self.Available then
         return True;
      elsif Self.Ended then
         return False;
      elsif Self.Borrows /= 0 then
         raise Program_Error with "cannot refill a borrowed input";
      end if;
      loop
         declare
            Next : constant Piece := Self.Refill (Self.Context);
            Before : constant Natural := Self.Data.Length;
            Retried : Boolean := False;
         begin
            if Next.Address = System.Null_Address or else Next.Length = 0
            then
               Self.Ended := True;
               return False;
            elsif Next.Length > Self.Maximum - Before then
               raise Input_Limit;
            end if;
            declare
               Bytes : constant String (1 .. Next.Length)
                 with Import, Address => Next.Address;
            begin
               --  A refill can reenter the public API or collect. Its guarded
               --  C invocation has already returned before this managed copy.
               --  Retry the same still-valid piece after emergency collection;
               --  requesting a new piece here would invalidate the old bytes.
               loop
                  begin
                     Self.Data.Append (Bytes);
                     exit;
                  exception
                     when Lua.Storage.Allocation_Error =>
                        if Self.Retry = null or else
                          not Self.Retry (Self.Context, Retried)
                        then
                           raise;
                        end if;
                  end;
               end loop;
            end;
            Self.Piece_First := Before + 1;
            Self.Piece_Last := Self.Data.Length;
            if Last <= Self.Piece_Last then
               return True;
            end if;
         end;
      end loop;
   end Ensure;

   function Ensure_Block
     (Self : in out Source; First : Positive; Count : Natural)
      return Boolean is
   begin
      if Count = 0 then
         return True;
      elsif not Self.Ensure (First) then
         return False;
      end if;
      return First >= Self.Piece_First and then
        Count <= Self.Piece_Last - First + 1;
   end Ensure_Block;

   function Element (Self : Source; Index : Positive) return Character is
   begin
      if Index > Self.Available then
         raise Program_Error with "input byte is not available";
      elsif Self.Is_Stream then
         return Self.Data.Element (Index);
      end if;
      declare
         Byte : constant Character
           with Import, Address => Self.View + Storage_Offset (Index - 1);
      begin
         return Byte;
      end;
   end Element;

   procedure Query
     (Self : in out Source; First : Positive; Length : Natural;
      Process : not null access procedure (Text : String))
   is
      Address : constant System.Address :=
        (if Self.Is_Stream then Self.Data.Address else Self.View);
   begin
      if Length > Self.Available or else
        First - 1 > Self.Available - Length
      then
         raise Program_Error with "input span is not available";
      end if;
      Self.Borrows := Self.Borrows + 1;
      begin
         if Length = 0 then
            Process ("");
         else
            declare
               Text : constant String (1 .. Length)
                 with Import,
                      Address => Address + Storage_Offset (First - 1);
            begin
               Process (Text);
            end;
         end if;
      exception
         when others =>
            Self.Borrows := Self.Borrows - 1;
            raise;
      end;
      Self.Borrows := Self.Borrows - 1;
   end Query;
end Lua.Inputs;
