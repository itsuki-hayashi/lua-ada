with Interfaces.C;
with System;

private package Lua.Platform_Locales is
   --  Locale is external process state, not Lua world state. Callers must
   --  serialize native locale changes with other host users of setlocale.
   --  The lexer deliberately does not use these classification functions.
   package C renames Interfaces.C;
   type Locale_Category is
     (All_Categories, Collation, Character_Classes, Monetary, Numeric, Time)
     with Convention => C;
   for Locale_Category use
     (All_Categories => 0, Collation => 1, Character_Classes => 2,
      Monetary => 3, Numeric => 4, Time => 5);
   for Locale_Category'Size use C.int'Size;

   function Set_Locale
     (Category : Locale_Category; Name : System.Address)
      return System.Address
     with Import, Convention => C, External_Name => "lua_ada_locale_set";
   --  Null Name queries the actual native category; a nonnull name is a
   --  borrowed NUL-terminated byte string. Null result means unavailable.
   --  Borrow/copy a nonnull result before another locale call; never retain
   --  its host pointer as a persistent Lua string or fabricated availability.

   function Decimal_Point return C.unsigned_char
     with Import, Convention => C,
          External_Name => "lua_ada_locale_decimal_point";
   --  Exactly localeconv()->decimal_point[0], as pinned Lua defines it.
   --  Runtime numeric strings accept that byte alongside an ordinary dot;
   --  source punctuation/grammar remains ASCII, and %q remains reloadable.

   type Character_Class is
     (Alphabetic, Control, Decimal, Graphic, Lowercase, Punctuation,
      Whitespace, Uppercase, Alphanumeric, Hexadecimal)
     with Convention => C;
   for Character_Class use
     (Alphabetic => 0, Control => 1, Decimal => 2, Graphic => 3,
      Lowercase => 4, Punctuation => 5, Whitespace => 6, Uppercase => 7,
      Alphanumeric => 8, Hexadecimal => 9);
   for Character_Class'Size use C.int'Size;
   function Matches
     (Byte : C.unsigned_char; Category : Character_Class) return C.int
     with Import, Convention => C, External_Name => "lua_ada_locale_class";
   function Lower (Byte : C.unsigned_char) return C.unsigned_char
     with Import, Convention => C, External_Name => "lua_ada_locale_lower";
   function Upper (Byte : C.unsigned_char) return C.unsigned_char
     with Import, Convention => C, External_Name => "lua_ada_locale_upper";
   --  Byte is unsigned, so 128..255 never become ctype's invalid negatives.
   --  Pattern %z, unknown classes and class inversion remain Ada semantics.

   function Collate (Left, Right : System.Address) return C.int
     with Import, Convention => C, External_Name => "strcoll";
   function Text_Length (Text : System.Address) return C.size_t
     with Import, Convention => C, External_Name => "strlen";
   --  Borrow NUL-terminated spans. Lua byte strings may contain NUL, so its
   --  complete ordering must compare each segment in Ada, retaining lengths;
   --  a single strcoll call would silently discard suffixes and is incorrect.
end Lua.Platform_Locales;
