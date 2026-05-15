# Security policy

## Reporting

This is a single-purpose argv-safety primitive. The class of bugs that
matter:

1. **A shell metacharacter escapes through tokenization** — e.g. an
   Exec line that, when parsed, produces an argv that re-enters a
   shell context. The regression test `parseExecLine: no shell expansion
   of $ or backticks` is the load-bearing guard.
2. **A field-code substitution that lets the extras hide a metachar** —
   e.g. an extras value containing `;rm -rf /` that, when substituted
   into `%f`, escapes the argv slot. argv slots are byte-strings; this
   cannot happen by construction, but a regression that re-tokenizes
   would be a critical bug.
3. **Path traversal via `exec DESKTOP_ID`** — if an attacker can
   place a `.desktop` file at `~/.local/share/applications/X` they
   already have user write access. Out of scope.

Report via the operator-private channel or by opening an issue
**without** an exploit body until coordinated.

## Past incidents

None.
