# lean-csdp

[![CI](https://github.com/kim-em/lean-csdp/actions/workflows/ci.yml/badge.svg)](https://github.com/kim-em/lean-csdp/actions/workflows/ci.yml)

Lean 4 FFI bindings for the [CSDP](https://github.com/coin-or/Csdp)
semidefinite-programming solver. Wraps the high-level `easy_sdp` entry
point so Lean code can solve standard-form SDPs

```
maximise     tr(C · X)
subject to   tr(Aᵢ · X) = bᵢ        for i = 1, …, k
             X ⪰ 0  with block-diagonal structure
```

CSDP itself (release 6.2.0) is vendored as a git submodule; this package
builds it from source against the system BLAS/LAPACK runtime.

## Using

```lean
import LeanCsdp
open LeanCsdp

-- Block sizes: positive => SDP block of that order;
-- negative => LP-style diagonal block of order |size|.
def problem : Problem := {
  blockSizes := #[2, -3],
  b := #[1.0, 2.0],
  c := #[
    ⟨1, 1, 1, 2.0⟩, ⟨1, 1, 2, 1.0⟩, ⟨1, 2, 2, 2.0⟩,
    -- ... (block, row, col, value), 1-indexed, upper triangle only
  ],
  a := #[
    ⟨1, 1, 1, 1, 3.0⟩, ⟨1, 1, 1, 2, 1.0⟩,
    -- ... (constraint, block, row, col, value)
  ]
}

#eval do
  let sol := solve problem
  IO.println s!"primal = {sol.pobj}, dual = {sol.dobj}"
```

`Solution.X` and `Solution.Z` come back split into per-block `Block`
values (`.sdp n entries` for column-major SDP blocks, `.diag n entries`
for diagonal blocks); `Solution.y` is a flat `FloatArray` of length `k`.

A worked example reproducing the canonical CSDP problem (objective
`2.75`) lives in [`Main.lean`](Main.lean) and is run as part of CI on
each platform.

## Building locally

```
git clone --recursive https://github.com/kim-em/lean-csdp
cd lean-csdp
lake build
.lake/build/bin/csdp-example   # Lean runs the SDP and prints the result
```

System dependencies (matching what CI installs):

| Platform | What you need                                       |
|----------|-----------------------------------------------------|
| Linux    | `liblapack-dev libblas-dev gfortran zstd`           |
| macOS    | Apple Command Line Tools (Accelerate framework)     |
| Windows  | MSYS2 mingw-w64 with `mingw-w64-x86_64-openblas`    |

On Windows the lakefile expects the OpenBLAS import library at
`vendor/mingw-libs/`; the CI workflow stages it from `$MINGW_PREFIX/lib`
and you can do the same locally before `lake build`.

## Repository layout

```
csdp/                  # CSDP 6.2.0 source (git submodule)
ffi/lean_csdp.c        # C glue translating flat sparse data to CSDP structs
ffi/lean_csdp_bridge.c # Lean-callable entry points
LeanCsdp/Basic.lean    # Lean-side types + opaque FFI declarations
Main.lean              # Worked example (used as smoke test)
lakefile.lean          # Build configuration
scripts/install-toolchain.sh  # Lean toolchain installer with GitHub-release fallback
```

## Licence

Apache License 2.0 (see [LICENSE](LICENSE)). CSDP itself is distributed
under the [Eclipse Public License 1.0](csdp/LICENSE).
