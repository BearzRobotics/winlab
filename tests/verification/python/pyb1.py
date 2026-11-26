"""Battery for foundations.python-basics. Runs each snippet in a fresh interpreter (the one running
this file) inside a new temporary folder, and prints its output and exit status. Standard library only.

    Windows:  python tests\\verification\\python\\pyb1.py
    Linux:    python3 tests/verification/python/pyb1.py
"""
import os
import shutil
import subprocess
import sys
import tempfile

WORK = tempfile.mkdtemp(prefix="wl-pyb1-")


def write(name, text):
    path = os.path.join(WORK, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    return path


def run(label, args, stdin=None):
    print(f"=== {label}")
    env = {k: v for k, v in os.environ.items() if not k.startswith("PYTHON")}
    r = subprocess.run([sys.executable, *args], cwd=WORK, input=stdin, env=env,
                       capture_output=True, timeout=60)
    for name, data in (("out", r.stdout), ("err", r.stderr)):
        text = data.decode("utf-8", errors="backslashreplace").replace(WORK, "<work>")
        for line in text.splitlines():
            print(f"{name}| {line}")
    print(f"exit {r.returncode}")


def snippet(label, code, *args):
    write("s.py", code)
    run(label, ["s.py", *args])


print("version:", sys.version)
print("platform:", sys.platform)

snippet("which interpreter", """import sys, platform
print(sys.executable)
print(sys.version_info[:3])
print(sys.version_info >= (3, 9))
print(platform.system())
""")
run("--version", ["--version"])
run("-c one-liner", ["-c", "print(6 * 7)"])
run("script read from stdin", ["-"], stdin=b"print('from stdin')\n")

snippet("types", """for v in (42, 3.5, "42", True, None, [1, 2], {"a": 1}):
    print(repr(v), type(v).__name__)
print(7 / 2, 7 // 2, 7 % 2, 2 ** 10)
print(0.1 + 0.2, 0.1 + 0.2 == 0.3)
print(int("42") + 1, str(42) + "1", "-" * 10)
""")
snippet("no implicit conversion", """count = "5"
print(count + 1)
""")
snippet("int of bad text", """print(int("12 GB"))
""")
snippet("input is text", """n = input("How many? ")
print(repr(n), n * 3, int(n) * 3)
""".replace("n = input(\"How many? \")", "n = '5'"))

snippet("fstrings", """name = "web01"
free = 12.3456
print(f"{name}: {free:.1f} GB free")
print(f"[{name:<8}][{free:>8.2f}]")
print(f"{name=} {free=}")
print(f"{1536000:,} bytes")
""")
snippet("string methods", """line = "  alice:x:1001:1001::/home/alice:/bin/bash  \\n"
clean = line.strip()
parts = clean.split(":")
print(len(parts), parts[0], parts[-1])
print(clean.startswith("alice"), "bash" in clean)
print(":".join(parts[:3]))
print("Report.TXT".lower().endswith(".txt"))
""")

snippet("windows path newline trap", """p = "C:\\new\\table.txt"
print(p)
print(repr(p))
print(r"C:\\new\\table.txt")
""")
snippet("windows path unicode escape trap", """p = "C:\\Users\\alice"
print(p)
""")
snippet("pathlib", """from pathlib import Path, PureWindowsPath, PurePosixPath
print(PureWindowsPath("C:/Logs") / "app" / "x.log")
print(PurePosixPath("/var/log") / "app" / "x.log")
p = Path("logs") / "app.log"
print(p.name, p.stem, p.suffix, p.parent)
print(p.exists())
""")

snippet("lists and dicts", """servers = ["web01", "db01"]
servers.append("web02")
print(servers, len(servers), servers[0], servers[-1], servers[0:2])
print(sorted(servers), servers)
ports = {"ssh": 22, "https": 443}
ports["rdp"] = 3389
for name, port in ports.items():
    print(f"{name} {port}")
print(ports.get("smtp"), ports.get("smtp", 25), "ssh" in ports)
""")
snippet("missing key", """ports = {"ssh": 22}
print(ports["smtp"])
""")
snippet("index out of range", """servers = ["web01"]
print(servers[1])
""")

snippet("if for range", """sizes = [10, 95, 99]
for number, pct in enumerate(sizes, start=1):
    if pct >= 98:
        level = "critical"
    elif pct >= 90:
        level = "warning"
    else:
        level = "ok"
    print(number, pct, level)
print(list(range(3)), list(range(1, 4)))
""")
snippet("indentation error", """for i in range(2):
    print(i)
  print("done")
""")
snippet("indent changes meaning", """total = 0
for n in [1, 2, 3]:
    total += n
    print("inside", total)
print("after", total)
""")
snippet("tabs and spaces", "if True:\n        print(1)\n\tprint(2)\n")

snippet("truthiness", """for v in (0, 1, "", "0", "False", [], [0], None):
    print(repr(v), bool(v))
""")
snippet("== and is", """a = [1, 2]
b = [1, 2]
print(a == b, a is b)
x = None
print(x is None)
""")
snippet("two names one list", """keep = ["a.log", "b.log"]
delete = keep
delete.append("c.log")
print(keep)
safe = ["a.log"]
other = safe.copy()
other.append("z")
print(safe, other)
""")
snippet("mutable default", """def add(item, seen=[]):
    seen.append(item)
    return seen
print(add("a"))
print(add("b"))
""")
snippet("remove while looping", """names = ["a.tmp", "b.tmp", "c.txt"]
for n in names:
    if n.endswith(".tmp"):
        names.remove(n)
print(names)
""")

snippet("functions", """def percent_used(used, total):
    \"\"\"Return used/total as a percentage.\"\"\"
    if total <= 0:
        raise ValueError("total must be positive")
    return used / total * 100

def forgot_return(x):
    x * 2

print(f"{percent_used(45, 60):.1f}")
print(forgot_return(4))
print(percent_used.__doc__)
""")
snippet("traceback", """def load(count_text):
    return int(count_text)

def main():
    print(load("ten"))

main()
""")
snippet("name error typo", """server_count = 3
print(server_cuont)
""")
snippet("typo assigns new name", """verbose = False
verbsoe = True
print(verbose)
""")
snippet("error late", """print("step 1 ran")
print(undefined_name)
""")
snippet("syntax error runs nothing", """print("step 1")
if True
    print(2)
""")
write("late.py", "print('ran')\nif True\n    pass\n")
run("py_compile bad", ["-m", "py_compile", "late.py"])
write("ok.py", "open('SHOULD-NOT-EXIST', 'w').close()\n")
run("py_compile good does not run it", ["-m", "py_compile", "ok.py"])
print("side effect happened:", os.path.exists(os.path.join(WORK, "SHOULD-NOT-EXIST")))

hello = """\"\"\"Greet each name given on the command line.\"\"\"
import sys


def main(argv):
    if len(argv) < 2:
        print("usage: hello.py NAME...", file=sys.stderr)
        return 2
    for name in argv[1:]:
        print(f"Hello, {name}!")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
"""
write("hello.py", hello)
run("hello two names", ["hello.py", "Alice", "Bob"])
run("hello none", ["hello.py"])
run("hello name with space", ["hello.py", "Mary Ann"])
run("import does not run main", ["-c", "import hello; print('imported', hello.__name__)"])
snippet("sys.exit with text", """import sys
sys.exit("config file not found")
""")
snippet("exit True", """import sys
sys.exit(True)
""")
snippet("print is not exit status", """print("FAILED: disk full")
""")
snippet("argv types", """import sys
print(sys.argv[1:])
""", "5", "a b", "--force")

# Shadowing: a file next to the script is imported instead of the standard module.
write("shadow/json.py", "print('!!! this is ./json.py, not the standard library')\n")
write("shadow/report.py", "import json\nprint(json.__file__)\nprint(hasattr(json, 'dumps'))\n")
run("shadow plain", [os.path.join("shadow", "report.py")])
run("shadow with -I", ["-I", os.path.join("shadow", "report.py")])
write("shadow2/random.py", "")
write("shadow2/pick.py", "import random\nprint(random.choice([1]))\n")
run("own file named random.py", [os.path.join("shadow2", "pick.py")])

# What an import can do: top-level code runs at import time.
write("helper.py", "print('helper.py ran code just by being imported')\n")
run("import runs top-level code", ["-c", "import helper"])

snippet("encodings", """import sys, locale
print("utf8_mode", sys.flags.utf8_mode)
print("preferred", locale.getpreferredencoding(False))
with open("n.txt", "w") as f:
    f.write("caf\\u00e9")
print(open("n.txt", "rb").read())
""")
snippet("bytes and text", """data = "caf\\u00e9".encode("utf-8")
print(data, len(data), len(data.decode("utf-8")))
print(data.decode("cp1252"))
""")

snippet("help text", """text = str.split.__doc__
print(text.splitlines()[0])
""")

run("-h mentions -I", ["-h"])
shutil.rmtree(WORK, ignore_errors=True)
