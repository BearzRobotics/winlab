*Draft for owner review.* Managing many devices is a different job from fixing one. This lesson covers the concepts behind modern endpoint management: how a device is enrolled and configured, how apps are delivered, and where the same ideas live in tools you can run locally. Cloud services (Microsoft Intune, Entra ID) need a tenant, which WinLab does not provide, so the practice here is the local equivalent.

## Provisioning a device

| Approach | What happens | Fits |
|---|---|---|
| Manual install | A person installs and configures | one machine |
| Imaging (answer file, captured image) | A prepared image is applied | many identical machines |
| Provisioning package | Settings and apps applied to a fresh install | small fleets |
| **Autopilot** | A factory-fresh device signs in, finds the organization, configures itself | remote and new devices |

An unattended install uses an **answer file** that supplies the answers the setup program would ask for. WinLab's own Windows installs use one: account, edition and options come from a file, not from clicking.

## Identity and enrollment

A device is **joined** to an identity system (a domain, or a cloud directory) and **enrolled** in a management service. Join answers "who owns this device"; enrollment lets the service push settings and apps. Home edition cannot join a domain; Pro and above can.

## Configuration

Settings are delivered as **policies**: Group Policy for domain machines, MDM profiles for enrolled devices. See "Windows updates and policy settings" for where they land on the machine. Design rules:

- Target by group, not by individual machine.
- Pilot on a small group first.
- Document each setting's purpose and owner.

## Applications

Apps arrive as installers (MSI, EXE, MSIX), through the Store, or through a package manager. Plan for **detection** (how the tool knows the app is installed), **requirements** (OS version, free space), **install command and exit codes**, and **uninstall**.

```
winget search 7zip          # package manager (if present)
Get-Package                 # installed packages (PowerShell)
wmic product get name       # legacy; slow, avoid on servers
msiexec /i app.msi /qn /l*v install.log     # silent MSI install with a log
```

Silent installs report success or failure in an **exit code** (0 success, 3010 success but reboot needed). The scripting lessons apply: check the code, do not trust the output.

## Update strategy

Keep an **inventory** (what is where, which version) so you can answer "which machines have not updated". Use rings: pilot, broad, last.

## Check yourself

1. What is the difference between joining a device and enrolling it?
2. Why does an app deployment need a detection rule?
3. Why do answer files make installs repeatable?
