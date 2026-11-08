-- Mandatory T control: restore only after actual selected-script entry.
T.alloccount()
local values = table.pack(...)
check_dynamic_arg(values)
io.write("PASS: cli-dynamic-arg-", case_name, "\n")
