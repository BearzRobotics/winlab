#!/usr/bin/env bash
echo "== no linger:"; cat /tmp/wl-linger-nolinger.log 2>&1
echo "== linger:";    cat /tmp/wl-linger-linger.log 2>&1
