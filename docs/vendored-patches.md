# Patches to vendored packages

`zig-pkg/` is tracked (ADR 0003), so a fix to a dependency is made in place. Every such change is listed here, so it can be reapplied or dropped when the package is updated. Updating or re-fetching a package **loses** its patches.

## FreeType 2.14.1: `src/autofit/aflatin.c`, accent adjustment (2026-11-26)

**WinLab crashed** (`signed integer overflow ... 'FT_Pos'`) on showing the draft Python lesson, in both the debug build and the installer's `ReleaseSafe` build (Zig traps C overflow in safe builds). `af_compute_vertical_extrema` leaves `FT_LONG_MAX` / `FT_LONG_MIN` in the limits of a contour it does not measure, and the two "find the nearest contour" loops of the accent adjustment subtract those values. The patch skips such a contour in both loops (`if ( max_y < min_y ) continue;`).

Reproduced with one lesson: it crashed as written and without its diagram, and ran with its accented letters (`é`, and the sample of mis-decoded text) replaced by plain ones. The same letters occur in other lessons. Other places in the file read the same arrays and are unchanged. Not reported upstream, and not checked whether a newer FreeType has fixed it.

## dvui 0.6.0-dev: `src/backends/dx11.zig`, `clipboardTextSet` (2026-11-26)

`CF_UNICODETEXT` data must end in a 16-bit zero. The function allocated `text.len * 2 + 1` bytes (one too few for it when the text is ASCII) and never wrote it, so text copied from WinLab could end in stray characters. The patch sizes the block from the converted UTF-16 length and writes the zero.

Seen by selecting lesson text, choosing Copy and reading the clipboard: it ended in a character that was not in the selection. Not reported upstream yet.
