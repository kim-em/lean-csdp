/-
  Reproduces the canonical CSDP example problem (`example/example.c`).

  The problem has three blocks (sizes 2, 3, 2-diagonal) and two constraints,
  with known optimal objective tr(C·X) = 2.75.
-/

import LeanCsdp

open LeanCsdp

def cExample : Array Triple := #[
  -- Block 1 (2x2)
  ⟨1, 1, 1, 2.0⟩, ⟨1, 1, 2, 1.0⟩, ⟨1, 2, 2, 2.0⟩,
  -- Block 2 (3x3)
  ⟨2, 1, 1, 3.0⟩, ⟨2, 1, 3, 1.0⟩, ⟨2, 2, 2, 2.0⟩, ⟨2, 3, 3, 3.0⟩
  -- Block 3 (diagonal of size 2): all zero
]

def aExample : Array ConstraintTriple := #[
  -- A₁ block 1: 1,1=3; 1,2=1; 2,2=3
  ⟨1, 1, 1, 1, 3.0⟩, ⟨1, 1, 1, 2, 1.0⟩, ⟨1, 1, 2, 2, 3.0⟩,
  -- A₁ block 3 (diagonal): 1=1
  ⟨1, 3, 1, 1, 1.0⟩,
  -- A₂ block 2: 1,1=3; 1,3=1; 2,2=4; 3,3=5
  ⟨2, 2, 1, 1, 3.0⟩, ⟨2, 2, 1, 3, 1.0⟩, ⟨2, 2, 2, 2, 4.0⟩, ⟨2, 2, 3, 3, 5.0⟩,
  -- A₂ block 3 (diagonal): 2=1
  ⟨2, 3, 2, 2, 1.0⟩
]

def exampleProblem : Problem := {
  blockSizes := #[2, 3, -2],
  b := #[1.0, 2.0],
  c := cExample,
  a := aExample
}

def main : IO UInt32 := do
  let sol := solve exampleProblem
  IO.println s!"return code: {sol.ret}"
  IO.println s!"primal objective: {sol.pobj}"
  IO.println s!"dual   objective: {sol.dobj}"
  IO.println s!"y = {sol.y.toList}"
  if sol.ret != 0 then
    IO.eprintln s!"CSDP failed with code {sol.ret}"
    return 1
  -- Sanity check: known optimum is 2.75.
  let expected : Float := 2.75
  let err := (sol.pobj - expected).abs
  if err > 1e-4 then
    IO.eprintln s!"objective {sol.pobj} differs from expected {expected} by {err}"
    return 2
  IO.println "OK"
  return 0
