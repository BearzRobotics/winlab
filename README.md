# WinLab

Offline-first Windows administration course (Zig, native Win32). Product contract: `ai/specs.md`;
engineering rules: `ai/AGENTS.md`. Design decisions are in `docs/decisions/` (0001-0007). The course
outline (a draft for review) is `outline.md`.

## Requirements
- Windows 11 x86-64, Zig **0.17.1** (ADR 0001). Building needs no network: dependencies (md, toml, pdf)
  are pinned in `build.zig.zon` and extracted into `zig-pkg/`, which release tarballs keep (ADR 0003).
- Optional, discovered at run time (never bundled): QEMU for lab VMs (ADR 0006), PowerShell 7,
  the Windows OpenSSH client (ships with Windows) and `curl.exe` (ships with Windows).

## Build, run, test
    zig build                       # build
    zig build run                   # version, shell and QEMU capability status
    zig build run -- browse course  # the course browser (lessons, search, notes, terminal, labs)
    zig build check-content         # validate course/ and labs/ (manifests, prerequisites, scenarios)
    zig build test                  # unit tests (some need QEMU and are reported as skipped without it)

## Commands (`winlab <command>`)
| Command | What it does |
| --- | --- |
| `browse [course-dir]` | Course browser: lessons, search (Ctrl+F), progress, notes, "Open terminal...", "Lab..." |
| `view <file.md>` | One Markdown file in the reader |
| `check <course-dir>` | Validate lesson manifests and the sibling `labs/` folder |
| `terminal <cmd\|powershell\|pwsh>` | A real shell in a ConPTY terminal window (ADR 0005) |
| `image list` / `image fetch <id>` | Installation media WinLab can download (asks first, HTTPS via curl.exe) |
| `image editions <iso>` / `image add <id> <iso> <server\|client> <index>` | Use an ISO you already have |
| `vm install <image-id> <vm-id>` | Build a lab VM (Windows Server unattended, or Ubuntu / AlmaLinux from a cloud image); runs until the guest answers over SSH |
| `vm resume\|list\|remove <vm-id>` | Continue an install, list VMs and scenarios, delete a VM WinLab created |
| `vm snapshot\|restore\|delete-snapshot <vm-id> <name>` | Snapshots of a stopped training VM |
| `vm reboot-test <vm-id>` | Prove a session survives a guest restart |
| `lab build\|verify <lab.toml> <vm-id>` | Author commands: bake a scenario, prove it works |
| `lab verify-set <vm-id> <lab.toml>...` | Prove several scripting labs in one boot |
| `coverage [exam-id]` | Show which certification domains have lessons and labs tagged to them |
| `lab start\|check\|reset\|end <lab.toml> <vm-id>` | The learner flow on the command line (the app's Lab window does the same) |
| `lab selftest <lab.toml> <vm-id>` | Run a lab live (inject, fix, validate, roll back) |

Settings are read from `%APPDATA%\WinLab\settings.toml` (`theme`, `text-scale`, `content-path`,
`qemu-path`, `lab-vm`); a bad key is reported and ignored, and the file is never rewritten.
Progress and notes live in `progress.toml` beside it (ADR 0004); registered VMs in `vms.toml`.
VM disks, keys and installation media are under `%LOCALAPPDATA%\WinLab\`.

## Layout
- `src/content/` Markdown to RTF, links, lesson manifests, catalog, search
- `src/storage/` settings, progress (atomic TOML files)
- `src/terminal/` ConPTY session and the VT screen model
- `src/vm/` provider interface, in-memory mock, QEMU provider and session supervisor, VM registry,
  image catalog and download, unattended-install answer files, ISO builder, guest control over SSH
- `src/labs/` lab manifests, scenario builder/runner, scripting-lab harness generator
- `src/ui/` browser, terminal and lab windows (Win32 + RichEdit)
- `course/` lessons; `labs/` lab files; `images/catalog.toml` downloadable media; `docs/decisions/` ADRs

## Status

**Verified on this machine** (Windows 11 Home, QEMU 11.1.1 with WHPX; unit tests pass; `zig build
check-content` is clean for 8 lessons and 43 labs):

- **Course browser:** Markdown rendering, search, notes, progress, text scale, dark theme, a real
  embedded terminal (CMD and Windows PowerShell 5.1). Eight draft lessons: architecture,
  troubleshooting method, and CMD / PowerShell / bash basics plus a control-flow lesson for each
  shell. **These lessons are drafts for the course owner's review.**
- **Lab VMs, built by WinLab:** Windows Server 2022 (unattended install from the evaluation ISO),
  Ubuntu 24.04 and AlmaLinux 9 (official cloud images, first-boot configured by a seed CD). SSH
  guest control with a per-VM key, snapshots, rollback, and a supervisor that keeps a session alive
  across guest restarts.
- **Baked scenarios** (the machine is broken ahead of time; the learner starts from a symptom):
  every scenario passes `winlab lab verify` (broken at start, fixable, and a reset breaks it
  again). Windows: 11. Ubuntu: 6. AlmaLinux: 9 (SELinux, firewalld, httpd, dnf, crond, and shared
  Linux labs).
- **Scripting labs** (the learner writes a CMD, PowerShell or bash script; Check runs it against
  freshly generated data and also checks exit codes and files left behind): 12 Windows labs pass
  `winlab lab verify-set`; 8 bash labs pass on both Ubuntu and AlmaLinux.
- **Lab window:** Start / Check / Hint / Reset / Stop VM on a worker thread. Driven end to end on a
  Windows VM and an Ubuntu VM: Start, a wrong answer gives precise feedback, the right answer
  gives "Fixed" and is recorded in `progress.toml`, Reset, close. (A lesson with several labs
  opens a menu first; that menu was driven by keystroke messages, not a real mouse.)

**Written but not verified:**
- The Windows 10/11 client install path (no client ISO available here; `-cpu max` itself boots
  under WHPX, shown with the AlmaLinux VM).
- The scripting-lab text shown to learners has not been reviewed for clarity by a person.

**Not done:**
- Curriculum beyond Part I: Parts II-VI (local administration, diagnostics, recovery, business IT,
  capstones) and an `outline.md`.
- Assessments (quizzes, rubrics, mastery tracking), a glossary and reference library, bookmarks,
  backup and export of progress.
- The Sysinternals advanced track and its external-tools label (ADR 0007).
- Narrator and real display-scaling checks (ADR 0002 stays "proposed" until they pass), a
  screen-reader-friendly terminal, searchable terminal history.
- Release packaging.

**Known limits and surprises** (details in the ADRs): QEMU on Windows takes no disk lock, so WinLab
detects a running VM itself; a guest restart inside one QEMU process hangs the BIOS under WHPX, so
QEMU runs with `-no-reboot` and is relaunched; baked faults must survive a reboot; Windows reserves
moving TCP port ranges, so ports are test-bound before use; a lab file's expected-value snippets are
code in the guest's own language (a bare word is a command, not a string).
