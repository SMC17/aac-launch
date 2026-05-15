"""aac_launch — Python binding for the argv-safe .desktop Exec launcher.

Wraps the `aac-launch` binary (Zig) with a Pythonic interface. The binary
itself does the argv-safe tokenization; this module is a thin
subprocess wrapper.

Quickstart:

    from aac_launch import parse, exec_cmd, exec_desktop

    # Parse without launching:
    argv = parse('echo $HOME `whoami`')
    # ['echo', '$HOME', '`whoami`']  ← literal, NOT expanded

    # Launch a .desktop file:
    exec_desktop('firefox.desktop')

    # Launch from an Exec-line string with file substitution:
    exec_cmd('code --new-window %f', ['/tmp/example.txt'])

Security: all argv tokenization happens in the Zig binary, which
does not invoke a shell. Calls from Python via subprocess use argv
lists (no shell=True). Shell metacharacters in extras pass through
as literal bytes.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from typing import Sequence

__version__ = "0.3.0"
__all__ = ["parse", "exec_cmd", "exec_desktop", "BinaryNotFound", "ExecError"]


class BinaryNotFound(RuntimeError):
    """Raised when the `aac-launch` binary is not on PATH."""


class ExecError(RuntimeError):
    """Raised when `aac-launch` returns a non-zero exit code."""


def _resolve_binary() -> str:
    """Locate the aac-launch binary. Override via $AAC_LAUNCH_BINARY."""
    override = os.environ.get("AAC_LAUNCH_BINARY")
    if override:
        if not os.path.isfile(override):
            raise BinaryNotFound(
                f"AAC_LAUNCH_BINARY={override} does not exist"
            )
        return override
    found = shutil.which("aac-launch")
    if not found:
        raise BinaryNotFound(
            "aac-launch binary not found on PATH. Install from "
            "github.com/SMC17/aac-launch or set $AAC_LAUNCH_BINARY."
        )
    return found


def parse(exec_line: str, extras: Sequence[str] = ()) -> list[str]:
    """Parse a .desktop Exec-line string and return the argv it would spawn.

    Does NOT launch anything. Useful for asserting argv-safety in tests.

    Args:
        exec_line: a Desktop Entry Spec `Exec=` value (without the `Exec=` prefix).
        extras: positional values for `%f` / `%F` / `%u` / `%U` substitution.

    Returns:
        list[str] of argv tokens, in order.
    """
    binary = _resolve_binary()
    cmd = [binary, "parse", exec_line, *extras]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise ExecError(
            f"aac-launch parse failed (exit {proc.returncode}): {proc.stderr.strip()}"
        )
    argv: list[str] = []
    for line in proc.stdout.splitlines():
        # Lines look like:  "argv[0]: firefox"
        if not line.startswith("argv["):
            continue
        _, _, value = line.partition(": ")
        argv.append(value)
    return argv


def exec_cmd(exec_line: str, extras: Sequence[str] = ()) -> None:
    """Spawn the binary indicated by an Exec-line string.

    Does NOT wait — the binary fork-and-detaches. Use this for UI launchers.

    Args:
        exec_line: a Desktop Entry Spec `Exec=` value.
        extras: positional values for `%f`/`%F`/`%u`/`%U`.
    """
    binary = _resolve_binary()
    cmd = [binary, "exec-cmd", exec_line, *extras]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise ExecError(
            f"aac-launch exec-cmd failed (exit {proc.returncode}): {proc.stderr.strip()}"
        )


def exec_desktop(desktop_id: str, extras: Sequence[str] = ()) -> None:
    """Launch a .desktop file by its id, resolved via XDG search paths.

    Args:
        desktop_id: e.g. "firefox.desktop"
        extras: positional values for the Exec-line's field codes.
    """
    binary = _resolve_binary()
    cmd = [binary, "exec", desktop_id, *extras]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise ExecError(
            f"aac-launch exec {desktop_id} failed (exit {proc.returncode}): {proc.stderr.strip()}"
        )
