#!/usr/bin/env bash
# Which implementation is each tool on this machine? (GNU vs uutils vs others)
for t in ls cp mv rm mkdir ln cat head tail wc sort uniq cut tr tee stat date mktemp touch chmod chown du df env seq sleep timeout basename dirname readlink realpath xargs find grep sed awk diff tar gzip; do
  p=$(command -v "$t") || { echo "$t: missing"; continue; }
  v=$("$t" --version 2>&1 | head -1)
  printf '%-9s %-22s %s\n' "$t" "$(readlink -f "$p" | sed 's#^/usr/##')" "${v:0:62}"
done
echo "--- packages"
dpkg -l coreutils rust-coreutils findutils grep sed gawk mawk diffutils 2>/dev/null | awk 'NR>5 {print $2, $3}'
echo "--- is there a GNU coreutils alternative installed? ls /usr/lib/cargo/bin/coreutils: $(ls /usr/lib/cargo/bin/coreutils 2>/dev/null | head -3 | tr '\n' ' ')"
echo "--- GNU-specific behaviour that may differ: ls option error for -rf.txt"
cd "$(mktemp -d)" && touch -- -rf.txt && ls -- -rf.txt; ls ./-rf.txt; ls -rf.txt 2>&1 | head -2
