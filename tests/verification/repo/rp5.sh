#!/bin/bash
# Package-repo battery 5: how big is a real apk repository? (Chimera; run as root via bash -s) Reads the index only.
apk --version
apk update 2>&1 | tail -2
ls -l /var/cache/apk 2>/dev/null | head -5
IDX=$(ls /var/cache/apk/APKINDEX.* | head -3 | tr "
" " ")
for f in /var/cache/apk/APKINDEX.*; do
  n=$(apk adbdump "$f" 2>/dev/null | grep -c '^  - name:')
  tot=$(apk adbdump "$f" 2>/dev/null | awk '/^    file-size:/ {s += $2} END {printf "%d", s}')
  big=$(apk adbdump "$f" 2>/dev/null | awk '/^  - name:/ {nm=$3} /^    file-size:/ {print $2, nm}' | sort -rn | head -3 | tr '\n' ';')
  echo "$(basename $f): $n packages, total $tot bytes ($((tot/1024/1024)) MiB) ; largest: $big"
done
echo "--- the index file itself"
ls -l /var/cache/apk/APKINDEX.* | awk '{print $5, $9}'
echo "--- how many package files per directory name pattern (architectures)"
for f in /var/cache/apk/APKINDEX.*; do apk adbdump "$f" 2>/dev/null | awk '/^    arch:/ {print $2}' | sort | uniq -c; done
echo done
