# Native allocator probe loaded-image identity (2026-11-08)

The native allocator observer now records the OS mapping of the actual
`l_memcontrol` data object used by its selected allocator. Windows uses
GetModuleHandleEx/GetModuleFileName; POSIX uses dladdr. Non-Windows probes
compile with PIC to avoid an executable copy relocation for that object.
The parent requires the selected runtime directory and library name and
records the hash of the resolved image. This strengthens the former explicit
`loaded_runtime_linkage_verified=false` limitation without changing Lua or
the allocator's implementation.

The Windows validation probe compiles with strict C99 warnings and passes
all seven actual allocator cases. Its captured mapping identifies the
selected libconformance_lua.dll; raw observations are in
reports/native-allocator-observer/ef84b6e01f9348ba87003199d5cffe40.
Linux/macOS execution and final frozen-image reconciliation remain pending.
This component report supplies neither source coverage nor target acceptance.

The combined tree also builds both strict validation test configurations and
passes 2,612 AUnit cases in each. Integration source guards correctly reject
stale configured-invariant, main-inventory and dynamic-argument bindings after
the hash and CLI transport changes. Those packets require explicit refresh;
their earlier captured runs remain dated observations. The 24 exact Verybig
Windows source-proposal guards pass without emitting an adapted whole file.
