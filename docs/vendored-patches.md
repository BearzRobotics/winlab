# Patches to vendored packages

`zig-pkg/` is tracked (ADR 0003), so a fix to a dependency is made in place. Every such change is listed here, so it can be reapplied or dropped when the package is updated. Updating or re-fetching a package **loses** its patches.

## dvui 0.6.0-dev: `src/backends/dx11.zig`, `clipboardTextSet` (2026-11-26)

`CF_UNICODETEXT` data must end in a 16-bit zero. The function allocated `text.len * 2 + 1` bytes (one too few for it when the text is ASCII) and never wrote it, so text copied from WinLab could end in stray characters. The patch sizes the block from the converted UTF-16 length and writes the zero.

Seen by selecting lesson text, choosing Copy and reading the clipboard: it ended in a character that was not in the selection. Not reported upstream yet.
