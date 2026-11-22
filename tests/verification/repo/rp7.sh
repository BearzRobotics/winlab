#!/bin/bash
# Package-repo battery 7: the apt repository health check, healthy and broken three ways (Ubuntu; run as root via bash -s). CHECK is substituted by the driver.
. /etc/os-release; echo "### $PRETTY_NAME  $(curl --version | head -1 | cut -d' ' -f1-2)  $(gpgv --version | head -1)"
cat > /usr/local/bin/wl-aptcheck.sh <<'WLEOF'
@@CHECK@@
WLEOF
chmod 755 /usr/local/bin/wl-aptcheck.sh
apt-get update >/tmp/upd.log 2>&1; DEBIAN_FRONTEND=noninteractive apt-get install -y dpkg-dev apt-utils gnupg >/tmp/inst.log 2>&1
export GNUPGHOME=/var/tmp/wl-gpg; R=/srv/wl-repo
rm -rf $R $GNUPGHOME /var/tmp/wl-pkg; mkdir -p $R/pool/main/w/wl-hello $GNUPGHOME; chmod 700 $GNUPGHOME
gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key "WinLab Test Repo <repo@lab.test>" ed25519 sign never >/dev/null 2>&1
gpg --export > /var/tmp/wl-repo.gpg
mkpkg() { d=/var/tmp/wl-pkg/wl-hello_$1; rm -rf $d; mkdir -p $d/DEBIAN $d/usr/bin; printf '#!/bin/sh\necho "wl-hello %s"\n' "$1" > $d/usr/bin/wl-hello; chmod 755 $d/usr/bin/wl-hello
  printf 'Package: wl-hello\nVersion: %s\nArchitecture: all\nMaintainer: WinLab Test <repo@lab.test>\nDescription: test %s\n' "$1" "$1" > $d/DEBIAN/control
  dpkg-deb --root-owner-group --build $d $R/pool/main/w/wl-hello/ >/dev/null; }
publish() { ( cd $R; mkdir -p dists/stable/main/binary-amd64
  dpkg-scanpackages --arch all pool 2>/dev/null > dists/stable/main/binary-amd64/Packages; gzip -9fk dists/stable/main/binary-amd64/Packages
  apt-ftparchive -o APT::FTPArchive::Release::Suite=stable -o APT::FTPArchive::Release::Codename=stable -o APT::FTPArchive::Release::Architectures=amd64 -o APT::FTPArchive::Release::Components=main release dists/stable > dists/stable/Release
  gpg --batch --yes --pinentry-mode loopback --passphrase '' -abs -o dists/stable/Release.gpg dists/stable/Release
  gpg --batch --yes --pinentry-mode loopback --passphrase '' --clearsign -o dists/stable/InRelease dists/stable/Release ) 2>/dev/null; }
mkpkg 1.0; mkpkg 1.1; publish
systemd-run --unit=wl-check-http --quiet python3 -m http.server 8092 --directory $R --bind 127.0.0.1; sleep 1
C="wl-aptcheck.sh http://127.0.0.1:8092 stable main amd64 /var/tmp/wl-repo.gpg"
run() { echo "\$ $*"; "$@"; echo "exit status $?"; }

echo "### 1. healthy"
run $C
echo "### 2. a package file is missing (index published before the file)"
mv $R/pool/main/w/wl-hello/wl-hello_1.1_all.deb /var/tmp/keep.deb
run $C
echo "### 3. a package file is the wrong size (truncated upload)"
head -c 300 /var/tmp/keep.deb > $R/pool/main/w/wl-hello/wl-hello_1.1_all.deb
run $C
cp /var/tmp/keep.deb $R/pool/main/w/wl-hello/wl-hello_1.1_all.deb
echo "### 4. the index was changed after signing"
cp $R/dists/stable/main/binary-amd64/Packages.gz /var/tmp/pk.keep
echo "# x" | gzip >> $R/dists/stable/main/binary-amd64/Packages.gz
run $C
cp /var/tmp/pk.keep $R/dists/stable/main/binary-amd64/Packages.gz
echo "### 5. signed by a different key"
export GNUPGHOME=/var/tmp/wl-gpg2; mkdir -p $GNUPGHOME; chmod 700 $GNUPGHOME
gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key "Other <o@lab.test>" ed25519 sign never >/dev/null 2>&1
gpg --batch --yes --pinentry-mode loopback --passphrase '' --clearsign -o $R/dists/stable/InRelease $R/dists/stable/Release 2>/dev/null
run $C
echo "### 6. usage errors"
run wl-aptcheck.sh http://127.0.0.1:8092 stable main
run wl-aptcheck.sh http://127.0.0.1:8092 stable main amd64 /nonexistent.gpg
systemctl stop wl-check-http; rm -rf $R /var/tmp/wl-gpg /var/tmp/wl-gpg2 /var/tmp/wl-pkg /var/tmp/*.keep /var/tmp/wl-repo.gpg; echo done
