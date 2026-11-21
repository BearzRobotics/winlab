WinLab — Application Specification
Status: Initial architecture specification
Project type: Offline-first Windows administration education application
Implementation language: Zig
Primary target: Windows 11 x86-64
1. Mission
WinLab is a substantial desktop application that teaches Windows administration from the ground up through structured lessons, guided practice, controlled failures, independent troubleshooting, and competency assessments. The product is a course and learning environment, not a general-purpose IT repair toolkit. Students should finish able to operate Windows' own tools without WinLab.
1.1 Success criteria
A student can independently investigate an unfamiliar Windows issue; gather evidence; distinguish symptoms from causes; use graphical consoles, CMD, and PowerShell appropriately; make a safe repair; verify it; and explain their reasoning. The application must remain useful offline and preserve progress between sessions.
1.2 Non-goals
- Replacing Registry Editor, Event Viewer, Task Manager, PowerShell, or other Windows administration tools.
- Implementing a new CMD or PowerShell interpreter.
- Offering one-click repairs to arbitrary customer computers.
- Automatically executing potentially destructive fixes on the host.
- Requiring Zig knowledge to complete the administration course.
- Making Linux comparisons the primary instructional model.
2. Audience and learning model
The initial learner has substantial Linux familiarity but limited Windows administration experience. Do not assume knowledge of Windows terminology, shell conventions, security architecture, or administrative consoles. Linux comparisons may clarify concepts, but must identify important differences and remain optional.

