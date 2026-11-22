*Draft for owner review.* Hosting a package repository sounds like a big infrastructure problem and is, at its core, a small one: **serve a directory of files over HTTP, update it without ever showing clients a half-finished state, keep the signing key away from the web server, and have enough disk.** This lesson takes the storage question first, with **measured** sizes of real repositories (Chimera, AlmaLinux, Ubuntu), then serving, publishing, mirroring and checking. It builds on the three format lessons (`packaging.apt-repository`, `packaging.dnf-repository`, `packaging.apk-repository`) and on the backup lesson (`homelab.backups`). The owner is building a repository for FenrirOS and choosing storage for it; I know nothing about FenrirOS, so everything here is general and tested on Ubuntu, AlmaLinux and Chimera only.

**What was tested, and where.** **Ubuntu 24.04.5** with **nginx 1.24.0**, **rsync 3.2.7**, **curl 8.5.0** and **gpgv 2.4.4** (`tests/verification/repo/rp4.sh`, `rp4b.sh`, `rp6.sh`, `rp7.sh`); **AlmaLinux 9.8** and **Chimera Linux** for the size measurements (`rp5.sh`, `rp6.sh`). Output is real. **Not tested:** **object storage** (S3-compatible or others) or a **CDN** in front of a repository; **HTTPS** and certificate renewal; **load**, bandwidth, or how many clients one machine can serve; **ZFS or btrfs snapshots** and filesystem choice; geographic mirrors; `reprepro`, `aptly`, `pulp` and other repository managers; and anything about FenrirOS.

## What a repository host has to do

1. **Serve files**, mostly large, mostly read once per client per update. There is no application server and no database.
2. **Serve the small files fresh and the big files from cache.** The index changes with every publish and clients must see the new one; the packages never change once published (a new version is a new file).
3. **Publish atomically**: a client must never see an index that points at a file that is not there yet, or a half-copied tree.
4. **Keep the signing key off the web server.** The server only needs the public files.
5. **Have the disk**, now and for the growth you plan, and be able to **rebuild or restore** it.

## How big is a repository? Measured

An index tells you the size of every package, so you can add them up without downloading anything. From the machines in the lab (each by its own tool; the commands are in `rp5.sh` and `rp6.sh`):

| Repository | Packages | Total size of package files |
|---|---|---|
| Chimera Linux **main**, x86_64 (`apk adbdump` of the index, summing `file-size`) | 9,007 | 16,620,518,385 bytes = **15.5 GiB** |
| AlmaLinux 9 **BaseOS** (`dnf repoquery --available`, `downloadsize`) | 2,632 | 2.90 GiB |
| AlmaLinux 9 **AppStream** | 13,374 | 14.47 GiB |
| AlmaLinux 9 **EPEL** (extra packages) | 53,402 | 19.48 GiB |
| Ubuntu 24.04 `noble`, `-updates`, `-backports`, `-security`, all four components (`apt-cache dumpavail`, summing `Size:`) | 88,827 package versions | **408.4 GiB** (amd64 324.0 GiB, architecture-independent 84.4 GiB) |

How to read this honestly:

- **These are not like for like.** Chimera's number is *one* repository, *one* architecture, *one* release. The Ubuntu number counts **every version of every package in four suites** (one package can appear in `noble`, in `-updates` and in `-security`), so it is an upper bound on what a mirror would store. The AlmaLinux counts are what `dnf repoquery --available` reported; that may include more than one version of a package, and I did not limit it to the latest.
- **The index is tiny next to the data.** Chimera's `Packages.adb` was **1,215,483 bytes** (1.2 MB) describing 15.5 GiB, about 0.007 % of it. Clients download the index on every update, the packages only when they install them.
- **A few packages dominate.** Chimera's largest were `xonotic-data` (1.1 GiB), `sauerbraten-data` (0.9 GiB) and `fonts-noto-serif-cjk-extra-otf` (437 MiB); Ubuntu's were `qgis-api-doc` (2.9 GB), `0ad-data` (1.4 GB) and `flightgear-data-base` (1.4 GB); AlmaLinux's `linux-firmware` (721 MB). Game data, documentation and firmware are the heavy parts. **A smaller distribution, with a smaller package set, is a smaller repository.**

