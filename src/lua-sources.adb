package body Lua.Sources is
   function Inspect_File_Preamble
     (Source : String) return File_Preamble_Info
   is
      Result : File_Preamble_Info;
   begin
      --  Empty String bounds may lie outside Positive. Relative counts avoid
      --  conversion or a Last+1 sentinel even at the largest legal index.
      if Source'Length = 0 then
         return Result;
      end if;
      if Source'Length >= 3 and then
        Source (Source'First .. Source'First + 2) =
          Character'Val (16#EF#) & Character'Val (16#BB#) &
          Character'Val (16#BF#)
      then
         Result.Skipped_Bytes := 3;
      end if;
      if Result.Skipped_Bytes < Source'Length and then
        Source (Source'First + Result.Skipped_Bytes) = '#'
      then
         for Offset in Result.Skipped_Bytes .. Source'Length - 1 loop
            exit when Source (Source'First + Offset) in
              Character'Val (10) | Character'Val (13);
            Result.Blanked_Bytes := Result.Blanked_Bytes + 1;
         end loop;
      end if;
      return Result;
   end Inspect_File_Preamble;

   function File_Preamble (Source : String) return String is
      Info : constant File_Preamble_Info := Inspect_File_Preamble (Source);
   begin
      --  Null strings may have bounds outside Positive. Do not constrain
      --  their first index or inspect any byte before this empty fast path.
      if Source'Length = 0 then
         return Source;
      end if;
      declare
         Text : String := Source;
      begin
         if Info.Skipped_Bytes = Source'Length then
            return "";
         end if;
         for Offset in 1 .. Info.Blanked_Bytes loop
            Text (Source'First + (Info.Skipped_Bytes + Offset - 1)) := ' ';
         end loop;
         return Text (Source'First + Info.Skipped_Bytes .. Text'Last);
      end;
   end File_Preamble;
end Lua.Sources;
