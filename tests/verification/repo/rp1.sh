#!/bin/bash
# Package-repo battery 1: a signed apt repository, built by hand, served as static files (Ubuntu; run as root via bash -s)
. /etc/os-release; echo "### $PRETTY_NAME"
apt-get update >/tmp/upd.log 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y dpkg-dev apt-utils gnupg >/tmp/inst.log 2>&1; tail -1 /tmp/inst.log
dpkg --version | head -1; apt-ftparchive --version 2>&1 | head -1; gpg --version | head -1
R=/srv/wl-repo; export GNUPGHOME=/var/tmp/wl-gpg
rm -rf $R $GNUPGHOME /var/tmp/wl-pkg; mkdir -p $R/pool/main/w/wl-hello $GNUPGHOME; chmod 700 $GNUPGHOME

echo "### 1. a signing key that exists only for this repository"
gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key "WinLab Test Repo <repo@lab.test>" ed25519 sign never 2>&1 | tail -1
gpg --list-keys --keyid-format long 2>/dev/null | grep -E 'pub|uid' | sed 's/  */ /g'
gpg --export > $R/wl-repo.gpg; gpg --export --armor > $R/wl-repo.asc
ls -l $R/wl-repo.gpg $R/wl-repo.asc | awk '{print $5, $9}'

mkpkg() {
  d=/var/tmp/wl-pkg/wl-hello_$1; rm -rf $d; mkdir -p $d/DEBIAN $d/usr/bin
  printf '#!/bin/sh\necho "wl-hello %s"\n' "$1" > $d/usr/bin/wl-hello; chmod 755 $d/usr/bin/wl-hello
  printf 'Package: wl-hello\nVersion: %s\nArchitecture: all\nMaintainer: WinLab Test <repo@lab.test>\nDescription: test package %s\n' "$1" "$1" > $d/DEBIAN/control
  dpkg-deb --root-owner-group --build $d $R/pool/main/w/wl-hello/ 2>&1 | tail -1
}
publish() {
  cd $R; mkdir -p dists/stable/main/binary-amd64
  dpkg-scanpackages --arch all pool 2>/dev/null > dists/stable/main/binary-amd64/Packages
  gzip -9fk dists/stable/main/binary-amd64/Packages
  apt-ftparchive -o APT::FTPArchive::Release::Origin=WinLab -o APT::FTPArchive::Release::Label=WinLab \
    -o APT::FTPArchive::Release::Suite=stable -o APT::FTPArchive::Release::Codename=stable \
    -o APT::FTPArchive::Release::Architectures=amd64 -o APT::FTPArchive::Release::Components=main \
    release dists/stable > dists/stable/Release
  gpg --batch --yes --pinentry-mode loopback --passphrase '' -abs -o dists/stable/Release.gpg dists/stable/Release
  gpg --batch --yes --pinentry-mode loopback --passphrase '' --clearsign -o dists/stable/InRelease dists/stable/Release
}
echo "### 2. build a package, publish it"
mkpkg 1.0
publish
find $R -type f | sort | sed "s|$R/||"
echo "--- Packages"; cat $R/dists/stable/main/binary-amd64/Packages
echo "--- Release (hashes shortened)"; sed -E 's/^ ([0-9a-f]{12})[0-9a-f]*/ \1.../' $R/dists/stable/Release

echo "### 3. serve the directory (static files, nothing else)"
systemd-run --unit=wl-repo-http --quiet python3 -m http.server 8081 --directory $R --bind 127.0.0.1
sleep 1; curl -s -o /dev/null -w 'Release over http: %{http_code}\n' http://127.0.0.1:8081/dists/stable/Release

