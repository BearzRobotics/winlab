# 0003 — Vendoring Zig dependencies via zig-pkg

- **Status:** accepted (owner's direction, 2026-11-07)
- **Context:** AGENTS.md requires vendored dependencies and offline builds. The owner's libraries (md-zig, toml-zig, pdf-zig, ...) are Zig packages.
- **Decision:** Declare each in `build.zig.zon` with `url` + `hash` (added by `zig fetch --save <release tarball>`). Zig 0.17.1 extracts them into the project-local `zig-pkg/` directory. Release tarballs of WinLab include `zig-pkg/` (listed in `.paths`), so building from a release needs no network. Developers fetch only when adding or updating a dependency.
- **Pinned:** md 0.3.0, toml 0.1.0, pdf 0.2.0 (all MIT, Zig 0.17.1, no dependencies of their own), from github.com/BearzRobotics release tarballs.
- **Obligations (AGENTS.md dependency policy):** keep each package's LICENSE inside `zig-pkg/`; record upstream URL and hash in `build.zig.zon` (done); record any local patch in this directory (none so far); update by re-running `zig fetch --save` and reviewing the diff.
- **Tradeoffs:** `zig-pkg/` is committed/shipped (repo size); non-Zig dependencies (e.g. a GUI toolkit's C code) still need their own vendoring decision.
