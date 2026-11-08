# Reviewed Verybig Windows source replay (2026-11-08)

Installed the independently reviewed exact Windows source equivalent through
the normal equivalent-approval graph. The author is runtime_gaps and the
reviewer is remaining_suite; Root inspected the original, counterpart and
review before installing their exact decision. The only replacement is the
12-byte os.tmpname expression at offset 3491 with the 17-byte expression
`'.'..os.tmpname()`. All other original bytes remain unchanged. The generated
SHA256 is d973c7a66fd1f4d50ec48c7d2bc49ad2bf8aa3e0df9cadf7033c52f1e3ce00dc.
The pinned references were not edited. No private-C exclusion was added.

Fresh copied native/Ada default/T images execute the complete generated large
program, original assertions and file removal, then return exactly one value,
10. All four raw outputs have SHA256
a61fcf3580a5cd9de6fae4722f686f695e1f29386baa5a5c7efe7fc5bad2481b;
stderr is empty. Every configuration probe measures the requested 2 GiB
ceiling. Actual child PID/run/configuration sidecars match and show zero
outstanding bytes/blocks; Ada reports completed shutdown without accounting
fault. No soft or port reduction is enabled. Each file has a 900-second limit.

The final local capture is
reports/exact-equivalent-review/verybig-558f995b25f94deaa7c6887ed5e40f9c.
The source-bound author observation records all four process/raw/image
identities. An earlier exploratory capture omitted its launch environment;
the fresh capture retains it and was inspected for actual run-ID binding.

The translation requires the observed Windows flat rooted tmpname shape and
a fresh disposable working directory. It is not a universal claim about C
tmpnam, Linux/macOS or arbitrary existing directories. Native applicability,
final immutable contexts and global certificate reconciliation remain separate
obligations. These local passes do not close the whole target.
