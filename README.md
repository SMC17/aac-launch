# aac-launch

Zig-native argv-safe app launcher. Replaces `eval exec setsid $LAUNCH_COMMAND`
style shell-string trust with a `.desktop` Exec-line tokenizer that produces
a real argv and spawns via `std.process.spawn` — no shell ever sees the
command.

Closes [stax-experiment HARNESS_AUDIT R7](https://github.com/SMC17/stax-experiment).

## Why

The standard Linux desktop launcher pattern (used by omarchy, gnome-shell,
KDE krunner, rofi, etc.) shells out via `eval`:

```bash
eval exec setsid $LAUNCH_COMMAND
```

This is a code-execution surface. Anything in `$LAUNCH_COMMAND` that looks
like `$foo`, `` `cmd` ``, `$(cmd)`, or `;rm -rf /` gets expanded by the
shell. The .desktop spec is *not* shell syntax — but `eval` doesn't know
that.

aac-launch parses the Exec line per the FreeDesktop spec, handles `%f`/`%F`/`%u`/`%U` field codes, strips deprecated `%i`/`%c`/`%k`, and passes `$foo` /
backticks through as **literal bytes**. No shell expansion.

## Build

    zig build                          # debug
    zig build -Doptimize=ReleaseFast   # release: ~4 MB
    zig build test                     # 7/7 tests including no-shell-expansion guard

Zig 0.16.0+, links only libc.

## Usage

    aac-launch exec firefox.desktop                       # launch by .desktop id
    aac-launch exec-cmd "code --new-window %f" /tmp/x.txt # safe Exec-line launch
    aac-launch parse "echo \$HOME \`whoami\`"             # show parsed argv

## Integration

Replace `eval exec setsid $LAUNCH_COMMAND` in any launcher with:

    exec setsid aac-launch exec-cmd "$LAUNCH_COMMAND"

Omarchy's `omarchy-launch-or-focus` is wired this way as of 2026-05-15.

## License

AGPL-3.0-or-later.
