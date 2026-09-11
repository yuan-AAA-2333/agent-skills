---
name: numerical-optimization-bug-patterns
description: Use when a numerical, geometric or combinatorial optimisation routine silently returns wrong or degenerate results, when a QUBO/penalty formulation prefers infeasible solutions, when an optimiser's later stage makes the answer worse, when a heuristic's quality must be proven rather than asserted, or when a derivation keeps contradicting what the code prints. Covers the specific defects that hide behind "it runs", the brute-force ground-truth harness, and stopping-the-derivation discipline.
---

# Numerical & optimisation bug patterns (and how they were actually found)

Every item below is a real defect that ran without error. None were visible by reading the code; all
were surfaced by testing a *property* or comparing against an enumerable ground truth.

## The discipline that finds them

**When a derivation keeps contradicting the printed numbers, stop deriving and enumerate.**
Four successive hand-derivations of a QUBO energy disagreed with the code; the resolution came from a
script that printed the diagonal, the cross-terms, the constant and the violation counts separately.
Five minutes of enumeration beats an hour of algebra, and the enumeration output is evidence you can
paste into a comment.

**Never tune a coefficient to make a test pass.** When a test asserting "feasible beats infeasible"
failed, the tempting fix was raising the penalty. Measuring instead showed that raising it *broke* the
ordering, and the real story was a sign error elsewhere. Calibrating to satisfy a test hides the defect
and corrupts the model.

## Defect catalogue

| # | Defect | Symptom | Detection |
|---|---|---|---|
| 1 | **Optimiser assumption of monotone stages** — the driver accepted each stage's result unconditionally | differential evolution converged to a *worse* local optimum than the coarse grid (3.15 → 0.0) | assert `final <= every stage`; the run reported stage 2 worse than stage 1 |
| 2 | **Constraint penalty: constant term dropped** | infeasible solutions scored *lower* than feasible ones | compare `energy(feasible)` vs `energy(all-zero)`; the all-zero vector won |
| 3 | **Constraint penalty: wrong sign on the diagonal** — `(Σx−1)²` expanded as `+P·Σx` instead of `−P·Σx` | "do nothing" became the global optimum | feasible solution scored **4008** while the zero vector scored **2000** |
| 4 | **Linear-term index boundary** — `two_opt` let the reversal span reach the trailing sentinel | clients silently dropped: 18 → 10 per cluster, 29/50 overall | after any improvement pass, compare the **set** of clients before/after |
| 5 | **Decoder not a bijection** — per-column argmax over an infeasible bit-vector produced repeats | downstream de-duplication deleted customers | assert `sorted(decoded) == sorted(expected)` after decoding, every time |
| 6 | **Variable shadowing inside a comprehension** — inner `lambda c:` shadowed the outer `for cid` | `NameError` crashed the multi-vehicle path only | the CLI smoke test failed while unit tests passed |
| 7 | **Divergence treated as arrival** — a "time to reach point" helper used a coarse sample + ternary search | 36.7 s instead of 67.0 s | assert the derived quantity against its closed form |
| 8 | **A coordinate convention silently halved the physics** — Cartesian with Y offset vs polar; `v = [-300, 0, -300]` gave 424 m/s where 300 was intended | reference solution collapsed from 4.95 s to 0.00 s | print `‖v‖` and the arrival time, don't assume them |

## The two harnesses to build

**1. Brute-force ground truth.** For small `n`, enumerate *all* permutations (9! = 362,880 takes 0.25 s)
and record the true optimum. Then quote the heuristic's gap. This converts "looks reasonable" into
`7 clients: 249 vs 249 → 0.00%`.

```python
def brute_force_best(instance, max_n=9):
    """Enumerate every permutation; refuse above max_n (factorial)."""
```
Pair it with a `gap_to_optimal(candidate)` helper. A heuristic that beats the brute-force optimum means
your *evaluator* is inconsistent — that is a bug signal, not a win.

**2. Least-one-violation probe.** Before trusting any relaxation, check the smallest infeasible
neighbour of a feasible solution:

```
feasible           energy = 8
one customer missing      = 406   (> feasible ✅)
one position doubled      = 411   (> feasible ✅)
all-zero (do nothing)     = 2000  (> feasible ✅)
```

If any of those is cheaper, the formulation will optimise toward it.

## Facts worth knowing about penalty formulations

- Expand the constraint honestly and keep all three parts: `−P` on the diagonal, `+2P` off-diagonal
  within the constrained group, `+P` constant. The constant does not change *which* solution is optimal
  but it changes **every comparison you print** — drop it and reports look wrong.
- **Bigger penalties are not safer.** Once the penalty dominates, the objective degenerates into
  "count violations" and real cost differences vanish; measured, a 1.8× increase flipped the ordering.
- **A QUBO linearisation of a nonlinear objective is not the objective.** Measured on one instance:
  the lowest-energy assignment was *not* the true optimum (energy 5.0 vs 16.0 true cost) because the
  linearisation omitted inter-node transition terms entirely. Say this out loud in the docs; the
  architecture must be "relaxation proposes, exact evaluator disposes" — QUBO seeds, local search refines.
- Score the relaxation's quality by the **exact evaluator**, never by its own energy.

## Verifying an optimiser end to end

- Log each stage's objective and **its own wall time**; a stage that never improves is information.
- Keep the best-so-far explicitly, and print "stage X gave 0.0 s, worse than incumbent 3.15 s — ignored".
- Check structural invariants after *every* improvement step, not just at the end: client set unchanged,
  path starts and ends at the depot, load ≤ capacity.
- Re-run the whole pipeline after any fix to a shared kernel — a boundary fix in one module changes
  every downstream result.

## Reusable artifact

`G:\Code\01-科研\Mathematical-Modeling-Research\mathorcup\代码\qubo_dispatch\` —
`src/qubo_dispatch/brute.py` (ground truth), `tests/test_qubo.py` (the three energy-ordering probes),
`tests/test_localsearch.py` (client-set preservation), `src/qubo_dispatch/optimizer.py` (best-so-far
tracking with an explicit "ignored, worse" log line).
