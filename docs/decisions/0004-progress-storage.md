# 0004: Progress and notes storage

Status: accepted (2026-11-07)

## Context

The spec needs per-lesson progress and learner notes, stored locally, readable
and recoverable by the user, with atomic writes and no hidden state. Search is
planned but the corpus is a few hundred lessons at most.

## Options

1. **TOML file** (`%APPDATA%\WinLab\progress.toml`) using the vendored toml-zig.
2. **SQLite**: needs build files for its C source, adds a binary format users
   cannot inspect, and is only valuable for indexed full-text search.

## Decision

Option 1. Keys are lesson ids (not titles or positions), so reordering or
retitling lessons keeps progress. Writes are atomic (temp file + replace). A
corrupt file is reported and never overwritten by an empty one. Entries with an
unknown status are dropped with a count; ids for lessons that no longer exist
are preserved. Notes are capped at 64 KiB per lesson. The file has
`schema_version = 1`; any other version is refused rather than guessed at.

Search is an in-memory scan of titles, summaries and bodies.

## Consequences

- No new native dependency; offline build and vendoring rules are unaffected.
- The whole file is rewritten on each save. Fine at this scale; revisit with
  SQLite only if notes volume or search needs outgrow it (a new ADR).
- Two running copies of WinLab can overwrite each other's changes (last writer
  wins). Accepted for a single-user desktop app.
