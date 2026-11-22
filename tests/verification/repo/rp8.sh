#!/bin/bash
# Package-repo battery 8: the dnf repository health check, healthy and broken four ways (AlmaLinux; run as root via bash -s). CHECK is substituted by the driver.
. /etc/os-release; echo "### $PRETTY_NAME  $(curl --version | head -1 | cut -d' ' -f1-2)  $(gpg --version | head -1)  $(awk --version | head -1)"
cat > /usr/local/bin/wl-dnfcheck.sh <<'WLEOF'
@@CHECK@@
WLEOF
chmod 755 /usr/local/bin/wl-dnfcheck.sh; export PATH=$PATH:/usr/local/bin
dnf -y install createrepo_c rpm-build rpm-sign gnupg2 >/tmp/inst.log 2>&1; tail -1 /tmp/inst.log
R=/srv/wl-rpm; export GNUPGHOME=/var/tmp/wl-gpg; T=/var/tmp/wl-rpmbuild
rm -rf $R $GNUPGHOME $T; mkdir -p $R/x86_64 $GNUPGHOME $T; chmod 700 $GNUPGHOME
gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key "WinLab Test Repo <repo@lab.test>" ed25519 sign never >/dev/null 2>&1
gpg --export --armor > /var/tmp/wl-repo.asc
mkrpm() {
  printf 'Name: wl-hello\nVersion: %s\nRelease: 1\nSummary: test %s\nLicense: MIT\nBuildArch: noarch\n%%description\ntest\n%%install\nmkdir -p %%{buildroot}/usr/bin\necho hi > %%{buildroot}/usr/bin/wl-hello\n%%files\n/usr/bin/wl-hello\n' "$1" "$1" > $T/wl-hello.spec
  rpmbuild -bb --define "_topdir $T" $T/wl-hello.spec >/dev/null 2>&1; cp $T/RPMS/noarch/wl-hello-$1-1.noarch.rpm $R/x86_64/; }
publish() { createrepo_c --update $R >/dev/null 2>&1; gpg --batch --yes --pinentry-mode loopback --passphrase '' --detach-sign --armor -o $R/repodata/repomd.xml.asc $R/repodata/repomd.xml; }
mkrpm 1.0; mkrpm 1.1; publish
echo "--- metadata files:"; ls $R/repodata | sed -E 's/[0-9a-f]{40,}-//'
systemd-run --unit=wl-check-http --quiet python3 -m http.server 8093 --directory $R --bind 127.0.0.1; sleep 1
C="wl-dnfcheck.sh http://127.0.0.1:8093 /var/tmp/wl-repo.asc"
run() { echo "\$ $*"; "$@"; echo "exit status $?"; }

echo "### 1. healthy"
run $C
echo "### 2. a package file is missing"
mv $R/x86_64/wl-hello-1.1-1.noarch.rpm /var/tmp/keep.rpm
run $C
echo "### 3. a package file is the wrong size (truncated upload)"
head -c 300 /var/tmp/keep.rpm > $R/x86_64/wl-hello-1.1-1.noarch.rpm
run $C
cp /var/tmp/keep.rpm $R/x86_64/wl-hello-1.1-1.noarch.rpm
echo "### 4. a metadata file was changed after signing"
P=$(ls $R/repodata/*-primary.xml.gz); cp $P /var/tmp/pk.keep; echo "<!-- x -->" | gzip >> $P
run $C
cp /var/tmp/pk.keep $P
echo "### 5. repomd.xml was changed after signing"
cp $R/repodata/repomd.xml /var/tmp/rm.keep; sed -i 's/<revision>/<revision>9/' $R/repodata/repomd.xml
run $C
cp /var/tmp/rm.keep $R/repodata/repomd.xml
echo "### 6. signed by a different key"
export GNUPGHOME=/var/tmp/wl-gpg2; mkdir -p $GNUPGHOME; chmod 700 $GNUPGHOME
gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key "Other <o@lab.test>" ed25519 sign never >/dev/null 2>&1
gpg --batch --yes --pinentry-mode loopback --passphrase '' --detach-sign --armor -o $R/repodata/repomd.xml.asc $R/repodata/repomd.xml 2>/dev/null
run $C
echo "### 7. no signature file at all"
rm $R/repodata/repomd.xml.asc
run $C
export GNUPGHOME=/var/tmp/wl-gpg; publish
echo "### 8. usage errors (the signature is back, so the third reaches the key check)"
run wl-dnfcheck.sh http://127.0.0.1:8093
run wl-dnfcheck.sh http://127.0.0.1:8093 /nonexistent.asc
run wl-dnfcheck.sh http://127.0.0.1:8093 /etc/hostname
systemctl stop wl-check-http; rm -rf $R $T /var/tmp/wl-gpg /var/tmp/wl-gpg2 /var/tmp/*.keep /var/tmp/wl-repo.asc; echo done
