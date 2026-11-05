package body Lua.Sources is
   function File_Preamble (Source : String) return String is
   begin
      --  Null strings may have bounds outside Positive. Do not constrain
      --  their first index or inspect any byte before this empty fast path.
      if Source'Length = 0 then
         return Source;
      end if;
      declare
         First : Positive := Source'First;
         Text : String := Source;
      begin
         if Source'Length >= 3 and then Source (First .. First + 2) =
           Character'Val (16#EF#) & Character'Val (16#BB#) &
           Character'Val (16#BF#)
         then
            --  Avoid computing Last+1 when a BOM-only string is located at
            --  Positive'Last. A nonempty suffix makes First+3 representable.
            if Source'Length = 3 then
               return "";
            end if;
            First := First + 3;
         end if;
         if Source (First) = '#' then
            --  Blanking rather than deleting keeps diagnostic line numbers
            --  stable. A for loop also avoids incrementing Positive'Last.
            for Position in First .. Source'Last loop
               exit when Source (Position) in
                 Character'Val (10) | Character'Val (13);
               Text (Position) := ' ';
            end loop;
         end if;
         return Text (First .. Text'Last);
      end;
   end File_Preamble;
end Lua.Sources;
