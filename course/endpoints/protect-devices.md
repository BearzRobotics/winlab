*Draft for owner review.* Protecting an endpoint means layers: a firewall, malware protection, disk encryption, and sign-in controls, each checked on the machine and enforced by policy. Built-in tools only.

## Windows Defender Firewall

Three profiles: **Domain** (joined to a domain network), **Private** (trusted network), **Public** (everything else). Each is on or off, and has default inbound and outbound actions.

```
Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction
Get-NetFirewallRule -Enabled True -Direction Inbound | Select-Object -First 10 DisplayName, Action
Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True
```

Switching a profile off turns off every rule in it at once, which is why "I turned it off to test" is a finding in a security audit. Prefer opening one port with a rule.

## Microsoft Defender Antivirus

```
Get-MpComputerStatus | Select-Object AntivirusEnabled, RealTimeProtectionEnabled, AntivirusSignatureLastUpdated
Update-MpSignature
Start-MpScan -ScanType QuickScan
```

Real-time protection should be on. Signatures should be recent. A third-party antivirus may switch Defender to passive mode; that is expected.

## Disk encryption

**BitLocker** encrypts a volume so a lost or stolen machine does not give up its data. It needs a TPM for the best experience (or a startup key). Key facts:

- The recovery key must be stored somewhere safe, such as Active Directory or the management service, *before* it is needed.
- `manage-bde -status` shows each volume's protection state.
- It is available on Pro and above; Home has a lighter "device encryption" on supported hardware.

## Sign-in and account protection

- Require a strong sign-in: PIN or biometrics with Windows Hello for Business, or MFA with a cloud identity.
- Use standard accounts for daily work; keep UAC on.
- Lock screens after inactivity (policy: "Interactive logon: machine inactivity limit").

## Compliance

Management services check each device against rules (encryption on, firewall on, OS version recent) and mark it compliant or not. Access to company data can then require a compliant device. The checks are the same facts you read with the commands above, so you can verify a "non-compliant" report by hand.

## Check yourself

1. A scan says "firewall disabled". Which command shows which profile, and which fixes it?
2. Why must a BitLocker recovery key be saved before the drive is encrypted?
3. What does it mean when Defender reports passive mode?
