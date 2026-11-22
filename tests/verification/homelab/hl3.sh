#!/bin/bash
# Home-lab battery 3: backups with rsync (hard-link snapshots), tar (incremental) and restic (run as root via bash -s)
. /etc/os-release; echo "### $PRETTY_NAME"
if command -v apt-get >/dev/null; then
  apt-get update >/tmp/upd.log 2>&1; DEBIAN_FRONTEND=noninteractive apt-get install -y rsync restic >/tmp/inst.log 2>&1; tail -1 /tmp/inst.log
else
  dnf -y install epel-release >/tmp/inst.log 2>&1; dnf -y install rsync restic >>/tmp/inst.log 2>&1; tail -1 /tmp/inst.log
fi
rsync --version | head -1; restic version; tar --version | head -1
W=/var/tmp/wl-bk; rm -rf $W; mkdir -p $W/data/docs $W/data/photos $W/dest
for i in 1 2 3; do head -c 2000000 /dev/urandom > $W/data/photos/p$i.bin; done
for i in 1 2 3 4 5; do echo "document $i" > $W/data/docs/d$i.txt; done
du -sh --apparent-size $W/data | cut -f1

echo "### 1. rsync snapshots with --link-dest (unchanged files become hard links)"
rsync -a $W/data/ $W/dest/snap1/
echo "changed" >> $W/data/docs/d1.txt
rsync -a --delete --link-dest=$W/dest/snap1 $W/data/ $W/dest/snap2/
echo "--- inode of photos/p1.bin in each snapshot (same inode = stored once)"
stat -c '%i %h links  %n' $W/dest/snap1/photos/p1.bin $W/dest/snap2/photos/p1.bin
echo "--- the changed file is a separate copy"
stat -c '%i %h links  %n' $W/dest/snap1/docs/d1.txt $W/dest/snap2/docs/d1.txt
echo "--- sizes: each looks full, together they cost one copy"
du -sh --apparent-size $W/dest/snap1 $W/dest/snap2 | awk '{print $1, $2}'
du -sh $W/dest | awk '{print $1, "both together"}'
echo "--- delete a file from the live data: older snapshot still has it"
rm $W/data/docs/d5.txt
rsync -a --delete --link-dest=$W/dest/snap2 $W/data/ $W/dest/snap3/
ls $W/dest/snap2/docs | wc -l; ls $W/dest/snap3/docs | wc -l
echo "--- a dry run shows what would change (-n, itemized)"
echo "new" > $W/data/docs/d6.txt
rsync -a -n --delete -i $W/data/ $W/dest/snap3/ | head
echo "--- restore and compare"
rsync -a $W/dest/snap1/ $W/restore1/ 2>/dev/null || { mkdir $W/restore1; rsync -a $W/dest/snap1/ $W/restore1/; }
diff -r $W/restore1 $W/dest/snap1 && echo "restore identical to snap1"
diff -rq $W/restore1 $W/data | head -4

echo "### 2. tar with --listed-incremental"
cd $W
tar --listed-incremental=$W/tar.snar -czf $W/level0.tgz data 2>&1
echo "new file" > data/docs/d7.txt; echo more >> data/docs/d2.txt
tar --listed-incremental=$W/tar.snar -czf $W/level1.tgz data 2>&1
ls -l level0.tgz level1.tgz | awk '{print $5, $9}'
echo "--- level1 holds only the changes"
tar -tzf level1.tgz | grep -v '/$'
echo "--- restore: level 0 first, then level 1, with --listed-incremental=/dev/null"
mkdir -p $W/r2 && tar -xzf level0.tgz -C $W/r2 --listed-incremental=/dev/null && tar -xzf level1.tgz -C $W/r2 --listed-incremental=/dev/null
diff -r $W/r2/data $W/data && echo "restore identical to live data"

echo "### 3. restic (encrypted, deduplicated)"
export RESTIC_REPOSITORY=$W/repo RESTIC_PASSWORD='lab-only-password'
restic init 2>&1 | head -3
restic backup $W/data 2>&1 | grep -E 'Files:|Added|snapshot'
echo "more words" >> $W/data/docs/d3.txt
restic backup $W/data 2>&1 | grep -E 'Files:|Added|snapshot'
restic snapshots 2>&1
echo "--- what changed between the two snapshots"
restic diff $(restic snapshots --json | grep -o '"short_id":"[0-9a-f]*"' | cut -d'"' -f4 | head -2 | paste -sd' ') 2>&1 | grep -E '^[+-M]|Added|Removed|Modified' | head
echo "--- repo size vs data size (deduplication)"
du -sh --apparent-size $W/repo | cut -f1; du -sh --apparent-size $W/data | cut -f1
echo "--- plain text in the repository? (grep for a word we wrote)"
grep -rl "document 1" $W/repo | wc -l
echo "--- check, then restore the latest snapshot and compare"
restic check 2>&1 | tail -2
restic restore latest --target $W/r3 2>&1 | tail -1
diff -r $W/r3$W/data $W/data && echo "restic restore identical"
echo "--- wrong password"
RESTIC_PASSWORD=nope restic snapshots 2>&1 | tail -2
echo "--- damage one pack file, then check"
PK=$(find $W/repo/data -type f -size +1000k | head -1)
printf 'XXXXXXXX' | dd of=$PK bs=1 seek=1000 conv=notrunc 2>/dev/null
restic check 2>&1 | tail -2
echo "--- check --read-data finds it"
restic check --read-data 2>&1 | grep -iE 'error|hash|damaged|failed|Fatal' | head -4
echo "--- retention"
restic forget --keep-last 1 --prune 2>&1 | grep -E 'keep|remove|snapshots' | head -4

echo "### 4. run a backup from a timer-like transient unit"
systemd-run --unit=wl-bk-test --on-active=3s --property=Environment="RESTIC_REPOSITORY=$W/repo2" --property=Environment=RESTIC_PASSWORD=x /bin/sh -c "restic init && restic backup $W/data" 2>&1 | tail -1
sleep 6
journalctl -u wl-bk-test.service --no-pager -o cat | grep -E 'created restic|snapshot|Files:' | head -3
systemctl reset-failed 'wl-bk-test*' 2>/dev/null
rm -rf $W; echo done
