# API stability

aac-launch follows [Semantic Versioning 2.0.0](https://semver.org/):

- **MAJOR** version bumps signal **breaking** changes to the CLI surface
  (subcommand removed/renamed, argument shape changed, exit-code semantics
  changed, output format changed in a non-additive way).
- **MINOR** version bumps add new subcommands, new flags, or new fields to
  output (additive, backward-compatible). Existing callers continue to work.
- **PATCH** bumps fix bugs without changing surface.

## Deprecation policy

A surface marked deprecated in version `X.Y` will be supported through the
end of the `X` major series — minimum **18 months** between deprecation
notice and removal. Deprecated surfaces emit a stderr warning on use.

## Public CLI surface

The following are STABLE under semver:

- Subcommand names: `exec`, `exec-cmd`, `parse`, `help`, `--help`, `-h`.
- The `parse` output format (`argv[N]: <value>` per line).
- Exit codes: `0` success, `2` bad usage, `3` desktop-file not found,
  `4` exec-line has no `Exec=` field, `5` parsed argv empty.

The following are EXPLICITLY UNSTABLE and may change at any minor bump:

- Debug output to stderr.
- The exact byte layout of CHANGELOG.md / README.md / SECURITY.md.
- Internal library API (`parseExecLine` in `src/main.zig`) — Zig
  callers should pin a version.

## Python binding (`aac_launch` on PyPI)

The Python wrapper follows the same semver, with the same stability promise
on the three public functions (`parse`, `exec_cmd`, `exec_desktop`).

## Signed releases

From v0.3.0 onward, tags are signed via [sigstore/cosign](https://github.com/sigstore/cosign).
Verify with:

```bash
cosign verify-blob --key cosign.pub --signature aac-launch-vX.Y.Z.sig aac-launch-vX.Y.Z.tar.gz
```

Public key is published in the GitHub release page for each tag.

## Migration log

| from | to | changes |
| --- | --- | --- |
| v0.1.0 | v0.2.0 | tests 7→26, README expansion, governance files, CI workflow |
| v0.2.0 | v0.3.0 | cross-platform CI matrix (5 targets), Python binding (`aac_launch` on PyPI), benchmark suite, signed releases (cosign) |
