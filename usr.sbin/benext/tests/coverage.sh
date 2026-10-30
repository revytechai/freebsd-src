#!/bin/sh
# Line coverage of sbin/benext: run the suite with benext traced (PS4 carries $LINENO).
T=$(cd "$(dirname "$0")" && pwd); SRC=$T/../sbin/benext; TR=$(mktemp /tmp/benext-trace.XXXXXX)
W=$(mktemp /tmp/benext-wrap.XXXXXX); chmod +x "$W"
printf '#!/bin/sh\nPS4="+@\\${LINENO}@ " exec ${COV_SH:-bash --posix} -x %s "$@" 2>>%s\n' "$SRC" "$TR" > "$W"
# stderr goes to the trace; tests only check exit codes and state, not stderr text.
BENEXT=$W sh "$T/run.sh" > "$TR.out" || { echo "suite failed under tracing"; grep -A3 ^FAIL "$TR.out"; exit 1; }
grep -o '^+*@[0-9]*@' "$TR" | tr -d '+@' | sort -u > "$TR.hit"
# executable lines: not blank/comment/structural-only
awk '{l=$0; sub(/^[ \t]+/,"",l)} l=="" || l ~ /^#/ || l ~ /^(}|fi|done|esac|else|then|;;|do|U|\{|cat >&2 <<U|usage: .*|benext .*)$/ || l ~ /^[a-z_]+\(\) \{$/ {next} {print NR}' "$SRC" | sort > "$TR.exe"
tot=$(wc -l < "$TR.exe"); miss=$(comm -23 "$TR.exe" "$TR.hit")
n=$(echo "$miss" | grep -c . || :)
echo "benext line coverage: $((tot-n))/$tot = $(( (tot-n)*100/tot ))%"
[ -z "$miss" ] || { echo "missed lines:"; for l in $miss; do printf '%4d: %s\n' "$l" "$(sed -n ${l}p "$SRC")"; done; }
rm -f "$TR" "$TR.hit" "$TR.exe" "$W"
[ -z "$miss" ]
