# 0006: First VM provider and lab safety model

Status: accepted (2026-11-07)

## Context

Labs change system state (registry, services, ACLs, network, boot). The spec
requires a clean Windows 11 VM as the lab target, a provider interface that does
not assume any hypervisor, explicit registration of a VM as a training target,
and verified capabilities (snapshots, guest control) before a lab is offered.

## Decision

1. **QEMU is the first real provider.** It is named in the spec, is free, runs on
   every Windows edition (the development machine is Windows 11 Home, where
   Hyper-V is unavailable), and was found here as QEMU 11.1.1 with the `whpx` and
   `tcg` accelerators. Hyper-V remains a possible later provider behind the same
   interface.
2. **A provider interface plus a mock.** Lab logic depends only on the interface
   (`src/vm/provider.zig`). `src/vm/mock.zig` implements it in memory, with
   fault injection, so lab, safety and cleanup logic is tested with no hypervisor
   (AGENTS.md: mock providers for tests that do not need one).
3. **Discovery, not assumption.** QEMU is an environment prerequisite, never
   bundled. It is looked for in: the `qemu-path` setting, `PATH`, `C:\Program
   Files\qemu`, and the MSYS2 install (`C:\msys64\ucrt64\bin`). If it is not found
   the app shows capability status and the install guidance instead of failing.
   Acceleration (`whpx`) is reported, not required: `tcg` works but is slow.
4. **Registration is explicit.** A VM is usable by labs only when it is listed
   in `%APPDATA%\WinLab\vms.toml` with `training_target = true`, which the learner
   sets knowingly. The record identifies the target by id, display name, disk
   image path and provider. The current host is never a target.
5. **Snapshots first, for QEMU: `qemu-img snapshot` on the qcow2 disk while the
   VM is stopped.** It needs no guest cooperation and is the rollback boundary
   for every lab that declares `snapshot_required`. Providers declare
   capabilities (`snapshots`, `power`, `guest_exec`); a lab whose requirements
   exceed them is not offered.
   **Measured on this machine (QEMU 11.1.1, Windows): QEMU takes no image lock,
   and `qemu-img snapshot -c` succeeded against a disk a running QEMU had open**,
   which would corrupt the guest. So "is the VM running" is decided by WinLab, not
   by qemu-img: `diskInUse` opens the image with share mode 0, which fails with a
   sharing violation while any process holds it. Every modifying operation checks
   it first. Tested against a real paused QEMU process.
6. **Guest control transport is NOT decided here.** `guest_exec` stays a
   capability that no real provider claims yet, so no lab can change guest state
   until that decision (virtio-serial/QMP guest agent, SSH or an in-guest
   companion) is made and recorded.

## Safety rules enforced in code

- A lab runs only against a registered training target, whose identity (id and
  disk path) is shown before the first state change.
- A lab that needs a snapshot takes `winlab-pre-<lab id>` before setup and
  refuses to continue if that fails.
- Reset restores that snapshot; if restore or cleanup fails the result is
  reported as incomplete, never as success.
- Nothing runs automatically: setup, fault injection and reset are separate
  explicit actions.

## Consequences

- Everything but the QEMU process calls is testable without a hypervisor.
- Real QEMU snapshot/restore is verified here on a throwaway qcow2 file; that
  proves the mechanism, not a Windows guest. A guest lab is not complete until
  setup and rollback are verified on a disposable Windows VM (spec section 10.3).

## Targets, profiles and image provisioning (direction, not yet built)

Requested by the project owner: different VM setups for different tasks,
automated installation from an ISO with QEMU, and possibly Linux for IT
learning. The interface above already allows it; this records the intended shape.

- **Profiles.** A lab declares the *profile* it needs (OS, edition, role), not a
  specific VM; the learner registers a VM per profile. Edition matters: Windows
  11 Home cannot join a domain or run Group Policy editing, so domain/GPO labs
  need Pro, Enterprise or Server. Proposed priority (from the owner's list):
  Windows 11 Pro and Home, Windows 10, Windows Server 2022 and 2025 (essential
  or high), then Server 2019 and Windows 11 Enterprise (medium), then
  Windows 7/8.1 (low; legacy, unsupported, no new lab depends on it).
- **Automated installs.** A build recipe (TOML) would describe: ISO path and
  expected SHA-256, an `autounattend.xml` for the edition, disk size, memory,
  and (for Windows 11) a virtual TPM (`swtpm`) plus UEFI firmware. The learner
  supplies the ISO and licence or evaluation key; WinLab does not download or
  redistribute Windows. Microsoft's evaluation ISOs (Windows Server, Windows 11
  Enterprise) are the natural no-cost path for labs. The result is a golden
  qcow2 plus a `winlab-clean` snapshot, which every lab starts from. Not
  verified yet: no Windows install has been run here, so none of this is claimed
  to work.
