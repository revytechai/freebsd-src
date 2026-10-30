#!/bin/sh
# benext - one-shot boot environment trials with automatic fallback to the
# last good BE, then to a protected rescue BE.  See benext(8).
# SPDX-License-Identifier: BSD-2-Clause
set -eu

BECTL=${BECTL:-bectl}
ZFS=${ZFS:-zfs}
ZPOOL=${ZPOOL:-zpool}
SYSCTL=${SYSCTL:-sysctl}
BENEXT_CONFIG=${BENEXT_CONFIG:-/etc/benext/config.json}
BENEXT_JSONGET=${BENEXT_JSONGET:-/usr/libexec/benext-jsonget}
P=org.cloudbsd

log() { ${BENEXT_LOG:-logger -s -t benext} "$*"; }
die() { rc=$1; shift; echo "benext: $*" >&2; exit "$rc"; }

# JSON config (rule 6).  Missing file = defaults.
cfg() {
	if [ -f "$BENEXT_CONFIG" ]; then
		v=$("$BENEXT_JSONGET" "$BENEXT_CONFIG" "$1") || die 4 "cannot read $1 from $BENEXT_CONFIG; run benext --check-config"
		[ -n "$v" ] && { echo "$v"; return; }
	fi
	echo "$2"
}

check_config() {
	f=${1:-$BENEXT_CONFIG}
	[ -f "$f" ] || die 4 "$f: no such file (copy config.json.sample)"
	"$BENEXT_JSONGET" "$f" --validate || die 4 "$f: invalid; fix the keys named above (see benext.json(5))"
	echo "benext: $f OK"
}

pool() {
	if [ -n "${BENEXT_POOL:-}" ]; then echo "$BENEXT_POOL"; return; fi
	r=$($ZFS list -H -o name /)
	echo "${r%%/*}"
}
beroot() { echo "$(pool)/ROOT"; }
getp() { $ZFS get -H -o value "$P:$1" "${2:-$(beroot)}"; }
setp() { $ZFS set "$P:$1=$2" "${3:-$(beroot)}"; }
exists() { $ZFS list -H -o name "$(beroot)/$1" >/dev/null 2>&1; }
booted() { r=$($ZFS list -H -o name /); echo "${r##*/}"; }
bootfs_be() { b=$($ZPOOL get -H -o value bootfs "$(pool)"); echo "${b##*/}"; }

protected() {
	for be in $($BECTL list -H | cut -f1); do
		[ "$(getp protected "$(beroot)/$be")" = on ] && { echo "$be"; return; }
	done
	echo -
}
refuse_protected() {
	[ "$1" != "$(protected)" ] || die 3 "$1 is the protected BE: refusing to $2 it"
}

cmd_protect() {
	exists "$1" || die 2 "no such BE: $1"
	p=$(protected)
	[ "$p" = - ] || [ "$p" = "$1" ] || die 2 "$p is already protected; only one protected BE is allowed"
	setp protected on "$(beroot)/$1"
	log "protected BE is now $1"
}

# Rule 31 / safe-kernel-deploy step 2 + 6: panic must power-cycle, live and in the candidate.
PANIC_SYSCTLS="debug.debugger_on_panic=0 kern.powercycle_on_panic=1 kern.panic_reboot_wait_time=5"
arm_panic() {
	$SYSCTL $PANIC_SYSCTLS >/dev/null
	mnt=$(mktemp -d "${TMPDIR:-/tmp}/benext.XXXXXX")
	$BECTL mount "$1" "$mnt" >/dev/null
	for s in $PANIC_SYSCTLS; do
		grep -q "^${s%%=*}=" "$mnt/etc/sysctl.conf" 2>/dev/null || echo "$s" >> "$mnt/etc/sysctl.conf"
	done
	$BECTL umount "$1"
	rmdir "$mnt"
}

cmd_try() {
	exists "$1" || die 2 "no such BE: $1"
	refuse_protected "$1" try
	t=$(getp trial)
	[ "$t" = - ] || [ -z "$t" ] || die 2 "trial of $t is still pending; run benext confirm or benext abort"
	good=$(bootfs_be)
	setp lastgood "$good"
	arm_panic "$1"
	setp trial "$1"
	$BECTL activate -t "$1" >/dev/null
	# bootfs MUST still be the known-good BE or the one-shot cannot revert.
	if [ "$(bootfs_be)" != "$good" ]; then
		$BECTL activate "$good" >/dev/null
		setp trial -
		die 5 "bootfs changed away from $good; restored it and cancelled the trial"
	fi
	log "one-shot trial of $1 armed; fallback $good"
}

