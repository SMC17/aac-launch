# aac_launch — Python binding

Pythonic wrapper around the [`aac-launch`](https://github.com/SMC17/aac-launch)
Zig binary. The binary does the argv-safe `.desktop` Exec tokenization; this
module makes it usable from Python without `shell=True`.

## Install

```bash
pip install aac_launch
```

The `aac-launch` binary must be on `PATH` (or pointed at via the
`AAC_LAUNCH_BINARY` env var). Build it from the parent repo:

```bash
cd ../..   # to the aac-launch repo root
zig build -Doptimize=ReleaseFast
install ./zig-out/bin/aac-launch ~/.local/bin/
```

## Quickstart

```python
from aac_launch import parse, exec_cmd, exec_desktop

# Parse without launching:
argv = parse('echo $HOME `whoami`')
assert argv == ['echo', '$HOME', '`whoami`']
# ↑ $HOME and backticks are LITERAL — no shell ever sees them.

# Launch a .desktop file:
exec_desktop('firefox.desktop')

# Launch from an Exec-line string with file substitution:
exec_cmd('code --new-window %f', ['/tmp/example.txt'])
```

## Why a Python binding?

Most agent/automation tooling is Python or JavaScript. To make
argv-safe launching reachable from those ecosystems without
re-implementing the FreeDesktop spec, wrap the Zig binary via
subprocess. The binary is the trust boundary; the binding is
ergonomics.

## License

AGPL-3.0-or-later (matches the parent).
