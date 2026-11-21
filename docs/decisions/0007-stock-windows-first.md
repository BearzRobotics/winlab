# 0007: Stock Windows first; Sysinternals as a labelled advanced track

Status: accepted (2026-11-08, project owner's direction)

## Context

A learner will meet machines whose installed software is unknown in advance. A
course that depends on third-party tools teaches skills that do not transfer to
the machine in front of them.

## Decision

1. **The core course teaches with what ships in Windows**: built-in consoles,
   CMD, Windows PowerShell 5.1, Event Viewer, Task Manager, Services, Task
   Scheduler, the registry editor, `netsh`, `sc`, `icacls`, built-in event and
   performance tooling. Every core lesson and lab must be solvable with these alone.
   PowerShell 7 stays an optional, discovered prerequisite (spec 3.2).
2. **An Advanced track may use Microsoft Sysinternals** (Process Explorer,
   Process Monitor, Autoruns, TCPView, PsTools, Sysmon, and similar). It is built
   after the core, and every lesson in it is labelled as using external tools.
3. **How it is handled:**
   - Lesson manifests will declare external tools (for example
     `external_tools = ["sysinternals"]`), the reader shows a visible
     "requires Sysinternals" label, and the capability status shows whether the tools
     are available.
   - WinLab does **not bundle or redistribute** Sysinternals (its licence limits
     redistribution). It is downloaded from Microsoft on the learner's explicit
     request, exactly like installation media (HTTPS, size and hash recorded,
     asked first), or the learner supplies their own copy. Inside lab VMs the tools
     are fetched or copied in by the lab's own setup, so the host is untouched.
   - The advanced track's lessons always say what the stock-Windows equivalent
     is and where it falls short, so the learner still learns the built-in way first.
4. **Labs follow the same rule.** A core lab's validation and solution use stock
   tools only; a lab that needs an external tool belongs to the advanced track and
   says so in its manifest.

## Consequences

- Core content stays fully offline and portable across machines.
- The advanced track is optional and may need a network connection once.
- Manifest and UI work is needed for the external-tools label and status (not built yet).
