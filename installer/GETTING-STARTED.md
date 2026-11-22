# WinLab: getting started (beta)

WinLab is an offline course for Windows and Linux administration: lessons, quizzes, learning paths and (optionally)
hands-on labs in virtual machines. **This is a beta. Every lesson is a draft** that says what was tested and what was
not. Your review is the point of this build.

## Install
- **Installer:** run `WinLab-<version>-x64.exe`. It installs for your user only (no administrator rights), adds a
  Start menu entry and an entry under Settings > Apps > Installed apps. The installer is **not code-signed yet**, so
  Windows SmartScreen may warn: choose "More info" > "Run anyway". Check the file against the SHA-256 list that came
  with it if you want to be sure.
- **Portable:** unzip `WinLab-<version>-portable.zip` anywhere and run `winlab.exe`.
- **Uninstall:** Settings > Apps > Installed apps > WinLab, or run `Uninstall-WinLab.ps1` in the install folder.
  Your settings and progress (`%APPDATA%\WinLab`) and any lab VMs (`%LOCALAPPDATA%\WinLab`) are kept.

## First run
A **setup window** shows what WinLab found on your PC. The lessons need nothing else. For the **labs** you need QEMU
(an emulator); if it is missing the window gives you a winget command to copy, the download page, or a setting to point
at an existing install. WinLab never installs software by itself. Reopen it from **Help > Setup and requirements**.
Then pick a **learning path** (advice, not a lock) or browse all lessons.

## Using it
- **Search:** Ctrl+F. **Text size:** Ctrl+= and Ctrl+-. **Dark theme:** View menu.
- **Progress** is saved per lesson; take a lesson's quiz to mark what you already know.
- **Practice** menu: open a real Command Prompt or PowerShell, or start a lab for the current lesson.
- **Copy** buttons on code blocks, and Lesson > Copy whole lesson, copy text out of the app.

## Labs (optional)
Labs run in virtual machines that WinLab builds from official images (Windows Server evaluation, Ubuntu, AlmaLinux,
Chimera). They need QEMU, the Windows OpenSSH client (a Windows optional feature), a few GB of disk, and an internet
connection the first time to download images (WinLab asks first). Hardware acceleration (Windows Hypervisor
Platform) makes them much faster.

## Reporting a problem
Use **Help > Copy diagnostics** and paste the result into your message, with what you did and what you expected. For
lesson errors say the lesson title and the line. Things a beta tester can most usefully tell us: a command that did
not behave as the lesson says (and your Windows version), a quiz question that is wrong or unclear, anything that
confused you.

## Known limits
Windows 11 is where this was developed; Windows 10 is untested. Narrator and other screen readers are untested.
There is no Linux or macOS version. The installer is unsigned.

## Silent install (for scripts)
Run `WinLab-<version>-x64.exe /Q` for a quiet per-user install, or `Install-WinLab.ps1 -Quiet` from the extracted files
(`WinLab-<version>-x64.exe /C /T:<folder>` extracts without installing). `-InstallDir` changes the folder.
