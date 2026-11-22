#!/bin/bash
# wl-apkcheck.sh BASEURL ARCH KEYSDIR
# Health check for an apk (v3) repository laid out as BASEURL/ARCH/Packages.adb with noarch packages in BASEURL/noarch/,
# from the outside, the way a client sees it:
#   1. Packages.adb verifies against the public keys in KEYSDIR (apk verify)
#   2. every package listed in the index exists on the server with the file-size the index promises
#   3. with WL_DEEP=1 in the environment, each package is also downloaded and verified (signature and structure)
# Prints ok/FAIL lines; exit status 0 if everything is fine, 1 if anything failed, 2 on a usage error.
[ $# -eq 3 ] || { echo "usage: wl-apkcheck.sh BASEURL ARCH KEYSDIR   (WL_DEEP=1 also downloads and verifies every package)" >&2; exit 2; }
base=${1%/} arch=$2 keys=$3
[ -d "$keys" ] || { echo "wl-apkcheck: $keys is not a directory" >&2; exit 2; }
tmp=$(mktemp -d) || exit 2; trap 'rm -rf "$tmp"' EXIT
fails=0
ok()  { printf 'ok    %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }

# 1. the signed index
curl -fsS -o "$tmp/Packages.adb" "$base/$arch/Packages.adb" 2>"$tmp/curl.err" || { bad "cannot fetch $arch/Packages.adb: $(tr -d '\n' < "$tmp/curl.err")"; exit 1; }
if out=$(apk --keys-dir "$keys" verify "$tmp/Packages.adb" 2>&1); then ok "$arch/Packages.adb signature: ${out#*: }"
else bad "$arch/Packages.adb: ${out#*: }"; exit 1; fi

# 2. every package in the index
n=0
while read -r parch file size; do
  n=$((n + 1))
  dir=$arch; [ "$parch" = noarch ] && dir=noarch
  url="$base/$dir/$file"
  code_len=$(curl -sI "$url" | tr -d '\r' | awk 'NR == 1 {c = $2} tolower($1) == "content-length:" {l = $2} END {print c, l}')
  code=${code_len%% *}; len=${code_len#* }
  if [ "$code" != 200 ]; then bad "$dir/$file: HTTP $code"; continue
  elif [ "$len" != "$size" ]; then bad "$dir/$file: $len bytes on the server, the index says $size"; continue
  fi
  # 3. optional: the package itself
  if [ -n "$WL_DEEP" ]; then
    curl -fsS -o "$tmp/pkg.apk" "$url" 2>/dev/null
    if out=$(apk --keys-dir "$keys" verify "$tmp/pkg.apk" 2>&1); then :
    else bad "$dir/$file: ${out#*: }"; fi
  fi
done < <(apk adbdump "$tmp/Packages.adb" | awk '/^  - name:/ {n = $3} /^    version:/ {v = $2} /^    arch:/ {a = $2} /^    file-size:/ {print a, n "-" v ".apk", $2}')
(( n > 0 )) || bad "the index lists no packages"
if (( fails == 0 )); then
  ok "$n package file(s) present with the right size${WL_DEEP:+, each verified}"
else printf '%d check(s) failed\n' "$fails"; fi
exit $(( fails > 0 ))
