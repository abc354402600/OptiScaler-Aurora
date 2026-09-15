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

Official upstream is `https://github.com/optiscaler/OptiScaler.git`; the local remote named `upstream` is instead the grim-susemi fork. Official audit cutoff is now `a4890db5b3c7c6918f4b35d0fd3318b42e2ccc66`. It adds only the Sword and Fairy 7 quirk after `4af2417b`; adopted with provenance. Nine commits before that, after `731f3b79`, were already reviewed. Do not repeat those audits.

Current package workflow builds this branch and runs production-header frame/handle guard tests. Keep the original installer layout inherited from `aurora`; do not restore RC3 tools.

The user subsequently provided ZZZ 11008 component-error screenshots and reports of disappearing files, and NTE menu stutter with an NPI workaround. GPU is tentatively RTX 40; exact build, missing filenames, protection history, and crash logs remain unknown. See [NTE/ZZZ follow-up](NTE_ZZZ_COMPATIBILITY.md). Do not confuse component errors, GPU exceptions, and absent FG input. No driver/game settings were changed by this work.

Git network requests on this host have worked with per-command `http.proxy=http://127.0.0.1:7897`; do not alter global proxy or disable TLS verification. Push only `origin Compatibility-fixes`.
