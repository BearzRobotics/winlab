# Battery for linux.containers-podman. RUN ONLY IN A THROWAWAY VM as root, started from the
# alma-container-service-fails lab (Podman and the almalinux:9 image are already there). Makes only its
# own containers and units (names start wl-) and removes them. Does not touch the lab's own service.
export LC_ALL=C
say() { printf '\n=== %s\n' "$*"; }
run() { printf '$ %s\n' "$*"; eval "$*" 2>&1; printf '[exit %s]\n' "$?"; }
IMG=quay.io/almalinux/almalinux:9
. /etc/os-release; echo "$PRETTY_NAME   $(podman --version)"
run 'podman images'

say 'same kernel, different files'
run 'uname -r'
run "podman run --rm $IMG uname -r"
run "podman run --rm $IMG head -2 /etc/os-release"

say 'a container is a process on the host'
run "podman run -d --name wl-demo $IMG sleep 300"
run 'podman ps'
run 'ps -eo pid,user,args | grep "[s]leep 300"'
run "podman exec wl-demo ps -eo pid,args"
run "podman exec wl-demo sh -c 'command -v ps || echo no ps in this image; cat /proc/1/cmdline | tr \"\\0\" \" \"; echo'"

say 'writes are lost with the container'
run "podman exec wl-demo sh -c 'echo important > /root/note.txt; cat /root/note.txt'"
run 'podman rm -f wl-demo'
run "podman run --name wl-demo $IMG cat /root/note.txt"
run 'podman rm wl-demo'

say 'exited containers and exit codes'
run "podman run --name wl-ok $IMG echo hello"
run "podman run --name wl-false $IMG false"
run "podman run --name wl-typo $IMG nosuchprogram"
run 'podman ps'
run 'podman ps -a --filter name=wl- --format "table {{.Names}}\t{{.Status}}\t{{.Command}}"'
run 'podman logs wl-ok'
run 'podman inspect wl-typo --format "{{.State.Status}} exit={{.State.ExitCode}} error={{.State.Error}}"'
run 'podman rm wl-ok wl-false wl-typo'

say 'a published port'
run "podman run --rm $IMG sh -c 'command -v python3'"
run "podman run -d --name wl-web -p 8080:8000 $IMG python3 -m http.server 8000"
sleep 3
run 'podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
run 'curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/'
run 'curl -sS -o /dev/null http://127.0.0.1:8000/'
run 'podman port wl-web'
run 'ss -ltnp | grep 8080'
run "podman run -d --name wl-web2 -p 8080:8000 $IMG python3 -m http.server 8000"
run 'podman ps -a --filter name=wl-web --format "table {{.Names}}\t{{.Status}}"'
sleep 1
run 'podman logs --tail 3 wl-web'
run 'podman rm -f wl-web wl-web2'

say 'bind mounts and SELinux'
run 'getenforce'
mkdir -p /srv/wl-data && echo 'from the host' > /srv/wl-data/file.txt
run 'ls -lZ /srv/wl-data'
run "podman run --rm -v /srv/wl-data:/data $IMG cat /data/file.txt"
run "podman run --rm -v /srv/wl-data:/data $IMG ls -l /data"
run 'ausearch --input-logs -m avc -ts recent 2>/dev/null | grep -c avc'
run "podman run --rm -v /srv/wl-data:/data:Z $IMG cat /data/file.txt"
run 'ls -lZ /srv/wl-data'
run "podman run --rm -v /srv/wl-data:/data:Z $IMG sh -c 'echo from the container >> /data/file.txt'"
run 'cat /srv/wl-data/file.txt'
run "podman run --rm -v /srv/wl-nope:/data:Z $IMG true"

say 'named volume'
run 'podman volume create wl-vol'
run "podman run --rm -v wl-vol:/data $IMG sh -c 'echo kept > /data/k'"
run "podman run --rm -v wl-vol:/data $IMG cat /data/k"
run 'podman volume inspect wl-vol --format "{{.Mountpoint}}"'
run 'podman volume rm wl-vol'

