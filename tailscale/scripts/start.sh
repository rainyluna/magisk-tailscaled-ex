#!/system/bin/sh
DIR=$(dirname "$(realpath "$0")")
# shellcheck source=../settings.sh
. "$DIR"/../settings.sh

# Ensure /dev/net/tun exists for kernel-side networking
mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    if [ -c /dev/tun ]; then
        ln -sf /dev/tun /dev/net/tun
    elif [ -e /dev/tun ]; then
        ln -sf /dev/tun /dev/net/tun
    else
        mknod /dev/net/tun c 10 200 2>/dev/null || true
        chmod 0666 /dev/net/tun 2>/dev/null || true
    fi
fi
case "$1" in
    postinstall)
      rm -rf $TS_RUN_DIR && mkdir -p $TS_RUN_DIR
      tailscaled.service restart >> "/dev/null" 2>&1 &
      return 0
    ;;
esac
start_service() {
  if [ ! -f "${TS_MOD_DIR}/disable" ]; then
    tailscaled.service start >> "/dev/null" 2>&1
    (sleep 3; [ -x "${DIR}/update-hosts.sh" ] && "${DIR}/update-hosts.sh" >> "/dev/null" 2>&1) &
    pkill -f route-keeper 2>/dev/null || true
    [ -x "${DIR}/route-keeper.sh" ] && nohup "${DIR}/route-keeper.sh" >> "/dev/null" 2>&1 &
  fi
}
start_inotifyd() {
  for PID in $(busybox pidof inotifyd); do
    if grep -q "tailscaled.inotify" "/proc/$PID/cmdline"; then
      kill -9 "$PID"
    fi
  done
  echo "${CURRENT_TIME} [Info]: Starting tailscaled inotify service" > "${TS_RUN_LOG_FILE}"
  inotifyd "tailscaled.inotify" "${TS_MOD_DIR}" >> "/dev/null" 2>&1 &
}

module_version=$(busybox awk -F'=' '!/^ *#/ && /version=/ { print $2 }' "$TS_MOD_PROP" 2>/dev/null)
log Info "Magisk Tailscaled version : ${module_version}."
start_service
start_inotifyd