#!/bin/bash
# wl-scope.sh: stop unless every target is inside the allowed ranges of a scope file.
# Usage:  wl-scope.sh SCOPEFILE TARGET...
# Scope file: one rule per line, "allow CIDR" or "deny CIDR"; blank lines and # comments are ignored. A deny wins over an allow.
# Exit status: 0 every target is in scope, 1 something is out of scope, 2 bad input.
# Targets must be IPv4 addresses, not names: a name can resolve to something else tomorrow.
set -u

die() { printf 'wl-scope: %s\n' "$*" >&2; exit 2; }

ip2int() {                       # 10.0.2.15 -> 167772687 ; returns 1 for anything that is not a dotted quad
  local ip=$1 a b c d
  [[ $ip =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  a=${BASH_REMATCH[1]} b=${BASH_REMATCH[2]} c=${BASH_REMATCH[3]} d=${BASH_REMATCH[4]}
  (( a < 256 && b < 256 && c < 256 && d < 256 )) || return 1
  echo $(( (a << 24) | (b << 16) | (c << 8) | d ))
}

in_cidr() {                      # in_cidr INT CIDR : is the address inside the range?
  local ipint=$1 net=${2%/*} bits=32 netint mask
  [[ $2 == */* ]] && bits=${2#*/}
  [[ $bits =~ ^[0-9]+$ ]] && (( bits <= 32 )) || return 2
  netint=$(ip2int "$net") || return 2
  mask=$(( bits == 0 ? 0 : (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF ))
  (( (ipint & mask) == (netint & mask) ))
}

(( $# >= 2 )) || die "usage: wl-scope.sh SCOPEFILE TARGET..."
scope=$1; shift
[[ -r $scope ]] || die "cannot read scope file: $scope"

allow=() deny=() n=0
while read -r verb cidr rest; do
  n=$((n + 1))
  [[ -z $verb || $verb == \#* ]] && continue
  [[ $verb == allow || $verb == deny ]] || die "$scope: rule $n: unknown word '$verb'"
  in_cidr 0 "$cidr" 2>/dev/null; (( $? != 2 )) || die "$scope: rule $n: '$cidr' is not an IPv4 address or range"
  if [[ $verb == allow && $cidr == */* ]] && (( ${cidr#*/} < 16 )); then die "$scope: rule $n: refusing to allow a range wider than /16 ($cidr)"; fi
  [[ $verb == allow ]] && allow+=("$cidr") || deny+=("$cidr")
done < "$scope"
(( ${#allow[@]} > 0 )) || die "$scope has no allow rules"

status=0
for t in "$@"; do
  ti=$(ip2int "$t") || { printf 'REFUSED  %-18s not an IPv4 address (names are not accepted)\n' "$t"; status=2; continue; }
  verdict=OUT
  for c in "${allow[@]}"; do in_cidr "$ti" "$c" && { verdict=IN; break; }; done
  for c in "${deny[@]}";  do in_cidr "$ti" "$c" && { verdict=DENIED; break; }; done
  case $verdict in
    IN) printf 'in scope  %s\n' "$t" ;;
    DENIED) printf 'DENIED    %-18s inside an excluded range\n' "$t"; (( status == 2 )) || status=1 ;;
    OUT) printf 'OUT       %-18s not in any allowed range\n' "$t"; (( status == 2 )) || status=1 ;;
  esac
done
exit $status
