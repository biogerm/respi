# vpngateway recovery watchdog

These files mirror the recovery watchdog deployed on the `vpngateway` host.
Site-specific addresses and service names belong in the untracked configuration
file shown by `openvpn-uk-route-watchdog.default.example`.

The watchdog runs once per minute. It checks the local Ethernet carrier,
interface state, expected IPv4 address, default route, OpenVPN service state,
and the route to the OpenVPN remote endpoint. It does not actively probe other
hosts.

For a local network failure it:

1. saves a persistent diagnostic trace;
2. resets `eth0` and `dhcpcd.service`, then waits up to 45 seconds;
3. requests one system reboot if the network is still unhealthy;
4. suppresses further watchdog reboots if the next boot is also unhealthy;
5. retries logical network recovery every 10 minutes, while physical-link
   failures are only recorded every 30 minutes.

Persistent traces are written to:

```text
/var/log/openvpn-uk-route-watchdog-trace.log
```

The script rotates the trace at 5 MiB and retains three rotated files. Runtime
state is stored under `/var/lib/openvpn-uk-route-watchdog/` and is not part of
the repository.

## Installed paths

```text
/usr/local/sbin/openvpn-uk-route-watchdog
/etc/default/openvpn-uk-route-watchdog
/etc/systemd/system/openvpn-uk-route-watchdog.service
/etc/systemd/system/openvpn-uk-route-watchdog.timer
```

Copy the example config outside the repository and replace every placeholder
with the deployment values. Keep the resulting file readable only by root:

```sh
sudo install -o root -g root -m 0600 \
  openvpn-uk-route-watchdog.default.example \
  /etc/default/openvpn-uk-route-watchdog
```

After installing the script, config, and systemd units, reload systemd and
enable the timer:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now openvpn-uk-route-watchdog.timer
```

A trace can be captured without changing network state:

```sh
sudo /usr/local/sbin/openvpn-uk-route-watchdog --trace-only
```