Instruction progresses from guided observation to supervised practice to independent diagnosis. Completion is competency-based, not merely page-based. Each lesson defines measurable objectives and prerequisites. Each chapter includes conceptual instruction, demonstrations, guided exercises, independent labs, review, and a practical assessment. Prefer real system behavior over artificial command memorization.
3. Product experience
3.1 Desktop application
Provide a polished, keyboard-accessible Windows desktop GUI. Required primary areas:
1. Dashboard: current course, progress, upcoming reviews, recent lab activity.
2. Course browser: parts, chapters, lessons, objectives, prerequisites, search.
3. Lesson reader: formatted Markdown, images/diagrams, code samples, callouts, glossary links, references, note-taking and bookmarks.
4. Terminal workspace: actual CMD and PowerShell sessions with selectable shell, copy/paste, scrolling, searchable history, resize, exit status, and working directory display.
5. Lab workspace: prerequisites, VM status, lab instructions, hints, validation, reset and cleanup.
6. Assessments: knowledge questions, scenario prompts, practical checks, feedback and retry.
7. Progress: per-objective mastery, attempts, completion dates, review schedule and export.
8. Reference library: searchable Windows terminology, commands, cmdlets, error codes, administration consoles and links to official documentation.
9. Settings: appearance, accessibility, content paths, VM providers, shell discovery, backup/export.
UI toolkit is intentionally undecided. Evaluate native Win32 and suitable vendored Zig-compatible GUI implementations against text rendering, accessibility, high-DPI behavior, keyboard use, long-form content, and maintenance. Record the choice in docs/decisions/.
3.2 Terminal integration
Use Windows ConPTY for supported interactive terminal sessions. Support cmd.exe and Windows PowerShell 5.1 when present; discover PowerShell 7 (pwsh.exe) as optional. Preserve genuine shell semantics. Clearly indicate whether a terminal is running on the host or in a training VM. Do not silently elevate processes. Treat command explanations as curated references, not a promise to semantically interpret arbitrary commands. Terminal commands entered by students are never assumed safe.
3.3 Offline-first operation
Bundle the core curriculum, exercises, diagrams, glossary and local references. No login, cloud account, telemetry, or network service is required for the core course. External documentation links may open online, but lessons must not depend on those links to remain intelligible. Explicitly distinguish features requiring an installed hypervisor, a Windows Server guest, PowerShell 7, or network access.
4. Curriculum
The course begins with a mandatory introduction to Windows architecture and organization. A separate outline.md will eventually enumerate individual chapters; the following areas are normative curriculum coverage.
Part I — Foundations
- Windows editions, installation, desktop navigation and built-in administrative consoles.
- Kernel versus user mode; Win32; processes, services, sessions, users, profiles, filesystem layout, environment variables and registry overview.
- Troubleshooting method: reproduce, scope, observe, hypothesize, test, repair, verify, document.
- CMD fundamentals, batch files, quoting, redirection, pipes, environment variables and exit codes.
- PowerShell fundamentals: discovery, help, objects, pipelines, formatting versus data, scripts, execution policy and error handling.
Part II — Local administration
- NTFS and ReFS overview; paths, volumes, attributes, junctions and symbolic links.
- Registry hives, keys, types, views, permissions, backup and restoration.
- Processes, threads, services, startup mechanisms and scheduled tasks.
- Local accounts, groups, SIDs, access tokens, UAC, ACLs, inheritance and elevation.
- Software installation, uninstall, application configuration and package-management concepts.
Part III — Diagnostics
- TCP/IP, DNS, DHCP, routing, network profiles, SMB and Windows Firewall.
- Event Viewer, Windows Event Log, providers, event IDs, filtering and correlation.
- Device Manager, Plug and Play, drivers, hardware inventory and USB troubleshooting.
- Disk/partition/volume management, SMART limitations, storage health and BitLocker fundamentals.
- Boot process, BCD, recovery environments, updates, component store, SFC and DISM.
- Performance investigation: CPU, memory, storage, startup and resource monitoring.
Part IV — Repair and recovery
- Evidence-driven repair, least-destructive-first decision making, rollback and documentation.
- Safe Mode, WinRE, restore points, backups, file recovery and recovery media.
- Malware-response fundamentals, isolation and escalation without teaching security bypasses.
- Multi-symptom cases and customer-facing diagnosis.
Part V — Business IT
- Remote assistance, RDP, WinRM, PowerShell remoting and their security models.
- SMB shares, permissions, mapped drives and printer troubleshooting.
- Windows Server foundations, Active Directory, DNS, DHCP and Group Policy in isolated domain labs.
- Deployment fundamentals: installation media, unattended installation, imaging concepts and provisioning.
- Ticket handling, communication, evidence collection, privacy and escalation.
Part VI — Capstones
- Unfamiliar scenarios combining multiple systems.
- Independent fault identification, safe remediation, verification and written incident report.
- Final competency assessment with a rubric based on reasoning and outcomes, not specific command strings.
5. Content and assessment model
5.1 Content packaging
Store lessons as Markdown and structured, versioned TOML manifests. Each lesson manifest includes a stable ID, title, objectives, prerequisites, estimated effort, required Windows features, required VM topology, lab fixture identifiers, evaluation criteria and reference links. Content is validated during builds. Avoid embedding course text in Zig source files.
5.2 Lesson sequence
1. Objectives and prerequisites.
2. Theory and Windows mental model.
3. Demonstration through GUI and/or shell.
4. Guided lab with hints.
5. Independent lab with fewer prompts.
6. Assessment and explanation of the result.
7. Review material and relevant official references.
Not every subject needs identical CMD, PowerShell and API demonstrations; choose methods that are genuinely useful. Zig API demonstrations are optional enrichment, never a prerequisite for Windows administration competency.
5.3 Assessments
Support multiple choice, short answer, evidence-based reasoning, ordered troubleshooting procedures, and practical state validation. Automated checks must distinguish a desired final state from the exact command used to achieve it. For subjective reasoning, use explicit rubrics and permit self-review or instructor review; do not pretend a simple keyword match proves competence. Record attempts and allow retries. Store mastery separately from lesson-reading progress.
5.4 Review
Track objective-level performance and schedule targeted review. Students can revisit any material and manually mark areas for practice. Progress data remains local and exportable.
6. Lab and VM system
6.1 Baseline environment
A clean, licensed Windows 11 VM is the initial lab target. Support a WinLab desktop instance on the Windows host and an optional in-guest companion for local observation and exercise validation. VM management must be abstracted behind a provider interface. QEMU may be the first implementation; Hyper-V is a possible later backend. Do not assume either is installed. Windows Server and additional client VMs are introduced for domain labs.
6.2 Isolation and trust
A VM must be explicitly registered and identified as a training target before a lab can change its state. Never infer that the current host is disposable. Lab setup, fault injection and reset require explicit user action and clear target identity. Do not assume guest integration or snapshots are universally available. Verify provider capabilities before offering a feature.
6.3 Lab lifecycle
check prerequisites -> confirm target -> establish baseline -> apply controlled fixture -> student investigation -> validate state and evidence -> explain outcome -> cleanup/reset.

Each lab declares expected changes, permissions, scope, hazards, validation strategy, cleanup strategy and whether a snapshot is required. Changes to registry, ACLs, network settings, services or boot configuration must have a tested rollback procedure. Particularly disruptive exercises must require a disposable VM snapshot. The application must report incomplete cleanup rather than claiming success.
6.4 Lab categories
- Safe local fixtures: dedicated registry subtree, test files, test scheduled tasks and deliberately configured test services.
- VM-only system configuration: networking, permissions, update/boot recovery and other disruptive cases.
- Multi-VM labs: domain joins, AD, Group Policy, DNS, DHCP, remote access and file shares.
Do not inject arbitrary faults into the host. Guest control channels and credentials must be secured, scoped and documented.
7. Architecture
Organize code by responsibility, keeping core interfaces independent of the GUI:
winlab/
  AGENTS.md
  spec.md
  outline.md                 # later curriculum deliverable
  README.md
  build.zig
  build.zig.zon
  vendor/
  src/
    main.zig
    app/                       # orchestration and application state
    ui/                        # screens, widgets, navigation
    content/                   # Markdown, TOML, indexing, validation
    terminal/                  # ConPTY, shell discovery, sessions
    learning/                  # prerequisites, objectives, mastery
    assessment/                # rubrics, attempts, evaluators
    labs/                      # lifecycle, fixtures, validation
    vm/                        # provider interface and backends
    windows/                   # Win32 bindings and OS integration
    storage/                   # progress, notes, settings, migrations
    reporting/                 # exports and incident reports
  course/
    foundations/
    local-administration/
    diagnostics/
    recovery/
    business-it/
    capstones/
  labs/
    manifests/
    fixtures/
    validation/
    cleanup/
  assets/
  docs/
    architecture.md
    references.md
    decisions/
  tests/
    unit/
    integration/
    vm/