- **Linux.** Linux labs can use the same provider interface with a Linux
  profile. Two cheap sources: prebuilt images (for example osboxes.org, whose
  VMDK/VDI images `qemu-img convert` turns into qcow2; licences and trust of the
  download are checked by the learner and a checksum is recorded), and WSL
  distributions, which already exist on this machine. A WSL provider would use
  `wsl --export` / `--import` as its snapshot/restore. Linux is outside the core
  Windows-administration spec, so it stays optional and later.
- **Guest control** remains undecided; the recipe approach could install an
  agent or enable OpenSSH during unattended setup, which is one candidate.

## Downloading media, and Windows 11 accounts (owner's direction, 2026-11-07)

- **Downloads are allowed**, as an explicit learner action only: WinLab shows the
  URL, size, free space and licence note, asks for "yes", then runs the system's
  `curl.exe` (full path under `%SystemRoot%\System32`, `--disable` so no `.curlrc`,
  HTTPS only including redirects, resume supported). The file is written as
  `.part`, size-checked, SHA-256 hashed and recorded, then renamed. No background
  or automatic fetching; no Windows activation or key handling by WinLab.
  This is separate from the build-time rule in AGENTS.md (no package downloads at
  build time): the build stays offline.
- **Verified:** `https://go.microsoft.com/fwlink/p/?LinkID=2195280` redirects to
  Microsoft's download host and serves the Windows Server 2022 evaluation ISO
  (5,044,094,976 bytes; last modified 2022-03-16). It is the only catalog entry
  so far. Microsoft publishes no checksum with it, so the hash is recorded after
  download rather than compared. Windows 10/11 Home and Pro have no stable direct
  URL (Microsoft issues time-limited links), so those need a learner-supplied ISO
  or URL; Server 2025 and Windows 11 Enterprise evaluation links are not yet
  checked and are therefore not listed.
- **Unkeyed installs.** Microsoft evaluation media installs without a key and is
  licensed for a trial period (Server: 180 days; Windows 11 Enterprise: 90 days).
  Lab VMs are short-lived and rebuilt from the clean snapshot long before that.
- **Windows 11 and the Microsoft-account prompt.** Home and Pro setup pushes a
  Microsoft account online. The unattended answer file can instead create a local
  account directly (`UserAccounts/LocalAccounts`, `AutoLogon`, and
  `OOBE/HideOnlineAccountScreens`), which should not depend on the ISO version;
  the old `oobe\bypassnro` trick is not relied on because newer builds removed it.
  Windows 11 Enterprise setup does not force a Microsoft account. If a given
  build ignores the answer file, the fallback is an older ISO. NONE OF THIS HAS
  BEEN TESTED: no Windows install has been run here yet.

## First end-to-end result: Windows Server 2022 under QEMU (2026-11-07)

`winlab vm install windows-server-2022-eval winlab-server2022` created a 48 GB
qcow2 disk, generated an answer file and random lab credentials, registered the
VM as a training target and started QEMU with WHPX. Observed with QMP
screenshots, on this machine (QEMU 11.1.1):

- Setup ran fully unattended (no language, disk or edition screens), rebooted
  itself, and reached the desktop with the Administrator account and the
  generated password. About 30 minutes in total.
- `winlab vm snapshot` took `winlab-clean` of the stopped VM through the QEMU
  provider; a file created inside the guest was gone after `winlab vm restore`
  and a reboot. **This is the first real proof of lab rollback on a Windows
  guest** (still only for a file, not yet for registry/service/ACL changes).

Things that did not work, so the defaults changed:

- The answer-file drive must look **removable**: as a plain USB disk QEMU's
  vvfat showed up as a fixed disk and Setup ignored it. `usb-storage,removable=on`
  fixes it. Disk 0 is the install target and the answer drive is Disk 1, so the
  answer file's `DiskID 0` wipe cannot hit it.
