#!/bin/bash
# Package-repo battery 4: hosting a repository: nginx, headers, publish order, atomic swap, mirroring (Ubuntu; run as root via bash -s)
. /etc/os-release; echo "### $PRETTY_NAME"
apt-get update >/tmp/upd.log 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y nginx dpkg-dev apt-utils gnupg rsync >/tmp/inst.log 2>&1; tail -1 /tmp/inst.log
nginx -v 2>&1
export GNUPGHOME=/var/tmp/wl-gpg; rm -rf $GNUPGHOME /var/tmp/wl-pkg /srv/wl-hosting; mkdir -p $GNUPGHOME /srv/wl-hosting; chmod 700 $GNUPGHOME
gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key "WinLab Test Repo <repo@lab.test>" ed25519 sign never >/dev/null 2>&1
mkpkg() { # repo-root version
  d=/var/tmp/wl-pkg/h_$2; rm -rf $d; mkdir -p $d/DEBIAN $d/usr/bin $1/pool/main/w/wl-hello
  printf '#!/bin/sh\necho "wl-hello %s"\n' "$2" > $d/usr/bin/wl-hello; chmod 755 $d/usr/bin/wl-hello
  printf 'Package: wl-hello\nVersion: %s\nArchitecture: all\nMaintainer: WinLab Test <repo@lab.test>\nDescription: test %s\n' "$2" "$2" > $d/DEBIAN/control
  dpkg-deb --root-owner-group --build $d $1/pool/main/w/wl-hello/ >/dev/null
}
index() { # repo-root
  ( cd $1; mkdir -p dists/stable/main/binary-amd64
    dpkg-scanpackages --arch all pool 2>/dev/null > dists/stable/main/binary-amd64/Packages; gzip -9fk dists/stable/main/binary-amd64/Packages
    apt-ftparchive -o APT::FTPArchive::Release::Suite=stable -o APT::FTPArchive::Release::Codename=stable -o APT::FTPArchive::Release::Architectures=amd64 -o APT::FTPArchive::Release::Components=main release dists/stable > dists/stable/Release
    gpg --batch --yes --pinentry-mode loopback --passphrase '' -abs -o dists/stable/Release.gpg dists/stable/Release
    gpg --batch --yes --pinentry-mode loopback --passphrase '' --clearsign -o dists/stable/InRelease dists/stable/Release ) 2>/dev/null
}
H=/srv/wl-hosting
mkpkg $H/r1 1.0; index $H/r1; gpg --export > $H/wl-repo.gpg
ln -sfn r1 $H/current.new; mv -T $H/current.new $H/current
echo "### 1. nginx serving the 'current' symlink"
cat > /etc/nginx/conf.d/wl-repo.conf <<'EOF'
server {
    listen 127.0.0.1:8090;
    root /srv/wl-hosting/current;
    autoindex on;
    location ~ \.(deb|gz)$ { add_header Cache-Control "public, max-age=3600"; }
    location /dists/ { add_header Cache-Control "no-cache"; }
}
EOF
nginx -t 2>&1 | tail -2
systemctl restart nginx; sleep 1; systemctl is-active nginx
echo "--- headers of an index file and of a package"
curl -sI http://127.0.0.1:8090/dists/stable/InRelease | grep -iE '^(HTTP|Content-Length|Last-Modified|ETag|Cache-Control|Accept-Ranges|Server)' | sed 's/\r//'
curl -sI http://127.0.0.1:8090/pool/main/w/wl-hello/wl-hello_1.0_all.deb | grep -iE '^(HTTP|Content-Length|Cache-Control|ETag)' | sed 's/\r//'
echo "--- conditional request (304 = no body sent)"
ET=$(curl -sI http://127.0.0.1:8090/dists/stable/InRelease | grep -i '^etag' | cut -d' ' -f2 | tr -d '\r')
curl -s -o /dev/null -w 'If-None-Match: %{http_code}\n' -H "If-None-Match: $ET" http://127.0.0.1:8090/dists/stable/InRelease
echo "--- range request (resume a download)"
curl -s -o /dev/null -w 'Range: %{http_code} %{size_download} bytes\n' -r 0-99 http://127.0.0.1:8090/pool/main/w/wl-hello/wl-hello_1.0_all.deb
echo "--- directory listing is on; and a file outside the root is not reachable"
curl -s http://127.0.0.1:8090/ | grep -oE 'href="[^"]*"' | head -4
curl -s -o /dev/null -w 'path traversal: %{http_code}\n' --path-as-is http://127.0.0.1:8090/../../etc/passwd

echo "### 2. a client against nginx"
mkdir -p /etc/apt/keyrings; cp $H/wl-repo.gpg /etc/apt/keyrings/wl-repo.gpg
printf 'Types: deb\nURIs: http://127.0.0.1:8090\nSuites: stable\nComponents: main\nSigned-By: /etc/apt/keyrings/wl-repo.gpg\n' > /etc/apt/sources.list.d/wl-hosting.sources
apt-get update 2>&1 | grep -E '8090|Err'
apt-cache policy wl-hello | grep -E 'Candidate'

echo "### 3. the wrong publish order: index first, package file later"
mkpkg $H/r2.tmp 1.1; index $H/r2.tmp
# r2 = copy of r1 + new index, but the package file is missing yet
cp -a $H/r1 $H/r2; cp -a $H/r2.tmp/dists $H/r2/; mkpkg $H/r2.tmp 1.1 >/dev/null
rm -f $H/r2/pool/main/w/wl-hello/wl-hello_1.1_all.deb
ln -sfn r2 $H/current.new; mv -T $H/current.new $H/current
apt-get update 2>&1 | grep -E '8090|Err'
apt-cache policy wl-hello | grep -E 'Candidate'
apt-get install -y wl-hello 2>&1 | grep -E 'E:|Err|404' | cut -c1-140
echo "--- now the file arrives, the same client works"
cp $H/r2.tmp/pool/main/w/wl-hello/wl-hello_1.1_all.deb $H/r2/pool/main/w/wl-hello/
apt-get install -y wl-hello 2>&1 | grep -E 'Setting up|E:'; wl-hello

echo "### 4. a mirror with rsync (what you would do to copy it to a second server)"
mkdir -p /srv/wl-mirror
rsync -a --delete $H/r2/ /srv/wl-mirror/
echo "--- second run transfers nothing (itemized output is empty)"
rsync -a --delete -i $H/r2/ /srv/wl-mirror/ | wc -l
echo "--- with --delay-updates the new files appear together at the end"
mkpkg $H/r2 1.2; index $H/r2
rsync -a --delete --delay-updates -v $H/r2/ /srv/wl-mirror/ 2>&1 | grep -vE '^$|^sending|^sent|^total' | head -8
diff -r $H/r2 /srv/wl-mirror && echo "mirror identical"

echo "### 5. size of a repository on disk"
du -sh --apparent-size $H/r2/pool | cut -f1; find $H/r2 -type f | wc -l

echo "### cleanup"
systemctl stop nginx; rm -f /etc/nginx/conf.d/wl-repo.conf /etc/apt/sources.list.d/wl-hosting.sources /etc/apt/keyrings/wl-repo.gpg
apt-get remove -y wl-hello >/dev/null 2>&1; rm -rf $H /srv/wl-mirror $GNUPGHOME /var/tmp/wl-pkg; echo done
