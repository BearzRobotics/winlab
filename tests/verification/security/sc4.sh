#!/bin/bash
# Security lesson battery 4: incident-response triage (run as root via bash -s). TRIAGE is substituted by the driver.
. /etc/os-release; echo "### $PRETTY_NAME"
cat > /usr/local/bin/wl-triage.sh <<'WLEOF'
@@TRIAGE@@
WLEOF
chmod 755 /usr/local/bin/wl-triage.sh

echo "### 1. plant a pretend intruder (all in this lab VM)"
useradd -m -s /bin/bash wl-svc 2>&1 | head -1
mkdir -p /home/wl-svc/.ssh
echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIWLLABFAKEKEYWLLABFAKEKEYWLLABFAKEKEYAAAA attacker@evil.example' > /home/wl-svc/.ssh/authorized_keys
chown -R wl-svc:wl-svc /home/wl-svc/.ssh; chmod 700 /home/wl-svc/.ssh; chmod 600 /home/wl-svc/.ssh/authorized_keys
echo '*/5 * * * * root /tmp/.wl-update >/dev/null 2>&1' > /etc/cron.d/wl-update
cp /bin/sleep /tmp/.wl-beacon; chmod 755 /tmp/.wl-beacon
nohup /tmp/.wl-beacon 100000 >/dev/null 2>&1 &
rm -f /tmp/.wl-gone; cp /bin/sleep /tmp/.wl-gone; nohup /tmp/.wl-gone 100000 >/dev/null 2>&1 &
sleep 0.5; rm -f /tmp/.wl-gone
cat > /etc/systemd/system/wl-backdoor.service <<'UNIT'
[Unit]
Description=Totally normal update helper
[Service]
ExecStart=/usr/bin/python3 -m http.server 4444 --bind 0.0.0.0
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload; systemctl enable --now wl-backdoor 2>&1 | tail -1
sleep 1

echo "### 2. run the triage to a different directory"
rm -rf /root/wl-evidence; time /usr/local/bin/wl-triage.sh /root/wl-evidence
ls -l /root/wl-evidence | awk '{print $1, $5, $9}' | head -40

echo "### 3. what the triage shows about the plants"
echo "--- 08-odd-exe"; cat /root/wl-evidence/08-odd-exe.txt
echo "--- 11-uid0"; cat /root/wl-evidence/11-uid0.txt | tail -n +2
echo "--- 13-authkeys"; cat /root/wl-evidence/13-authkeys.txt
echo "--- 14-cron"; cat /root/wl-evidence/14-cron.txt | tail -n +2
echo "--- 16-units-local"; cat /root/wl-evidence/16-units-local.txt | tail -n +2
echo "--- 04-sockets (4444)"; grep 4444 /root/wl-evidence/04-sockets.txt | sed 's/  */ /g'
echo "--- 30-recent-etc (head)"; grep -E 'wl-|cron.d|systemd' /root/wl-evidence/30-recent-etc.txt | head -8
echo "--- 03-processes (beacon)"; grep -E 'wl-beacon|wl-gone|http.server' /root/wl-evidence/03-processes.txt | sed 's/  */ /g' | cut -c1-120

echo "### 4. check the seal, then change a file and check again"
( cd /root/wl-evidence && sha256sum -c SHA256SUMS 2>&1 | grep -vc ': OK$' )
echo tampered >> /root/wl-evidence/11-uid0.txt
( cd /root/wl-evidence && sha256sum -c SHA256SUMS 2>&1 | grep -v ': OK$' )

echo "### 5. recover the deleted binary from /proc"
GP=$(for p in /proc/[0-9]*; do readlink $p/exe 2>/dev/null | grep -q 'wl-gone (deleted)' && echo ${p#/proc/}; done | head -1)
echo "pid of deleted process: $GP"
ls -l /proc/$GP/exe | sed 's/.*-> //'
cp /proc/$GP/exe /root/wl-evidence/recovered-wl-gone && sha256sum /root/wl-evidence/recovered-wl-gone /bin/sleep | awk '{print $1}' | uniq -c

echo "### 6. contain, then clean (lab only): stop and disable the service, kill the process, lock the account"
systemctl disable --now wl-backdoor 2>&1 | tail -1
pkill -f wl-beacon; pkill -f wl-gone
usermod -L wl-svc; passwd -S wl-svc
rm -f /etc/systemd/system/wl-backdoor.service /etc/cron.d/wl-update /tmp/.wl-beacon
systemctl daemon-reload
userdel -r wl-svc 2>&1 | head -1
rm -rf /root/wl-evidence
echo done
