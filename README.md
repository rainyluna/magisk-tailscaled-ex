[![anasfanani - Magisk-Tailscaled](https://img.shields.io/static/v1?label=anasfanani&message=Magisk-Tailscaled&color=blue&logo=github)](https://github.com/anasfanani/Magisk-Tailscaled "Go to GitHub repo")
[![Check and Update Tailscale Binary](https://github.com/anasfanani/Magisk-Tailscaled/actions/workflows/update.yml/badge.svg)](https://github.com/anasfanani/Magisk-Tailscaled/actions/workflows/update.yml)
[![Github All Releases](https://img.shields.io/github/downloads/anasfanani/Magisk-Tailscaled/total.svg)]()
[![GitHub release](https://img.shields.io/github/release/anasfanani/Magisk-Tailscaled?include_prereleases=&sort=semver&color=blue)](https://github.com/anasfanani/Magisk-Tailscaled/releases/)
[![issues - Magisk-Tailscaled](https://img.shields.io/github/issues/anasfanani/Magisk-Tailscaled)](https://github.com/anasfanani/Magisk-Tailscaled/issues)
[![Static Badge](https://img.shields.io/badge/Discussion-Telegram-blue?style=flat&logo=telegram&link=t.me%2Fsystembinsh%2F158)](https://t.me/systembinsh/158)

# Magisk Tailscaled Ex (Extended)

[![rainyluna - magisk-tailscaled-ex](https://img.shields.io/static/v1?label=rainyluna&message=magisk-tailscaled-ex&color=blue&logo=github)](https://github.com/rainyluna/magisk-tailscaled-ex "Go to GitHub repo")
[![Based on anasfanani/Magisk-Tailscaled](https://img.shields.io/badge/based%20on-anasfanani%2FMagisk--Tailscaled-lightgrey)](https://github.com/anasfanani/Magisk-Tailscaled)

An enhanced Magisk/KernelSU module for running native Tailscale on rooted Android devices with kernel WireGuard TUN networking, automatic route persistence, systemless `/etc/hosts` peer sync, and transparent AdGuard Home DNS interception.

---

## What is Changed vs. Original (`anasfanani/Magisk-Tailscaled`)?

This fork (`magisk-tailscaled-ex`) addresses the primary real-world pain points of running Tailscale as a background daemon on modern Android:

| Feature | Original Upstream | Magisk Tailscaled Ex |
| :--- | :--- | :--- |
| **Networking Mode** | Userspace networking (`hev-socks5-tunnel`), requiring SOCKS5 proxy configuration | **Native kernel TUN (`-tun=tailscale0`)** using Linux kernel WireGuard. Direct app connectivity with 0 configuration. |
| **Routing Stability** | Rules frequently lost when roaming between Wi-Fi and mobile data | **`route-keeper` daemon** listening to netlink events (`ip monitor`) and heartbeat loop to continuously re-assert Table 52 rules. |
| **MagicDNS / Peer Discovery** | MagicDNS broken (Android apps cannot query `100.100.100.100` via root daemon) | **Systemless `/system/etc/hosts` bind mount** (`update-hosts.sh`) dynamically populating all tailnet peer short names and FQDNs. |
| **DNS Interception & Filtering** | None (DNS queries bypass Tailnet or fail) | **Transparent Port 53 DNAT & MASQUERADE** redirecting all app DNS queries to AdGuard Home (or custom upstream) over Tailscale. |
| **Process Lifecycle** | Can be frozen by Android App Freezer / Doze | Daemon automatically added to root cgroup (`cgroup.procs`) to prevent freeze. |
| **Teardown & Cleanup** | Partial cleanup | Clean teardown of iptables NAT rules, route-keeper daemon, and `/system/etc/hosts` unmount on stop/uninstall. |

---

## Highlights of Enhancements

### 1. Native Kernel WireGuard TUN (`tailscale0`)
* Eliminates the userspace proxy layer (`hev-socks5-tunnel`).
* Automatically checks and initializes `/dev/net/tun` kernel nodes and sets `net.ipv4.ip_forward=1`.
* All Android apps and terminal tools can reach Tailscale IPs directly.

### 2. `route-keeper` Background Daemon
* Android's `netd` periodically rewrites policy routing (`ip rule`), wiping custom routing tables when interfaces toggle (Wi-Fi ↔ LTE/5G).
* `route-keeper` runs in the background, listening to real-time netlink events (`ip monitor route rule link`).
* Instantly re-asserts:
  * Table 52 routing rules (`to 100.64.0.0/10 lookup 52 pref 5210`, `from 100.64.0.0/10 lookup 52 pref 5230`)
  * IPv6 ULA routing (`fd7a:115c:a1e0::/48`)
  * Systemless `/system/etc/hosts` mount
  * Outgoing port 53 DNS redirection rules

### 3. Systemless Host Resolution (`update-hosts.sh`)
* Resolves the "MagicDNS on Android" limitation.
* Runs on service start and can be manually refreshed with `su -c tailscaled.service sync-hosts`.
* Parses `tailscale status --json` with `jq` and writes peer names (e.g. `jellyfin`, `jellyfin.tailnet.ts.net`) into a custom hosts file, bind-mounting it over `/system/etc/hosts` without modifying the read-only `/system` partition.

### 4. Transparent AdGuard Home / Custom DNS Interception
* Intercepts outgoing port 53 (UDP and TCP) DNS traffic from all apps and redirects it to your AdGuard Home instance (default `100.85.255.48:53`) over Tailscale.
* Automatically injects `POSTROUTING MASQUERADE` on `tailscale0` to prevent Android socket source IP mismatches from breaking resolution.
* **Fail-Safe**: If `tailscale0` goes down or Tailscale is stopped, DNS redirection rules are immediately removed to avoid breaking internet connectivity.
* Easily configurable in `settings.sh` (`TS_DNS_UPSTREAM`) or via `/data/adb/tailscale/dns_upstream`.

---

## Requirements

- A basic networking knowledge.
- An Android device with Magisk or KernelSU root installed.
- Kernel TUN device support (`/dev/tun` in the Android kernel).

## Quick Start & Installation

1. Download the latest zip file from the [Releases](https://github.com/anasfanani/Magisk-Tailscaled/releases/latest) page.
2. Install the downloaded zip file using Magisk & reboot your phone.
3. Open the Terminal.
4. Login with `su -c tailscale login`
5. Disable accept-dns `su -c tailscale set --accept-dns=false`
6. Run 'tailscale login' to login to your Tailscale account.
7. Open the URL in a browser to authorize your device.
8. Run 'tailscale ip' to retrieve your Tailscale IP.
9. Alternatively, you can open the [Tailscale Admin Dashboard](https://login.tailscale.com/admin/machines) to manage your devices.

After installation, the Tailscale daemon (`tailscaled`) will run automatically on boot.

## Limitation

- This module only supports `arm` or `arm64` architecture.
- Requires kernel TUN device support (`/dev/tun` in the Android kernel).
- When using MagicDNS, you may need to disable accept-dns (`tailscale set --accept-dns=false`) depending on ROM DNS configuration.

## Usage of this module

This module runs `tailscaled` using native kernel-side networking:

```bash
tailscaled -tun=tailscale0 -no-logs-no-support
```
The daemon creates a native `tailscale0` TUN interface in the Linux kernel using WireGuard. All applications on the device can communicate directly with your Tailscale network without needing a SOCKS5/HTTP proxy.

The state file for tailscaled is stored at `/data/adb/tailscale/tailscaled.state`, socket at `/data/adb/tailscale/tailscaled.sock`, and log output is written to `/data/adb/tailscale/run/tailscaled.log`.

## Available command

- `tailscale`: This command executes tailscale operations.
- `tailscaled`: This command executes tailscaled daemon operations.
- `tailscaled.service`: This command manages the tailscaled service (start, stop, restart, status, logs).
  
## Example of Using Tailscale

### SSH to Termux

You can use Tailscale to connect SSH from Termux on Android to a Windows PC. Here's how:

#### On your Android device:

1. Set up SSHD:

```bash
apt update && apt upgrade
apt install openssh
passwd
```

Enter your password when prompted, for example, `123`.

2. Run ssh daemon with command `sshd`
3. Get your IP with the command `tailscale ip` or check your IP in the [Tailscale Admin Dashboard](https://login.tailscale.com/admin/machines).

#### On your Windows PC:

1. Download & install [Tailscale for Windows](https://tailscale.com/download/windows)
1. Open app & login to the Tailscale.
3. Open the terminal & SSH to your Android IP:

```bash
ssh <root>@<tailscale_ip> -p 8022
```

For example:

```bash
ssh root@100.95.95.95 -p 8022
```

### SSH access to your Android device

You can also enable SSH access to your Android device using [Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh?slug=kb&slug=1193&slug=tailscale-ssh). To do this, advertise SSH on the host with the command `tailscale up --ssh`.

By default, Tailscale's SSH feature may not work on Android because it requires `getent`, which is part of GNU libc, and relies on glibc-specific features like nsswitch.conf.

To overcome this, I've created a mock `getent` and placed it in `tailscale/bin/`. This mock `getent` is used by Tailscale's [userLookupGetent](https://github.com/tailscale/tailscale/blob/5812093d31c8a7f9c5e3a455f0fd20dcc011d8cd/util/osuser/user.go#L121C19-L121C33) function.

After advertising SSH on the host, you can SSH into your Android device using `ssh root@<tailscale_ip>`.

### ADB over Tailscale

You can run ADB over Tailscale. First, you need to enable ADB over TCP/IP. You can do this with the following commands:

```bash
setprop service.adb.tcp.port 5555
stop adbd
start adbd
```

These commands set the ADB daemon to listen on TCP port 5555 and then restart the ADB daemon to apply the change.

After enabling ADB over TCP/IP, you can connect to your Android device from your Windows machine using the `adb connect` command followed by your Tailscale IP and the port number:

```bash
adb connect <tailscale_ip>:5555
```

## Avalilable command

```
USAGE
  tailscale [flags] <subcommand> [command flags]

For help on subcommands, add --help after: "tailscale status --help".

This CLI is still under active development. Commands and flags will
change in the future.

SUBCOMMANDS
  up         Connect to Tailscale, logging in if needed
  down       Disconnect from Tailscale
  set        Change specified preferences
  login      Log in to a Tailscale account
  logout     Disconnect from Tailscale and expire current node key
  switch     Switches to a different Tailscale account
  configure  [ALPHA] Configure the host to enable more Tailscale features
  netcheck   Print an analysis of local network conditions
  ip         Show Tailscale IP addresses
  status     Show state of tailscaled and its connections
  ping       Ping a host at the Tailscale layer, see how it routed
  nc         Connect to a port on a host, connected to stdin/stdout
  ssh        SSH to a Tailscale machine
  funnel     Turn on/off Funnel service
  serve      Serve content and local servers
  version    Print Tailscale version
  web        Run a web server for controlling Tailscale
  file       Send or receive files
  bugreport  Print a shareable identifier to help diagnose issues
  cert       Get TLS certs
  lock       Manage tailnet lock
  licenses   Get open source license information
  exit-node

FLAGS
  --socket string
        path to tailscaled socket (default /var/run/tailscale/tailscaled.sock)
```

For more details about CLI commands, check out the [Tailscale CLI documentation](https://tailscale.com/kb/1080/cli#using-the-cli).

## FAQ & Troubleshooting

Tailscale has manny issues. You can check them out [here](https://github.com/tailscale/tailscale/issues).

### Cannot access other tailnet devices

This module runs `tailscaled` with native kernel-side networking. Traffic is routed directly through the kernel `tailscale0` TUN interface and WireGuard tunnel:

1. Verify that `tailscaled.service` is running:
    ```bash
    su -c 'tailscaled.service status'
    ```
2. Verify that the `tailscale0` kernel interface exists and has an assigned IP:
    ```bash
    su -c 'ip addr show tailscale0'
    ```
3. Check routing rules and table 52:
    ```bash
    su -c 'ip rule show'
    su -c 'ip route show table 52'
    ```
4. Test tailnet ping to a peer:
    ```bash
    su -c 'tailscale ping <peer_tailnet_ip>'
    ```
5. If connections fail, verify `/dev/net/tun` exists and kernel TUN support is active:
    ```bash
    ls -l /dev/net/tun /dev/tun
    ```

### Subnet routes & Exit nodes

Because kernel-side networking is active, subnet routes and exit nodes work via standard Tailscale commands without manual socks5 wrappers:

- **Advertise subnet routes from phone**:
  ```bash
  su -c 'tailscale up --advertise-routes=192.168.1.0/24'
  ```
- **Accept routes from peers**:
  ```bash
  su -c 'tailscale up --accept-routes=true'
  ```
- **Use an exit node**:
  ```bash
  su -c 'tailscale up --exit-node=<exit-node-ip-or-name>'
  ```
- **Advertise as an exit node**:
  ```bash
  su -c 'tailscale up --advertise-exit-node'
  ```

### ipv6

Unfortunately, I'm verry lazy to learn ipv6.

### Headscale 

Check [this](https://github.com/anasfanani/Magisk-Tailscaled/issues/19#issuecomment-2091579177).
Also explore on the issue first, then you can ask trough telegram.


### Other Error & Bugs

You can explore to the issue tab, if there not exists, you can open issue, for help me resolve the problem, you can include fresh log.

1. Restart tailscaled with `tailscaled.service restart`
2. Reproduce what are you doing which has problem.
3. Get log at `/data/adb/tailscale/run/tailscaled.log`

## Notes

This module is confirmed to be supported for KernelSU, as [confirmed by the author of KernelSU](https://github.com/anasfanani/Magisk-Tailscaled/issues/2#issue-2055047162). If you encounter any problems, please let me know.

For more information, check out the links below:

## Links

- [Tailscale Userspace Networking](https://tailscale.com/kb/1112/userspace-networking/)
- [Termux Issue #10166](https://github.com/termux/termux-packages/issues/10166)
- [Tailscale Static Packages](https://pkgs.tailscale.com/stable/#static)
- [Tailscale Knowledge Base](https://tailscale.com/kb)

## Credits

- [Tailscale Inc & AUTHORS](https://github.com/tailscale/tailscale). for the static binaries of tailscale & tailscaled
- [John Wu & Authors](https://github.com/topjohnwu/Magisk). for The Magic Mask for Android
- [heiher & Authors](https://github.com/heiher/hev-socks5-tunnel). for the hev-socks5-tunnel

## Disclaimer

This module is provided as-is, I'm not employee at official tailscale, not a verry genius people which can resolve all your problem.
This module is not affiliated with the official Tailscale. It is a third-party implementation and the author is not responsible for any damage to your device that may occur from its use. Use at your own risk.
Any improvements is required, any PR is verry required, not just welcome.

## License

Released under [BSD 3-Clause License](/LICENSE).