#!/usr/bin/env bash
p=/home/user/archive.tar.gz
echo "unquoted ~ in replacement : ${p/#\/home/~}"
echo "escaped \\~               : ${p/#\/home/\~}"
echo "quoted in the pattern     : ${p/#\/home/"~"}"
v='a[$(echo INJECTED-test >&2)]'
echo -n '[ "$v" -eq 5 ] in bash  : '; ( [ "$v" -eq 5 ] ) 2>&1 | head -2
echo -n '[[ $v -eq 5 ]] in bash  : '; ( [[ $v -eq 5 ]] ) 2>&1 | head -2
