#!/system/bin/sh
TS_DIR="/data/adb/tailscale"
TS_BIN="$TS_DIR/bin/tailscale"
JQ_BIN="$TS_DIR/bin/jq"
HOSTS_FILE="$TS_DIR/hosts"
BASE_HOSTS="$TS_DIR/hosts.base"
SYSTEM_HOSTS="/system/etc/hosts"

if [ "$1" = "unmount" ]; then
    while grep -q " /system/etc/hosts " /proc/mounts; do
        umount /system/etc/hosts 2>/dev/null || break
    done
    exit 0
fi

# Ensure base hosts file exists (preserving localhost & user custom hosts)
if [ ! -f "$BASE_HOSTS" ] || [ ! -s "$BASE_HOSTS" ]; then
    if [ -f "$SYSTEM_HOSTS" ]; then
        sed '/# === TAILSCALE PEERS START ===/,/# === TAILSCALE PEERS END ===/d' "$SYSTEM_HOSTS" | \
            grep -v '^# Tailscale Peers' > "$BASE_HOSTS" 2>/dev/null || true
    fi
    if [ ! -s "$BASE_HOSTS" ]; then
        printf "127.0.0.1\tlocalhost\n::1\tip6-localhost\n" > "$BASE_HOSTS"
    fi
fi

TMP_HOSTS="/data/local/tmp/hosts.tmp.$$"
cat "$BASE_HOSTS" > "$TMP_HOSTS"

if [ -x "$TS_BIN" ] && [ -x "$JQ_BIN" ]; then
    TS_JSON=$(timeout 5 "$TS_BIN" status --json 2>/dev/null || true)
    if [ -n "$TS_JSON" ] && echo "$TS_JSON" | "$JQ_BIN" -e '.Self.TailscaleIPs[0]' >/dev/null 2>&1; then
        echo "" >> "$TMP_HOSTS"
        echo "# === TAILSCALE PEERS START ===" >> "$TMP_HOSTS"
        echo "$TS_JSON" | "$JQ_BIN" -r '
          (.Self, .Peer[]?) |
          (.DNSName // "" | rtrimstr(".")) as $fqdn |
          select($fqdn != "") |
          ($fqdn | split(".")[0]) as $dnsShort |
          (if (.HostName // "" | test("^[a-zA-Z0-9_-]+$")) and .HostName != $dnsShort then .HostName else "" end) as $rawHost |
          .TailscaleIPs[]? as $ip |
          if $rawHost != "" then
            "\($ip)\t\($dnsShort)\t\($fqdn)\t\($rawHost)"
          else
            "\($ip)\t\($dnsShort)\t\($fqdn)"
          end
        ' >> "$TMP_HOSTS" 2>/dev/null || true
        echo "# === TAILSCALE PEERS END ===" >> "$TMP_HOSTS"
    fi
fi

# Write in-place so existing bind mount sees changes without needing remount
if [ -f "$HOSTS_FILE" ]; then
    cat "$TMP_HOSTS" > "$HOSTS_FILE"
else
    cp -f "$TMP_HOSTS" "$HOSTS_FILE"
fi
rm -f "$TMP_HOSTS"

# Ensure readable by all apps and processes under Android SELinux
chmod 0644 "$HOSTS_FILE"
chcon u:object_r:system_file:s0 "$HOSTS_FILE" 2>/dev/null || true

# Systemless bind-mount (strictly read-only /system, no filesystem remount)
if ! grep -q " /system/etc/hosts " /proc/mounts; then
    mount -o bind "$HOSTS_FILE" "$SYSTEM_HOSTS" 2>/dev/null || true
fi
