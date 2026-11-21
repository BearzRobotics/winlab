# Verification scripts

Every code example in the scripting lessons was run before it was written down. These are the scripts that did it. They write only to temporary folders (`%TEMP%\wl-cmd-demo`, `%TEMP%\wl-ps-demo`, `wl-data`, `wl-mods`), so they are safe to re-run when a lesson changes.

- `cmd\*.cmd`: run with `cmd /c script.cmd` from a scratch folder. Clear `NoDefaultCurrentDirectoryInExePath` in the environment first (`Remove-Item Env:NoDefaultCurrentDirectoryInExePath`) if you want cmd's default behaviour.
- `powershell\*.ps1`: run under each edition: `powershell.exe -NoProfile -File x.ps1` (5.1), `pwsh -NoProfile -File x.ps1` (7), and on Linux `wsl -d Ubuntu-26.04 -- /home/dakota/pwsh/pwsh -NoProfile -File /mnt/c/.../x.ps1` (run `wsl` from PowerShell, not Git Bash).
- `srv.ps1`, `srv2.ps1`: throwaway local HTTP listeners (ports 8765 and 8766) so web examples need no internet. Start with `Start-Process pwsh -ArgumentList '-NoProfile','-File','srv2.ps1'`; `/stop` ends `srv2`.
- `rem2.ps1`, `rem3.ps1`, `rem1.ps1`: remoting tests meant to run **inside the Server lab VM** (copy with scp; they read the VM password from the environment variable `WLPW`, never from a file). `sshrem.ps1` is the host-side SSH-remoting client test (currently fails: see docs/HANDOFF.md section 8).
- Paths inside some scripts point at `C:\Users\Dakota\...`; adjust if the user name differs.
