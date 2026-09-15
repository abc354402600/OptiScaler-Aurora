# Aurora compatibility work

Read `docs/CODEX_HANDOFF.md` before continuing. Source repository is this directory.

- Active branch: `Compatibility-fixes`, based on `aurora` at `e1673a16`.
- The user discontinued RC3 installer development. Preserve its historical branches; do not bring installer changes into this branch.
- Focus on evidenced game compatibility and performance defects. Review upstream/fork patches before adopting them; record provenance and deferred risks.
- Ordinary commits and pushes to `Compatibility-fixes` are authorized. Do not merge into `aurora`, force-push, or publish Releases.
- Do not modify installed games or claim CPU tests/builds establish GPU compatibility. Preserve native Streamline 1.x, Aurora's verified 6X path, and `DualFeature=false` behavior.
- Run focused checks and the full DLL build for affected C++ changes. Do not rerun unrelated legacy installer suites or produce replacement archives.

