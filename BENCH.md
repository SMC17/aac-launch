# BENCH.md — aac-launch parseExecLine throughput

Honest measurements of `parseExecLine` — the load-bearing primitive
that tokenizes `.desktop` `Exec=` lines into argv arrays. The R7
contract requires that this tokenization is correct (no shell
expansion) AND fast enough that no realistic launcher workload can
backlog.

## TL;DR — sub-microsecond per launcher invocation on typical shapes

On a 5-year-old laptop (Intel i7-1065G7 @ 1.3 GHz, ReleaseFast,
MONOTONIC timing), parseExecLine operates at:

| Shape                | Throughput        | ns/op | Notes                          |
|----------------------|-------------------|------:|--------------------------------|
| bare (1 token)       | 3.9 M ops/sec     |   254 | `firefox`                      |
| multi-word           | 1.35 M ops/sec    |   741 | `firefox %u --new-tab`         |
| quoted               | 1.19 M ops/sec    |   843 | shell-quoted with spaces       |
| percent-f            | 2.39 M ops/sec    |   418 | single-file `%f` substitution  |
| percent-F-large      | 1.38 M ops/sec    |   724 | multi-file `%F` substitution   |
| long-line            | 195 K ops/sec     |  5120 | 1 KB Exec line stress case     |
| deprecated codes     | 2.02 M ops/sec    |   496 | `%d %D %n %N %v %m` skipping   |

Numbers from `zig build bench -Doptimize=ReleaseFast` on 2026-05-15.
Raw output in `bench/results/2026-05-15.out`.

## What these numbers mean

A user launching apps from a menu does maybe 10 launcher invocations
per minute. Each invocation does one `parseExecLine` call on the
relevant `.desktop` file. At ~1 µs per call, the launcher costs
**10 µs of CPU per minute** at the absolute worst.

Even an automated batch (a Wayland session starting and walking every
`.desktop` file on the system at startup) is bounded by the file I/O
to read each `.desktop` file, not by parseExecLine. On a typical
desktop with ~200 `.desktop` files, the full parse pass takes
~0.5 ms — well under the perceptual budget.

## The load-bearing invariant

The `parseExecLine: no shell expansion of $ or backticks` test asserts
that `Exec=$(rm -rf ~)` and ``Exec=`rm -rf ~` `` are passed through
to the launched binary as literal text, never executed by a shell.
The performance numbers above are meaningless without this guard —
a faster parser that re-tokenized into a shell context would be
trivially exploitable.

The bench is a performance witness, not a correctness proof. The
correctness proof lives in the 26 in-source tests, including the
named regression test.

## Honest scope

These numbers are:
- **Single-threaded.** No batch-parser pipeline.
- **No PGO, no LTO.** Stock `-Doptimize=ReleaseFast`.
- **One CPU.** Intel i7-1065G7 (Ice Lake, 4C/8T).
- **Synthetic input shapes.** Real `.desktop` files have similar
  shape distribution but specific content varies.

These numbers are NOT:
- A claim that aac-launch is faster than `gtk-launch` or `xdg-open`.
  Those tools do far more than tokenize an Exec line (D-Bus
  activation, GTK init, X11 hand-off). Apples to oranges.

## Reproducing

```sh
git clone https://github.com/SMC17/aac-launch
cd aac-launch
zig build bench -Doptimize=ReleaseFast 2> bench-output.txt
cat bench-output.txt
```

Expected format per line:
```
bench=parse size=<shape> iters=N total_ns=N ns_per_op=N ops_per_sec=N
```