**Planning arithmetic** (arithmetic, not measurement): disk needed ≈ *size of one release and architecture* × *number of architectures* × *number of releases you keep* + *old package versions you keep* + *working space to publish*. For a Chimera-sized package set that is about 16 GiB per architecture per release before any history. If your publish method **copies** the tree to a new directory (like the symlink swap below), the working space is another full copy, unless you use **hard links** (the `rsync --link-dest` technique from the backup lesson shares unchanged files between trees; I did not test that for a repository, but the mechanism is the same).

**What this says about storage choice.** At the scale of tens of GiB the choice is not about capacity: any single disk holds it. It is about **what happens when something goes wrong**: whether you can restore the repository (the packages can be rebuilt from source, but only if you still have the sources, build recipes and **the signing key**), whether you can **keep old releases** cheaply, and whether corruption is **detected** (a damaged `.deb` is caught by clients through the hash in the index; a damaged *index* is caught by the signature). Filesystem features such as checksumming and snapshots (ZFS, btrfs) address those; I did not test them, so I cannot say how they behave under this workload.

## Serve it with nginx

nginx serves static files efficiently with a few lines. The configuration I tested, with the repository root a symlink (`/srv/wl-hosting/current`, explained under publishing) and a first attempt at cache rules:

```text
server {
    listen 127.0.0.1:8090;
    root /srv/wl-hosting/current;
    autoindex on;
    location ~ \.(deb|gz)$ { add_header Cache-Control "public, max-age=3600"; }
    location /dists/ { add_header Cache-Control "no-cache"; }
}
```

`nginx -t` said `syntax is ok`; `apt-get update` and `apt-get install` against it worked. What the server sends:

```text
$ curl -sI http://127.0.0.1:8090/dists/stable/InRelease
HTTP/1.1 200 OK
Server: nginx/1.24.0 (Ubuntu)
Content-Length: 1694
Last-Modified: Sun, 22 Nov 2026 13:56:56 GMT
ETag: "6b02f4a8-69e"
Cache-Control: no-cache
Accept-Ranges: bytes
$ curl -sI .../pool/main/w/wl-hello/wl-hello_1.0_all.deb
HTTP/1.1 200 OK
Content-Length: 532
Cache-Control: public, max-age=3600
ETag: "6b02f4a8-214"
```

Four things a repository server gets for free from a static file server, all tested:

- **`ETag` and `Last-Modified`** let a client ask "has this changed?". With `If-None-Match: "6b02f4a8-69e"` nginx answered **304** (no body sent): the cheap path for the index. Clients can use these for cheap re-checks; I did not capture what `apt` itself sends.
- **Range requests** (`curl -r 0-99`) returned **206** with exactly 100 bytes, so an interrupted download of a large package can resume.
- **A directory listing** (`autoindex on`) returned `href="dists/"`, `href="pool/"`. Nice for people, and not needed by `apt`, `dnf` or `apk`. Consider turning it off for a public server.
- **A path outside the root is not reachable**: `curl --path-as-is http://127.0.0.1:8090/../../etc/passwd` returned **400**.

### A bug in my first configuration

The two `location` blocks above look as if they say "files under `/dists/` are not cached, `.deb` and `.gz` files are cached for an hour". Test each kind of file:

```text
dists/stable/InRelease                       Cache-Control: no-cache
dists/stable/main/binary-amd64/Packages.gz   Cache-Control: public, max-age=3600     <-- the INDEX, cached for an hour
pool/main/w/wl-hello/x_1.0_all.deb           Cache-Control: public, max-age=3600
```

