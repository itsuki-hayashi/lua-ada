# Documentation Index

See [frontend compatibility](frontend.md) and the
[M2a milestone](milestones/m2a.md) for the current frontend work.
Its [validation record](validation-m2a.md) owns immutable acceptance evidence.

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
| [Upstream inventory](upstream-tests.md)       | All upstream files and subset mappings            |
| [Module fixtures](../tests/modules/README.md) | Real-world consumer pins and future parity inputs |
| [Decisions](decisions/README.md)              | Durable rationale                                 |
| [Sessions](sessions/README.md)                | Dated evidence and handoff                        |

Update the owning document and link to it elsewhere. Current status owns
capability claims; session records retain historical evidence. Wrap prose near
100 columns, align tables, and use relative links for local documents.
