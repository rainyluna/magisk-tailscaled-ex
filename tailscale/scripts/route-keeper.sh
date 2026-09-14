#!/system/bin/sh
# Prevent Android App Freezer from suspending route-keeper
if [ -f /sys/fs/cgroup/cgroup.procs ]; then
    echo $$ > /sys/fs/cgroup/cgroup.procs 2>/dev/null || true
fi

DIR=$(dirname "$(realpath "$0")")
[ -f "$DIR/../settings.sh" ] && . "$DIR/../settings.sh"
[ -f "/data/adb/tailscale/settings.sh" ] && . "/data/adb/tailscale/settings.sh"

get_dns_upstream() {
    local upstream="${TS_DNS_UPSTREAM:-100.85.255.48}"
    if [ -f "/data/adb/tailscale/dns_upstream" ]; then
        upstream=$(cat /data/adb/tailscale/dns_upstream | tr -d '[:space:]')
    fi
    case "$upstream" in
        none|off|disable|disabled|"") echo "" ;;
        *) echo "$upstream" ;;
    esac
}

clean_dns_rules() {
    local upstream
    upstream=$(get_dns_upstream)
    [ -z "$upstream" ] && upstream="100.85.255.48"

    while iptables -t nat -D OUTPUT -p udp ! -d "$upstream" --dport 53 -j DNAT --to-destination "$upstream:53" 2>/dev/null; do :; done
    while iptables -t nat -D OUTPUT -p tcp ! -d "$upstream" --dport 53 -j DNAT --to-destination "$upstream:53" 2>/dev/null; do :; done
    while iptables -t nat -D POSTROUTING -o tailscale0 -j MASQUERADE 2>/dev/null; do :; done
}

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

    # Re-assert Tailscale DNS redirection to AdGuard Home if interface is UP
    local dns_target
    dns_target=$(get_dns_upstream)
    if [ -n "$dns_target" ] && ip link show dev tailscale0 2>/dev/null | grep -q "UP"; then
        if ! iptables -t nat -C POSTROUTING -o tailscale0 -j MASQUERADE 2>/dev/null; then
            iptables -t nat -I POSTROUTING -o tailscale0 -j MASQUERADE 2>/dev/null || true
        fi
        if ! iptables -t nat -C OUTPUT -p udp ! -d "$dns_target" --dport 53 -j DNAT --to-destination "$dns_target:53" 2>/dev/null; then
            iptables -t nat -I OUTPUT -p udp ! -d "$dns_target" --dport 53 -j DNAT --to-destination "$dns_target:53" 2>/dev/null || true
        fi
        if ! iptables -t nat -C OUTPUT -p tcp ! -d "$dns_target" --dport 53 -j DNAT --to-destination "$dns_target:53" 2>/dev/null; then
            iptables -t nat -I OUTPUT -p tcp ! -d "$dns_target" --dport 53 -j DNAT --to-destination "$dns_target:53" 2>/dev/null || true
        fi
    else
        clean_dns_rules
    fi
}

case "$1" in
    clean|stop)
        clean_dns_rules
        exit 0
        ;;
esac

trap clean_dns_rules EXIT INT TERM

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
        clean_dns_rules
        kill "$MONITOR_PID" 2>/dev/null || true
        exit 0
    fi
    apply_rules
    sleep 10
done
