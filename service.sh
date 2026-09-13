#!/system/bin/sh
# this service later will moved to General Scripts for enabling and disabling tailscaled service when default state is disabled
# wait for boot to complete
while [ "$(getprop sys.boot_completed)" != 1 ]; do
    sleep 1
done

# wait for /dev/tun to be available
I=0
while [ ! -c /dev/tun ] && [ ! -c /dev/net/tun ] && [ "$I" -lt 30 ]; do
    sleep 1
    I=$((I + 1))
done

# ensure /dev/net/tun exists for kernel-side networking
mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    if [ -c /dev/tun ]; then
        ln -sf /dev/tun /dev/net/tun
    else
        mknod /dev/net/tun c 10 200 2>/dev/null || true
        chmod 0666 /dev/net/tun 2>/dev/null || true
    fi
fi

# enable kernel IP forwarding
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1 || true

# ensure boot has actually completed & network is ready
sleep 5
# start service
/data/adb/tailscale/scripts/start.sh

# Wait for tailscaled socket and ensure hosts are mounted before service.sh exits
I=0
while [ ! -S /data/adb/tailscale/tailscaled.sock ] && [ "$I" -lt 15 ]; do
    sleep 1
    I=$((I + 1))
done
[ -x /data/adb/tailscale/scripts/update-hosts.sh ] && /data/adb/tailscale/scripts/update-hosts.sh >> /dev/null 2>&1 || true