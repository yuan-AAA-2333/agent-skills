---
name: refactor-verified-against-reference
description: Use when restructuring code that already works and whose numerical output must not change 鈥?turning research/competition scripts into a configurable package, merging duplicated implementations that drifted apart, generalizing a one-off model so a different case can use it, or producing code deliverables (software-copyright source listings, handover packages) from throwaway scripts. Covers the read-only original, cross-validating against the reference implementation to bit-equality, extracting the single source of truth for the objective, and the failure modes that only appear months later.
---

# Refactoring working code without changing its behaviour

The deliverable is a package that still produces **the same numbers** as the original scripts, is
configurable, and is tested. The discipline that makes it safe: the original is read-only, and
equivalence is *measured*, not asserted.

## Layout that keeps the original intact

```
<original>.py            鈫?untouched, still runnable
<project>/               鈫?the new engineered package
鈹溾攢鈹€ configs/             鈫?every previously-hardcoded constant, with the original value as default
鈹溾攢鈹€ src/<pkg>/           鈫?config, domain model, <single objective>, algorithms, cli
鈹溾攢鈹€ tests/               鈫?incl. a reference cross-check module
鈹斺攢鈹€ docs/                鈫?ALGORITHM / DATA / REFACTOR_NOTES
```

Snapshot the original (byte-identical copy) *before* touching anything. Keep a packaging test that
asserts the original files still exist and still contain their key identifiers 鈥?that test is what
stops a later "helpful" edit from silently invalidating every recorded number.

## Rule 1 鈥?extract the single source of truth for the objective

Duplicated evaluators are the classic defect. Four copies of `evaluate_route` with *different penalty
constants* (`M1=10/M2=20` in two files, `250` in a third, `200` in a fourth) means the four problems
were never comparable. Merge to one parameterised implementation, take the most common original value
as the default, and make the variants explicit parameters.

Then cross-validate: write a script that **re-implements the original's formula line by line** (with
the original line numbers in comments) and compares outputs over hundreds of random inputs.

```
Reference cross-check 鈥?the bar to clear
  2000 random parameter sets, objective max |difference| = 0.000e+00
  non-zero-solution counts identical on both sides
  edge/invalid inputs (out of bounds, below ground, past horizon) identical
  derived quantities compared too: arrival time must match to <1e-12 relative
```

**Bit-equality is achievable and worth insisting on** when you feed identical inputs.

## Rule 2 鈥?decimal literals in configs lose precision

Reproducing a reference that computes `T = 鈥杙鈧€鈥?v` by writing `v: [-298.5111570629967, 鈥` as a
config literal reintroduces a 1鈥? ulp round-trip error (measured: 6e-9 absolute, 9e-14 relative) and
breaks a strict equality test. Fix: let the config express the **quantity that matters**, not a
derived vector 鈥?e.g. `arrival_time: 66.99917080747261`, and derive the velocity inside the code so
`鈥杙鈧€鈥?鈥杤鈥朻 is exact.

Prefer an *authoritative declared value* over a recomputed one for anything that goes into a report:
store it on the object and return it verbatim.

## Rule 3 鈥?make the optional dependency optional

A research script that `import kaiwu` (or `torch`, `tensorflow`, `cv2`) at module scope cannot run,
cannot be tested, and cannot be handed over on a machine without the SDK. Introduce an **adapter +
fallback**: one interface, several backends, `auto` tries the specialised one and degrades to a local
implementation, printing *why*. Credentials move to environment variables 鈥?never inline them, and add
a source-scanning test for long literal secrets.

Same for heavy imports in tests: `pytest.importorskip("torch")`, never `pip install` to make a test run.

## Rule 4 鈥?subagents in parallel: constrain, then cross-audit

Fanning projects out to one subagent each works well when:

- they all read **one standards file on disk** (`_ENGINEERING_STANDARD.md`) rather than repeating rules
  in each prompt;
- each is told to **create new files only** 鈥?never edit the original or another agent's files;
- each leaves a **fingerprint** (sha256 + mtime) of inputs it depended on, so a later change can be
  detected;
- each proves it kept the originals: byte size + MD5 of the source files before/after.

Independent subagents genuinely catch each other's mistakes 鈥?one unflagged a real physics bug in a
sibling module it did not own. But they *can* break each other: concurrent edits silently reverted one
agent's fix. After they finish, **re-run everything yourself** and re-verify the shared invariants.

## Rule 5 鈥?the report must state what was NOT verified

Every refactor of this kind has parts you cannot execute: data that is not on the machine, a GPU path,
a 25 GB dataset, a licence-gated SDK. Record them in a table with the reason. A "done" that hides three
unrunnable paths is worse than a "done (3 paths unverified)" that names them.

## Worked example

`E:\dsh\migration\scripts\crosscheck-smoke.py` 鈥?the line-by-line reference reimplementation plus the
2000-case comparison harness. `G:\Code\01-绉戠爺\Mathematical-Modeling-Research\鏈熶腑浣滀笟\smoke_screen_opt\`
is the resulting package; its `tests/test_reference_crosscheck.py` freezes the calibrated numbers, and
`tests/test_packaging.py` proves the original scripts were never modified.