- With `-accel whpx,kernel-irqchip=off` the guest sat at the BIOS screen after
  Setup's first reboot (a busy vCPU, no boot). The same disk booted with plain
  `-accel whpx`, so that is the default now. Cause not isolated further.
- **Unexplained:** one early boot of the finished install paused itself
  (`status: paused`, `cont` stopped again within 5 ms) with no error output. It
  has not recurred in three later boots with the same arguments. Not diagnosed;
  watch for it, and capture QEMU's stderr when starting VMs.
- `system_powerdown` over QMP shuts the guest down cleanly in about 10 s, and the
  disk was safe to snapshot afterwards.

Not done: guest command execution (so labs still cannot run), a start/stop
command in the product (start was driven by a script), the Windows 11 path, and
removing the installer ISO from the boot order automatically (the first reboot
relied on the "press any key" prompt timing out).

## Guest control: OpenSSH (decided 2026-11-07)

Decision: lab scripts run inside the guest over **OpenSSH with a per-VM key**, as
PowerShell, through a QEMU port forward bound to 127.0.0.1 only.

- **Setup path.** The answer file's first-logon command runs
  `winlab-firstlogon.ps1` from the answer drive. It installs the OpenSSH Server
  Windows capability (a one-time download from Windows Update, so the guest needs
  internet once), starts `sshd` automatically, makes PowerShell the SSH shell, and
  authorises exactly one public key (`administrators_authorized_keys`, ACL limited
  to Administrators and SYSTEM). The private key (`id_ed25519`) and `known_hosts`
  stay in the VM's folder; the loopback port is in `guest.toml`.
- **Why SSH.** The Windows host already ships `ssh.exe`; it needs no guest agent
  of our own, no network exposure beyond loopback, and the key can be revoked by
  deleting the VM folder. Rejected for now: a QEMU guest agent / virtio-serial
  (needs drivers and a service we would have to ship), WinRM (heavier, password
  based by default).
- **Commands.** `ssh -o BatchMode=yes -o IdentitiesOnly=yes ... powershell
  -NoProfile -NonInteractive -OutputFormat Text -EncodedCommand <base64>`; scripts
  are capped at 4000 bytes; exit code 255 from ssh means "could not connect" and is
  never reported as a script result.
- **Power.** `start` spawns QEMU and returns once SSH answers (up to 6 minutes);
  `stop` runs `shutdown /s /t 0`, waits for the disk to be released, and only then
  ends the recorded QEMU process. The provider now reports `power` and
  `guest_exec` when `ssh.exe` is available.
- **Ports.** Windows reserves TCP port ranges that move (`netsh int ipv4 show
  excludedportrange`); one random port landed in 64405-64504 and QEMU failed with
  "Failed to bind socket". Ports are now proven by listening on them first.

Verified on the real Windows Server 2022 VM: `winlab lab selftest
labs/spooler-stopped.toml winlab-server2022` snapshotted, booted, waited for SSH,
stopped the Print Spooler, saw validation fail, applied the authoring solution,
saw validation pass, then stopped the VM and restored the snapshot (complete).
The SSH-enabling script was first run by hand on that VM and then frozen into the
`winlab-clean` snapshot; whether the **answer-file route** installs SSH on a fresh
VM is being verified with a second VM (see README status).

## Correction and result: restarts, answer media, SSH from the answer file (2026-11-08)

Two earlier explanations in this record were wrong and are replaced here.

