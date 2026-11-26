# Battery for hardware.hardware-concepts. Read-only. Run as root in a lab VM.
export LC_ALL=C
run() { printf '$ %s\n' "$*"; eval "$*" 2>&1; printf '[exit %s]\n' "$?"; }
. /etc/os-release; echo "$PRETTY_NAME"
run 'lscpu | grep -E "^(Architecture|CPU\(s\)|Model name|Thread|Core|Socket|Virtualization|Hypervisor)|BIOS"'
run 'nproc'
run 'free -h'
run 'grep -E "^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree):" /proc/meminfo'
run 'swapon --show'
run 'uptime'
run 'ps -eo pid,rss,comm --sort=-rss | head -5'
run 'lsblk -d -o NAME,ROTA,TYPE,SIZE,MODEL,TRAN'
run 'cat /sys/block/sda/queue/rotational'
run 'command -v dmidecode smartctl lspci lsusb'
run 'dmidecode -t system | grep -E "Manufacturer|Product Name"'
run 'dmidecode -t memory | grep -E "Size|Speed|Locator|Type:" | head -12'
run 'systemd-detect-virt'
run 'lspci | head -8'
run 'cat /proc/mdstat'
run 'journalctl -k -p err --no-pager -n 6 -o cat'
run 'dmesg -T --level=err,warn | tail -5 | cut -c1-160'
run 'df -h /'
echo done