cmd_abort() { $BECTL activate -T >/dev/null 2>&1 || :; setp trial -; log "trial cancelled"; }

cmd_arm() {
	p=$(protected); b=$(booted)
	[ "$p" != - ] || { log "no protected BE; not arming"; return 0; }
	if [ "$b" = "$p" ]; then
		setp result fallback-protected
		setp armed -
		log "BOOTED THE PROTECTED BE $p: the trial and last good BE both failed"
		return 0
	fi
	[ "$b" = "$(getp trial)" ] && return 0	# loader consumed the trial one-shot; fallback is bootfs
	setp armed on
	$BECTL activate -t "$p" >/dev/null
	log "armed one-shot fallback to protected BE $p"
}

run_checks() {
	d=$(cfg checks_dir /etc/benext.d)
	[ -d "$d" ] || return 0
	for c in "$d"/*; do
		[ -x "$c" ] || continue
		"$c" || { log "health check failed: $c"; return 1; }
	done
}

cmd_confirm() {
	b=$(booted); t=$(getp trial)
	setp booted_kernel "$(uname -v | tr ' ' _ )"
	if run_checks; then
		[ "$(getp armed)" = on ] && $BECTL activate -T >/dev/null
		setp armed -
		if [ "$b" = "$t" ]; then
			$BECTL activate "$b" >/dev/null
			setp lastgood "$b"; setp trial -; setp result ok
			log "trial $b healthy: now permanent"
		fi
		return 0
	fi
	setp result failed
	[ "$b" = "$t" ] && setp trial -
	log "boot of $b unhealthy: rebooting to fallback"
	eval "$(cfg reboot_cmd 'shutdown -r now')"
}

cmd_status() {
	k="lastgood trial armed result booted_kernel"
	if [ "${1:-}" = --json ]; then
		printf '{"booted":"%s","bootfs":"%s","protected":"%s"' "$(booted)" "$(bootfs_be)" "$(protected)"
		for x in $k; do printf ',"%s":"%s"' "$x" "$(getp $x)"; done
		echo '}'
	else
		echo "booted=$(booted)"; echo "bootfs=$(bootfs_be)"; echo "protected=$(protected)"
		for x in $k; do echo "$x=$(getp $x)"; done
	fi
}

cmd_prune() {
	keep=${1:-$(cfg keep 3)}
	p=$(protected); good=$(getp lastgood); t=$(getp trial)
	# bectl list -H: name active mountpoint space created ; oldest first
	list=$($BECTL list -H -c creation | cut -f1,2)
	first=$(echo "$list" | head -1 | cut -f1)
	cands=
	for row in $(echo "$list" | tr '\t' ':'); do
		name=${row%%:*}; flags=${row#*:}
		case "$flags" in *N*|*R*|*T*) continue ;; esac
		case "$name" in "$first"|"$p"|"$good"|"$t") continue ;; esac
		cands="$cands $name"
	done
	cands=$(echo $cands | tr ' ' '\n')
	n=$(echo "$cands" | grep -c . || :)
	echo "$cands" | head -n $((n > keep ? n - keep : 0)) | while read -r be; do
		[ -n "$be" ] || continue
		$BECTL destroy -o "$be" && log "pruned $be"
	done
}

usage() {
	cat >&2 <<U
usage: benext protect BE | try BE | abort | boot-arm | confirm | status [--json]
       benext destroy BE | rename OLD NEW | mount-rw BE DIR | prune [KEEP]
       benext --check-config [FILE]
U
	exit 64
}

[ $# -ge 1 ] || usage
c=$1; shift
case "$c" in
protect) [ $# -eq 1 ] || usage; cmd_protect "$1" ;;
try) [ $# -eq 1 ] || usage; cmd_try "$1" ;;
abort) cmd_abort ;;
boot-arm) cmd_arm ;;
confirm) cmd_confirm ;;
status) cmd_status "$@" ;;
destroy) [ $# -eq 1 ] || usage; refuse_protected "$1" destroy; exec $BECTL destroy "$1" ;;
rename) [ $# -eq 2 ] || usage; refuse_protected "$1" rename; exec $BECTL rename "$1" "$2" ;;
mount-rw) [ $# -eq 2 ] || usage; refuse_protected "$1" "mount read-write"; exec $BECTL mount "$1" "$2" ;;
prune) cmd_prune "$@" ;;
--check-config|--dry-run) check_config "${1:-}" ;;
*) usage ;;
esac
