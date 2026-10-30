# benext: real demo (ZFS-root, OpenZFS master 1547ff6, real reboots)

VM: `hk2`, `~/secure/vmware/openzfs-ci/hawkeye-hack/hk2/hk2.vmx` (linked clone of hk1; base VM untouched)
IP: `172.16.176.238`  Root: `zroot/ROOT/<BE>` on ZFS  Kernel module: `openzfs.ko` (zfs-kmod-2.4.99-1.1424.g1547ff6bc)
Open in GUI: `vmware ~/secure/vmware/openzfs-ci/hawkeye-hack/hk2/hk2.vmx &`, or File > Open in Workstation.
Serial console log (on laptop): `~/secure/vmware/openzfs-ci/hawkeye-hack/hk2/serial.log`

Nothing is simulated. No shims and no fake reboots. Health check: `/usr/local/etc/benext.d/10-sshd` (sshd must be running).
`demo-break-be BE` really breaks a BE by setting `sshd_enable=NO` in it (via sysrc). It refuses the protected BE.

## Reset (laptop, one command)
    ~/hkx/demo-real-reset        # reverts to snapshot real-start, starts with GUI, verifies booted=good, nothing protected

## Script (as root on hk2: `ssh root@172.16.176.238`)
    benext status
    bectl list
    benext protect protected          # 1. protect

    benext destroy protected          # 2. all refused
    benext rename protected x
    benext mount-rw protected /mnt
    benext try protected
    benext protect good
    demo-break-be protected
    zfs destroy -nv zroot/ROOT/protected   # raw ZFS: NOT blocked (dry run only, -n)
    bectl list                        #    protected still there

    demo-break-be new                 # 3. break a trial BE
    benext try new
    shutdown -r now                   # REBOOT: boots new, check fails, auto-reboots into good
    benext status                     #    booted=good result=failed

    demo-break-be good                # 4. kill the active BE
    shutdown -r now                   # REBOOT: boots good, check fails, auto-reboots into protected
    benext status                     #    booted=protected result=fallback-protected
    bectl destroy protected           #    refused (it's booted)
    bectl list

On the laptop, watch the reboots live with `tail -f ~/secure/vmware/openzfs-ci/hawkeye-hack/hk2/serial.log | grep -a -e benext -e 'mount root'`.

## Honest limits
- Raw `bectl destroy protected` / `zfs destroy zroot/ROOT/protected` are **not** blocked while protected isn't booted. Protection is enforced by `benext` and `demo-break-be`, not by ZFS. The demo uses `zfs destroy -n` (a dry run) so the BE survives. Once protected is booted, bectl refuses to destroy it because it's the active BE.
- The kernel module is OpenZFS master (1547ff6). `/sbin/zfs`, `bectl` and libbe are the base 16-CURRENT userland. The master userland is in `/usr/local/sbin`.
- The kernel is the stock GENERIC snapshot with WITNESS, so the serial log shows OpenZFS lock-order-reversal warnings. These are not panics.

