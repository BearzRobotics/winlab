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
