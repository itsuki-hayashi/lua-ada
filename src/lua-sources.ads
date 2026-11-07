package Lua.Sources is
   pragma Pure;

   type File_Preamble_Info is record
      Skipped_Bytes : Natural := 0;
      Blanked_Bytes : Natural := 0;
   end record;
   --  Relative byte counts, independent of an Ada String's lower bound.
   --  @field Skipped_Bytes Initial BOM or binary interpreter prefix to remove.
   --  @field Blanked_Bytes Following interpreter bytes to replace with spaces.
   function Inspect_File_Preamble (Source : String) return File_Preamble_Info;
   --  Inspect without copying or changing source bytes. Managed loaders can
   --  apply these offsets in place while sharing File_Preamble's exact policy.
   --  @param Source File bytes, including arbitrary empty/nonempty bounds.
   --  @return Counts whose sum is no greater than Source'Length.

   function File_Preamble (Source : String) return String;
   --  Prepare file/stdin bytes for the shared frontend. Remove one leading
   --  UTF-8 byte-order mark and blank an initial interpreter line beginning
   --  with '#', ignoring lone CR bytes through LF and preserving a final
   --  CRLF pair and all subsequent source bytes.
   --  For binary input, discard an initial interpreter line through its LF
   --  instead of blanking it, so the signature/alignment starts at byte one.
   --  Raw load strings and command-line snippets do not use this policy.
   --  @param Source File bytes with any legal String bounds, including empty.
   --  @return Prepared bytes, never longer than Source. Storage is bounded by
   --    the supplied source length; no file I/O or runtime state is retained.
end Lua.Sources;