## Captured output (validation run 2 after reset; run 1 was identical apart from timestamps and pids)
```
root@zfs16:~ # benext status
booted=good
bootfs=good
protected=-
lastgood=-
trial=-
armed=-
result=-
booted_kernel=FreeBSD_16.0-CURRENT_#0_main-n290352-61c70dc16a79:_Tue_Oct_27_10:57:16_UTC_2026_____root@releng3.nyi.freebsd.org:/usr/obj/usr/src/amd64.amd64/sys/GENERIC
root@zfs16:~ # bectl list
BE        Active Mountpoint Space Created
good      NR     /          2.51G 2026-10-30 23:40
new       -      -          1K    2026-10-30 23:41
protected -      -          1K    2026-10-30 23:41
root@zfs16:~ # benext protect protected
benext 1697 - - protected BE is now protected
root@zfs16:~ # benext status
booted=good
bootfs=good
protected=protected
lastgood=-
trial=-
armed=-
result=-
booted_kernel=FreeBSD_16.0-CURRENT_#0_main-n290352-61c70dc16a79:_Tue_Oct_27_10:57:16_UTC_2026_____root@releng3.nyi.freebsd.org:/usr/obj/usr/src/amd64.amd64/sys/GENERIC
root@zfs16:~ # benext destroy protected
benext: protected is the protected BE: refusing to destroy it
root@zfs16:~ # benext rename protected x
benext: protected is the protected BE: refusing to rename it
root@zfs16:~ # benext mount-rw protected /mnt
benext: protected is the protected BE: refusing to mount read-write it
root@zfs16:~ # benext try protected
benext: protected is the protected BE: refusing to try it
root@zfs16:~ # benext protect good
benext: protected is already protected; only one protected BE is allowed
root@zfs16:~ # demo-break-be protected
demo-break-be: protected is the protected BE: refusing
root@zfs16:~ # zfs destroy -nv zroot/ROOT/protected
would destroy zroot/ROOT/protected
root@zfs16:~ # bectl list
BE        Active Mountpoint Space Created
good      NR     /          2.51G 2026-10-30 23:40
new       -      -          1K    2026-10-30 23:41
protected -      -          1K    2026-10-30 23:41
root@zfs16:~ # demo-break-be new
sshd_enable: YES -> NO
killed new: sshd off at next boot
root@zfs16:~ # benext try new
benext 2120 - - one-shot trial of new armed; fallback good
root@zfs16:~ # shutdown -r now      <-- VM REALLY REBOOTS
shutdown: [pid 2125]
Shutdown NOW!
Shutdown NOW!

System shutdown time has arrived
--- serial console during reboot (benext + boot lines) ---
Uptime: 20s
Trying to mount root from zfs:zroot/ROOT/new []...
benext: /usr/local/etc/cloudbsd/benext/config.json OK
benext 1939 - - health check failed: /usr/local/etc/benext.d/10-sshd
benext 1951 - - boot of new unhealthy: rebooting to fallback
Shutdown NOW!
Uptime: 21s
Trying to mount root from zfs:zroot/ROOT/good []...
benext 228 - - armed one-shot fallback to protected BE protected
benext: /usr/local/etc/cloudbsd/benext/config.json OK
login: 
--- back up: booted=good ---
root@zfs16:~ # benext status
booted=good
bootfs=good
protected=protected
lastgood=good
trial=-
armed=-
result=failed
booted_kernel=FreeBSD_16.0-CURRENT_#0_main-n290352-61c70dc16a79:_Tue_Oct_27_10:57:16_UTC_2026_____root@releng3.nyi.freebsd.org:/usr/obj/usr/src/amd64.amd64/sys/GENERIC
root@zfs16:~ # demo-break-be good
sshd_enable: YES -> NO
killed good (active): sshd off at next boot
root@zfs16:~ # shutdown -r now      <-- VM REALLY REBOOTS
shutdown: [pid 1800]
Shutdown NOW!
Shutdown NOW!

System shutdown time has arrived
--- serial console during reboot (benext + boot lines) ---
login: Stopping sshd.
Uptime: 14s
Trying to mount root from zfs:zroot/ROOT/good []...
benext 228 - - armed one-shot fallback to protected BE protected
benext: /usr/local/etc/cloudbsd/benext/config.json OK
benext 1947 - - health check failed: /usr/local/etc/benext.d/10-sshd
benext 1955 - - boot of good unhealthy: rebooting to fallback
Shutdown NOW!
Uptime: 21s
Trying to mount root from zfs:zroot/ROOT/protected []...
benext 228 - - BOOTED THE PROTECTED BE protected: the trial and last good BE both failed
benext: /usr/local/etc/cloudbsd/benext/config.json OK
login: 
--- back up: booted=protected ---
root@zfs16:~ # benext status
booted=protected
bootfs=good
protected=protected
lastgood=good
trial=-
armed=-
result=fallback-protected
booted_kernel=FreeBSD_16.0-CURRENT_#0_main-n290352-61c70dc16a79:_Tue_Oct_27_10:57:16_UTC_2026_____root@releng3.nyi.freebsd.org:/usr/obj/usr/src/amd64.amd64/sys/GENERIC
root@zfs16:~ # bectl destroy protected
cannot destroy active boot environment
root@zfs16:~ # bectl list
BE        Active Mountpoint Space Created
good      R      -          2.51G 2026-10-30 23:40
new       -      -          290K  2026-10-30 23:41
protected N      /          279K  2026-10-30 23:41
```
