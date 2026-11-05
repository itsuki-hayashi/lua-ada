# Test Layout

No executable test harness exists yet. See [test strategy](../docs/testing.md).

The next build milestone will create a nested AUnit crate here with a local
parent pin. Reserve `unit/` for Ada cases, `lua/` for project compatibility and
regression scripts, and `c_api/` for C hosts/modules. Create those directories
with real tests rather than empty coverage placeholders. Generated harnesses,
logs, and fuzz/proof sessions belong in ignored build/report directories.

Upstream tests remain in the reference submodule. Execute them from disposable
workspaces and report any reduced modes, exclusions, and Ada-internal mappings.
