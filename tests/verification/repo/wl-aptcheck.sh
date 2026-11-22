#!/bin/bash
# wl-aptcheck.sh BASEURL SUITE COMPONENT ARCH KEYRING
# Health check for an apt repository, from the outside, the way a client sees it:
#   1. InRelease verifies against KEYRING (a binary keyring made with gpg --export)
#   2. the Packages.gz named in Release has the size and SHA-256 that Release promises
#   3. every package listed in Packages exists on the server with the size Packages promises
# Prints ok/FAIL lines; exit status 0 if everything is fine, 1 if anything failed, 2 on a usage error.
[ $# -eq 5 ] || { echo "usage: wl-aptcheck.sh BASEURL SUITE COMPONENT ARCH KEYRING" >&2; exit 2; }
base=${1%/} suite=$2 comp=$3 arch=$4 keyring=$5
[ -r "$keyring" ] || { echo "wl-aptcheck: cannot read keyring $keyring" >&2; exit 2; }
tmp=$(mktemp -d) || exit 2; trap 'rm -rf "$tmp"' EXIT
fails=0
ok()  { printf 'ok    %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }

# 1. the signed Release
curl -fsS -o "$tmp/InRelease" "$base/dists/$suite/InRelease" 2>"$tmp/curl.err" || { bad "cannot fetch InRelease: $(tr -d '\n' < "$tmp/curl.err")"; exit 1; }
if gpgv --keyring "$keyring" --output "$tmp/Release" "$tmp/InRelease" 2>"$tmp/gpgv.err"; then
  ok "InRelease signature: $(grep -o 'using [A-Z0-9 ]* key [0-9A-F]*' "$tmp/gpgv.err" | head -1)"
else
  bad "InRelease signature: $(grep -m1 -iE 'BAD|no public key|can.t check' "$tmp/gpgv.err")"; exit 1
fi

# 2. the index named in Release
rel="$comp/binary-$arch/Packages.gz"
read -r want_hash want_size < <(awk -v f="$rel" '/^SHA256:/ {s = 1; next} /^[A-Za-z]/ {s = 0} s && $3 == f {print $1, $2; exit}' "$tmp/Release")
[ -n "$want_hash" ] || { bad "$rel is not listed in Release"; exit 1; }
curl -fsS -o "$tmp/Packages.gz" "$base/dists/$suite/$rel" 2>"$tmp/curl.err" || { bad "cannot fetch $rel: $(tr -d '\n' < "$tmp/curl.err")"; exit 1; }
got_hash=$(sha256sum "$tmp/Packages.gz" | cut -d' ' -f1); got_size=$(stat -c %s "$tmp/Packages.gz")
if [ "$got_hash" = "$want_hash" ] && [ "$got_size" = "$want_size" ]; then ok "$rel matches Release ($got_size bytes)"
else bad "$rel differs from Release: size $got_size (Release says $want_size), hash ${got_hash:0:12} (Release says ${want_hash:0:12})"; exit 1; fi

# 3. every package on the server, with the promised size
n=0
while read -r file size; do
  n=$((n + 1))
  code_len=$(curl -sI -o /dev/null -w '%{http_code} %header{content-length}' "$base/$file")
  code=${code_len%% *}; len=${code_len#* }
  if [ "$code" != 200 ]; then bad "$file: HTTP $code"
  elif [ "$len" != "$size" ]; then bad "$file: $len bytes on the server, Packages says $size"
  fi
done < <(zcat "$tmp/Packages.gz" | awk '/^Filename:/ {f = $2} /^Size:/ {print f, $2}')
(( fails == 0 )) && ok "$n package file(s) present with the right size"
(( fails == 0 )) || printf '%d check(s) failed\n' "$fails"
exit $(( fails > 0 ))
