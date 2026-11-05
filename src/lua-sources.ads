package Lua.Sources is
   pragma Pure;

   function File_Preamble (Source : String) return String;
   --  Prepare file/stdin bytes for the shared frontend. Remove one leading
   --  UTF-8 byte-order mark and blank an initial interpreter line beginning
   --  with '#', preserving its newline bytes and all subsequent source bytes.
   --  Raw load strings and command-line snippets do not use this policy.
   --  @param Source File bytes with any legal String bounds, including empty.
   --  @return Prepared bytes, never longer than Source. Storage is bounded by
   --    the supplied source length; no file I/O or runtime state is retained.
end Lua.Sources;
