# WinLab

Offline-first Windows and Linux administration course (Zig, DVUI on Direct3D 11, Windows only). Product contract: `ai/specs.md`;
engineering rules: `ai/AGENTS.md`. Design decisions are in `docs/decisions/` (0001-0007). The course
outline (a draft for review) is `outline.md`.

## Requirements
- Windows 10 or 11 x86-64 (developed and tested on Windows 11 only), Zig **0.17.1** (ADR 0001). Building needs no network: dependencies (md, toml, pdf)
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
`qemu-path`, `lab-vm`, `setup-done`, `badges`); a bad key is reported and ignored. WinLab writes the file only to record that the first-run setup window was seen (`setup-done`).
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


**First run.** A setup window opens once. It lists what WinLab found (shells, the OpenSSH client, QEMU) and, if QEMU is
missing, your choices: a winget command to copy, the QEMU download page, or a `qemu-path` setting. WinLab never installs
software by itself. Reopen it from Help > Setup and requirements. The lessons need none of this; only the labs need QEMU.

## Status (2026-11-22)

`winlab check course` reports **68 lessons, 69 labs, 58 quiz files (2,296 questions) and 13 learning paths** with no
problems (18 path-ordering warnings remain: a lesson recommends a prerequisite that is not earlier on that path).
**Every lesson is a draft for the course owner's review**; each states what was tested and what was not, and cites
official documentation. Tracks: Windows administration, CMD, PowerShell (9 lessons), bash and POSIX sh, Linux
administration (systemd, dinit), networking, security fundamentals, cybersecurity (7), home lab (4), package
repositories (4), and certification-mapped paths.

**Tested on this machine** (Windows 11 Home, QEMU 11.1.1 with WHPX): badges (Lesson > Badges, derived from progress, off with `badges = false`), the course browser, search, notes and progress,
quizzes, learning paths, the embedded terminal (CMD and Windows PowerShell 5.1), the first-run setup window, text scaling to
200%, and the Copy and plain-text view features. Lab VMs built by WinLab: Windows Server 2022, Ubuntu 24.04, AlmaLinux 9
and Chimera Linux, with SSH guest control, snapshots and rollback. Baked scenarios pass `winlab lab verify`
(see `docs/HANDOFF.md`, appendix B, for the few that are still unverified).

**Not tested:** Windows 10 and the Windows 11 client install path (no client ISO here), Narrator and other screen readers,
typing into quiz answers by automation (blocked in the test environment), and anything on Linux or macOS.

**Not done:** a Windows installer, a Linux port (the window
backend, terminal and process handling are Windows-specific), the Sysinternals advanced track (ADR 0007), and an
OPNsense lesson (OPNsense 26.7 crashed under QEMU with WHPX in a first attempt; see `docs/HANDOFF.md`).

**Known limits and surprises** (details in the ADRs): QEMU on Windows takes no disk lock, so WinLab detects a running VM
itself; a guest restart inside one QEMU process hangs the BIOS under WHPX, so QEMU runs with `-no-reboot` and is
relaunched; baked faults must survive a reboot; Windows reserves moving TCP port ranges, so ports are test-bound before
use; a lab file's expected-value snippets are code in the guest's own language (a bare word is a command, not a string).
