# Contributing to aac-launch

## Invariant — the R7 regression guard

The test `parseExecLine: no shell expansion of $ or backticks` MUST
continue to pass for every change. It's the load-bearing assertion
that `eval`-replaceable launcher patterns route through us safely. A
PR that breaks it will be rejected.

## Adding a new field code

If the FreeDesktop spec gains a new `%X` field code:

1. Add a variant to the `FieldCode` enum in `src/main.zig`.
2. Match the variant in `parseExecLine`'s `%` switch.
3. Add a test that asserts substitution shape: bare line → expected argv.
4. Run `zig build test --summary all`.

## Build + test

```bash
zig build -Doptimize=ReleaseFast
zig build test --summary all
```

Zig 0.16.0+, libc-only.

## Patch flow

1. Branch from `main`.
2. Add a test that fails on the bug, then fix the code.
3. PR description: name the claim + falsifier (so it can be
   registered in [`stax-experiment`](https://github.com/SMC17/stax-experiment)).
