# benext: one-shot BE trials with a protected fallback (OpenZFS Hackathon, Track #1658)

Goal (Mark): "make sure we can have a protected BE that will always start".

## How it works
- `benext protect <be>` marks a BE `org.cloudbsd:protected=on`; it cannot be tried, destroyed by `prune`, or renamed away.
- `benext try <be>` arms a one-shot boot (`bectl activate -t`) into the new BE and records `lastgood`; `bootfs` stays on the last good BE, so any failure of the trial lands back on it.
- `rc.d/benext_arm` (early boot) arms a one-shot to the protected BE, so a hard hang/panic of *this* boot comes up on the protected BE next time.
- `rc.d/benext_confirm` (late boot) runs the health checks in `/etc/benext.d/`; pass -> trial becomes the permanent `bootfs` and `lastgood`; fail -> reboot to last-good.
- Fallback chain: **new -> last-good -> protected**.
- `benext status --json`, `benext --check-config` (JSON config, see benext.json(5)), `rc.conf`: `benext_enable="YES"`.

## Demo (fake bectl/zfs harness, real tool)
```
sh usr.sbin/benext/tests/run.sh
```
See `tests-output.txt` (34 passed, 0 failed; 127/127 lines covered in the VM run).

## Man pages
`benext.8.html`, `benext.json.5.html`, `rc.conf.5.html` (rendered with `mandoc -Thtml`; `mandoc -Tlint` clean for the new text).

## Still owed
- Real-VM proof of the full new -> last-good -> protected chain.
- Two-step protected-BE replacement (`benext protect --candidate`, promote only after a confirmed boot) requested by Mark: designed, not in this branch.
- Full (non-degraded) code review; this was committed on a degraded receipt (commit-review gate not available after the box reset).
