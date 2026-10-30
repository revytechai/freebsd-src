#!/bin/sh
# Red-green suite for benext.  BENEXT=path overrides the tool under test.
T=$(cd "$(dirname "$0")" && pwd); B=${BENEXT:-$T/../benext.sh}
pass=0; fail=0
setup() {
	FAKE=$(mktemp -d /tmp/benextt.XXXXXX); export FAKE; mkdir -p "$FAKE/props"
	printf 'default\ngood\nnew\n' > "$FAKE/bes"; echo good > "$FAKE/booted"; echo good > "$FAKE/bootfs"
	export BECTL="$T/fakes/bectl" ZFS="$T/fakes/zfs" ZPOOL="$T/fakes/zpool" SYSCTL="$T/fakes/sysctl"
	export BENEXT_JSONGET="$T/fakes/jsonget" BENEXT_LOG=: BENEXT_CONFIG="$FAKE/config.json"
	export TMPDIR="$FAKE" BENEXT_CHECKS="$FAKE/checks"; mkdir -p "$FAKE/checks"
	printf '{"checks_dir":"%s","keep":1,"reboot_cmd":"echo reboot >> %s/reboots"}\n' "$FAKE/checks" "$FAKE" > "$FAKE/config.json"
}
p() { cat "$FAKE/props/zroot%ROOT${2:+%$2}/$1" 2>/dev/null || echo -; }
fakeboot() { if [ -f "$FAKE/bootonce" ]; then mv "$FAKE/bootonce" "$FAKE/booted"; else cp "$FAKE/bootfs" "$FAKE/booted"; fi; }
failcheck() { printf '#!/bin/sh\nexit 1\n' > "$FAKE/checks/10-fail"; chmod +x "$FAKE/checks/10-fail"; }
okcheck() { rm -f "$FAKE/checks/10-fail"; printf '#!/bin/sh\nexit 0\n' > "$FAKE/checks/05-ok"; chmod +x "$FAKE/checks/05-ok"; }
reboots() { cat "$FAKE/reboots" 2>/dev/null | wc -l | tr -d ' '; }
ok() { [ "$1" = "$2" ] || { echo "    expected [$2] got [$1]"; return 1; }; }