**The index was told to be cached for an hour.** `Packages.gz` lives under `/dists/`, but nginx tries **regular-expression locations after the longest matching prefix** and the regex wins unless the prefix carries `^~`, so `.(deb|gz)$` took precedence over `/dists/`. The [nginx `location` documentation](https://nginx.org/en/docs/http/ngx_http_core_module.html#location) says so: "Then regular expressions are checked, in the order of their appearance", and "If the longest matching prefix location has the "^~" modifier, then regular expressions and predicate locations are not checked." A client or proxy cache could keep serving an hour-old index. (I found it by testing each kind of file; my first full test used this configuration and did not notice, because it checked only that `apt` worked, not the headers.) The fix is the `^~` modifier, which makes a prefix match **final**:

```text
location ^~ /dists/ { add_header Cache-Control "no-cache"; }
location ~ \.(deb)$ { add_header Cache-Control "public, max-age=31536000, immutable"; }
```

```text
dists/stable/InRelease                       Cache-Control: no-cache
dists/stable/main/binary-amd64/Packages.gz   Cache-Control: no-cache
pool/main/w/wl-hello/x_1.0_all.deb           Cache-Control: public, max-age=31536000, immutable
```

Now the packages, which never change under the same name, are cacheable for a year and the index is not cacheable at all. **`immutable` is only true if you never overwrite a published file**; a repository where you replace `foo_1.0_all.deb` in place breaks that promise. (I also did not test what an `apt` or `dnf` client does with these headers beyond the update and install above.)

Python's `http.server`, which the earlier lessons used, is for **testing**. I did not load-test it or nginx. For a real server also consider HTTPS and a rate limit: not tested.

## Publish without showing clients a broken state

Two habits, both tested on this nginx:

**1. Files first, index last.** I published an index that listed `wl-hello 1.1` **before** the `.deb` existed. A client that updated in that window saw `Candidate: 1.1` and the install failed:

```text
Err:1 http://127.0.0.1:8090 stable/main amd64 wl-hello all 1.1
  404  Not Found [IP: 127.0.0.1 8090]
E: Failed to fetch http://127.0.0.1:8090/pool/main/w/wl-hello/wl-hello_1.1_all.deb  404  Not Found
```

When the file arrived the same client succeeded. **Copy the package files, then replace the index and its signature.**

**2. Swap a whole tree with a symlink.** Build the new tree in a new directory, then replace the symlink in one step:

```text
$ ln -sfn r2 /srv/wl-hosting/current.new; mv -T /srv/wl-hosting/current.new /srv/wl-hosting/current
```

`mv -T` is one atomic rename, so a request sees the old tree or the new one. nginx followed the symlink in my tests (its default allows it; I did not test `disable_symlinks`). Keep the previous tree (`r1`) for a while: a client in the middle of a download may still be reading from it, and it is your **rollback**: point the symlink back.

## Mirror it

To put the same repository on a second server (for redundancy, or closer to users) the standard tool is `rsync` (see the rsync section of the backup lesson):

```text
$ rsync -a --delete $H/r2/ /srv/wl-mirror/
$ rsync -a --delete -i $H/r2/ /srv/wl-mirror/ | wc -l
0                                           (the second run changed nothing)
$ rsync -a --delete --delay-updates -v $H/r2/ /srv/wl-mirror/
dists/stable/InRelease
dists/stable/Release
...
$ diff -r $H/r2 /srv/wl-mirror && echo "mirror identical"
mirror identical
```

`--delay-updates` makes `rsync` put all updated files in place **together at the end** instead of one by one, which narrows the window where a mirror holds a mixed state (I did not observe the window itself). **A mirror inherits the publish-order problem**: if the index arrives before the packages, clients of the mirror see the same 404 as before. A safer sequence copies the pool first (`rsync` the `pool/` directory), then `dists/`.

## Check it from the outside

A repository can be unhealthy while the web server is perfectly fine. This script checks it **the way a client sees it** and uses only `curl`, `gpgv`, `sha256sum` and `awk`: that `InRelease` verifies against the public key, that the index named in `Release` has the size and hash promised, and that every package listed exists with the promised size. Run it after every publish and from a different machine on a schedule.

```bash
#!/bin/bash
# wl-aptcheck.sh BASEURL SUITE COMPONENT ARCH KEYRING
# Health check for an apt repository, from the outside, the way a client sees it:
#   1. InRelease verifies against KEYRING (a binary keyring made with gpg --export)
#   2. the Packages.gz named in Release has the size and SHA-256 that Release promises
#   3. every package listed in Packages exists on the server with the size Packages promises
# Prints ok/FAIL lines; exit status 0 if everything is fine, 1 if anything failed, 2 on a usage error.
[ $# -eq 5 ] || { echo "usage: wl-aptcheck.sh BASEURL SUITE COMPONENT ARCH KEYRING" >&2; exit 2; }
base=${1%/} suite=$2 comp=$3 arch=$4 keyring=$5
[ -r "$keyring" ] || { echo "wl-aptcheck: cannot read keyring $keyring" >&2; exit 2; }
tmp=$(mktemp -d) || exit 2; trap 'rm -rf "$tmp"' EXIT
fails=0
ok()  { printf 'ok    %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }

# 1. the signed Release
curl -fsS -o "$tmp/InRelease" "$base/dists/$suite/InRelease" 2>"$tmp/curl.err" || { bad "cannot fetch InRelease: $(tr -d '\n' < "$tmp/curl.err")"; exit 1; }
if gpgv --keyring "$keyring" --output "$tmp/Release" "$tmp/InRelease" 2>"$tmp/gpgv.err"; then
  ok "InRelease signature: $(grep -o 'using [A-Z0-9 ]* key [0-9A-F]*' "$tmp/gpgv.err" | head -1)"
else
  bad "InRelease signature: $(grep -m1 -iE 'BAD|no public key|can.t check' "$tmp/gpgv.err")"; exit 1
fi

# 2. the index named in Release
rel="$comp/binary-$arch/Packages.gz"
read -r want_hash want_size < <(awk -v f="$rel" '/^SHA256:/ {s = 1; next} /^[A-Za-z]/ {s = 0} s && $3 == f {print $1, $2; exit}' "$tmp/Release")
[ -n "$want_hash" ] || { bad "$rel is not listed in Release"; exit 1; }
curl -fsS -o "$tmp/Packages.gz" "$base/dists/$suite/$rel" 2>"$tmp/curl.err" || { bad "cannot fetch $rel: $(tr -d '\n' < "$tmp/curl.err")"; exit 1; }
got_hash=$(sha256sum "$tmp/Packages.gz" | cut -d' ' -f1); got_size=$(stat -c %s "$tmp/Packages.gz")
if [ "$got_hash" = "$want_hash" ] && [ "$got_size" = "$want_size" ]; then ok "$rel matches Release ($got_size bytes)"
else bad "$rel differs from Release: size $got_size (Release says $want_size), hash ${got_hash:0:12} (Release says ${want_hash:0:12})"; exit 1; fi

# 3. every package on the server, with the promised size
n=0
while read -r file size; do
  n=$((n + 1))
  code_len=$(curl -sI -o /dev/null -w '%{http_code} %header{content-length}' "$base/$file")
  code=${code_len%% *}; len=${code_len#* }
  if [ "$code" != 200 ]; then bad "$file: HTTP $code"
  elif [ "$len" != "$size" ]; then bad "$file: $len bytes on the server, Packages says $size"
  fi
done < <(zcat "$tmp/Packages.gz" | awk '/^Filename:/ {f = $2} /^Size:/ {print f, $2}')
(( fails == 0 )) && ok "$n package file(s) present with the right size"
(( fails == 0 )) || printf '%d check(s) failed\n' "$fails"
exit $(( fails > 0 ))
```

(Bash shebang: it uses process substitution `< <( ... )` and `(( ))`. `%header{content-length}` in `curl -w` needs a reasonably new curl; 8.5.0 here.) I tested it against a healthy repository and four breakages, each with its own exit status:

```text
healthy:                  ok    InRelease signature: using EDDSA key 553DAF70...
                          ok    main/binary-amd64/Packages.gz matches Release (281 bytes)
                          ok    1 package file(s) present with the right size            exit status 0
package file missing:     FAIL  pool/main/w/wl-hello/wl-hello_1.1_all.deb: HTTP 404      exit status 1
file truncated:           FAIL  ...wl-hello_1.1_all.deb: 300 bytes on the server, Packages says 532    exit status 1
index changed after
signing:                  FAIL  main/binary-amd64/Packages.gz differs from Release: size 305 (Release says 281), hash ed8a0bb21b58 (Release says 4ea94b645384)    exit status 1
signed by another key:    FAIL  InRelease signature: gpgv: Can't check signature: No public key    exit status 1
wrong usage:              usage: ...  (exit status 2)      missing keyring: wl-aptcheck: cannot read keyring ...  (exit status 2)
```

Note `1 package file(s)` for a pool holding **two** package versions (1.0 and 1.1): `dpkg-scanpackages` lists only the newest by default, so the checker checks what clients can ask for, not every file in the pool. The checker is apt-specific, and checks one suite, one component and one architecture; a dnf or apk version would follow the same three steps with that format's files (not written). It does **not** verify the package signatures or contents, only presence and size.

## Where the signing key lives

- **Not on the web server.** The server needs only public files; if it is compromised an attacker can *delete* or *corrupt* things (and your checks will notice) but cannot *sign* anything new.
- **On a machine that does the signing**, ideally one that does not run untrusted build steps. In the apk test the **index-signing key was the trust root** (see `packaging.apk-repository`), so that key and the machine holding it need the most protection.
- **With a passphrase, an expiry and a rotation plan** for a real key; the keys in these lessons were throwaway.
- **Backed up separately** from the repository. Losing it means every client must be given a new trusted key (the repository's own `.asc` or `.rsa.pub` file is where clients get the public half; I did not test rotation).
- **Public key distribution is itself a trust problem.** A client that fetches the public key from the same server it is about to trust gains nothing. Put the fingerprint somewhere independent (a signed release note, a separate site, a printed card).

## Backing up the repository

The pool is **immutable once published** (a changed package is a new file), so a backup tool that deduplicates or syncs by file name copies each package once. `rsync -a` to a second disk, or a restic repository (see `homelab.backups`), both fit. What you cannot recover from the published files alone is the **signing key** and the **sources and build recipes**: back those up on their own schedule, and **test a restore of the whole chain** by building a fresh repository from a backup and running the health check against it. I did not run that end-to-end test.

## Common mistakes

- **Letting a regex location swallow your index rule.** Test the cache headers of each kind of file; use `^~` for the prefix.
- **Cache headers that promise `immutable` for files you overwrite.**
- **Index first, files later.** Clients see 404s.
- **Editing the live tree.** Build elsewhere and swap a symlink; keep the old tree for rollback.
- **The signing key on the web server**, or only on the machine that builds untrusted code.
- **Serving the public key from the same place as the repository and calling that trust.**
- **No outside check.** The web server being up does not mean the repository is valid.
- **Counting capacity from one number.** Multiply by architectures and releases kept, add history, add working space.
- **Treating a mirror as a backup.** A mirror copies your mistakes too.
- **Directory listings left on** for a server that does not need them.

## Check yourself

1. Add up the package sizes of a repository you use (from its index) and estimate the disk for three architectures and two releases with history.
2. Configure nginx for a repository and prove with `curl -I` that the index is not cacheable and a `.deb` is. Then break it with a regex location and show the difference.
3. Publish in the wrong order, show the client's 404, then publish in the right order.
4. Swap two trees with the symlink method and roll back.
5. Run the health checker against a healthy and a broken repository and explain each failure line.
6. Where does your signing key live, who can reach it, and how would you rotate it?

## Not tested, and honest limits

Object storage and CDNs; HTTPS and certificates; load and bandwidth; filesystem features (ZFS, btrfs, inodes); geographic mirrors; repository managers; the checker for dnf and apk; a restore of the whole repository from backup; key rotation; and FenrirOS. The size table mixes different tools and different kinds of count and is a guide to the order of magnitude, not a comparison.
