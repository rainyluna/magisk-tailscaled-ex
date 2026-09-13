#!/system/bin/sh
while grep -q " /system/etc/hosts " /proc/mounts; do
    umount /system/etc/hosts 2>/dev/null || break
done
/data/adb/tailscale/bin/tailscaled --cleanup >/dev/null 2>&1 || true
rm -rf /data/adb/tailscale
SERVICE_DIR="/data/adb/service.d"
if [ -f "$SERVICE_DIR/tailscaled_service.sh" ]; then
    rm -f "$SERVICE_DIR/tailscaled_service.sh"
fi