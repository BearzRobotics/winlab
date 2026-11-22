#!/bin/bash
# Package-repo battery 9: the apk repository health check, healthy and broken five ways (Chimera; run as root via bash -s). CHECK is substituted by the driver.
. /etc/os-release; echo "### $PRETTY_NAME  $(apk --version | head -1)"
apk add curl >/tmp/inst.log 2>&1; tail -1 /tmp/inst.log; curl --version | head -1 | cut -d' ' -f1-2
cat > /usr/local/bin/wl-apkcheck.sh <<'WLEOF'
@@CHECK@@
WLEOF
chmod 755 /usr/local/bin/wl-apkcheck.sh
W=/var/tmp/wl-apk; R=/srv/wl-apk; rm -rf $W $R; mkdir -p $W/keys $R/main/x86_64 $R/main/noarch; cd $W
openssl genrsa -out k.rsa 2048 2>/dev/null; openssl rsa -in k.rsa -pubout -out k.rsa.pub 2>/dev/null
KN=winlab-test@lab.test-$(openssl rsa -in k.rsa -pubout -outform DER 2>/dev/null | sha256sum | cut -c1-8).rsa.pub; cp k.rsa.pub keys/$KN
mkdir -p nokeys
mkpkg() { d=$W/p$1; mkdir -p $d/usr/bin; echo "$1" > $d/usr/bin/wl-hello
  apk mkpkg --info name:wl-hello --info version:$1-r0 --info arch:noarch --info description:t --info license:MIT --info url:https://lab.test --files $d --sign-key k.rsa --output $R/main/noarch/wl-hello-$1-r0.apk >/dev/null 2>&1; }
publish() { apk --keys-dir $W/keys mkndx $MK --sign-key k.rsa --output $R/main/x86_64/Packages.adb $R/main/noarch/*.apk 2>&1 | tail -1; }
mkpkg 1.0; mkpkg 1.1; MK=; publish
cd $R; nohup python3 -m http.server 8094 --bind 127.0.0.1 >/dev/null 2>&1 & SRV=$!; sleep 1; cd $W
C="wl-apkcheck.sh http://127.0.0.1:8094/main x86_64 $W/keys"
run() { echo "\$ $*"; "$@"; echo "exit status $?"; }

echo "### 1. healthy"
run $C
echo "### 2. healthy, deep (download and verify every package)"
WL_DEEP=1 run $C
echo "### 3. a package file is missing"
mv $R/main/noarch/wl-hello-1.1-r0.apk $W/keep.apk
run $C
echo "### 4. a package file is the wrong size (truncated upload)"
head -c 300 $W/keep.apk > $R/main/noarch/wl-hello-1.1-r0.apk
run $C
cp $W/keep.apk $R/main/noarch/wl-hello-1.1-r0.apk
echo "### 5. the index was changed after signing"
cp $R/main/x86_64/Packages.adb $W/idx.keep; printf garbage >> $R/main/x86_64/Packages.adb
run $C
cp $W/idx.keep $R/main/x86_64/Packages.adb
echo "### 6. the checker has the wrong keys"
run wl-apkcheck.sh http://127.0.0.1:8094/main x86_64 $W/nokeys
echo "### 7. an unsigned package inside a signed index: size check alone, then deep"
d=$W/pu; mkdir -p $d/usr/bin; echo x > $d/usr/bin/wl-unsigned
apk mkpkg --info name:wl-unsigned --info version:1-r0 --info arch:noarch --info description:t --files $d --output $R/main/noarch/wl-unsigned-1-r0.apk >/dev/null 2>&1
MK=--allow-untrusted; publish; MK=
run $C
WL_DEEP=1 run $C
echo "### 8. index missing, and usage errors"
rm $R/main/x86_64/Packages.adb; run $C
run wl-apkcheck.sh http://127.0.0.1:8094/main x86_64
run wl-apkcheck.sh http://127.0.0.1:8094/main x86_64 /nonexistent
kill $SRV; apk del curl >/dev/null 2>&1; rm -rf $W $R /usr/local/bin/wl-apkcheck.sh; echo done
