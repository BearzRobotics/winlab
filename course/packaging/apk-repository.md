*Draft for owner review.* **apk** is the package manager of Alpine Linux and of **Chimera Linux**, which is why it matters for the owner's FenrirOS: I have **not seen FenrirOS** and know nothing about which package manager it uses, but it is described as Chimera-influenced and as building its own package repository. **If** it follows Chimera, this lesson applies. Everything below was run on **Chimera Linux** and nothing else.

This is the third format lesson. The shape of the work is the one in `packaging.apt-repository` and `packaging.dnf-repository`: a signed index plus a pile of packages, served as static files. What differs is the tools (all in `apk` itself), the **layout** (one directory per architecture, and a surprise for `noarch`), and, most importantly, **where the trust sits**: in this test, the signed index vouched for packages that were themselves unsigned.

**What was tested, and where.** **Chimera Linux** (kernel 7.3.1, **apk-tools 3.0.8**, OpenSSL 3.6.5, Python 3.14.6, build 20261103 of the lab image), as root with `doas`, a package built with `apk mkpkg`, an index with `apk mkndx`, served from `127.0.0.1` by Python's `http.server`, with the lab VM restored to its clean snapshot before the final run (`tests/verification/repo/rp3.sh`; output is real, hashes shortened). I also read the upstream manual sources for [apk-repositories(5)](https://github.com/alpinelinux/apk-tools/blob/master/doc/apk-repositories.5.scd), [apk-mkndx(8)](https://github.com/alpinelinux/apk-tools/blob/master/doc/apk-mkndx.8.scd) and [apk-mkpkg(8)](https://github.com/alpinelinux/apk-tools/blob/master/doc/apk-mkpkg.8.scd) (the Alpine GitLab and wiki refused my automated requests with HTTP 403/418, so I cite the GitHub copies of the same files). **Not tested:** **`cbuild` and Chimera's `cports`** build system, which is how Chimera really makes packages (I did not run it, and I do not know whether FenrirOS uses it), Alpine's `abuild`, **apk v2** (the older `APKINDEX.tar.gz` format), more than one architecture, packages with dependencies, install scripts or triggers, `--pkgname-spec`, repository **mirrors**, HTTPS, key rotation, and anything on a real FenrirOS image.

## apk in short

- **Two index formats.** apk 3 uses **v3**, a binary index called **`Packages.adb`**; the older **v2** used `APKINDEX.tar.gz`. A repository line begins with the format: `v3 URL` or `v2 URL`.
- **Repository lines live in `*.list` files.** The manual says apk reads `/etc/apk/repositories.d/*.list` and `/lib/apk/repositories.d/*.list`. On Chimera the distribution's own file is `/usr/lib/apk/repositories.d/01-repo-main.list` (`/lib` is a link to `usr/lib` there), containing `v3 ${CHIMERA_REPO_URL}/${CHIMERA_REPO_RELEASE}/main` plus two `set -default` variable lines. **You add yours under `/etc/apk/repositories.d/`.**
- **Layout rule** (from apk-repositories(5), and confirmed by what the client asked my server for): for a repository of this kind `url` is the **base URL**; the index is at **`$base_url/$arch/Packages.adb`** and packages by default at **`$base_url/$arch/$name-$version.apk`**. `$arch` is the **architecture of the package**, which for a script package is `noarch`.
- **Keys** are public keys in `/etc/apk/keys/` (Chimera ships its own there, e.g. `x86_64@chimera-linux.org-669d70ff.rsa.pub`).

The real Chimera repository follows this layout: `https://repo.chimera-linux.org/current/main/x86_64/Packages.adb` answered `200` with a length of 1,215,483 bytes.

## A signing key

Chimera's own keys are **RSA** (`.rsa.pub`), so I used RSA:

```text
$ openssl genrsa -out wl-repo.rsa 2048
$ openssl rsa -in wl-repo.rsa -pubout -out wl-repo.rsa.pub
$ ls -l wl-repo.rsa wl-repo.rsa.pub | awk '{print $1, $5, $9}'
-rw------- 1704 wl-repo.rsa
-rw-r--r-- 451 wl-repo.rsa.pub
```

