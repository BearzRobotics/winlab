AGENTS.md — WinLab Engineering Instructions
Mission and scope
WinLab is a Windows administration course delivered through a substantial Zig desktop application. It is not an IT repair toolkit. Every feature must help the learner understand Windows, practice with its built-in administration tools, or demonstrate competency. The learner should become independent of WinLab.

Read spec.md before architecture or feature work. Treat spec.md as the product contract; propose and document changes rather than silently changing scope.
Non-negotiable rules
1. Implement application code primarily in Zig. Pin the supported Zig version and verify compatibility before using compiler/stdlib APIs.
2. Vendor every third-party source dependency. Do not add a build-time package download or silently fetch code. Preserve licenses, version, upstream URL, checksums where available, and local patches. External Windows tools and hypervisors are optional environment prerequisites, not vendored libraries.
3. Build and run the core course offline. No mandatory account, cloud service, telemetry or runtime content download.
4. Never treat the host machine as a disposable training target. System-changing labs run only against explicitly registered and verified training VMs or strictly scoped, reversible safe fixtures.
5. No hidden elevation, security bypass, credential harvesting, or unapproved system modifications.
6. Do not reimplement CMD, PowerShell or native administration consoles. Teach their real behavior.
7. Use official Windows/PowerShell/Windows SDK and Zig documentation for technical claims. Cite authoritative links in course content and important design decisions.
8. Preserve the distinction between reading a lesson, performing a lab, and demonstrating mastery.
Development workflow
Before implementing a substantial change:
1. Identify the learner outcome or application requirement it serves.
2. Inspect the relevant modules, course manifests and tests.
3. Confirm the pinned Zig version and existing vendored dependencies.
4. Identify Windows version, privileges, VM prerequisites and failure modes.
5. For consequential design choices, add a decision record under docs/decisions/ describing context, alternatives, choice and tradeoffs.
6. Implement the smallest coherent change with tests and documentation.
7. Run relevant checks; report what was actually tested and what could not be tested.
Do not claim successful builds, tests, VM snapshots or lab cleanup without evidence.
Architecture and code quality
- Separate UI, curriculum, assessment, terminal, VM providers, Windows integration and persistence behind clear interfaces.
- Keep reusable logic independent of UI widgets and hypervisor backends.
- Avoid global mutable state unless there is a specific documented reason.
- Prefer explicit ownership, clear lifetime management and error propagation.
- Use meaningful types and names; avoid opaque flags and magic constants.
- Keep files cohesive and reasonably sized. Do not enforce an arbitrary 500-line maximum at the expense of clarity.
- Design for testability: use mocks for VM providers and Windows-dependent services where useful.
- Avoid speculative abstractions and unnecessary dependencies.
- Treat text encodings, Windows UTF-16 APIs, handle ownership and resource cleanup carefully.
- Do not suppress errors or report success before verifying outcomes.
- Log useful diagnostic context without exposing secrets.
- Honor NO_COLOR in CLI/helper output.
Windows API and process rules
- Prefer documented, supported Win32 interfaces; document minimum supported Windows versions.
- Close handles, release resources, and check error codes and partial failures.
- Never assume a process has administrator rights.
- Distinguish Windows PowerShell 5.1 (powershell.exe) from PowerShell 7 (pwsh.exe); discover optional installations.
- Use ConPTY for interactive terminal sessions where supported; do not fake shell behavior.
- Avoid shell injection: pass arguments through appropriate process APIs and quote correctly when shell interpretation is genuinely required.
- Make host-versus-guest execution obvious in the interface and logs.
- Treat all terminal output and guest data as untrusted input.
VM and lab safety
- A lab manifest must declare target type, prerequisites, permissions, expected modifications, validation, cleanup and risk level.
- Before any system-changing lab, verify registered VM identity and required isolation/snapshot capabilities.
- Require explicit learner confirmation for potentially disruptive operations.
- Prefer dedicated test registry keys, directories, services and accounts over changing real configuration.
- Boot, network, ACL, security and domain labs must use disposable VMs and verified rollback strategies.
- Validate both the student's result and cleanup outcome; report incomplete cleanup accurately.
- Do not run fault-injection or destructive integration tests on the developer's host.
- Do not store VM passwords or tokens in plaintext logs or exported reports.
Course authoring standards
Every lesson must have:
- Stable ID, title, prerequisites and measurable objectives.
- Clear explanations of what, why and how.
- Windows-version and privilege assumptions.
- Genuine built-in tool examples where appropriate (GUI, CMD, PowerShell).
- Guided practice followed by independent work.
- Troubleshooting reasoning and verification steps.
- Explicit references to official documentation.
- Assessment criteria and expected evidence of competency.
Linux comparisons are allowed but supplemental. Do not teach Windows as merely Linux with renamed commands. Avoid requiring Zig programming for core administration lessons; optional Zig/Win32 exercises may deepen understanding.

Prefer assessments of actual state and reasoning over matching a particular command string. Never assert that keyword-based scoring can reliably judge free-form technical reasoning. Explain why an answer or repair is correct or incorrect.
Content, formats and storage
- Use Markdown for lessons and TOML for structured course/lab manifests and configuration.
- Validate manifests against versioned schemas or equivalent validators.
- Store progress, attempts and notes durably with migrations and export/backup support.
- Never couple course content to executable releases unnecessarily.
- Keep the core course readable offline. Online links are supplemental.
- Do not modify user progress destructively during schema migrations.
Dependency policy
When adding a dependency, record:
- Purpose and reason existing code/Windows APIs are insufficient.
- Upstream project and exact version or commit.
- License and redistribution requirements.
- Vendored location and any local changes.
- Build integration and offline verification procedure.
- Security/maintenance implications.
Do not depend on network package resolution in build.zig or installation scripts. Prefer a deterministic, reproducible build. Do not commit unlicensed third-party code.
Testing requirements
- Unit-test parsers, prerequisites, scoring, migrations and non-platform logic.
- Integration-test terminal behavior, OS interfaces and persistence on supported Windows versions.
- Test VM operations only on explicitly configured disposable guests.
- Test both successful and failed setup, validation and rollback.
- Validate curriculum manifests and ensure every required objective has suitable instructional material and assessment.
- Keep a documented manual GUI smoke-test checklist for navigation, accessibility, high-DPI and keyboard use.
- Mark tests requiring Windows, a hypervisor or a Windows Server guest; never silently skip and report a full pass.
Documentation and decisions
- spec.md: authoritative product goals, architecture, scope and acceptance requirements.
- outline.md: course sequence and learning objectives (to be authored separately).
- README.md: setup, supported environment, build, run and test instructions.
- docs/architecture.md: component boundaries and data flows.
- docs/references.md: primary official documentation sources.
- docs/decisions/: why consequential technical choices were made, including rejected alternatives and tradeoffs.
Update documentation when behavior changes. Never invent implementation status, API guarantees or citations.
Agent handoff expectations
At the end of a change, summarize files changed, learner-facing behavior, build/test commands and results, safety implications, and remaining work. If a requested feature requires an unvendored dependency, unsupported API, unavailable Windows test environment or missing VM, state the blocker and offer a compliant next step. Do not silently substitute a weaker feature.