# 0001 — Pin Zig 0.17.1

- **Status:** accepted
- **Context:** Zig's standard library and build API change between releases (e.g. `std.Io`, `std.process.Init`). AGENTS.md requires a pinned, verified compiler.
- **Alternatives:** track latest/nightly (unstable); an older release (unfamiliar APIs, would need rework later).
- **Decision:** Pin Zig 0.17.1 (`minimum_zig_version` in `build.zig.zon`, asserted by a unit test in `src/app/version.zig`). Scaffold APIs were taken from `zig init` output of this exact compiler.
- **Tradeoffs:** upgrades are deliberate work; contributors must install this version.
