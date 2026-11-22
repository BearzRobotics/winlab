#!/bin/bash
# Package-repo battery 3: a signed apk (v3) repository, built by hand, served as static files (Chimera; run as root via bash -s)
. /etc/os-release; echo "### $PRETTY_NAME  $(uname -r)"
apk --version; openssl version; python3 --version
W=/var/tmp/wl-apk; R=/srv/wl-apk; rm -rf $W $R; mkdir -p $W $R/main/x86_64 $R/main/noarch; cd $W

echo "### 1. a signing key (RSA; Chimera's own keys are .rsa.pub files)"
openssl genrsa -out wl-repo.rsa 2048 2>&1 | tail -1
openssl rsa -in wl-repo.rsa -pubout -out wl-repo.rsa.pub 2>&1 | tail -1
ls -l wl-repo.rsa wl-repo.rsa.pub | awk '{print $1, $5, $9}'
KEYNAME=winlab-test@lab.test-$(openssl rsa -in wl-repo.rsa -pubout -outform DER 2>/dev/null | sha256sum | cut -c1-8).rsa.pub
mkdir -p $W/keys; cp wl-repo.rsa.pub $W/keys/$KEYNAME; MKNDX_OPTS=""
echo "--- is the real Chimera index also called Packages.adb?"; python3 -c "import urllib.request as u; r=u.urlopen(u.Request('https://repo.chimera-linux.org/current/main/x86_64/Packages.adb',method='HEAD')); print(r.status, r.headers.get('Content-Length'))" 2>&1 | tail -1
echo "key file name: $KEYNAME"

mkpkg() {   # version
  d=$W/pkg-$1; rm -rf $d; mkdir -p $d/usr/bin
  printf '#!/bin/sh\necho "wl-hello %s"\n' "$1" > $d/usr/bin/wl-hello; chmod 755 $d/usr/bin/wl-hello
  apk mkpkg --info name:wl-hello --info version:$1-r0 --info arch:noarch --info description:"test package $1" \
     --info license:MIT --info url:https://lab.test --files $d --sign-key $W/wl-repo.rsa \
     --output $R/main/noarch/wl-hello-$1-r0.apk 2>&1 | tail -2
}
publish() {
  apk --keys-dir $W/keys $MKNDX_OPTS mkndx --sign-key $W/wl-repo.rsa --output $R/main/x86_64/Packages.adb $R/main/noarch/*.apk 2>&1 | tail -2
}

echo "### 2. build and index"
mkpkg 1.0
(cd $R/main && find . -type f | sort | xargs ls -l | awk '{print $5, $9}')
echo "--- apk adbdump of the package"
apk adbdump $R/main/noarch/wl-hello-1.0-r0.apk 2>&1 | head -30
publish
(cd $R/main && find . -type f | sort | xargs ls -l | awk '{print $5, $9}')
echo "--- apk adbdump of the index"
apk adbdump $R/main/x86_64/Packages.adb 2>&1 | head -30

echo "### 3. serve it, and log every request apk makes"
cd $R; nohup python3 -m http.server 8083 --bind 127.0.0.1 >$W/http.log 2>&1 &
SRV=$!; sleep 1
echo "### 4. client: without the key first (untrusted)"
mkdir -p /etc/apk/repositories.d
echo "v3 http://127.0.0.1:8083/main" > /etc/apk/repositories.d/99-wl.list
apk update 2>&1 | tail -4
echo "--- what apk asked the server for"; sed -E 's/^127.0.0.1 - - \[[^]]*\] //' $W/http.log | tail -4
echo "--- install the public key, try again"
cp $W/wl-repo.rsa.pub /etc/apk/keys/$KEYNAME
apk update 2>&1 | tail -3
apk search wl-hello; apk policy wl-hello 2>&1 | head -6
apk add wl-hello 2>&1 | tail -3
echo "--- requests the server saw"; awk -F'"' '/GET/ {print $2, $3}' $W/http.log | tail -6
wl-hello; apk info -v wl-hello

echo "### 5. publish 1.1 and upgrade"
mkpkg 1.1; publish
apk update 2>&1 | tail -2
apk add --upgrade wl-hello 2>&1 | tail -3; wl-hello

echo "### 6. failures a client reports"
echo "--- (a) key removed from /etc/apk/keys"
mv /etc/apk/keys/$KEYNAME $W/key.keep
apk update 2>&1 | tail -3
apk add --no-cache wl-hello 2>&1 | tail -2
mv $W/key.keep /etc/apk/keys/$KEYNAME
echo "--- (b) the index is changed after signing"
cp $R/main/x86_64/Packages.adb $W/Packages.adb.keep
printf 'garbage' >> $R/main/x86_64/Packages.adb
apk update 2>&1 | tail -3
cp $W/Packages.adb.keep $R/main/x86_64/Packages.adb
echo "--- (c) an unsigned package"
d=$W/pkg-unsigned; mkdir -p $d/usr/bin; echo 'echo x' > $d/usr/bin/wl-unsigned; chmod 755 $d/usr/bin/wl-unsigned
apk mkpkg --info name:wl-unsigned --info version:1.0-r0 --info arch:noarch --info description:unsigned --files $d --output $R/main/noarch/wl-unsigned-1.0-r0.apk 2>&1 | tail -1
echo "--- the index tool refuses it"; publish
echo "--- unless told to accept it, then a client refuses it"; MKNDX_OPTS=--allow-untrusted; publish; MKNDX_OPTS=
apk update 2>&1 | tail -2
apk add wl-unsigned 2>&1 | tail -3
echo "--- (d) the same, with --allow-untrusted is only for a local file you inspected"
apk verify $R/main/noarch/wl-unsigned-1.0-r0.apk 2>&1 | tail -2
apk verify $R/main/noarch/wl-hello-1.1-r0.apk 2>&1 | tail -2

echo "### cleanup"
kill $SRV; apk del wl-hello >/dev/null 2>&1
rm -f /etc/apk/repositories.d/99-wl.list /etc/apk/keys/$KEYNAME; rm -rf $W $R
apk update 2>&1 | tail -1; echo done
