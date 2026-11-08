# CLI argument callback ordering and ownership

Date: 2026-11-08, Asia/Tokyo. Follow-up diagnostic on author base a4ab133.
The original 21 controls remain unchanged. No production implementation or
upstream source adaptation is part of this checkpoint.

The [eight follow-up cases](../../tests/conformance/targets/remaining-upstream-compatibility/cli-arg-lifecycle.author-cases.json)
add actual C ancestry/temporaries, file-loading order, initial-environment
capture, typed callback exit and two mandatory T allocation controls. The
[observation](../../tests/conformance/targets/remaining-upstream-compatibility/cli-arg-lifecycle.author-observation.json)
binds the actual raw processes and the inspected driver/root source. The
[observer](../../scripts/observe-cli-arg-lifecycle.ps1) uses frozen executable
and native DLL copies; source/GPR hashes do not claim a compile receipt.

Native default satisfies all six ordinary contracts; native T satisfies all
eight. Ada conformance default and both product variants satisfy only syntax
and missing-file ordering, failing the other four ordinary controls. Ada T
conformance satisfies those two and fails the other six. The product CLI has
no T adapter; default and product roles explicitly receive no credit for the
two mandatory T bodies. No T-absent return is counted as their execution.

Both native callbacks see one actual anonymous C caller. At length, its actual
temporary types are number, userdata, function, table. At global lookup they
are number, userdata, function, string. The real compiled selected function
is present in both; the original argument table is present at length. These
sequences are retained observations, not prescribed positions or a requirement
to copy C's backing layout. The fixture asserts the real C caller and relevant
function/table identity, then records all actual types.

A length handler replaces registry globals and collects. Native still runs
the selected closure against its original environment. This proves that
compiling a prototype before callbacks but creating a closure afterward is
insufficient. The actual callable must exist before querying arg. Source
inspection confirms New_Closure creates the initial environment cells and
clears Entry_Code after its new closure owns the prototype.

Both implementations reject malformed source or a missing selected file
before invoking the argument length handler. Keep that precedence. Native
length-handler os.exit(37,true) closes its lexical value, prints the marker,
never enters the selected script and exits 37 with empty stderr in both modes.
This bypasses conformance main-return telemetry. Neither native exit has an
invented sidecar or inferred byte balance. Current Ada does not call the
handler and instead enters the sentinel script, which fails.

The native T refusal-recovery handler genuinely sets alloccount to zero,
catches a real table allocation failure, restores the limit and verifies typed
arguments plus healthy allocation afterward. Its sidecar records two managed
refusals, zero backing refusals and zero final bytes/blocks. The second native
T handler leaves M0 armed after warming actual call depth; only the actual
selected script restores allocation. It succeeds with zero refused growth and
then verifies values and healthy allocation. The separately authored
[refused-entry script](../../tests/conformance/platform/cli-dynamic-arg-refused-entry.lua)
restores the count before packing values; no helper resets it on the way in.
Current Ada fails these guards because its length callback never runs.

The final campaign has 40 case processes and six configuration probes, each
with a 30-second deadline and 1 MiB capture cap. All 26 measured normal-return
workload sidecars match actual PID/run/configuration/2 GiB cap and end with
zero bytes and blocks; Ada reports completed shutdown without accounting
fault. The two native exits have the explicit no-main-return exception above.
Product images have no measured allocator ceiling. Raw output, environment,
argv, source/hash, return status and sidecars remain under
reports/cli-arg-lifecycle/6129280577c24245bac64f532cf61137 in the isolated
remaining-c-api worktree. The source/image/record/input/capture hash audit
checks 220 actual file identities. Both callback fixtures remain ordinary
public semantics; only the two explicitly marked fault cases require T.

The recommended implementation uses the existing CLI-only session child and
its real C primitive transports. Root authorized it after this source audit;
implementation and independent code review remain pending:

1. Compile and create the actual selected closure before argument callbacks.
   Put it in a real Current.Arguments root. Tiny C callbacks carry closure to
   closure/table through lua_getglobal and closure/table to
   closure/table/integer through luaL_len. All validation, argument iteration
   and policy stay in Ada.
2. Pre-reserve Current.Arguments for private metadata plus the actual
   Minimum_C_Stack, and a separate selected-owner argument-only vector for
   Minimum_C_Stack, before callbacks. Existing Take_Results uses
   Transfer_Result_Ownership: when the target fits, it preserves target
   capacity and copies while the source remains rooted. No new root field
   or Machine entry is needed.
3. After length, keep closure, original table and fixed count in
   Current.Arguments. Reserve final capacity transactionally while that packet
   remains rooted. Raw-read and append each actual argument into the same
   traced packet before any possible later safe point. Charge each pass.
4. Build the separate argument-only vector while all its actual values remain
   strongly rooted in the full packet. Invoke existing Function_Value Start
   without first trimming or clearing the packet. Start_Borrowed does not
   clear Current.Arguments; Begin_Operation drops only temporary epoch pins.
   Dispatch pins Function_Value and Arguments before Activate allocates or
   publishes a frame. Thus callee and arguments survive any pin growth,
   reservation refusal or collection without relying on local Value copies.
5. Clear Current.Arguments only after Start successfully publishes the actual
   callee and arguments. Call hooks may be above that callee; do not assume
   Stack.Last_Element identifies it. No vector element borrow may span the
   clear. On failure, cancel and unwind before dropping the packet. Finish
   the normal existing iterative driver, preserving budget/exit/error policy.

Steps is not reset by Start/Finish; initialize one work budget before the
whole compile/query/length/copy/call operation. Begin_Operation does end prior
temporary-root epochs, so Operation_Programs alone cannot keep code or
Operation_Roots alone keep a local callable across another Start. The actual
traced closure prefix supplies that lifetime. The original table alone is
also insufficient for copied values if it is weak or later mutated: publish
copied values in Current.Arguments too. ADR 0042 is reserved for the resulting
reviewed implementation; this session does not claim that code exists.

Both new PowerShell/Lua author files and the JSON are first-party probes. No
Alire/GPR, production modification, AUnit pass, source approval or full main
acceptance occurred. Parent's newer harness changes intentionally make the
older strict 21-case source checker stale; preserve those dated captures and
use explicit snapshot-aware verification or a fresh combined-image campaign
rather than blindly updating a hash. Final implementation validation must
retain all 21 controls, these eight, real refusal, callbacks and cleanup.
