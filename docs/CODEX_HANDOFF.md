# Compatibility branch handoff — 2026-09-15

The user abandoned the RC3 one-click installer branch and authorized compatibility work, local commits, and ordinary pushes to `Compatibility-fixes`. No merge to `aurora` or Release. No replacement ZIP deliverable.

## Baseline and evidence

- `aurora` / initial `Compatibility-fixes`: `e1673a16673070401612db04cc0593ca4dc3a6f6`.
- Old installer branch remains `aurora-rc3-installer-20260913`; old Witcher experiment remains `experiment/witcher-mfg-frame-sync-20260915`.
- User confirmed Witcher panel and 6X worked after installer fixes, then reproduced crashes loading with saved Dynamic MFG and toggling Dynamic/manual 6X or FG. Slight rapid flicker also remains. This is not a claim that the compatibility fixes have passed in-game testing.
- Existing crash evidence includes GPU DEVICE_HUNG / frame mismatch / Reflex failures, and separate CPU crashes at `witcher3.exe+0x1f1f4ea`. One fix must not be assumed to explain all signatures.
- User logs and dumps remain in the Codex task workspace `work/`, not in this public repository. Never commit private dumps or full user logs.
- See [compatibility audit](COMPATIBILITY_AUDIT_20260915.md) for adopted changes, sources, limitations, and validation.

## Continuation rules

Official upstream is `https://github.com/optiscaler/OptiScaler.git`; the local remote named `upstream` is instead the grim-susemi fork. Official audit cutoff is `4af2417b24d05c9ff2a2531bbffe67ec1af9e4ea`. Nine commits after the previously audited `731f3b79` were reviewed. Do not repeat the older seventeen-commit audit.

Current package workflow builds this branch and runs production-header frame/handle guard tests. Keep the original installer layout inherited from `aurora`; do not restore RC3 tools.

No new Genshin/Star Rail/ZZZ crash logs from the user were provided in this batch. An optional question about affected games, trigger, bridge, and ReShade remains unanswered. Continue source work without treating that silence as test confirmation.

Git network requests on this host have worked with per-command `http.proxy=http://127.0.0.1:7897`; do not alter global proxy or disable TLS verification. Push only `origin Compatibility-fixes`.
