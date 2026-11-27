# 0011: Challenges with flags

Status: accepted. One challenge exists (`labs/linux-challenge-night-visitor.toml`).

## Context

WinLab is to grow capture-the-flag style security practice. Labs until now could only pass or fail the final state of the VM. The owner decided on 2026-11-27: start with investigate-and-defend challenges on one VM (many other kinds are wanted later), stay offline (a scoreboard only if the course is ever made into a game, which is not decided), and start on Linux.

## Decision

1. A challenge is an ordinary scenario lab with `[[flags]]` tables: `name`, `question`, `recover`. Up to 8.
2. `setup` and `fault` plant each flag with `{{flag:name}}`, `{{flag_b64:name}}` or `{{flag_hex:name}}`. A manifest that plants an unknown flag, never plants a declared one, or no longer fits the 4000-byte guest script limit once filled in is invalid.
3. Every preparation draws new values (`WL{` + 12 random hex digits `}`). They are saved in `flags-<lab-id>.txt` in the VM's folder, with which ones have been handed in and whether the containment check passed. No record (or one that does not match the lab's flags) means the lab is not prepared, and it is built again.
4. `recover` is a guest script that prints the flag. `winlab lab verify` runs each one on the prepared machine before the solution, so a challenge whose flag cannot be found fails verification.
5. A challenge is complete when every flag has been handed in and the containment check (`[validate]`) has passed, in either order. Reset keeps the same flags; `winlab lab build --rebuild` makes new ones.
6. `winlab lab selftest` refuses a lab with flags: it does not keep a record.

## What this does not do

- **It does not stop cheating on one's own computer.** The record is plain text, the lab file shows how each flag is planted and recovered, and the learner is root in the VM. New values per preparation only stop answers being passed from one person or attempt to another. A scoreboard would need the checking to happen somewhere the learner does not control.
- There is no button in the window for new flags; use `winlab lab build <lab> <vm> --rebuild`.

The window has a **Challenges** menu listing every lab with flags (owner decision, 2026-11-27, after looking for the first challenge among the learning paths). A challenge can also be opened from its lesson's Practice menu. Learning paths do not list challenges separately.

## Writing a challenge

- Do not plant a flag in plain form, or `grep -r 'WL{'` finds them all. Encode it, and check on a built VM that no file holds a plain flag.
- Everything planted must be a harmless stand-in. No malware samples.
- Set `network = "isolated"` (decision 0010). The VM then cannot download, so use only what the image has.
- A stopped VM is saved without its memory: anything that should be running must be started again at boot.
- WinLab's own SSH sign-ins (labadmin from 10.0.2.2) are in the guest's logs. Say so in the briefing.

## Verified

2026-11-27, Ubuntu 24.04 lab VM, Windows 11 host with QEMU and WHPX.

- `winlab lab verify`: the prepared machine fails the check, all five flags are recovered, the solution passes, and Reset brings the failing state back. Passed twice, on separate preparations.
- In the guest: no file and no journal entry held a plain flag; nothing found from the setup scripts themselves; the VM had no default route and a connection to the internet failed while the intranet site answered; the deleted program was recovered from `/proc/PID/exe`; after killing only the process, the timer started it again; containing by expiring the account instead of restoring its shell reached the same final state, apart from the shell.
- Command line: wrong, correct (with surrounding spaces) and repeated answers; rebuild made five new values and the old answers were refused; selftest refused the lab.
- Window: briefing, isolation notice, hints, a failed and a passed check, a wrong flag, all five flags, "Challenge complete", completion saved to progress, and "Prepare and start" after the record was removed.
- Challenges menu (full course, from an unrelated lesson): the menu listed the challenge with its flag count and opened it. The "completed" suffix was not exercised.
- Unit tests cover placeholders, the record, manifest rules and the build/submit/rebuild lifecycle with the mock provider.

**Not tested:** a person solving it from the hints alone (the checks above used the reference commands), AlmaLinux or Windows challenges, and a Linux host.
