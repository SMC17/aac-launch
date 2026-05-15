# aac-launch

Zig-native argv-safe app launcher. Replaces `eval exec setsid $LAUNCH_COMMAND`
shell-string trust with a `.desktop` Exec-line tokenizer that produces a
real argv and spawns via `std.process.spawn` — **no shell ever sees the
command**.

Closes [HARNESS_AUDIT R7](https://github.com/SMC17/agent-app-control/blob/main/README.md#lineage-harness_audit-closures).

## What this fixes

The standard Linux desktop launcher pattern (omarchy, krunner, rofi,
most agent-side wrappers) shells out via `eval`:

```bash
eval exec setsid $LAUNCH_COMMAND
```

This is a remote code execution surface. Anything in `$LAUNCH_COMMAND`
that looks like `$foo`, `` `cmd` ``, `$(cmd)`, or `;rm -rf /` gets
expanded by the shell. The FreeDesktop `.desktop` spec is **not** shell
syntax — but `eval` doesn't know that.

aac-launch parses the Exec line per the [Desktop Entry Spec §Exec][spec]:

- Splits on unquoted whitespace
- Honors `"quoted segments"` with `\\` `\"` `` \` `` `\$` escapes
- Handles `%f`/`%F`/`%u`/`%U` field codes (file/URL substitution)
- Strips deprecated `%i`/`%c`/`%k`
- Preserves `%%` as literal `%`
- Passes `$foo` and backticks through as **literal bytes** (no expansion)

[spec]: https://specifications.freedesktop.org/desktop-entry-spec/desktop-entry-spec-latest.html#exec-variables

## Quickstart

```bash
zig build -Doptimize=ReleaseFast
./zig-out/bin/aac-launch help

# Launch by .desktop id (searches standard XDG paths):
aac-launch exec firefox.desktop

# Launch via an Exec-line string with file substitution:
aac-launch exec-cmd "code --new-window %f" /tmp/example.txt

# Inspect parsing without launching:
aac-launch parse 'echo $HOME `whoami`'
# argv[0]: echo
# argv[1]: $HOME       ← literal, NOT expanded
# argv[2]: `whoami`    ← literal, NOT expanded
```

## Integration

Replace any shell-eval launcher:

```bash
# In a bash launcher:
exec setsid aac-launch exec-cmd "$LAUNCH_COMMAND"

# As a Hyprland binding:
bindd = SUPER, T, Terminal, exec, aac-launch exec-cmd "uwsm-app -- alacritty"

# As an omarchy helper:
exec aac-launch exec "$DESKTOP_ID"
```

Omarchy's `omarchy-launch-or-focus` is wired this way as of 2026-05-15.

## Subcommands

| subcommand | purpose |
| --- | --- |
| `exec DESKTOP_ID [extras...]` | resolve `.desktop` id via XDG search, launch with extras for `%f/%F/%u/%U` |
| `exec-cmd EXEC_LINE [extras...]` | launch an Exec-line string directly (skip XDG lookup) |
| `parse "Exec-line" [extras...]` | print parsed argv (no spawn) — useful for debugging |
| `help` / `--help` / `-h` | usage |

## Field code handling

| code | meaning | aac-launch behavior |
| --- | --- | --- |
| `%f` | a single file | substituted with `extras[0]` if present, else dropped |
| `%F` | multiple files | each extra becomes its own argv slot |
| `%u` | a single URL | substituted with `extras[0]` |
| `%U` | multiple URLs | same as `%F` shape |
| `%%` | literal `%` | preserved |
| `%i` `%c` `%k` | deprecated (Icon=/Name=/location) | silently stripped |
| `%d` `%D` `%n` `%N` `%v` `%m` | deprecated | silently stripped |

## XDG search paths

`exec DESKTOP_ID` looks in (in order):

1. `~/.local/share/applications/<id>`
2. `/usr/share/applications/<id>`
3. `/usr/local/share/applications/<id>`
4. `/run/current-system/sw/share/applications/<id>` (NixOS)

First match wins.

## Testing

```bash
zig build test --summary all
```

The suite asserts:

- Bare argv tokenization
- Multi-word + quoted segments
- `%f` / `%F` / `%u` / `%U` substitution shapes
- `%%` literal preservation
- **No shell expansion of `$` or backticks** — the regression guard against R7
- Deprecated `%i`/`%c`/`%k` silently stripped

## Security

Threat: **a malicious `.desktop` file in `~/.local/share/applications/`**
could try to inject shell metacharacters into its `Exec=` line. With
`eval` the shell expands them; with aac-launch they become literal bytes
in the argv.

Out of scope:

- A `.desktop` whose binary IS the vector — that's a binary-trust
  question, not a launcher question.
- Path traversal in `.desktop` paths — handled by XDG-share file
  permissions.

## Lineage

- The launcher pattern this replaces lives in `omarchy-launch-or-focus`,
  `omarchy-launch-webapp`, `omarchy-launch-tui`, and ~5 other places in
  the Omarchy distro. Each had a shell-eval surface.
- The Zig-native argv-safe parser was prototyped on 2026-05-15, ~360 lines.
- The Bash wrapper pattern in `omarchy-launch-or-focus` now prefers
  aac-launch when available, falls back to `eval` only if aac-launch is
  missing.

## Build

```bash
zig build                          # debug
zig build -Doptimize=ReleaseFast   # release: ~4 MB
zig build test --summary all       # tests
```

Requires Zig 0.16.0+, links libc only.

## License

AGPL-3.0-or-later. See `LICENSE`.

## See also

- [`SMC17/agent-app-control`](https://github.com/SMC17/agent-app-control)
- [`SMC17/stax-experiment`](https://github.com/SMC17/stax-experiment)
