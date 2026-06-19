Pi 180 boot configuration
=========================

`pi180-config.txt` is a snapshot of `/boot/config.txt` from LivingRoom.

Local change:

- Disable `dtoverlay=w1-gpio` because the host was enumerating bogus `00-*`
  1-Wire devices and the `w1_bus_master1` kernel thread was consuming CPU.

Runtime rollback:

```sh
sudo modprobe w1_gpio
```

Persistent rollback:

Uncomment `dtoverlay=w1-gpio` in `/boot/config.txt`, then reboot.
