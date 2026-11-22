*Draft for owner review.* **Threat modelling** is deciding, before you build or harden anything, **what could go wrong and what you will do about it**. Without it, hardening is a list of settings someone once recommended; with it, each control has a reason and each gap is a decision you made on purpose. This lesson is mostly thinking, and I say so. The part that runs on a computer is a small bash script that ranks a threat table and fails when an open threat is too serious, which I tested on two VMs. Your own lab only.

**What was tested, and where.** `wl-threats.sh` (below) ran on **Ubuntu 24.04.5** (bash 5.2.21, GNU Awk 5.2.1) and **AlmaLinux 9.8** (bash 5.1.8, GNU Awk 5.1.0) with identical output (`tests/verification/security/sc7.sh`). **Not tested:** anything beyond that script. The method itself (the questions, STRIDE) comes from the two sources cited, whose pages I read for the quoted parts only; I did not use a threat-modelling tool, draw a formal data-flow diagram in software, or test the method on a real project. The example table is **mine**, written for a home lab; the likelihood and impact numbers are **judgements**, not measurements.

## Three questions

The [OWASP Threat Modeling](https://owasp.org/www-community/Threat_Modeling) page frames the work as a few plain questions, which are all you need at home:

1. **What are we working on?** (assets, parts and how they connect)
2. **What can go wrong?** (threats)
3. **What are we going to do about it?** (controls, or a decision to accept the risk)

It also lists structured ways to answer the second one, naming STRIDE, kill chains and attack trees. I would add a fourth question of my own, **did we do a good enough job?**, answered by testing the controls (the earlier lessons in this track are how).

### 1. What are we working on?

Write down, on one page:

- **Assets**: things worth protecting. For the owner's lab: family photos on a file share, the backup repository, the **package-repository signing key** (a leaked key lets someone publish a package your machines will trust, see the packaging lessons), the DNS server, the logs, the lab VMs themselves.
- **Components and data flows**: who talks to whom (a laptop to the file share over the LAN; a VM to the repository over HTTP; you to a VM over SSH).
- **Trust boundaries**: lines where the level of trust changes: the internet versus the home LAN; the LAN versus a guest Wi-Fi; a VM versus its host; a normal user versus root. **Most threats happen when data or a command crosses a boundary.**
- **Who the attackers are, and what they want** (be modest: a bot scanning the internet for SSH passwords is a real attacker; a targeted nation-state is probably not your threat).

### 2. What can go wrong? STRIDE

Microsoft's [threat modelling tool documentation](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats) describes the **STRIDE** model, which "categorizes different types of threats". Six letters, one per kind of threat; ask all six of each component:

| Letter | Threat | Plain meaning | A lab example |
|---|---|---|---|
| **S** | Spoofing | pretending to be someone or something else | a stolen SSH password; a fake package from a forged repository |
| **T** | Tampering | "malicious modification of data" (Microsoft's words) | ransomware encrypting the backup; a changed `Packages` index |
| **R** | Repudiation | being able to deny doing something, because nothing recorded it | an intruder deletes the log, so nothing can be proved |
| **I** | Information disclosure | data reaching someone who should not see it | a guest reading the family photos |
| **D** | Denial of service | making a service unavailable to valid users | flooding the DNS server |
| **E** | Elevation of privilege | an unprivileged user gains privileged access | a guest VM escaping to the host; a user becoming root |

The same page defines tampering as "the malicious modification of data", denial of service as attacks that "deny service to valid users", and elevation of privilege as "an unprivileged user gains privileged access and thereby has sufficient access to compromise or destroy the entire system". The other three rows in the table are my paraphrases, not quotes.

### 3. What are we going to do about it?

For each threat there are four honest answers: **mitigate** (add a control), **avoid** (remove the feature), **transfer** (let someone else carry it, for example insurance, or a hosted service) or **accept** (write down that you know). "We will not do anything about this one, because..." is a legitimate row. "We did not think of it" is the failure.

## A threat table you can run

A table in a text file can be checked by a program. The format is **tab-separated**, one threat per line: `id`, `element`, `stride` (one letter), `threat`, `likelihood` (1 to 3), `impact` (1 to 3), `control`, `status` (`open`, `planned`, `done`). Risk is **likelihood times impact**, from 1 to 9: crude on purpose (a simple method; there are finer ones). The ranker (bash shebang; the work is in `awk`, which was GNU awk on both machines; I did not test mawk or busybox awk):

```bash
#!/bin/bash
# wl-threats.sh THREATS.tsv [MIN_RISK]
# Rank a threat table. Input is tab-separated, one threat per line, '#' lines and blank lines ignored:
#   id  element  stride  threat  likelihood(1-3)  impact(1-3)  control  status(open|planned|done)
# Prints the threats by risk (likelihood x impact, highest first), a count per STRIDE letter and per status.
# Exit status: 0 fine, 1 if an open threat has risk >= MIN_RISK (default 6), 2 on a bad table.
file=${1:?usage: wl-threats.sh THREATS.tsv [MIN_RISK]}; min=${2:-6}
[ -r "$file" ] || { echo "wl-threats: cannot read $file" >&2; exit 2; }

awk -F'\t' -v min="$min" '
  /^#/ || NF == 0 { next }
  {
    if (NF != 8)                            { printf "wl-threats: line %d: expected 8 tab-separated fields, found %d\n", NR, NF > "/dev/stderr"; bad = 1; next }
    if ($3 !~ /^[STRIDE]$/)                 { printf "wl-threats: line %d: STRIDE must be one letter of S T R I D E, got \"%s\"\n", NR, $3 > "/dev/stderr"; bad = 1; next }
    if ($5 !~ /^[123]$/ || $6 !~ /^[123]$/) { printf "wl-threats: line %d: likelihood and impact must be 1, 2 or 3\n", NR > "/dev/stderr"; bad = 1; next }
    if ($8 !~ /^(open|planned|done)$/)      { printf "wl-threats: line %d: status must be open, planned or done, got \"%s\"\n", NR, $8 > "/dev/stderr"; bad = 1; next }
    if (seen[$1]++)                         { printf "wl-threats: line %d: duplicate id %s\n", NR, $1 > "/dev/stderr"; bad = 1; next }
    n++; risk[n] = $5 * $6; id[n] = $1; st[n] = $3; el[n] = $2; status[n] = $8; thr[n] = $4; ctl[n] = $7
    bystride[$3]++; bystatus[$8]++
    if ($8 == "open" && risk[n] >= min) flagged++
  }
  END {
    if (bad) exit 2
    for (i = 1; i <= n; i++) order[i] = i                 # insertion sort: risk high to low, then id
    for (i = 2; i <= n; i++) {
      v = order[i]; j = i - 1
      while (j >= 1 && (risk[order[j]] < risk[v] || (risk[order[j]] == risk[v] && id[order[j]] > id[v]))) { order[j + 1] = order[j]; j-- }
      order[j + 1] = v
    }
    printf "%-4s %-5s %-1s %-16s %-8s %s\n", "RISK", "ID", "S", "ELEMENT", "STATUS", "THREAT  ->  CONTROL"
    for (i = 1; i <= n; i++) { k = order[i]; printf "%-4d %-5s %-1s %-16s %-8s %s  ->  %s\n", risk[k], id[k], st[k], el[k], status[k], thr[k], ctl[k] }
    printf "\nby STRIDE letter:"; split("S T R I D E", L, " "); for (i = 1; i <= 6; i++) printf " %s=%d", L[i], bystride[L[i]] + 0; printf "\n"
    printf "by status:"; split("open planned done", S, " "); for (i = 1; i <= 3; i++) printf " %s=%d", S[i], bystatus[S[i]] + 0; printf "\n"
    if (flagged) { printf "%d open threat(s) with risk >= %d\n", flagged, min; exit 1 }
  }' "$file"
```

The input I wrote for a small home lab (tabs between fields; shown here with spaces for reading):

```text
T1  ssh on the VM    S  someone guesses a password and logs in               3 3  key-only login, PasswordAuthentication no (wl-baseline.sh)   done
T2  samba share      I  a guest reads the family photos                      2 3  valid users = @group, no guest access                          done
T3  backups          T  ransomware encrypts the only backup                  2 3  restic repo on a second disk plus an offline copy             planned
T4  repo signing key S  the signing key leaks and a fake package is published 1 3  key kept offline, subkeys, rotation plan                       open
T5  dns server       D  the resolver is flooded                              1 2  listen on the LAN only                                         done
T6  logs             R  an intruder deletes the logs so nothing can be proved 2 2  ship logs to a second machine                                    open
T7  vm host          E  a guest escapes to the host                          1 3  keep the hypervisor patched                                    open
```

The output (identical on both VMs):

```text
$ wl-threats.sh lab.tsv
RISK ID    S ELEMENT          STATUS   THREAT  ->  CONTROL
9    T1    S ssh on the VM    done     someone guesses a password and logs in  ->  key-only login, PasswordAuthentication no (wl-baseline.sh)
6    T2    I samba share      done     a guest reads the family photos  ->  valid users = @group, no guest access
6    T3    T backups          planned  ransomware encrypts the only backup  ->  restic repo on a second disk plus an offline copy
4    T6    R logs             open     an intruder deletes the logs so nothing can be proved  ->  ship logs to a second machine
3    T4    S repo signing key open     the signing key leaks and a fake package is published  ->  key kept offline, subkeys, rotation plan
3    T7    E vm host          open     a guest escapes to the host  ->  keep the hypervisor patched
2    T5    D dns server       done     the resolver is flooded  ->  listen on the LAN only

by STRIDE letter: S=2 T=1 R=1 I=1 D=1 E=1
by status: open=3 planned=1 done=3
exit status 0
```

With the default threshold of 6 no **open** threat is serious enough to fail (the two risk-6 rows are `done` and `planned`), so the exit status is `0`. Lowering the threshold to 4 (`wl-threats.sh lab.tsv 4`) printed `1 open threat(s) with risk >= 4` and exit status `1`: the log-deletion row (T6). The point of the exit status is the same as in the other scripts: a scheduler or a commit hook can fail when the table says something is open and serious.

Bad input is rejected with a line number and exit status 2: a STRIDE letter that is not one of the six (`got "Q"`), a number outside 1 to 3, a line with seven fields instead of eight, a duplicate id, a status that is not `open`, `planned` or `done` (`got "maybe"`), and a missing file. I tested each.

## Reading the table

- **Done does not mean safe.** T1 is `done` and still ranks first: the *residual* risk after a control is not zero, and the table does not recompute it. A fuller model has a separate "risk after the control" column; this one does not, on purpose, to stay small.
- **Likelihood and impact are your estimates.** Two people will score the same row differently. Write why next to the numbers if it matters.
- **One control, several threats.** A control such as "logs on a second machine" helps more than one row (T6, and any later investigation). Look for controls that cover many rows.
- **Rows with no control are the work.** T4 and T6 are `open`; they decide your next lesson or task. The two logging and recovery topics in this track (shipping logs, keeping a backup copy away from the machine) are the gaps this table points to.
- **The table is a living file.** Keep it next to the thing it describes and update it when the design changes, such as when you add a new service or open a new port.

## Common mistakes

- **Listing attacks instead of assets.** Start from what you are protecting, then ask what could go wrong with it.
- **Skipping the boundary.** If you cannot say where trust changes, you cannot say where to put the control.
- **Rating everything 3 and 3.** A table where all rows are urgent ranks nothing.
- **No owner and no date.** A threat with no one to act on it will stay `open`.
- **Modelling once.** A model of last year's design describes last year's lab.
- **Treating a model as a proof.** It lists what you thought of; the attacker is not obliged to think the same.

## Check yourself

1. Write down five assets in your own lab and where trust changes between them.
2. For one component, give one threat for each STRIDE letter, or say why none applies.
3. Put your threats in a table, run the ranker and explain the top three.
4. Pick one `open` row and write the control, the test that would show it works and the test that would show it does not.
5. Why does a `done` row still have a risk score?

## Not tested, and honest limits

The method on a real design; formal data-flow diagrams and tools (the Microsoft Threat Modeling Tool, OWASP Threat Dragon); other methods (PASTA, LINDDUN, attack trees, kill chains); quantitative risk; and compliance frameworks. The risk numbers in the example are guesses. Only the script was run; the rest is reading, and I read only the quoted parts of the two pages.
