#!/usr/bin/env bash
# Battery 5a for the dinit lessons: run as the ordinary user labadmin over SSH (a real login: turnstile starts the user dinit).
# Usage: this script is piped to "bash -s" by the harness. The session ends when it finishes (that is the logout).
echo "user: $(id -un) uid=$(id -u)"
echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-unset}   DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unset}"
echo "DINIT_SOCKET_PATH=${DINIT_SOCKET_PATH:-unset}"
ls -d "$XDG_RUNTIME_DIR" 2>&1 | head -1
echo "== user dinit process:"; ps -eo user,pid,args | grep "[d]init" | grep "^labadmin\|--user" | sed 's/  */ /g' | cut -c1-120
echo "== dinitctl --user list:"; dinitctl --user list 2>&1 | head -12 | sed 's/pid: [0-9]*/pid: <pid>/'
echo "== user boot service:"; cat /usr/lib/dinit.d/user/boot 2>&1 | head -12; ls /usr/lib/dinit.d/user/boot.d 2>&1 | tr '\n' ' '; echo
echo "== dirs:"; ls -d ~/.config/dinit.d /etc/dinit.d/user 2>&1 | head -2
mkdir -p ~/.config/dinit.d/boot.d
cat > ~/.config/dinit.d/wl-user <<'EOS'
type = process
command = /bin/sleep 7777
EOS
echo "== start a user service:"; dinitctl --user start wl-user 2>&1
dinitctl --user list 2>&1 | grep wl- | sed 's/pid: [0-9]*/pid: <pid>/'
echo "== is the same service visible to the SYSTEM dinit?"; dinitctl --system status wl-user 2>&1 | head -2
echo "== enable for the user boot service:"; dinitctl --user enable wl-user 2>&1 | head -3; ls -l ~/.config/dinit.d/boot.d 2>&1 | tail -2 | sed 's/.* wl-/wl-/'
echo "== sleep process:"; pgrep -u labadmin -f "sleep 7777" | head -1 | sed 's/.*/running (pid <pid>)/'
echo "== system dinitctl as a normal user:"; dinitctl --system list 2>&1 | head -2
echo "== exit status of a failing user service:"
cat > ~/.config/dinit.d/wl-ubad <<'EOS'
type = process
command = /usr/bin/slepe 1
EOS
dinitctl --user start wl-ubad 2>&1 | head -4
