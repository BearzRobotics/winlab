# Code signing the Windows installer (guide, not yet done)

**Status (2026-11-22):** the installer and `winlab.exe` are **not signed**. Windows SmartScreen shows "Windows protected your PC"
on first run (More info > Run anyway). That is accepted for the beta. This page is what to do when that is worth fixing; reassess
before a wider release. Prices, eligibility rules and product names below change often: **check each provider's current page**
before acting. Nothing here was tested.

## What signing does and does not do

- A code-signing certificate proves who published a file. A signed installer shows the publisher's name instead of "Unknown publisher".
- It does **not** change how the installer works.
- A **self-signed** certificate is useless for the public: Windows does not trust it and the warning stays.
- Even a correctly signed file can show SmartScreen warnings until enough people have downloaded it (reputation builds over time).
  Do not promise testers a warning-free first run.

## What to sign

- `WinLab-<version>-x64.exe` (the installer, made by `installer/build-installer.ps1` with IExpress).
- Ideally also `winlab.exe` inside it, signed **before** it is packed, so the installed program is signed too. The portable zip then
  carries the signed exe.
- Sign, then compute `SHA256SUMS` (signing changes the file's bytes, so checksums must be made afterwards; `release.yml` already
  computes them in its last job, so signing must happen in the Windows job before the artifact upload).

## Options for an open-source project

| Option | Cost | Notes |
| --- | --- | --- |
| **SignPath Foundation** (signpath.org, open-source programme) | free | Apply with the project. They expect a public repository, an OSI-approved licence (GPL-2.0 qualifies), builds in CI (ours are) and a review of the project. Signing runs as a CI step against their service; the private key never leaves them. First choice. |
| **Azure Trusted Signing** (Microsoft) | about $10 a month | Works from GitHub Actions. Needs an identity validation of the publisher; eligibility depends on country and on being an individual or an organisation. |
| **A commercial certificate** (DigiCert, Sectigo, SSL.com and others) | a few hundred dollars a year | The private key must be on a hardware token or in the provider's cloud signing service, so it is the most work. |

## Plan when ready (SignPath Foundation)

1. Read their current eligibility page and application form.
2. Apply. The facts they will ask for: public repo `https://github.com/BearzRobotics/winlab`, licence GPL-2.0 (`LICENSE`), builds only
   in GitHub Actions (`.github/workflows/release.yml`), no closed-source parts, a description (offline Windows and Linux
   administration course with labs), and the release process in `docs/HANDOFF.md` section 8d.
3. Once approved, they give an organisation id and a project/signing policy. Store the API token as a GitHub Actions secret
   (for example `SIGNPATH_API_TOKEN`); never commit it.
4. In `release.yml`, in the `windows` job: build, upload the unsigned files as an artifact, call their GitHub Action to sign them
   (follow their current documentation for the action name and inputs), download the signed files, then continue. Keep the
   checksum step last.
5. Test on a tag that is not a real release (use a `-test` tag and delete the release afterwards). Right-click the installer >
   Properties > Digital Signatures should list the publisher; `Get-AuthenticodeSignature .\WinLab-*-x64.exe` should say `Valid`.
6. Update `README.md`, `installer/GETTING-STARTED.md` and the release notes: remove the "unsigned" wording, keep a short note that
   SmartScreen may still warn until the file has been downloaded often enough.

## Plan with Azure Trusted Signing or a commercial certificate

Same shape: put the credentials in GitHub Actions secrets, add a signing step after the build and before the checksums, and verify
with `Get-AuthenticodeSignature`. For a hardware-token certificate CI cannot sign; use the provider's cloud signing service instead,
or sign by hand on your machine with `signtool sign /fd SHA256 /tr <timestamp-url> /td SHA256 ...` (always timestamp, so the
signature stays valid after the certificate expires).

## Until then

The release notes say the installer is unsigned and the release publishes `SHA256SUMS`. Testers can compare the hash
(`Get-FileHash .\WinLab-*-x64.exe`) before choosing Run anyway.
