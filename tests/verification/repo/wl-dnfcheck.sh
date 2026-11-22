#!/bin/bash
# wl-dnfcheck.sh BASEURL KEYFILE
# Health check for a dnf/rpm repository, from the outside, the way a client sees it:
#   1. repomd.xml verifies against repomd.xml.asc with the public key in KEYFILE (ASCII-armored)
#   2. every metadata file named in repomd.xml has the size and SHA-256 that repomd.xml promises
#   3. every package listed in the primary metadata exists on the server with the size it promises
# Prints ok/FAIL lines; exit status 0 if everything is fine, 1 if anything failed, 2 on a usage error.
[ $# -eq 2 ] || { echo "usage: wl-dnfcheck.sh BASEURL KEYFILE" >&2; exit 2; }
base=${1%/} key=$2
[ -r "$key" ] || { echo "wl-dnfcheck: cannot read key file $key" >&2; exit 2; }
tmp=$(mktemp -d) || exit 2; trap 'rm -rf "$tmp"' EXIT
fails=0
ok()  { printf 'ok    %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }

# 1. the signed repomd.xml (a private keyring, so the check never touches the machine's own)
curl -fsS -o "$tmp/repomd.xml" "$base/repodata/repomd.xml" 2>"$tmp/curl.err" || { bad "cannot fetch repomd.xml: $(tr -d '\n' < "$tmp/curl.err")"; exit 1; }
curl -fsS -o "$tmp/repomd.xml.asc" "$base/repodata/repomd.xml.asc" 2>"$tmp/curl.err" || { bad "cannot fetch repomd.xml.asc: $(tr -d '\n' < "$tmp/curl.err")"; exit 1; }
export GNUPGHOME=$tmp/gnupg; mkdir -m 700 "$GNUPGHOME"
gpg --batch --quiet --import "$key" 2>/dev/null || { echo "wl-dnfcheck: $key is not a usable public key" >&2; exit 2; }
if gpg --batch --verify "$tmp/repomd.xml.asc" "$tmp/repomd.xml" 2>"$tmp/gpg.err"; then
  ok "repomd.xml signature: $(grep -m1 -o 'using [A-Z0-9]* key [0-9A-F]*' "$tmp/gpg.err")"
else
  bad "repomd.xml signature: $(grep -m1 -iE 'BAD|no public key|can.t check' "$tmp/gpg.err")"; exit 1
fi

# 2. each metadata file: type, location, sha256 checksum, size
awk '/<data type=/ {match($0, /type="[^"]*"/); t = substr($0, RSTART + 6, RLENGTH - 7)}
     /<checksum type="sha256"/ {gsub(/.*">|<\/checksum>.*/, ""); h = $0}
     /<size>/ {gsub(/.*<size>|<\/size>.*/, ""); s = $0}
     /<location href=/ {match($0, /href="[^"]*"/); l = substr($0, RSTART + 6, RLENGTH - 7)}
     /<\/data>/ {print t, l, h, s}' "$tmp/repomd.xml" > "$tmp/data.txt"
[ -s "$tmp/data.txt" ] || { bad "repomd.xml lists no metadata files"; exit 1; }
primary=
while read -r type loc want_hash want_size; do
  f="$tmp/$(basename "$loc")"
  if ! curl -fsS -o "$f" "$base/$loc" 2>"$tmp/curl.err"; then bad "$loc: cannot fetch ($(tr -d '\n' < "$tmp/curl.err"))"; continue; fi
  got_hash=$(sha256sum "$f" | cut -d' ' -f1); got_size=$(stat -c %s "$f")
  if [ "$got_hash" = "$want_hash" ] && [ "$got_size" = "$want_size" ]; then ok "$type matches repomd.xml ($got_size bytes)"
  else bad "$type differs from repomd.xml: size $got_size (repomd.xml says $want_size), hash ${got_hash:0:12} (repomd.xml says ${want_hash:0:12})"; fi
  [ "$type" = primary ] && primary=$f
done < "$tmp/data.txt"
[ -n "$primary" ] || { bad "no primary metadata"; exit 1; }
(( fails == 0 )) || { printf '%d check(s) failed\n' "$fails"; exit 1; }

# 3. every package named in the primary metadata, with the promised size
case $primary in
  *.gz)  unpack="gzip -dc" ;;
  *.zst) unpack="zstd -dc" ;;
  *.xz)  unpack="xz -dc" ;;
  *.bz2) unpack="bzip2 -dc" ;;
  *)     unpack="cat" ;;
esac
n=0
while read -r file size; do
  n=$((n + 1))
  code_len=$(curl -sI "$base/$file" | tr -d '\r' | awk 'NR == 1 {c = $2} tolower($1) == "content-length:" {l = $2} END {print c, l}')
  code=${code_len%% *}; len=${code_len#* }
  if [ "$code" != 200 ]; then bad "$file: HTTP $code"
  elif [ "$len" != "$size" ]; then bad "$file: $len bytes on the server, the metadata says $size"
  fi
done < <($unpack "$primary" | awk '/<size package=/ {match($0, /package="[0-9]*"/); s = substr($0, RSTART + 9, RLENGTH - 10)}
                                    /<location href=/ {match($0, /href="[^"]*"/); print substr($0, RSTART + 6, RLENGTH - 7), s}')
(( fails == 0 )) && ok "$n package file(s) present with the right size"
(( fails == 0 )) || printf '%d check(s) failed\n' "$fails"
exit $(( fails > 0 ))