t_try_sets_props_and_oneshot() { $B try new && ok "$(cat $FAKE/bootonce)" new && ok "$(cat $FAKE/bootfs)" good && ok "$(p trial)" new && ok "$(p lastgood)" good; }
t_try_arms_panic_reboot() { $B try new && grep -q kern.powercycle_on_panic=1 "$FAKE/sysctl" && grep -q 'mount new' "$FAKE/calls" && grep -q 'umount new' "$FAKE/calls"; }
t_try_keeps_bootfs() { touch "$FAKE/activate_breaks_bootfs"; $B try new 2>/dev/null; rc=$?; ok $rc 5 && ok "$(cat $FAKE/bootfs)" good && ok "$(p trial)" -; }
t_try_refuses_missing() { $B try nope 2>/dev/null; ok $? 2; }
t_try_refuses_protected() { $B protect default && { $B try default 2>/dev/null; ok $? 3; }; }
t_try_refuses_pending() { $B try new && { $B try new 2>/dev/null; ok $? 2; }; }
t_abort_clears_trial() { $B try new && $B abort && ok "$(p trial)" - && [ ! -f "$FAKE/bootonce" ]; }
t_confirm_pass_promotes_trial() { okcheck; $B try new && fakeboot && $B confirm && ok "$(cat $FAKE/bootfs)" new && ok "$(p lastgood)" new && ok "$(p result)" ok && ok "$(p trial)" -; }
t_confirm_pass_nontrial_noop() { okcheck; $B confirm && ok "$(cat $FAKE/bootfs)" good && ok "$(p result)" -; }
t_confirm_fail_trial_reboots_to_lastgood() { failcheck; $B try new && fakeboot && $B confirm; ok "$(reboots)" 1 && ok "$(p result)" failed && fakeboot && ok "$(cat $FAKE/booted)" good; }
t_boot_arm_sets_oneshot_to_protected() { $B protect default && $B boot-arm && ok "$(cat $FAKE/bootonce)" default && ok "$(p armed)" on; }
t_boot_arm_no_protected() { $B boot-arm && [ ! -f "$FAKE/bootonce" ]; }
t_boot_arm_on_trial_does_not_rearm() { $B protect default && $B try new && fakeboot && $B boot-arm && [ ! -f "$FAKE/bootonce" ]; }
t_confirm_pass_disarms() { okcheck; $B protect default && $B boot-arm && $B confirm && [ ! -f "$FAKE/bootonce" ] && ok "$(p armed)" -; }
t_chain_trial_and_lastgood_fail_lands_on_protected() {
	failcheck; $B protect default && $B try new || return 1
	fakeboot; ok "$(cat $FAKE/booted)" new || return 1; $B boot-arm; $B confirm	# trial unhealthy
	fakeboot; ok "$(cat $FAKE/booted)" good || return 1; $B boot-arm; $B confirm	# last good unhealthy
	fakeboot; ok "$(cat $FAKE/booted)" default || return 1; $B boot-arm
	ok "$(p result)" fallback-protected && ok "$(reboots)" 2
}
t_protect_only_one() { $B protect default && { $B protect good 2>/dev/null; ok $? 2; } && $B protect default; }
t_protect_missing() { $B protect nope 2>/dev/null; ok $? 2; }
t_destroy_protected_refused() { $B protect default && { $B destroy default 2>/dev/null; ok $? 3; } && grep -qx default "$FAKE/bes"; }
t_destroy_unprotected_passes() { $B destroy new && ! grep -qx new "$FAKE/bes"; }
t_rename_protected_refused() { $B protect default && { $B rename default x 2>/dev/null; ok $? 3; }; }
t_rename_unprotected_passes() { $B rename new newer && grep -qx newer "$FAKE/bes"; }
t_mountrw_protected_refused() { $B protect default && { $B mount-rw default /mnt 2>/dev/null; ok $? 3; }; }
t_mountrw_unprotected_passes() { $B mount-rw new "$FAKE/m" && [ -d "$FAKE/m/etc" ]; }
t_prune_keeps_protected_and_lastgood() {
	printf 'orig\nold1\nold2\nold3\nprot\ngood\nnew\n' > "$FAKE/bes"; $B protect prot && $B try new && $B abort && $B prune 2
	for k in orig prot good new old3; do grep -qx $k "$FAKE/bes" || { echo "    lost $k"; return 1; }; done
	! grep -qx old1 "$FAKE/bes" && ! grep -qx old2 "$FAKE/bes"
}
t_prune_default_keep_from_config() { printf 'orig\na\nb\ngood\n' > "$FAKE/bes"; $B prune && ! grep -qx a "$FAKE/bes" && grep -qx b "$FAKE/bes"; }
t_status_output() { $B protect default && $B status | grep -qx protected=default && $B status | grep -qx booted=good && $B status | grep -q '^booted_kernel='; }
t_status_json() { $B status --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["booted"]=="good" and d["bootfs"]=="good"'; }
t_check_config_valid() { $B --check-config >/dev/null; }
t_check_config_invalid() { echo '{"bogus":1}' > "$FAKE/bad.json"; $B --check-config "$FAKE/bad.json" 2>/dev/null; ok $? 4; }
t_check_config_missing() { $B --check-config "$FAKE/none.json" 2>/dev/null; ok $? 4; }
t_config_unreadable_key() { echo 'not json' > "$FAKE/config.json"; $B prune 2>/dev/null; ok $? 4; }
t_config_absent_uses_defaults() { rm "$FAKE/config.json"; printf 'orig\na\nb\nc\nd\ne\ngood\n' > "$FAKE/bes"; $B prune && grep -qx c "$FAKE/bes" && ! grep -qx a "$FAKE/bes"; }
t_pool_override() { BENEXT_POOL=zroot $B status | grep -qx bootfs=good; }
t_usage() { $B 2>/dev/null; ok $? 64 && { $B bogus 2>/dev/null; ok $? 64; } && { $B try 2>/dev/null; ok $? 64; } && { $B protect 2>/dev/null; ok $? 64; } && { $B destroy 2>/dev/null; ok $? 64; } && { $B rename a 2>/dev/null; ok $? 64; } && { $B mount-rw a 2>/dev/null; ok $? 64; }; }

for t in $(grep -o '^t_[a-z_]*' "$0"); do
	setup
	if ( $t ) > "$FAKE/out" 2>&1; then echo "PASS $t"; pass=$((pass+1)); else echo "FAIL $t"; sed 's/^/    /' "$FAKE/out"; fail=$((fail+1)); fi
	[ -n "${KEEP_FAKE:-}" ] || rm -rf "$FAKE"
done
echo "== $pass passed, $fail failed"
[ $fail -eq 0 ]