echo "### 4. a client uses it: key in /etc/apt/keyrings, source with Signed-By"
mkdir -p /etc/apt/keyrings; cp $R/wl-repo.gpg /etc/apt/keyrings/wl-repo.gpg
cat > /etc/apt/sources.list.d/wl-repo.sources <<'EOF'
Types: deb
URIs: http://127.0.0.1:8081
Suites: stable
Components: main
Signed-By: /etc/apt/keyrings/wl-repo.gpg
EOF
apt-get update 2>&1 | grep -E '127.0.0.1|Err|W:|E:'
apt-cache policy wl-hello | sed 's/  */ /g'
apt-get install -y wl-hello 2>&1 | grep -E 'Get:|Setting up|E:'
wl-hello; dpkg -s wl-hello | grep -E '^(Status|Version)'

echo "### 5. publish 1.1, the client upgrades"
mkpkg 1.1; publish
apt-get update 2>&1 | grep -E '127.0.0.1|Err'
apt list --upgradable 2>/dev/null | grep wl-hello
apt-get install -y --only-upgrade wl-hello 2>&1 | grep -E 'Setting up'; wl-hello

echo "### 6. failures a client reports"
echo "--- (a) the index is changed after signing"
cp $R/dists/stable/main/binary-amd64/Packages.gz /var/tmp/Packages.gz.keep
echo "# tampered" | gzip >> $R/dists/stable/main/binary-amd64/Packages.gz
rm -f /var/lib/apt/lists/127.0.0.1*
apt-get update 2>&1 | grep -E 'Err|E:|W:|mismatch|Hash' | cut -c1-150
cp /var/tmp/Packages.gz.keep $R/dists/stable/main/binary-amd64/Packages.gz
echo "--- (b) repository signed with a different key than the client trusts"
export GNUPGHOME=/var/tmp/wl-gpg2; rm -rf $GNUPGHOME; mkdir -p $GNUPGHOME; chmod 700 $GNUPGHOME
gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key "Other Key <other@lab.test>" ed25519 sign never 2>/dev/null
cd $R; gpg --batch --yes --pinentry-mode loopback --passphrase '' --clearsign -o dists/stable/InRelease dists/stable/Release; gpg --batch --yes --pinentry-mode loopback --passphrase '' -abs -o dists/stable/Release.gpg dists/stable/Release
apt-get update 2>&1 | grep -E 'Err|E:|W:|NO_PUBKEY|signatures' | cut -c1-170
export GNUPGHOME=/var/tmp/wl-gpg; publish
echo "--- (c) no signature files at all"
mv $R/dists/stable/InRelease /var/tmp/InRelease.keep; mv $R/dists/stable/Release.gpg /var/tmp/Release.gpg.keep
apt-get update 2>&1 | grep -E 'Err|E:|W:|not signed' | cut -c1-170
mv /var/tmp/InRelease.keep $R/dists/stable/InRelease; mv /var/tmp/Release.gpg.keep $R/dists/stable/Release.gpg
apt-get update 2>&1 | grep -E 'Hit|Get|Err' | head -3

echo "### 7. publishing without a half-updated window: build in a new directory, swap a symlink"
mkdir -p /srv/wl-repo-releases; cp -a $R /srv/wl-repo-releases/r1; ln -sfn r1 /srv/wl-repo-releases/current.new; mv -T /srv/wl-repo-releases/current.new /srv/wl-repo-releases/current
readlink /srv/wl-repo-releases/current
cp -a $R /srv/wl-repo-releases/r2; ln -sfn r2 /srv/wl-repo-releases/current.new; mv -T /srv/wl-repo-releases/current.new /srv/wl-repo-releases/current
readlink /srv/wl-repo-releases/current

echo "### cleanup"
systemctl stop wl-repo-http; apt-get remove -y wl-hello >/dev/null 2>&1
rm -rf /etc/apt/sources.list.d/wl-repo.sources /etc/apt/keyrings/wl-repo.gpg $R /srv/wl-repo-releases /var/tmp/wl-gpg /var/tmp/wl-gpg2 /var/tmp/wl-pkg
apt-get update 2>&1 | grep -cE 'Err|127.0.0.1'; echo done
