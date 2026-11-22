#!/bin/bash
# Package-repo battery 2: a signed dnf/rpm repository, built by hand, served as static files (AlmaLinux; run as root via bash -s)
. /etc/os-release; echo "### $PRETTY_NAME"
dnf -y install createrepo_c rpm-build rpm-sign gnupg2 >/tmp/inst.log 2>&1; tail -1 /tmp/inst.log
createrepo_c --version; rpmbuild --version; rpm --version; gpg --version | head -1
R=/srv/wl-rpm; export GNUPGHOME=/var/tmp/wl-gpg; T=/var/tmp/wl-rpmbuild
rm -rf $R $GNUPGHOME $T; mkdir -p $R/x86_64 $GNUPGHOME $T; chmod 700 $GNUPGHOME

echo "### 1. a signing key for this repository"
gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key "WinLab Test Repo <repo@lab.test>" ed25519 sign never 2>&1 | tail -1
KEYID=$(gpg --list-keys --with-colons | awk -F: '/^fpr/ {print $10; exit}')
gpg --list-keys --keyid-format long 2>/dev/null | grep -E 'pub|uid' | sed 's/  */ /g'
gpg --export --armor > $R/wl-repo.asc; wc -c < $R/wl-repo.asc

mkrpm() {
  cat > $T/wl-hello.spec <<EOF
Name: wl-hello
Version: $1
Release: 1
Summary: test package $1
License: MIT
BuildArch: noarch
%description
test package $1
%install
mkdir -p %{buildroot}/usr/bin
printf '#!/bin/sh\necho "wl-hello $1"\n' > %{buildroot}/usr/bin/wl-hello
chmod 755 %{buildroot}/usr/bin/wl-hello
%files
/usr/bin/wl-hello
EOF
  rpmbuild -bb --define "_topdir $T" $T/wl-hello.spec 2>&1 | grep -E 'Wrote|error' | sed "s|$T/||"
  cp $T/RPMS/noarch/wl-hello-$1-1.noarch.rpm $R/x86_64/
}
signrpm() { rpmsign --addsign --define "_gpg_name $KEYID" --define "__gpg_sign_cmd %{__gpg} gpg --batch --no-verbose --no-armor --pinentry-mode loopback --passphrase '' --no-secmem-warning -u %{_gpg_name} -sbo %{__signature_filename} --digest-algo sha256 %{__plaintext_filename}" "$@" 2>&1 | tail -1; }
publish() {
  createrepo_c --update $R 2>&1 | tail -1
  gpg --batch --yes --pinentry-mode loopback --passphrase '' --detach-sign --armor -o $R/repodata/repomd.xml.asc $R/repodata/repomd.xml
}

echo "### 2. build, sign the package, publish the repository"
mkrpm 1.0
echo "--- before signing"; rpm -qp --qf '%{NAME} %{VERSION} signature: %{SIGPGP:pgpsig}%{SIGGPG:pgpsig}\n' $R/x86_64/wl-hello-1.0-1.noarch.rpm 2>/dev/null; rpm -Kv $R/x86_64/wl-hello-1.0-1.noarch.rpm 2>&1 | sed -n '2,6p'
signrpm $R/x86_64/wl-hello-1.0-1.noarch.rpm
echo "--- after signing (the key is not in the rpm database yet)"
rpm -Kv $R/x86_64/wl-hello-1.0-1.noarch.rpm 2>&1 | sed -n '2,6p'
publish
find $R -type f | sort | sed "s|$R/||"
echo "--- repomd.xml (data entries)"; grep -E '<data type|<location' $R/repodata/repomd.xml | sed 's/  */ /g' | paste - - | sed -E 's/-[0-9a-f]{20,}//' | head -6

echo "### 3. serve it"
systemd-run --unit=wl-rpm-http --quiet python3 -m http.server 8082 --directory $R --bind 127.0.0.1
sleep 1; curl -s -o /dev/null -w 'repomd.xml over http: %{http_code}\n' http://127.0.0.1:8082/repodata/repomd.xml

echo "### 4. a client uses it"
cat > /etc/yum.repos.d/wl.repo <<'EOF'
[wl]
name=WinLab test repository
baseurl=http://127.0.0.1:8082/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=http://127.0.0.1:8082/wl-repo.asc
EOF
dnf -y makecache --repo wl 2>&1 | grep -vE '^$' | cut -c1-140 | tail -8
dnf -y install wl-hello 2>&1 | grep -E 'Importing|Key imported|Installing|Installed|wl-hello|Error' | cut -c1-140 | head -8
wl-hello
rpm -q --qf '%{NAME} %{VERSION}-%{RELEASE} %{SIGPGP:pgpsig}\n' wl-hello | cut -c1-120
rpm -qa 'gpg-pubkey*' --qf '%{NAME}-%{VERSION}-%{RELEASE}  %{SUMMARY}\n' | grep -i winlab

echo "### 5. publish 1.1 and upgrade"
mkrpm 1.1; signrpm $R/x86_64/wl-hello-1.1-1.noarch.rpm; publish
dnf -y check-update --refresh --repo wl 2>&1 | grep wl-hello
dnf -y upgrade wl-hello 2>&1 | grep -E 'Upgrading|Upgraded|wl-hello' | head -4; wl-hello
dnf repoquery --repo wl wl-hello 2>&1 | tail -3

echo "### 6. failures a client reports"
echo "--- (a) a package that was not signed"
mkrpm 1.2; publish
dnf -y clean metadata >/dev/null 2>&1
dnf -y install wl-hello-1.2 2>&1 | grep -E 'not signed|Error|GPG|Failed' | cut -c1-150 | head -4
echo "--- (b) repomd.xml changed after it was signed"
sed -i 's/<revision>/<revision>9/' $R/repodata/repomd.xml
dnf -y clean metadata >/dev/null 2>&1
dnf -y makecache --repo wl 2>&1 | grep -E 'GPG|signature|Error|Failed' | cut -c1-150 | head -4
publish
echo "--- (c) after republishing correctly it works again"
dnf -y clean metadata >/dev/null 2>&1; dnf -y makecache --repo wl 2>&1 | tail -1

echo "### cleanup"
systemctl stop wl-rpm-http; dnf -y remove wl-hello >/dev/null 2>&1
for k in $(rpm -qa 'gpg-pubkey*' --qf '%{NAME}-%{VERSION}-%{RELEASE} %{SUMMARY}\n' | grep -i winlab | cut -d' ' -f1); do rpm -e $k; done
rm -rf /etc/yum.repos.d/wl.repo $R $T /var/tmp/wl-gpg; dnf -y clean all >/dev/null 2>&1; echo done
