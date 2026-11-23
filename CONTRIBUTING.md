# Contributing to WinLab

Thank you for helping. WinLab is a beta: the lessons are **drafts**, and the most useful help is finding what is wrong.

## Reporting a problem

Open an issue and pick the template:

- **Lesson or quiz error**: a wrong claim, a command that does not behave as the lesson says, a broken link, a confusing step.
  Say which lesson (the id shown under its title, for example `foundations.architecture`), your Windows or Linux version, and what
  you saw instead. Paste real output.
- **Bug**: a crash, a wrong window, a lab that will not start. Use **Help > Copy diagnostics (for bug reports)** in the app and paste
  the result. Say whether you used the installer, the portable zip or the Linux tarball.
- **Lab**: a scenario that cannot be fixed, or cannot be broken, or whose check is wrong. Name the lab file in `labs/`.

Please do not paste passwords or private keys. Lab VM credentials are throwaway, but still leave them out.

## Lessons: the rules

Every lesson states what was tested and what was not, cites official documentation with inline links, and shows real output.
If you correct a lesson, run the commands yourself and say on which system you ran them. Content rules are in `ai/AGENTS.md`.
Bash scripts that use bash features name `bash` in the shebang; `#!/bin/sh` means POSIX only.

## Code

    zig build test              # unit tests (labs need QEMU and are skipped without it)
    zig build check-content     # validates every lesson, lab, quiz and learning path

Both must pass before a pull request; CI runs them on Windows and Linux. Zig is pinned at 0.17.1. Platform differences belong in
`src/platform.zig`, not scattered through the code. Keep changes small and explain the reason in the description.

## Licence

By contributing you agree that your contribution is licensed under GPL-2.0, like the rest of the project (see `LICENSE`).