- **The BIOS hang is not `kernel-irqchip=off` and not the USB answer drive.** It
  happens whenever the guest *restarts inside the same QEMU process*: SeaBIOS
  spins at one address forever (EIP stayed 0xEB72B across samples). A brand-new
  QEMU process on the same disk boots normally, with or without the answer media.
  Seen on three installs. Workaround: QEMU runs with `-no-reboot` and WinLab
  relaunches it after each guest restart (`winlab vm install` and
  `winlab vm resume` do this and finish when the guest answers over SSH; the
  provider's `start` also uses `-no-reboot`). Consequence for labs: a lab step
  that restarts the guest ends the QEMU process, so such labs need the runner to
  relaunch and wait; not built yet.
- **Answer media is now an ISO, not a USB drive** (`src/vm/iso9660.zig`, level 2,
  files `AUTOUNATTEND.XML`, `WINLAB_FIRSTLOGON.PS1`, `AUTHORIZED_KEY.PUB`). It was
  built because of the wrong USB theory, but it is simpler and deterministic, so
  it stays; Windows Setup reads it from the second CD-ROM. Boot order is disk
  first, installer ISO second.

Verified: on a VM installed entirely by `winlab vm install` (third install,
`winlab-lab-c`), SSH was enabled by the answer file's first-logon script with no
manual step, and `winlab lab selftest labs/spooler-stopped.toml winlab-lab-c`
passed with clean output (fault injected, failing validation, solution, passing
validation, snapshot rollback complete). The VM then got its own `winlab-clean`
snapshot.

## Direction: baked scenarios (owner's idea, 2026-11-08; not built)

Instead of injecting a fault when the learner starts a lab, build the broken
machine ahead of time and let the learner begin with the problem already there.

- **Shape.** A scenario is a lab plus a *baked snapshot*: starting from
  `winlab-clean`, run `setup` and `fault`, shut down, and snapshot as
  `winlab-scenario-<lab id>`. A learner session restores that snapshot, boots,
  and works the problem; reset restores it again. Starting is fast and does not
  depend on a script running correctly at the moment the learner clicks.
- **Why it matters.** It makes faults that need a restart possible (boot
  configuration, driver, startup and logon problems), because the restart
  happens while building the snapshot, not during a session. It also lets one
  clean image serve many scenarios (the ISO-built install is done once).
- **Learner view.** A scenario shows a symptom report ("the shared printer stopped
  working for me"), not the cause. The lab manifest keeps `fault` and `solution`
  for authors and for `lab selftest`; a `symptom` text and optional `hints` would
  be added, and the learner UI must not display the fault script.
- **Checks.** Validation stays about the final state (is the service healthy,
  is the setting correct), never the exact commands used.
- **Open questions.** Snapshot size grows with each scenario (qcow2 internal
  snapshots share data, so it stays small); scenarios built on an older clean
  image must be rebuilt when the clean image changes; the guest's clock and
  Windows Update behaviour after restoring old snapshots.
- **Prerequisite.** The restart-capable runner (relaunch QEMU after a guest
  restart), which the same supervisor code used for installs can provide.

### Finding from the first scenario `verify` (2026-11-08)

A baked scenario keeps the machine's *disk*, not its running state. The first
Print Spooler lab only stopped the service, so after the snapshot was restored and
the VM booted, the service started again and the scenario was not broken
(`verify` caught it: "validation before the fix: PASSED (unexpected!)").
**Faults must survive a reboot**: change startup types, configuration, files or
permissions, not just runtime state. The lab was changed to also disable the
service, and `lab verify` is now a required check for every scenario.

## Lab window, session supervisor, tooling (2026-11-08)

- **Lab window** (`src/ui/lab_win.zig`): the lesson view's "Lab..." button opens a
  window per scenario with the reported problem, Start / Check / Hint / Reset /
  Stop VM. Every step runs on a worker thread and posts its result back, so the
  window never freezes, and it will not close mid-step. A passing Check records the
  lab as completed under the lab's id in `progress.toml`, separate from lesson
  reading. The VM used is the `lab-vm` setting, else the first training target that
  has `guest.toml`; with no usable VM the button explains what is missing.
- **Session supervisor** (`src/vm/qemu.zig`): after `start`, a thread notices when QEMU
  has exited without a stop request (a guest restart) and relaunches it with the
  same arguments, never while the disk is still open (two QEMUs on one disk would
  corrupt it). `stop` ends the supervisor first. `waitReady` blocks until the guest
  answers and never runs a script. A guest *shutdown* looks like a restart and is
  also relaunched. If the app is closed with the VM left running, nothing
  supervises it any more.
- **Tooling:** `winlab check` also validates `labs/` (parse, unique ids, lesson
  exists, scenario has a solution and a hint); `winlab vm list` shows state, the
  clean snapshot and which scenarios are built; `winlab vm remove` deletes a VM
  WinLab created (asks first, only under `%LOCALAPPDATA%\WinLab\vms`).

## Direction: CMD and scripting labs (owner's idea, 2026-11-08; not built)

- **Shell-neutral scenarios.** Today every lab's setup, fault and validation is
  PowerShell, because that is what WinLab runs over SSH. That is only the harness:
  a learner may fix a problem with CMD (`sc`, `net user`, `icacls`, `reg`,
  `schtasks`, `netsh`) or PowerShell, and validation looks at the final state, so
  both work. Hints and lesson text should show both routes, and some scenarios
  should be written to be most natural in CMD.
- **Scripting labs** (a new lab kind): the task is "write a script", not "fix a
  fault". The learner writes a `.bat`/`.cmd` or `.ps1` in the VM (Notepad is
  enough) at an agreed path, from a starter file. **Check** runs it against **fresh
  fixtures generated at check time**, so hard-coding the answer cannot pass, and
  compares the output or resulting state with the expected result computed
  independently. The harness never reads the script's text for keywords; the
  spec forbids pretending keyword matching proves competence.
- **Sketch of a lab file:** `kind = "script"`, `task`, `language = "cmd" | "powershell"`,
  `script_path`, `starter`, and one or more `[[tests]]` each with a fixture
  generator, an expected-result script, and optional limits (run time, exit
  code). Ladder: CMD basics (redirection, loops with `for`, exit codes) to PowerShell
  (objects, pipeline, error handling) to scheduled/robust scripts.
- **Safety.** The learner's script runs only inside the disposable VM, after the
  snapshot, with a time limit; nothing runs on the host.

## Windows 10/11 client images: groundwork (2026-11-08; NOT tested, no client ISO available here)

Microsoft's consumer download page hands out time-limited links, so there is no
catalog URL for Windows 10/11 Home or Pro. The learner supplies the ISO:

1. `winlab image editions <file.iso>` mounts the ISO read-only for a moment, lists
   the editions in `install.wim` with their index numbers, and dismounts it
   (verified on the Server 2022 ISO).
2. `winlab image add <id> <file.iso> client <index> [name]` records it in
   `%LOCALAPPDATA%\WinLab\images\local.toml` by absolute path (nothing is copied).
   The catalog parser accepts `path` entries; `image list` and `vm install` use them.
3. `winlab vm install <id> <vm-id>` builds the VM exactly as for Server, with the
   `client` answer file: a local administrator account (no Microsoft account),
   online-account screens hidden, hardware-check bypass for TPM / Secure Boot / RAM
   (a plain QEMU VM fails them), and `cpu = "max"` in `guest.toml`, because Windows 11
   24H2 requires SSE4.2/POPCNT, which QEMU's default `qemu64` model lacks.

Unverified and likely to need work: whether `-cpu max` boots under WHPX on this
host; whether Setup accepts BIOS boot with the bypass keys on every build (newer
builds may need UEFI firmware, which is not set up); whether the local-account
route holds on current builds (the fallback is an older ISO, as noted earlier);
first-logon SSH setup on a client edition (OpenSSH capability name and ACL file
location differ slightly). A Windows 11 Home VM cannot join a domain, so
domain/GPO labs must target Pro, Enterprise or Server.

## Direction: Linux system-administration labs alongside Windows (owner's idea, 2026-11-08; not built)

The same lab ideas (a stopped service, a permissions problem, broken name
resolution, a disabled scheduled job, a locked account, a wrong time zone, a
change that needs a restart, scripting tasks) exist on Linux, and a learner who
administers both benefits from seeing them side by side. Nothing in the provider
interface is Windows-specific; what differs:

- **Images.** Official Ubuntu or Debian *cloud images* (qcow2) have stable
  download URLs and published SHA-256 sums, so the existing image catalog,
  download, and hash check apply, and the hash can actually be compared (unlike
  the Server ISO). No licence key is involved. WSL stays an option but is not a
  disposable VM with a snapshot model.
- **First boot.** Cloud images are configured by a cloud-init "seed" ISO (volume label
  `cidata`, files `user-data` and `meta-data`). `iso9660.zig` already builds
  small ISOs; it needs to allow hyphens in names. The seed creates the user,
  authorises the per-VM SSH key and enables SSH, so there is no unattended-install
  step and a VM is ready in about a minute.
- **Guest control.** Same per-VM key and loopback port. Scripts run under `bash`
  instead of PowerShell, so `guest.toml` gains a `shell` field and the SSH
  command line is built per shell.
- **Lab files.** A `target = "windows" | "linux"` field, and a lesson can list a
  lab for each OS. Validation is still final-state, never the exact commands.
- **Stock tools first** (ADR 0007) applies: `systemctl`, `chmod`, `getent`, `cron`/`systemd`
  timers, `ufw`/`nft`, `journalctl`, with nothing installed from outside the distribution.
