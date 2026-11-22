#!/bin/bash
# wl-authreport.sh [MINUTES] [THRESHOLD]
# Summarise failed SSH logins from the journal: attempts per source address and per user name, and flag sources at or above THRESHOLD.
# Run as root (or a member of systemd-journal). Reads only. Exit status 1 if any source reached the threshold, else 0.
mins=${1:-60}; thr=${2:-5}
unit=ssh; systemctl cat sshd.service >/dev/null 2>&1 && unit=sshd     # Ubuntu calls it ssh, the Red Hat family sshd

journalctl -u "$unit" --since "-${mins}min" --no-pager -o cat | awk -v thr="$thr" '
  # One rule per kind of failure line; $N are the words of the message. "Failed password for invalid user" is
  # deliberately not counted: it always follows an "Invalid user" line for the same attempt.
  /^Invalid user /                                                  { who = $3; from = $5; hit = 1 }
  /^Failed password for / && !/^Failed password for invalid user /  { who = $4; from = $6; hit = 1 }
  /^Connection closed by authenticating user/                       { who = $6; from = $7; hit = 1 }
  hit { n++; byuser[who]++; bysrc[from]++; who = ""; from = ""; hit = 0 }
  END {
    sortcmd = "sort -rn"
    printf "%d failure lines in the window\n", n
    print "by source:"
    for (s in bysrc) { printf "  %5d  %s%s\n", bysrc[s], s, (bysrc[s] >= thr ? "   <-- at or above " thr : "") | sortcmd }
    close(sortcmd)
    print "by user:"
    for (u in byuser) { printf "  %5d  %s\n", byuser[u], u | sortcmd }
    close(sortcmd)
    for (s in bysrc) if (bysrc[s] >= thr) exit 1
  }'
