# Reader spike: sample lesson

This file exercises the Markdown to RTF to RichEdit path. It is **not** course content.

## Inline formatting

Plain, *emphasis*, **strong**, ~~strike~~, `inline code`, and a [link to Microsoft Learn](https://learn.microsoft.com/windows-server/administration/windows-commands/windows-commands).
Unicode: café, Ω, 日本語, 😀

## Lists

1. Open an elevated terminal
2. Run the command
   - nested bullet
   - another
3. Verify

- [x] done task
- [ ] open task

> A quoted note: least-destructive-first.

## Code

```
Get-Process | Sort-Object CPU -Descending | Select-Object -First 5
```

| Tool | Shell |
|------|-------|
| dir | cmd |
| Get-ChildItem | PowerShell |

---

End.
