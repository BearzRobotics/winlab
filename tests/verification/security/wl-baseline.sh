#!/bin/bash
# wl-baseline.sh: read-only checks of a few common Linux weaknesses. Prints PASS, FAIL or INFO per check.
# Run as root. It changes nothing. Exit status is the number of FAIL lines (255 at most).
fails=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
info() { printf 'INFO  %s\n' "$1"; }

# 1. sshd effective settings (sshd -T prints what the daemon would use)
sshd_opt() { sshd -T 2>/dev/null | awk -v k="$1" '$1 == k { print $2; exit }'; }
v=$(sshd_opt permitrootlogin);       case $v in no|prohibit-password|without-password) pass "sshd permitrootlogin = $v";; *) fail "sshd permitrootlogin = $v";; esac
v=$(sshd_opt passwordauthentication); [ "$v" = no ] && pass "sshd passwordauthentication = no" || fail "sshd passwordauthentication = $v"
v=$(sshd_opt permitemptypasswords);   [ "$v" = no ] && pass "sshd permitemptypasswords = no" || fail "sshd permitemptypasswords = $v"
v=$(sshd_opt maxauthtries);           [ "${v:-99}" -le 4 ] && pass "sshd maxauthtries = $v" || fail "sshd maxauthtries = $v (want 4 or less)"

# 2. accounts
extra=$(awk -F: '$3 == 0 && $1 != "root" { print $1 }' /etc/passwd | paste -sd, -)
[ -z "$extra" ] && pass "only root has UID 0" || fail "other accounts with UID 0: $extra"
empty=$(awk -F: '$2 == "" { print $1 }' /etc/shadow | paste -sd, -)
[ -z "$empty" ] && pass "no account has an empty password" || fail "empty password: $empty"
nopw=$(grep -rhE '^[^#].*NOPASSWD' /etc/sudoers /etc/sudoers.d 2>/dev/null | wc -l)
info "sudoers lines with NOPASSWD: $nopw"

# 3. files
[ "$(stat -c %a /etc/shadow)" -le 640 ] && pass "/etc/shadow mode $(stat -c %a /etc/shadow)" || fail "/etc/shadow mode $(stat -c %a /etc/shadow)"
ww=$(find / -xdev \( -path /proc -o -path /sys \) -prune -o -type f -perm -0002 -print 2>/dev/null | head -5 | paste -sd' ' -)
[ -z "$ww" ] && pass "no world-writable regular files on the root filesystem" || fail "world-writable files: $ww"
nosticky=$(find / -xdev -type d -perm -0002 ! -perm -1000 -print 2>/dev/null | head -5 | paste -sd' ' -)
[ -z "$nosticky" ] && pass "every world-writable directory has the sticky bit" || fail "no sticky bit: $nosticky"
info "setuid files on the root filesystem: $(find / -xdev -type f -perm -4000 2>/dev/null | wc -l)"

# 4. network
listen=$(ss -H -tln | awk '{ print $4 }' | grep -vE '^(127\.|\[::1\]|::1)' | sort -u | paste -sd' ' -)
info "TCP listeners on non-loopback addresses: ${listen:-none}"
fwd=$(sysctl -n net.ipv4.ip_forward); [ "$fwd" = 0 ] && pass "net.ipv4.ip_forward = 0" || fail "net.ipv4.ip_forward = $fwd"

# 5. mandatory access control and firewall (whichever exists)
if command -v getenforce >/dev/null; then
  [ "$(getenforce)" = Enforcing ] && pass "SELinux Enforcing" || fail "SELinux $(getenforce)"
elif command -v aa-status >/dev/null; then
  aa-status --enabled 2>/dev/null && pass "AppArmor enabled" || fail "AppArmor not enabled"
fi
if command -v ufw >/dev/null; then info "ufw: $(ufw status | head -1)"; fi
if command -v firewall-cmd >/dev/null; then info "firewalld: $(firewall-cmd --state 2>&1)"; fi

printf '%s failed check(s)\n' "$fails"
exit $(( fails > 255 ? 255 : fails ))
