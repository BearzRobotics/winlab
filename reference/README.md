# Cached reference documents

> **Rights holders: takedown notice.** The documents in this folder are public. Copyright stays with their
> owners. They are kept here as preservation copies. **If you are the copyright holder of any document here and
> want it removed, tell the project owner and it will be removed.** Open an issue on the project's issue tracker
> (or contact the owner) and name the file. Nothing here is offered as a replacement for the original.

The lessons cite official documents: Microsoft Learn, the Linux manual pages, the RFCs and the IANA registries.
Each lesson links the official page at the point it is used. This folder keeps copies of those documents, as the
vendor or standards body publishes them, so a learner can read the exact text a lesson was written against
without a network (WinLab is offline-first), and so the references stay readable when a vendor moves or removes
a page.

- `MANIFEST.md`: every file, its source URL, sha256, which lessons cite it, and its licence status with the
  evidence quoted.
- `MANIFEST.tsv`: the same list for scripts. Both are produced by `gen_manifest.ps1`; do not edit them by hand.
- `fetch.ps1`: verifies every stored file against the manifest and downloads any that is missing
  (`fetch.ps1 -Check` verifies only; `-Force` replaces files whose checksum differs).
- `gen_manifest.ps1`: the one place a document is added. It downloads, hashes, reads the licence evidence out of
  the stored file, finds which lessons cite it, and rewrites the manifest.

## Rule for what is included

A document is included if it is **public** and **nothing explicitly prohibits redistributing it**. This is the
project owner's rule. The manifest then sorts what is stored into two honest groups:

| Section in `MANIFEST.md` | What | Licence status |
|---|---|---|
| **A. Permissive licence** | documents whose licence we read and which grants redistribution | CC-BY-4.0 (Microsoft Learn sources), CC0-1.0 (IANA registries), GPL-2.0 (iproute2 manual pages), IETF Trust Legal Provisions or the ISOC copyright statement (RFCs that grant copying), MIT and CC-BY licence texts. The evidence is quoted per file. |
| **B. Not explicitly granted** | free downloads where the document itself states no redistribution licence (early RFCs with no notice, and RFCs whose notice only says the authors retain their rights under BCP 78) | included on the owner's rule above; **these are the first to remove if a rights holder asks** |

A document that explicitly forbids redistribution is **not** stored. Check before you add one.

## Folders

| Folder | Contents | Source |
|---|---|---|
| `microsoft/windows-commands/` | Windows command reference pages (`ipconfig`, `netstat`, `ping`, ...) | Markdown sources from the MicrosoftDocs `windowsserverdocs` repository |
| `microsoft/powershell/` | networking cmdlet pages (`NetTCPIP`, `DnsClient`, `NetSecurity`) | MicrosoftDocs `windows-powershell-docs` repository |
| `microsoft/windows-server-networking/` | DHCP and DNS overviews | MicrosoftDocs `windowsserverdocs` repository |
| `linux/iproute2/` | `ip(8)`, `ip-neighbour(8)`, `ss(8)` manual pages (troff) | iproute2 repository on kernel.org |
| `iana/` | port-number and IPv4 special-purpose registries (CSV) | IANA |
| `rfc/` | the RFCs the lessons cite (plain text) | RFC Editor |

The Microsoft pages are Markdown **sources**, not the rendered Learn pages, so the files read well in any text
viewer (and in WinLab's own reader). Files are stored **verbatim**: nothing is edited.

## Attribution (Creative Commons BY 4.0)

Documentation from Microsoft Learn is © Microsoft Corporation and licensed under the Creative Commons
Attribution 4.0 International licence (`microsoft/LICENSE-CC-BY-4.0.txt`); code samples in those documents are
under the MIT licence (`microsoft/LICENSE-CODE-MIT.txt`). The files are not modified. The source of each file
is the URL in `MANIFEST.md`. The Linux manual pages are part of iproute2, under the GNU GPL v2
(`linux/iproute2/COPYING-GPL-2.0.txt`). The IANA registries are dedicated to the public domain under CC0 1.0.

## Preservation copies

A cached copy is a snapshot taken on the date it was fetched. **Prefer the original URL** (the lessons link it;
`MANIFEST.md` repeats it) for the current version. A checksum mismatch usually means the publisher updated the
document under the same URL: the stored copy is what the lesson was written against, so `fetch.ps1` keeps it and
warns.

## What is not cached

`MANIFEST.md`, section C, lists every URL the lessons cite that is **not** stored, with the reason where one is
known (for example a page that is generated from a template, or a source whose licence has not been read yet) and
"not stored yet" otherwise. It doubles as the to-do list for this folder.

## Adding a document

1. Read the document's licence or terms. Do not store it if they prohibit redistribution.
2. Add one `Add-Doc` call to `gen_manifest.ps1` with the real source URL (a mirror of doubtful origin is not
   acceptable), the page the lessons cite (`-Cite`), and the licence evidence quoted from the licence page.
3. Run `pwsh -NoProfile -File reference/gen_manifest.ps1` (Windows PowerShell 5.1 also works) and read the new
   entry in `MANIFEST.md`.
4. Cite the official URL in the lesson first; the local copy is a convenience.
