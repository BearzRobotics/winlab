# 0005: Terminal workspace

Status: accepted (2026-11-07)

## Context

The spec (3.2) requires real CMD and PowerShell sessions through ConPTY, with
copy/paste, scrolling, resize, exit status and a visible host/VM indicator, and
no silent elevation. AGENTS.md forbids faking shell behaviour.

## Decision

- **ConPTY** (`src/terminal/conpty.zig`) hosts the unmodified shell
  (`cmd.exe`, `powershell.exe -NoLogo`, optional `pwsh.exe -NoLogo`). The shell
  inherits the current token and environment: no elevation, no altered profile.
  `STARTF_USESTDHANDLES` is set with null handles, otherwise the child inherits
  WinLab's own redirected stdio instead of the pseudo console (found by test).
- **No threads.** A 15 ms UI timer polls the output pipe (`PeekNamedPipe`), so
  there is no locking. Our pipe ends are closed before `ClosePseudoConsole`,
  which can otherwise block.
- **Own screen model** (`src/terminal/screen.zig`): a bounded VT parser (cursor,
  erase, scroll regions, SGR incl. 256/truecolor, alternate screen, DSR/DA
  replies, OSC title and cwd). Output is untrusted: unknown sequences are
  ignored, sizes and string lengths are capped, titles have control characters
  removed. This is rendering, not shell emulation; shell semantics stay real.
- **Window** (`src/ui/terminal_win.zig`): GDI-drawn grid, always a dark palette
  (PSReadLine and similar choose colours for dark consoles). Mouse selection,
  Ctrl+C copies when text is selected (otherwise it interrupts), Ctrl+V pastes,
  mouse wheel and Shift+PgUp/PgDn scroll, 5000 lines of scrollback.
- **Safety:** the title says the shell runs on this computer as the current
  user. Pasted text has control characters removed, and a multi-line paste asks
  first (default No) because each line would run. Closing the window while the
  shell runs asks first and then ends the shell.
- **Lesson linkage:** the lesson list offers "Open terminal..." with each
  installed shell; the terminal title names the lesson it was opened from.
  Nothing starts until the learner chooses.
- `winlab terminal <cmd|powershell|pwsh>` opens a terminal on its own.

## Known limits

- A custom-drawn grid is not exposed to screen readers like a standard control.
  Ctrl+Shift+A copies the whole buffer as text as a workaround. This is a real
  accessibility gap; a UI Automation text provider is future work.
- No searchable history yet, no training-VM sessions (labs milestone), no
  hyperlink or IME support, wide (CJK) characters are drawn one cell wide.
- The working directory is shown only if the shell announces it (OSC 9;9);
  otherwise the title shows the directory the shell started in.
- Keys are not mapped for F-keys or Ctrl/Alt arrow combinations yet.
