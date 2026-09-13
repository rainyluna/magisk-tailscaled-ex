#!/system/bin/sh
# Prevent Android App Freezer from suspending route-keeper
if [ -f /sys/fs/cgroup/cgroup.procs ]; then
    echo $$ > /sys/fs/cgroup/cgroup.procs 2>/dev/null || true
fi

apply_rules() {
    # Re-assert Tailscale kernel routing rules (table 52)
    if ! ip rule show | grep -q "to 100.64.0.0/10.*lookup 52"; then
        ip rule add to 100.64.0.0/10 lookup 52 pref 5210 2>/dev/null || true
    fi
    if ! ip rule show | grep -q "from 100.64.0.0/10.*lookup 52"; then
        ip rule add from 100.64.0.0/10 lookup 52 pref 5230 2>/dev/null || true
    fi
    if ! ip -6 rule show | grep -q "to fd7a:115c:a1e0::/48.*lookup 52"; then
        ip -6 rule add to fd7a:115c:a1e0::/48 lookup 52 pref 5210 2>/dev/null || true
    fi
    if ! ip -6 rule show | grep -q "from fd7a:115c:a1e0::/48.*lookup 52"; then
        ip -6 rule add from fd7a:115c:a1e0::/48 lookup 52 pref 5230 2>/dev/null || true
    fi

    # Re-assert systemless /system/etc/hosts bind mount
    if ! grep -q " /system/etc/hosts " /proc/mounts; then
        if [ -f "/data/adb/tailscale/hosts" ]; then
            chmod 0644 /data/adb/tailscale/hosts
            chcon u:object_r:system_file:s0 /data/adb/tailscale/hosts 2>/dev/null || true
            mount -o bind /data/adb/tailscale/hosts /system/etc/hosts 2>/dev/null || true
        fi
    fi
}

apply_rules

# Real-time event listener via netlink
(
    while true; do
        ip monitor route rule link 2>/dev/null | while read -r _; do
            apply_rules
        done
        sleep 5
    done
) &
MONITOR_PID=$!

# Heartbeat loop
while true; do
    if ! pidof tailscaled >/dev/null 2>&1; then
        kill "$MONITOR_PID" 2>/dev/null || true
        exit 0
    fi
    apply_rules
    sleep 10
done