say 'quadlet: a good unit'
q=/etc/containers/systemd/wl-quad.container
printf '[Unit]\nDescription=wl demo\n\n[Container]\nImage=%s\nContainerName=wl-quad\nExec=sleep infinity\n\n[Service]\nRestart=on-failure\n\n[Install]\nWantedBy=multi-user.target\n' "$IMG" > $q
run 'systemctl daemon-reload'
run 'systemctl is-active wl-quad.service'
run 'systemctl start wl-quad.service'
run 'systemctl is-active wl-quad.service'
run 'systemctl status wl-quad.service --no-pager | head -5'
run 'systemctl cat wl-quad.service | grep -E "^# /|^ExecStart="  | cut -c1-200'
run 'systemctl enable wl-quad.service'
run 'systemctl is-enabled wl-quad.service'
run 'ls /run/systemd/generator/multi-user.target.wants/ | grep wl-'
run 'systemctl stop wl-quad.service'
run 'podman ps -a --filter name=wl-quad'

say 'quadlet: image that cannot be found'
sed -i 's|^Image=.*|Image=localhost/wl-nope:1|' $q
run 'systemctl daemon-reload'
run 'systemctl start wl-quad.service'
sleep 3
run 'systemctl status wl-quad.service --no-pager | head -8'
run 'journalctl -u wl-quad.service --no-pager -n 12 -o cat'
run 'podman ps -a --filter name=wl-quad'
run 'systemctl stop wl-quad.service; systemctl reset-failed wl-quad.service'

say 'quadlet: misspelled key'
sed -i "s|^Image=.*|Image=$IMG|; s|^ContainerName=|ContainerNme=|" $q
run 'systemctl daemon-reload'
run 'systemctl start wl-quad.service'
run '/usr/libexec/podman/quadlet -dryrun 2>&1 | grep -i -E "wl-quad|unsupported|converting" | cut -c1-200'
run 'journalctl -b --no-pager -o cat | grep -i "quadlet" | grep -i "wl-quad" | tail -3 | cut -c1-250'
rm -f $q; systemctl daemon-reload
run 'systemctl start wl-quad.service'

say 'rootless, as labadmin'
podman save -q -o /tmp/wl-img.tar $IMG && chmod 644 /tmp/wl-img.tar
U='runuser -u labadmin -- env HOME=/home/labadmin XDG_RUNTIME_DIR=/run/user/$(id -u labadmin) sh -c'
cd /tmp
run "$U 'cd /tmp; podman images'"
run "$U 'cd /tmp; podman load -q -i /tmp/wl-img.tar'"
run "$U 'cd /tmp; podman run -d --name wl-rootless $IMG sleep 200'"
run "$U 'cd /tmp; podman exec wl-rootless id'"
run 'ps -eo user,args | grep "[s]leep 200"'
run "$U 'cd /tmp; podman unshare cat /proc/self/uid_map'"
run "$U 'cd /tmp; podman ps --format \"{{.Names}}\"'"
run 'podman ps -a --filter name=wl-rootless --format "{{.Names}}"'
run "$U 'cd /tmp; podman run --rm -p 80:8000 $IMG true'"
run "$U 'cd /tmp; podman rm -f wl-rootless; podman rmi $IMG'"

say 'build'
mkdir -p /root/wl-build && cd /root/wl-build
echo 'hello from my image' > message.txt
printf 'FROM %s\nCOPY message.txt /srv/message.txt\nRUN date > /srv/built.txt\nCMD ["cat", "/srv/message.txt"]\n' "$IMG" > Containerfile
run 'podman build --pull=never -t wl-hello .'
run 'podman run --rm wl-hello'
run 'podman build --pull=never -t wl-hello .'
run 'podman images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"'
run 'podman history wl-hello --format "table {{.Size}}\t{{.CreatedBy}}" | cut -c1-110'
run 'podman rmi wl-hello'
cd /; rm -rf /root/wl-build /srv/wl-data /tmp/wl-img.tar
run 'podman ps -a --filter name=wl- --format "{{.Names}}"'
say done
