# Aurora compatibility work

Read `docs/CODEX_HANDOFF.md` before continuing. Source repository is this directory.

- Active branch: `Compatibility-fixes`, based on `aurora` at `e1673a16`.
- The user discontinued RC3 installer development. Preserve its historical branches; do not bring installer changes into this branch.
- Focus on evidenced game compatibility and performance defects. Review upstream/fork patches before adopting them; record provenance and deferred risks.
- Ordinary commits and pushes to `Compatibility-fixes` are authorized. The user's latest 2026-09-17 instruction also authorizes synchronizing to `aurora` after the ongoing lifecycle fixes, review, focused checks and full DLL build are complete; real-game testing is deferred and is not a merge prerequisite. Do not merge unfinished lifecycle work, force-push, or publish Releases. Record unverified game behavior accurately.
- Do not modify installed games or claim CPU tests/builds establish GPU compatibility. Preserve native Streamline 1.x, Aurora's verified 6X path, and `DualFeature=false` behavior.
- Run focused checks and the full DLL build for affected C++ changes. Do not rerun unrelated legacy installer suites or produce replacement archives.