The exact structure may evolve through documented architectural decisions. Separate interfaces from platform backends. Avoid global mutable state unless justified. Keep code cohesive; favor small modules without arbitrary line-count mandates.
8. Technology and dependencies
- Zig is the primary implementation language. Pin and document the exact supported Zig compiler version; do not assume unstable standard-library APIs are portable across releases.
- All third-party source dependencies must be vendored in the repository with pinned versions, provenance, license notices and documented modifications. Build must not download dependencies implicitly.
- Prefer native Windows APIs where appropriate; vendored bindings and libraries are permitted when they improve correctness or maintainability.
- Configuration and lesson manifests use TOML. Select and vendor a parser or use an independently maintained local module; document the decision.
- Use a durable local database for progress, attempts and notes; SQLite is a candidate, not an irrevocable requirement. Vendor it if chosen. Provide schema migrations, backup and export.
- External system tools such as Windows-supplied executables, PowerShell 7 and hypervisors are environment prerequisites, not bundled source dependencies. Discover them and show capability status.
- No mandatory runtime downloads, accounts or hosted services.
9. Security, privacy and reliability
- No hidden elevation, unattended host repairs, automatic credential collection, or bypass of Windows security controls.
- Least privilege by default; explain elevation before operations requiring it.
- Treat command output, guest data, Markdown content, and imported files as untrusted.
- Escape/quote process arguments correctly; never concatenate untrusted input into shell commands unnecessarily.
- Restrict lab write operations to verified targets and declared fixture scopes.
- Redact secrets from logs and exports; make diagnostic collection opt-in and visible.
- Store progress locally with crash-safe writes and recoverable migrations.
- Respect NO_COLOR for any CLI/helper output; GUI theming is controlled separately.
- Support keyboard-only navigation, readable text scaling, high-DPI displays, and accessible contrast.
10. Testing and acceptance
10.1 Test levels
- Unit: content parsing, prerequisites, scoring, progress, migrations, command construction.
- Integration: ConPTY, shell discovery, Win32 integration, storage, UI smoke tests.
- VM: fixtures, snapshot/reset behavior, fault injection, validation, cleanup and safety boundaries.
- Curriculum: schema checks, reference checks, objective coverage, reproducible labs and assessment rubrics.
Never run destructive VM tests against an unverified host. Provide mock provider implementations for tests that do not need a hypervisor.
10.2 Initial delivery milestones
1. Foundation: reproducible Zig build, vendored dependency mechanism, GUI shell, settings and content loader.
2. Reader and progress: navigation, Markdown rendering, objectives, bookmarks, notes and persistence.
3. Terminal: real CMD/PowerShell sessions, shell detection and lesson linkage.
4. First course block: Windows architecture, navigation, troubleshooting methodology, CMD and PowerShell basics.
5. Labs: registered VM provider, safe fixture lifecycle, validation and reset.
6. Assessment: practical checks, rubrics, mastery tracking and review.
7. Expanded curriculum: local administration, diagnostics, recovery and business IT.
8. Polish: accessibility, packaging, export, full offline tests and capstones.
10.3 Definition of done
A feature is complete only when it is documented, tested on its declared supported environment, fails safely, works offline where promised, and has no undeclared dependencies. A lesson is complete only when its objectives, exercises, validation/assessment and references are reviewed. A VM lab is complete only when both setup and rollback have been verified on a disposable VM.
11. Open decisions
Record decisions with evidence in docs/decisions/ before committing to: GUI toolkit; Markdown rendering strategy; database implementation; first VM provider; guest control transport; content indexing/search; assessment serialization; Windows Server lab topology. These decisions must not block independent foundational work.
12. Authoritative references
Use official Microsoft Learn and Windows SDK documentation as primary references for Windows behavior, APIs, CMD, PowerShell, security and administration. Prefer Zig language documentation for compiler and build behavior. Include source links and applicable Windows/version assumptions in lessons and architectural decisions. Do not claim undocumented behavior as guaranteed.