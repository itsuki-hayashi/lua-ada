-- Exercise raw byte output, including NUL and invalid UTF-8. The differential
-- runner compares streams as bytes, preserving distinctions text decoding loses.
print("\0\1\127\128\192\255", "\255\254", #"\0\255")
assert("\128" < "\255")
assert(#("\0" .. "\255") == 2)
