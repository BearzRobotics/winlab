#!/bin/bash
# Package-repo battery 4b: nginx location precedence and cache headers (Ubuntu; run as root via bash -s)
H=/srv/wl-h2; rm -rf $H; mkdir -p $H/dists/stable/main/binary-amd64 $H/pool/main/w/wl-hello
echo release > $H/dists/stable/Release; echo inrelease > $H/dists/stable/InRelease
echo pk | gzip > $H/dists/stable/main/binary-amd64/Packages.gz; echo deb > $H/pool/main/w/wl-hello/x_1.0_all.deb
cat > /etc/nginx/conf.d/wl-repo2.conf <<'EOF'
server {
    listen 127.0.0.1:8091;
    root /srv/wl-h2;
    location ~ \.(deb|gz)$ { add_header Cache-Control "public, max-age=3600"; }
    location /dists/ { add_header Cache-Control "no-cache"; }
}
EOF
nginx -t 2>&1 | tail -1; systemctl restart nginx; sleep 1
echo "--- first config (regex location + prefix location)"
for f in dists/stable/InRelease dists/stable/main/binary-amd64/Packages.gz pool/main/w/wl-hello/x_1.0_all.deb; do printf '%-52s ' $f; curl -sI http://127.0.0.1:8091/$f | grep -i '^cache-control' | tr -d '\r'; echo; done
cat > /etc/nginx/conf.d/wl-repo2.conf <<'EOF'
server {
    listen 127.0.0.1:8091;
    root /srv/wl-h2;
    location ^~ /dists/ { add_header Cache-Control "no-cache"; }
    location ~ \.(deb)$ { add_header Cache-Control "public, max-age=31536000, immutable"; }
}
EOF
nginx -t 2>&1 | tail -1; systemctl reload nginx; sleep 1
echo "--- second config (^~ prefix wins over the regex)"
for f in dists/stable/InRelease dists/stable/main/binary-amd64/Packages.gz pool/main/w/wl-hello/x_1.0_all.deb; do printf '%-52s ' $f; curl -sI http://127.0.0.1:8091/$f | grep -i '^cache-control' | tr -d '\r'; echo; done
systemctl stop nginx; rm -f /etc/nginx/conf.d/wl-repo2.conf; rm -rf $H; echo done
