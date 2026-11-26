#!/usr/bin/env bash
# Battery for foundations.python-basics: how Python is started on Linux. Writes only to a temp folder.
#   bash tests/verification/python/pyb3.sh
work=$(mktemp -d) || exit 1
trap 'rm -rf -- "$work"' EXIT
cd "$work" || exit 1
show() { printf '=== %s\n' "$1"; }

show 'names'
for n in python python3; do
    command -v "$n" || echo "$n: not found"
done
ls -l /usr/bin/python3

show 'python (without 3)'
python --version 2>&1; echo "exit $?"

printf '#!/usr/bin/env python3\nimport sys\nprint("args:", sys.argv[1:])\nsys.exit(3)\n' > hello.py
show 'no execute bit'
./hello.py 2>&1 | sed "s|$work|<work>|g"; echo "exit ${PIPESTATUS[0]}"
show 'python3 hello.py'
python3 hello.py a 'b c'; echo "exit $?"
show 'chmod +x and run'
chmod +x hello.py
./hello.py a 'b c'; echo "exit $?"

show 'no shebang'
printf 'import sys\nprint(sys.version_info[:2])\n' > bare.py
chmod +x bare.py
# bash runs a file with no shebang as a SHELL script, so "import" is looked up as a command. Where ImageMagick is
# installed that is its screen-capture tool, which waits for a mouse click: no display, and a time limit.
echo "import is: $(command -v import || echo 'not found')"
env -u DISPLAY -u WAYLAND_DISPLAY timeout 10 ./bare.py 2>&1 | sed "s|$work|<work>|g" | head -8; echo "exit ${PIPESTATUS[0]}"
ls

show 'CRLF line endings'
printf '#!/usr/bin/env python3\r\nprint("hi")\r\n' > crlf.py
chmod +x crlf.py
./crlf.py 2>&1; echo "exit $?"
show 'CRLF through python3'
python3 crlf.py; echo "exit $?"

show 'quoting'
python3 -c 'print("hi there")'

show 'help without a pager'
python3 -c 'import shutil; help(shutil.disk_usage)' | cat
