#!/bin/bash
# ufw delete forms (Ubuntu; run as root via bash -s). ufw is installed here only for the test.
. /etc/os-release; echo "### $PRETTY_NAME  $(ufw version | head -1)"
command -v ufw >/dev/null || apt-get install -y ufw >/dev/null 2>&1
ufw --force disable >/dev/null
ufw allow 22/tcp >/dev/null; ufw --force enable >/dev/null
echo "### add a rule with a source, then the short delete"
ufw allow from 192.168.1.0/24 to any port 8080 proto tcp
ufw status numbered
echo "\$ ufw delete allow 8080/tcp"; ufw delete allow 8080/tcp; echo "[exit $?]"
echo "### delete with the same words"
echo "\$ ufw delete allow from 192.168.1.0/24 to any port 8080 proto tcp"; ufw delete allow from 192.168.1.0/24 to any port 8080 proto tcp; echo "[exit $?]"
ufw status numbered
echo "### a plain port rule: the short form works for a rule added the short way"
ufw allow 8080/tcp >/dev/null; echo "\$ ufw delete allow 8080/tcp"; ufw delete allow 8080/tcp; echo "[exit $?]"
echo "### numbered delete"
ufw allow from 192.168.1.0/24 to any port 9090 proto tcp >/dev/null
ufw status numbered
n=$(ufw status numbered | awk -F'[][]' '/9090/ {print $2; exit}'); echo "rule number: $n"
echo "\$ ufw --force delete $n"; ufw --force delete $n; echo "[exit $?]"
ufw status numbered
ufw --force disable
echo done