`wl-repo.rsa` is the **private** key; keep it readable by its owner only. I named the public key `winlab-test@lab.test-02729b6b.rsa.pub` when installing it on the client, following the pattern of the keys that ship with Chimera (`name@host-hex.rsa.pub`); the hex part I made up from a hash of the key. **The name worked, and I did not test whether apk cares what it is called.** (2048-bit RSA is fine for a test; for a real key choose the size and algorithm your distribution documents.)

## Build a package: `apk mkpkg`

`apk mkpkg` takes metadata and a **folder of files** and writes one `.apk` ([apk-mkpkg(8)](https://github.com/alpinelinux/apk-tools/blob/master/doc/apk-mkpkg.8.scd): `--info KEY:VALUE` for metadata, `--files PATH` for the root of the files, `--sign-key` to sign, `--output` for the file name):

```bash
d=pkg-1.0; mkdir -p $d/usr/bin
printf '#!/bin/sh\necho "wl-hello 1.0"\n' > $d/usr/bin/wl-hello; chmod 755 $d/usr/bin/wl-hello
apk mkpkg --info name:wl-hello --info version:1.0-r0 --info arch:noarch \
   --info description:"test package 1.0" --info license:MIT --info url:https://lab.test \
   --files $d --sign-key wl-repo.rsa --output /srv/wl-apk/main/noarch/wl-hello-1.0-r0.apk
```

The version `1.0-r0` is **version, then `-r` and a revision number** (the packaging revision, bumped when you change the package but not the program), the Alpine convention. `apk adbdump` prints the package's internal structure (`adb` is apk 3's binary format):

```text
$ apk adbdump wl-hello-1.0-r0.apk
#%SCHEMA: 676B6370
# ADB block, size: 320, compat: 0, ver: 0
info:
  name: wl-hello
  version: 1.0-r0
  hashes: 4fbc4ab70145c83d2cdc5981a616e99d6207fb1a
  description: test package 1.0
  arch: noarch
  license: MIT
  url: https://lab.test
  installed-size: 30
paths: # 3 items
  - acl: ...
  - name: usr ...
  - name: usr/bin
    files: # 1 items
      - name: wl-hello
        acl:
          mode: 0755
```

The package file is 591 bytes. Note `hashes:` (the content hash) and the **file modes and owners recorded per path**: the package records `root:root` and `0755` for each directory, not who built it.

## Make the index: `apk mkndx`, and the first error

```text
$ apk mkndx --sign-key wl-repo.rsa --output /srv/wl-apk/main/x86_64/Packages.adb /srv/wl-apk/main/noarch/*.apk
ERROR: /srv/wl-apk/main/noarch/wl-hello-1.0-r0.apk: UNTRUSTED signature
ERROR: 1 errors, not creating index
```

`apk mkndx` **verifies the packages it indexes**, and the build machine did not trust my new key. That is a good default: an index cannot be made from packages that fail your own trust check. There are two honest ways out: give `mkndx` a **private key directory that contains only the public key** (`--keys-dir DIR`), which leaves the machine's own trust alone, or `--allow-untrusted`, which switches the check off. I used the first:

```text
$ mkdir keys; cp wl-repo.rsa.pub keys/winlab-test@lab.test-02729b6b.rsa.pub
$ apk --keys-dir keys mkndx --sign-key wl-repo.rsa --output /srv/wl-apk/main/x86_64/Packages.adb /srv/wl-apk/main/noarch/*.apk
Index has 1 packages (of which 1 are new)
$ (cd /srv/wl-apk/main && find . -type f | sort | xargs ls -l | awk '{print $5, $9}')
591 ./noarch/wl-hello-1.0-r0.apk
478 ./x86_64/Packages.adb
```

(Hash and signature values in this lesson come from several runs of the same test, so they do not match each other.) The index is **478 bytes**: one entry holding the name, version, **a hash of the package** (`hashes: 1115ef6b...`), the size (`file-size: 591`) and the metadata, plus the **signature**:

```text
$ apk adbdump Packages.adb
packages: # 1 items
  - name: wl-hello
    version: 1.0-r0
    hashes: 1115ef6b70b0f3860a65b2c11a028a7fb19298e07f1d4ca707b8a78d6297b27b
    description: test package 1.0
    arch: noarch
    license: MIT
    url: https://lab.test
    installed-size: 30
    file-size: 591
# sig v00 h04 5e71eb49...: UNTRUSTED signature
```

The last line is `adbdump` telling you the signature is **not trusted on this machine**, which was true of the builder (its trust store did not hold my key), not a defect in the index.

**The layout surprise.** The tree has two directories under `main/`: the index is under **`x86_64/`** but the package is under **`noarch/`**. My first run put the package in `x86_64/` next to the index, and the client failed:

```text
(1/1) Installing wl-hello (1.0-r0)
ERROR: wl-hello-1.0-r0: HTTP 404: Not Found
```

The server log showed what apk had asked for:

```text
GET /main/x86_64/Packages.adb HTTP/1.1  200
GET /main/noarch/wl-hello-1.0-r0.apk HTTP/1.1  404
```

apk looks up each package at **`$base_url/$arch/$name-$version.apk` where `$arch` is the package's own architecture**, here `noarch`. It fetches the index from the *client's* architecture directory, and each file from *its* directory. Move the file to `main/noarch/` and it works. (apk-mkndx(8) also documents a `--pkgname-spec` option to put packages elsewhere; I did not test it.) **A repository that serves several architectures needs a `noarch/` directory too.**

## Serve it, and use it

```text
$ cd /srv/wl-apk && python3 -m http.server 8083 --bind 127.0.0.1 &
$ echo "v3 http://127.0.0.1:8083/main" > /etc/apk/repositories.d/99-wl.list
```

First **without** the key on the client:

```text
$ apk update
WARNING: updating and opening http://127.0.0.1:8083/main/x86_64/Packages.adb: UNTRUSTED signature
 [https://repo.chimera-linux.org/current/main]
1 unavailable, 0 stale; 9065 distinct packages available
```

apk **refuses my repository but carries on** with Chimera's own: it counts mine as "1 unavailable". Then install the public key and try again:

```text
$ cp wl-repo.rsa.pub /etc/apk/keys/winlab-test@lab.test-02729b6b.rsa.pub
$ apk update
 [https://repo.chimera-linux.org/current/main]
 [http://127.0.0.1:8083/main]
OK: 9066 distinct packages available
$ apk search wl-hello
wl-hello-1.0-r0
$ apk policy wl-hello
wl-hello policy:
  1.0-r0:
    http://127.0.0.1:8083/main
$ apk add wl-hello
(1/1) Installing wl-hello (1.0-r0)
OK: 1286.2 MiB in 521 packages
$ wl-hello
wl-hello 1.0
```

(Note that plain HTTP worked here: apk did not insist on HTTPS. Chimera's own repository line uses HTTPS.)

## Publish an update

```text
$ mkpkg 1.1; publish          (a new package file in main/noarch/, then apk mkndx again)
Index has 2 packages (of which 2 are new)
$ apk update
 [http://127.0.0.1:8083/main]
OK: 9067 distinct packages available
$ apk add --upgrade wl-hello
(1/1) Upgrading wl-hello (1.0-r0 -> 1.1-r0)
$ wl-hello
wl-hello 1.1
```

**A warning from my own test.** My first version of that step was `apk upgrade`, with no package name. That upgrades **every** installed package from **all** configured repositories, and here that included Chimera's real repository: it began upgrading the whole lab system (its output included `Adding boot menu entry for UEFI Firmware Settings`, a bootloader hook, and the totals grew from 520 to 524 packages), which is nothing to do with my test package. I restored the VM from its snapshot and used **`apk add --upgrade wl-hello`**, which upgrades only that package. On a machine that matters, run `apk upgrade --simulate` first and read the list.

## What the client says when something is wrong

**(a) The key is missing.** (the first test above) The repository is ignored with `UNTRUSTED signature`, and everything else keeps working. After removing the key again from `/etc/apk/keys` and running `apk update`, the same warning returned.

**(b) The index was changed after it was signed.** I appended 7 bytes of text to `Packages.adb` and ran `apk update`. The output was:

```text
 [https://repo.chimera-linux.org/current/main]
 [http://127.0.0.1:8083/main]
0 unavailable, 1 stale; 9067 distinct packages available
```

**No error message at all.** apk reported my repository as `1 stale` (it could not refresh it) and used the copy it had cached from the earlier good run, so a client that has **seen a good index once** can go on running on an old one with only a quiet "stale" count. I did not capture a warning line for this case (the `tail -3` I used may have cut it), so I cannot say whether apk printed one. **Watch for `stale` in your monitoring.**

**(c) An unsigned package in a signed index: the surprise.** I built `wl-unsigned` **without** `--sign-key`, and:

```text
$ apk --keys-dir keys mkndx --sign-key wl-repo.rsa --output .../Packages.adb .../*.apk
ERROR: /srv/wl-apk/main/noarch/wl-unsigned-1.0-r0.apk: UNTRUSTED signature
ERROR: 1 errors, not creating index
```

`mkndx` refused, as it did before, since the package had no trusted signature. Then I forced the index with `--allow-untrusted` (which signs the index with my key regardless) and tried to install on the client:

```text
$ apk add wl-unsigned
(1/1) Installing wl-unsigned (1.0-r0)
OK: 1286.2 MiB in 522 packages
```

**The client installed it, without any complaint.** The same file checked on its own says what you would expect:

```text
$ apk verify wl-unsigned-1.0-r0.apk
wl-unsigned-1.0-r0.apk: UNTRUSTED signature
$ apk verify wl-hello-1.1-r0.apk
wl-hello-1.1-r0.apk: OK
```

I did not read why; the index holds a **hash of each package** (`hashes:` and `file-size:` in the dump above), so a plausible reading is that the **signed index vouches for the package contents** and the client checks the downloaded file against it, instead of requiring a signature on every package. That is my interpretation of what I saw, **not** something I confirmed in the documentation. The practical consequence is large either way: **in this test the signing key for the index was the trust root.** Whoever can run `mkndx --allow-untrusted` with that key, or can write the index, can publish packages the clients will install. Guard the index-signing key and the machine that uses it more carefully than any single package. (This is the opposite of the dnf case, where an unsigned RPM in a signed index was refused.)

## How big is a real repository?

Because the index lists each package's `file-size`, you can add them up. From Chimera's real `main` index for `x86_64` (downloaded by `apk update`, read with `apk adbdump`): **9,007 packages totalling 16,620,518,385 bytes (about 15.5 GiB)**, with the index file itself at 1.2 MB. The three largest packages were game data (`xonotic-data` at 1.1 GiB, `sauerbraten-data` at 0.9 GiB) and a font (`fonts-noto-serif-cjk-extra-otf` at 437 MiB). That is the order of magnitude to plan storage for a distribution of that breadth, for **one** architecture and **one** release; the hosting lesson uses it. (`apk update` itself reported `9065 distinct packages` for the same repository; I did not reconcile the difference with the 9,007 I counted in the index.)

## Cleaning up the test

I removed the package, the `.list` file, the key and the test tree, and ran `apk update` to confirm the machine was back to Chimera's repository only. The lab VM is restored from its snapshot afterwards anyway.

## Common mistakes

- **Putting a `noarch` package next to the index.** apk asks for `$base_url/noarch/...`.
- **Running `apk upgrade` to test one package.** It upgrades everything. Use `apk add --upgrade NAME`.
- **`--allow-untrusted` as a habit.** It switches off the check that stopped a bad build. Use `--keys-dir` with only the key you mean.
- **Treating `stale` as harmless.** It can mean a tampered or unreachable index while you run on an old copy.
- **Letting many machines hold the index-signing key.** In this test that key decided what clients would install.
- **A private key anyone can read.** `chmod 600`, and keep it off the web root.
- **Forgetting the revision.** `1.1-r0`, then `1.1-r1` when only the packaging changes.
- **Testing on the machine you care about.** Use a throwaway VM.

## Check yourself

1. Build a package with `apk mkpkg`, index it with `apk mkndx` and install it from your own repository on a VM.
2. Why did `apk mkndx` refuse the first time, and which two ways round it exist? Which is safer?
3. Put the package in the wrong directory and read the server log. Where should it be, and why?
4. Install an unsigned package through a signed index and explain what that shows about where the trust is.
5. How would you notice a stale or tampered index on a fleet of machines?

## Not tested, and honest limits

`cbuild` and `cports`; Alpine's `abuild`; apk v2; more than one architecture; dependencies, scripts and triggers; `--pkgname-spec`; mirrors; HTTPS; key rotation; the tamper case beyond one appended string; and **anything on FenrirOS**. The package is trivial and the repository is one package deep. Chimera was at apk-tools 3.0.8, a young major version whose behaviour may change.
