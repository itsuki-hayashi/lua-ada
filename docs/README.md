# Documentation Index

[M3](milestones/m3.md) owns the active complete-upstream-coverage target and its
thirteen staged gates. M3-01 establishes the
[conformance inventory and harness](../tests/conformance/README.md); it does not
complete the later runtime, C API, canonical execution or CLI work.

The completed [M2b validation](validation-m2b.md) records core-library and
three-file upstream execution evidence across all 18 configurations.

See [frontend compatibility](frontend.md) and the
[M2a milestone](milestones/m2a.md) for the current frontend work.
Its [validation record](validation-m2a.md) owns immutable acceptance evidence.
The [M2b target](milestones/m2b.md) owns the current library/metamethod delivery;
[status](status.md) summarizes accepted capability and remaining milestones.

The completed [M1 target](milestones/m1.md) owns the interpreter subset and gates.
The [validation record](validation.md) owns platform evidence.

| Document                                      | Owns                                              |
| --------------------------------------------- | ------------------------------------------------- |
| [Goals](goals.md)                             | Objectives and success criteria                   |
| [Architecture](../ARCHITECTURE.md)            | Components and ownership                          |
| [Development](development.md)                 | Setup, tools, profiles, commands                  |
| [Coding](coding-standards.md)                 | Ada and Markdown standards                        |
| [API documentation](api-documentation.md)     | GNATdoc conventions and verification              |
| [Testing](testing.md)                         | Test layers and optional tools                    |
| [Compatibility](compatibility.md)             | Baseline and compatibility contracts              |
| [Roadmap](roadmap.md)                         | Milestone ordering and gates                      |
| [Backlog](backlog.md)                         | Work IDs and acceptance criteria                  |
| [Status](status.md)                           | Actual capability and evidence                    |
| [Validation](validation.md)                   | Passing M1 configurations and gate evidence       |
| [Capabilities](capabilities.md)               | Implemented subset and deferred areas             |
| [Embedding](embedding.md)                     | Ada session use and lifetime contracts            |
| [Batch CLI](cli.md)                           | Execution/checking options and source handling    |
| [Upstream inventory](upstream-tests.md)       | All upstream files and subset mappings            |
| [M3 milestone](milestones/m3.md)              | Complete coverage contract and staged gates       |
| [Module fixtures](../tests/modules/README.md) | Real-world consumer pins and future parity inputs |
| [Decisions](decisions/README.md)              | Durable rationale                                 |
| [Sessions](sessions/README.md)                | Dated evidence and handoff                        |

Update the owning document and link to it elsewhere. Current status owns
capability claims; session records retain historical evidence. Wrap prose near
100 columns, align tables, and use relative links for local documents.
