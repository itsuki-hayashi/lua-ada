-- Authored public CLI argument probe. No T body or upstream source is used.
-- Setup comes from the recorded -e argument; the selected script receives
-- actual varargs before this checker runs, then verifies values/identities.
local values = table.pack(...)
check_dynamic_arg(values)
io.write("PASS: cli-dynamic-arg-", case_name, "\n")
