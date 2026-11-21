#!/usr/bin/env bash
# Battery 2 for foundations.shells-and-posix: ShellCheck, syntax-check modes, versions, package info.
SC="$HOME/tools/shellcheck-v0.11.0/shellcheck"
D=$(mktemp -d)

echo "--- versions"
dpkg -l dash bash 2>/dev/null | awk 'NR>5 {print $2, $3}'
"$SC" --version | sed -n 2p
echo "--- apt knows shellcheck? (apt-cache needs no root)"
apt-cache policy shellcheck 2>/dev/null | head -3
echo "--- pipefail in dash (the claim to check)"
dash -c 'set -o pipefail; false | true; echo "pipefail rc=$?"'

cat > "$D/a.sh" <<'EOF'
#!/bin/sh
name=$1
if [[ $name == b* ]]; then
    echo -e "starts with b: $name"
fi
files=(one two)
echo ${files[0]}
for f in $(ls); do
    rm $f
done
EOF

echo "--- shellcheck on a #!/bin/sh script full of bashisms and unquoted variables"
"$SC" "$D/a.sh"
echo "(exit status $?)"
echo "--- same file with --shell=bash is checked as bash"
"$SC" --shell=bash "$D/a.sh" | grep -E '^In|SC[0-9]+' | head -12

echo "--- bash -n and dash -n (syntax only; they do NOT run the script)"
bash -n "$D/a.sh"; echo "bash -n rc=$?"
dash -n "$D/a.sh"; echo "dash -n rc=$?"

echo "--- bash -n misses what only runs: a typo in a command name is not a syntax error"
printf '#!/usr/bin/env bash\necho start\nlss /tmp\n' > "$D/b.sh"
bash -n "$D/b.sh"; echo "bash -n rc=$?"
"$SC" "$D/b.sh"; echo "shellcheck rc=$?"

echo "--- a clean POSIX script passes"
cat > "$D/c.sh" <<'EOF'
#!/bin/sh
set -eu
for f in ./*.txt; do
    [ -e "$f" ] || continue
    printf '%s\n' "$f"
done
EOF
"$SC" "$D/c.sh"; echo "shellcheck rc=$?"

echo "--- shell directive and disabling one check on purpose"
cat > "$D/d.sh" <<'EOF'
#!/bin/sh
# shellcheck disable=SC2086   # intentional word splitting of a list of options
opts="-l -a"
ls $opts /tmp > /dev/null
EOF
"$SC" "$D/d.sh"; echo "shellcheck rc=$?"

echo "--- shellcheck output formats and severity"
"$SC" -f gcc -S warning "$D/a.sh" | head -3
echo "--- shellcheck -x follows sourced files; a sourced path it cannot find"
printf '#!/bin/sh\n. ./lib.sh\n' > "$D/e.sh"
"$SC" "$D/e.sh"; echo "rc=$?"

echo "--- how a script is started: shebang, env, and a missing interpreter"
printf '#!/usr/bin/env nosuchshell\necho hi\n' > "$D/f.sh"; chmod +x "$D/f.sh"
"$D/f.sh"; echo "rc=$?"
printf '#!/no/such/bash\necho hi\n' > "$D/g.sh"; chmod +x "$D/g.sh"
"$D/g.sh"; echo "rc=$?"
printf '#!/bin/bash\r\necho hi\r\n' > "$D/h.sh"; chmod +x "$D/h.sh"
"$D/h.sh"; echo "CRLF shebang rc=$?"
printf 'echo no shebang; echo "$0"\n' > "$D/i.sh"; chmod +x "$D/i.sh"
"$D/i.sh"; echo "no shebang, run from bash: rc=$?"
sh "$D/i.sh"
echo "--- what runs a script with no execute bit"
printf '#!/usr/bin/env bash\necho ran\n' > "$D/j.sh"
"$D/j.sh"; echo "rc=$?"
bash "$D/j.sh"

echo "--- login/interactive/non-interactive"
bash -c 'echo "interactive? [$-]"; shopt -q login_shell && echo login || echo not-login'
bash -ic 'echo "interactive? [$-]"' 2>/dev/null
echo "--- which startup files? (strace is not needed: check the manual text)"
bash --version | head -1
echo "--- sh is which program here"
ls -l /bin/sh
rm -rf "$D"
