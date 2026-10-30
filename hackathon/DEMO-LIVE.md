# benext (#1658) live demo, run on demo-host (FreeBSD 16.0-CURRENT main-n290352, VM hk1), 2026-10-30 ~3:14 PM PT

benext: freebsd-src branch hawkeye/benext-1658 (847b56f) in revytechai. The commands and output below are verbatim.

Honest setup notes:
- The hk1 root is UFS, so this demo uses a real file-backed ZFS pool `demo` laid out like a boot pool (demo/ROOT/{protected,good,new,...}). bectl runs with `-r demo/ROOT`, and benext runs with BENEXT_POOL=demo.
- All the bectl, zfs and zpool calls, the one-shot nextboot (zfsbootcfg) and the bootfs changes are real. The only simulated part is which BE is booted: a 3-line zfs shim answers `zfs list /` from a file. Reboots are replaced by an echo (config reboot_cmd). No real reboot was done (Demo B skipped because the root isn't ZFS).
- Health check failure is simulated by a check script that exits 1.

```

# truncate -s 1g /root/demo/disk0 && zpool create -O mountpoint=none demo /root/demo/disk0
[exit 0]

# for b in protected good new old1 old2; do zfs create -p -o canmount=noauto -o mountpoint=/ demo/ROOT/$b; mkdir -p /tmp/m; mount -t zfs demo/ROOT/$b /tmp/m; mkdir -p /tmp/m/etc; touch /tmp/m/etc/sysctl.conf; umount /tmp/m; done; zpool set bootfs=demo/ROOT/good demo
[exit 0]

# bectl -r demo/ROOT list
BE        Active Mountpoint Space Created
good      R      -          25K   2026-10-30 22:13
new       -      -          25K   2026-10-30 22:13
old1      -      -          25K   2026-10-30 22:13
old2      -      -          25K   2026-10-30 22:13
protected -      -          25K   2026-10-30 22:13
[exit 0]

# sh /root/hk/benext/sbin/benext protect protected
benext: protected BE is now protected
[exit 0]

# zfs get -H org.cloudbsd:protected demo/ROOT/protected
demo/ROOT/protected	org.cloudbsd:protected	on	local
[exit 0]

# sh /root/hk/benext/sbin/benext destroy protected
benext: protected is the protected BE: refusing to destroy it
[exit 3]

# sh /root/hk/benext/sbin/benext rename protected p2
benext: protected is the protected BE: refusing to rename it
[exit 3]

# sh /root/hk/benext/sbin/benext try protected
benext: protected is the protected BE: refusing to try it
[exit 3]

# sh /root/hk/benext/sbin/benext protect good
benext: protected is already protected; only one protected BE is allowed
[exit 2]

# sh /root/hk/benext/sbin/benext status --json
{"booted":"good","bootfs":"good","protected":"protected","lastgood":"-","trial":"-","armed":"-","result":"-","booted_kernel":"-"}
[exit 0]

# sh /root/hk/benext/sbin/benext --check-config /root/demo/config.json
benext: /root/demo/config.json OK
[exit 0]

# sh /root/hk/benext/sbin/benext --check-config /root/demo/bad.json
/root/demo/bad.json: unknown key "bogus"
/root/demo/bad.json: key "keep" must be a number
benext: /root/demo/bad.json: invalid; fix the keys named above (see benext.json(5))
[exit 4]

# zfsbootcfg -z demo 2>&1; zpool get -H bootfs demo
demo	bootfs	demo/ROOT/good	local
[exit 0]

# sh /root/hk/benext/sbin/benext try new
benext: one-shot trial of new armed; fallback good
[exit 0]

# zfsbootcfg -z demo; zpool get -H bootfs demo; bectl -r demo/ROOT list
zfs:demo/ROOT/new:
demo	bootfs	demo/ROOT/good	local
BE        Active Mountpoint Space Created
good      R      -          25K   2026-10-30 22:13
new       T      -          25K   2026-10-30 22:13
old1      -      -          25K   2026-10-30 22:13
old2      -      -          25K   2026-10-30 22:13
protected -      -          25K   2026-10-30 22:13
[exit 0]

# sh /root/hk/benext/sbin/benext status
booted=good
bootfs=good
protected=protected
lastgood=good
trial=new
armed=-
result=-
booted_kernel=-
[exit 0]
## simulate: loader consumed one-shot, booted new; health check fails

# sh /root/hk/benext/sbin/benext boot-arm
[exit 0]

# sh /root/hk/benext/sbin/benext confirm
check: sshd not listening
benext: health check failed: /root/demo/checks/10-sshd
benext: boot of new unhealthy: rebooting to fallback
[demo] would run: shutdown -r now
[exit 0]

# sh /root/hk/benext/sbin/benext status
booted=new
bootfs=good
protected=protected
lastgood=good
trial=-
armed=-
result=failed
booted_kernel=FreeBSD_16.0-CURRENT_#0_main-n290352-61c70dc16a79:_Tue_Oct_27_10:57:16_UTC_2026_____root@releng3.nyi.freebsd.org:/usr/obj/usr/src/amd64.amd64/sys/GENERIC
[exit 0]
## simulate: reboot lands on bootfs=good, but good's health check also fails

# sh /root/hk/benext/sbin/benext boot-arm
benext: armed one-shot fallback to protected BE protected
[exit 0]

# zfsbootcfg -z demo
zfs:demo/ROOT/protected:
[exit 0]

# sh /root/hk/benext/sbin/benext confirm
check: sshd not listening
benext: health check failed: /root/demo/checks/10-sshd
benext: boot of good unhealthy: rebooting to fallback
[demo] would run: shutdown -r now
[exit 0]
## simulate: armed one-shot boots protected

# sh /root/hk/benext/sbin/benext boot-arm
benext: BOOTED THE PROTECTED BE protected: the trial and last good BE both failed
[exit 0]

# sh /root/hk/benext/sbin/benext status --json
{"booted":"protected","bootfs":"good","protected":"protected","lastgood":"good","trial":"-","armed":"-","result":"fallback-protected","booted_kernel":"FreeBSD_16.0-CURRENT_#0_main-n290352-61c70dc16a79:_Tue_Oct_27_10:57:16_UTC_2026_____root@releng3.nyi.freebsd.org:/usr/obj/usr/src/amd64.amd64/sys/GENERIC"}
[exit 0]

# sh /root/hk/benext/sbin/benext prune 1
could not open snapshot's origin
[exit 11]

# bectl -r demo/ROOT list
BE        Active Mountpoint Space Created
good      R      -          25K   2026-10-30 22:13
new       -      -          25K   2026-10-30 22:13
old1      -      -          25K   2026-10-30 22:13
old2      -      -          25K   2026-10-30 22:13
protected T      -          25K   2026-10-30 22:13
[exit 0]
## prune retry with real bectl-cloned BEs (old1/old2 above were bare datasets with no origin, so bectl destroy -o failed)

# zfs destroy demo/ROOT/old1; zfs destroy demo/ROOT/old2; bectl -r demo/ROOT create -e good old1; sleep 1; bectl -r demo/ROOT create -e good old2; sleep 1; bectl -r demo/ROOT create -e good old3
[exit 0]

# bectl -r demo/ROOT list -c creation
BE        Active Mountpoint Space Created
new       -      -          25K   2026-10-30 22:13
good      R      -          25K   2026-10-30 22:13
protected T      -          25K   2026-10-30 22:13
old1      -      -          1K    2026-10-30 22:14
old2      -      -          1K    2026-10-30 22:14
old3      -      -          1K    2026-10-30 22:14
[exit 0]

# sh /root/hk/benext/sbin/benext prune 1
benext: pruned old1
benext: pruned old2
[exit 0]

# bectl -r demo/ROOT list -c creation
BE        Active Mountpoint Space Created
new       -      -          25K   2026-10-30 22:13
good      R      -          25K   2026-10-30 22:13
protected T      -          25K   2026-10-30 22:13
old3      -      -          1K    2026-10-30 22:14
[exit 0]

# sh /root/hk/benext/sbin/benext destroy protected
benext: protected is the protected BE: refusing to destroy it
[exit 3]

# zpool destroy demo; rm -rf /root/demo/disk0
[exit 0]
```
