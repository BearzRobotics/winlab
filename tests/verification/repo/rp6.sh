#!/bin/bash
# Package-repo battery 6: how big are the repositories this machine is configured for? (run as root via bash -s; reads metadata only)
. /etc/os-release; echo "### $PRETTY_NAME"
if command -v apt-get >/dev/null; then
  apt-get update >/tmp/upd.log 2>&1
  echo "--- sources"; grep -hE '^(URIs|Suites|Components)' /etc/apt/sources.list.d/*.sources 2>/dev/null | paste -sd' ' | cut -c1-200
  echo "--- every available package version, from the local index (apt-cache dumpavail)"
  apt-cache dumpavail | awk '/^Package:/ {n++} /^Size:/ {s += $2} END {printf "%d package versions, %d bytes = %.1f GiB\n", n, s, s/1024/1024/1024}'
  echo "--- by architecture"
  apt-cache dumpavail | awk '/^Architecture:/ {a=$2} /^Size:/ {s[a] += $2; c[a]++} END {for (k in s) printf "%-8s %7d files %8.2f GiB\n", k, c[k], s[k]/1024/1024/1024}'
  echo "--- the biggest five"
  apt-cache dumpavail | awk '/^Package:/ {p=$2} /^Size:/ {print $2, p}' | sort -rn | head -5
else
  dnf -q makecache >/dev/null 2>&1
  echo "--- repositories"; dnf -q repolist 2>/dev/null
  for r in $(dnf -q repolist --enabled 2>/dev/null | awk 'NR>1 {print $1}'); do
    dnf -q repoquery --repo $r --available --qf '%{downloadsize} %{name}\n' 2>/dev/null | awk -v r=$r '{n++; s += $1} END {printf "%-22s %6d packages %8.2f GiB\n", r, n, s/1024/1024/1024}'
  done
  echo "--- the biggest five (all enabled repositories)"
  dnf -q repoquery --available --qf '%{downloadsize} %{name}\n' 2>/dev/null | sort -rn | head -5
fi
echo done
