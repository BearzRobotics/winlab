# 0002 — GUI toolkit

- **Status:** proposed (not accepted: no candidate has been built against Zig 0.17.1 yet)
- **Context:** spec §3.1 requires a keyboard-accessible, high-DPI, long-form-text GUI with accessible output, all dependencies vendored, offline build. Zig is pinned to 0.17.1 ([0001](0001-pin-zig-version.md)). Companion libraries by the project owner (toml-zig, md-zig, pdf-zig; all MIT, Zig 0.17.1, no dependencies) are available; md-zig exposes a public node tree and `Walker` intended for custom viewers.

## Evidence gathered (GitHub metadata/README/build.zig.zon, 2026-11-07; nothing built)
| Candidate | Declared min Zig | Notes |
|---|---|---|
| **dvui** (MIT) | 0.17.0 | Backends incl. SDL3, DX11, raylib, wio. Text entry, scroll areas, rich text layout with clickable parts. Keyboard nav in most widgets. AccessKit via `-Daccesskit`; no OS high-contrast integration; LTR-only simple text shaping; IME only on SDL/web. Dependencies are URL/hash in `build.zig.zon` (many `lazy`) -> would have to be vendored, incl. SDL3/freetype/zigwin32 fork. |
| Native Win32 (own bindings) | n/a | Best OS accessibility (UIA/MSAA, high contrast, DPI, IME) for standard controls; but long-form rich text, Markdown rendering and custom widgets must be hand-built; large bindings surface. |
| capy | 0.14.1 | Declared version far behind 0.17.1; unverified, treated as rejected for now. |
| zgui (Dear ImGui) | 0.16.0 | Immediate-mode; weak accessibility; poor fit for a screen-reader-accessible course reader. |
| raylib(-zig) | 0.17.0 (raylib), raylib-zig 0.14.0/archived | Game-oriented; no accessibility story. |

## Leading option
dvui with the DX11 (or SDL3) backend, rendering lessons from md-zig's tree, for development speed and a ready-made widget set. Main risks: accessibility is partial (AccessKit integration, no high-contrast OS hook), text shaping limits, vendoring size, and dvui is `0.6.0-dev`. Fallback: native Win32 shell with a custom-drawn lesson view.

## Required before accepting
1. In a throwaway directory, build the dvui DX11 and SDL3 standalone examples with Zig 0.17.1 on Windows 11 (not yet done; blocked by the session's permission policy for fetching external code).
2. Spike: render a md-zig document (headings, code, tables, links) in a scroll area; check keyboard-only navigation, 150%/200% DPI, text scaling, and Narrator behaviour with `-Daccesskit`.
3. Record vendoring plan (exact commits, licenses, checksums, local patches) per AGENTS.md dependency policy.

## Addendum: GTK4 (owner's dkde stack)
Evidence (dkde README, 2026-11-07): dkde uses GTK4 as **system libraries** (apt: libgtk-4-dev etc.) on Linux/Wayland, with GTK bindings from Ghostty's zig-gobject build, downloaded from deps.files.ghostty.org. The public repos show no Windows build of it. Considerations for WinLab:
- For: mature text (Pango/HarfBuzz, RTL, IME), DPI scaling, a toolkit the owner already uses; md-zig's tree is designed for a GTK viewer.
- Against: C/meson chain (GLib, GIO, Pango, Cairo, HarfBuzz, gdk-pixbuf, Graphene, ...) that `zig build` does not build; vendoring it means either vendoring all source and a meson build, or vendoring a pinned prebuilt Windows runtime (binaries + LGPL notices + checksums), which needs an explicit exception to AGENTS.md "vendor source". zig-gobject bindings must be vendored and verified on Zig 0.17.1. Windows screen-reader support in GTK4 is unverified here.
- Open: ask the owner how/where GTK4 was built on Windows previously (toolchain, runtime source, version).

## Update: direction chosen — native Win32 + RichEdit (owner, 2026-11-07)
GTK4 was rejected for now: dkde's Windows calendar is plain Win32/GDI (no GTK on Windows), and building GTK4's C stack with Zig build files is a large unverified effort. Spike implemented: `src/content/rtf.zig` (md-zig tree -> RTF, unit-tested, escapes untrusted text, raw HTML shown as text) and `src/ui/reader_win.zig` (Win32 window + RICHEDIT50W, read-only). `winlab view <file.md>` runs it. Verified: builds, 6 unit tests pass, window starts and stays up. NOT verified: visual output at 150%/200% DPI, keyboard-only use, Narrator behaviour, link activation (clicks currently do nothing; must restrict to http/https when added). Still **proposed** until those checks pass.

## Update: browser verified by screenshot (2026-11-07)
`winlab browse tests/fixtures/course` was captured with `PrintWindow` and inspected: headings, bold, bullets, generated manifest header, list font (10 pt Segoe UI scaled by DPI), link styling, and the link confirmation dialog all render as intended. Findings: RichEdit reports the link *target URL* as the clicked text for RTF HYPERLINK fields (links are resolved by URL, then by text, only against the page's own links); `ENLINK` is 4-byte packed in richedit.h so its fields must be laid out manually on x64 (asserted at compile time). Still unverified: 150%/200% DPI, WM_DPICHANGED (not handled), Narrator, Tab focus order, mouse selection. Status remains **proposed**.

## Update: settings, text scale, Tab order (2026-11-07)
Verified by screenshot/message tests: `text-scale = 200` scales both the list font and the reader (EM_SETZOOM must be re-applied after every text load or it is lost); corrupt/invalid settings are reported and defaulted; Tab was trapped in the reader (RichEdit claims it) so the message loop now toggles focus list<->reader explicitly. WM_DPICHANGED handling (move to suggested rect, rebuild font) is implemented but could not be exercised without changing the display scale. Theme is not applied. Status remains **proposed**.

## Update: migrated to DVUI (owner, 2026-11-21)
The owner chose DVUI. The browser is now `src/ui/gui.zig` (window, list grouped by area, search, status, notes, lab panel, dialogs) and `src/ui/md_view.zig` (md-zig tree -> DVUI widgets), on DVUI's Direct3D 11 backend, pinned to dvui commit `59c8d66` (needs Zig 0.17; v0.5.0 does not) and vendored in `zig-pkg/` with its lazy dependencies (zigwin32, freetype, tree-sitter, ...). RichEdit, `browser_win.zig`, `lab_win.zig` and `rtf.zig` are removed. The shell terminal window (`terminal_win.zig`) is still native Win32 and is opened from the Practice menu; DVUI's message pump drives it.
Segoe UI and Consolas are loaded from `%SystemRoot%\Fonts` (bundled Vera if absent). Verified by screenshot at 100% DPI only. NOT verified: 150%/200% DPI, Narrator (DVUI's accessibility is partial: AccessKit is off), keyboard-only use end to end, the lab panel against a real VM. Status stays **proposed** until those checks pass.
