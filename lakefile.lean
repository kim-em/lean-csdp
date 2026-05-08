import Lake
open System Lake DSL

package leanCsdp where

/-! ## Platform-specific BLAS / LAPACK linkage. -/

/--
Linker arguments for the BLAS / LAPACK runtime CSDP requires.

* macOS: link Apple's `Accelerate` framework. Lake passes `--sysroot`
  pointing at the Lean toolchain directory (which has no system frameworks),
  so we override with a later `-isysroot` pointing at a real macOS SDK. We
  hard-code the Command Line Tools SDK path because (a) it is the most
  universally available across user machines and CI runners and (b) `Lake`'s
  configuration phase has no clean way to call `xcrun` at load time.
* Linux: reference BLAS + LAPACK packages plus the gfortran runtime
  (LAPACK is Fortran code).
* Windows (MSYS2 / mingw-w64): the OpenBLAS package, which bundles BLAS,
  LAPACK, and the Fortran runtime.
-/
def macSdkPath : String :=
  "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"

def blasLapackLinkArgs : Array String :=
  if System.Platform.isOSX then
    -- Pass the SDK path as a linker flag so it overrides Lake's earlier
    -- `--sysroot` pointing at the Lean toolchain.
    #[s!"-Wl,-syslibroot,{macSdkPath}", "-framework", "Accelerate"]
  else if System.Platform.isWindows then
    -- `-L` paths cover the typical MSYS2 mingw64 install location so that
    -- Lean's bundled lld can find the OpenBLAS / Fortran runtime libraries
    -- that we install via pacman in CI.
    #["-LC:/msys64/mingw64/lib", "-lopenblas", "-lgfortran", "-lquadmath", "-lm"]
  else
    -- Linux: reference BLAS + LAPACK packages plus the gfortran runtime
    -- (LAPACK is Fortran code). Lean's bundled clang sets `--sysroot` to
    -- the toolchain dir, so system library paths need to be added
    -- explicitly. We probe the standard Debian/Ubuntu and Red Hat /
    -- Fedora locations.
    -- We use `-l:libgfortran.so.5` (the SONAME of the runtime library) so
    -- linking does not depend on the gfortran-dev package being installed
    -- and leaving a `libgfortran.so` symlink behind.
    #[ "-L/usr/lib/x86_64-linux-gnu",
       "-L/usr/lib/aarch64-linux-gnu",
       "-L/usr/lib64",
       "-L/usr/lib",
       "-llapack", "-lblas", "-l:libgfortran.so.5", "-lm" ]

/-! ## CSDP object compilation. -/

def csdpSrcs : Array String := #[
  "Fnorm.c", "add_mat.c", "addscaledmat.c", "allocmat.c",
  "calc_dobj.c", "calc_pobj.c", "chol.c", "copy_mat.c",
  "easysdp.c", "freeprob.c", "initparams.c", "initsoln.c",
  "linesearch.c", "make_i.c", "makefill.c", "mat_mult.c",
  "mat_multsp.c", "matvec.c", "norms.c", "op_a.c", "op_at.c",
  "op_o.c", "packed.c", "psd_feas.c", "qreig.c", "readprob.c",
  "readsol.c", "sdp.c", "solvesys.c", "sortentries.c",
  "sym_mat.c", "trace_prod.c", "tweakgap.c", "user_exit.c",
  "writeprob.c", "writesol.c", "zero_mat.c"
]

def csdpCFlags (pkg : Package) : Array String :=
  let inc := pkg.dir / "csdp" / "include"
  -- CSDP's source uses K&R-style definitions and unprototyped declarations
  -- (`int foo()` meaning "any args"). Modern C compilers default to C23,
  -- where `()` means `(void)` and the K&R bodies are reported as
  -- prototype mismatches. Force gnu89 so the legacy semantics apply, and
  -- silence the residual -W warnings.
  #[ "-O2", "-DBIT64", "-DNOSHORTS", "-fPIC", "-std=gnu89",
     "-Wno-implicit-function-declaration",
     "-Wno-deprecated-non-prototype",
     "-Wno-old-style-definition",
     "-I", inc.toString ]

private def csdpOTarget (pkg : Package) (src : String) :
    FetchM (Job FilePath) := do
  let stem := src.dropEnd 2
  let oFile := pkg.dir / defaultBuildDir / "csdp" / s!"{stem}.o"
  let srcTarget ← inputTextFile <| pkg.dir / "csdp" / "lib" / src
  buildFileAfterDep oFile srcTarget fun srcFile => do
    compileO oFile srcFile (csdpCFlags pkg)

extern_lib csdp (pkg) := do
  let name := nameToStaticLib "csdp"
  let oTargets ← csdpSrcs.mapM (csdpOTarget pkg)
  buildStaticLib (pkg.staticLibDir / name) oTargets

/-! ## Lean ↔ CSDP bridge. -/

def bridgeSrcs : Array String := #["lean_csdp.c", "lean_csdp_bridge.c"]

private def bridgeOTarget (pkg : Package) (src : String) :
    FetchM (Job FilePath) := do
  let stem := src.dropEnd 2
  let oFile := pkg.dir / defaultBuildDir / "ffi" / s!"{stem}.o"
  let srcTarget ← inputTextFile <| pkg.dir / "ffi" / src
  buildFileAfterDep oFile srcTarget fun srcFile => do
    let leanInc := (← getLeanIncludeDir).toString
    let csdpInc := (pkg.dir / "csdp" / "include").toString
    let ffiInc  := (pkg.dir / "ffi").toString
    compileO oFile srcFile #[
      "-O2", "-DBIT64", "-fPIC",
      "-I", leanInc,
      "-I", csdpInc,
      "-I", ffiInc
    ]

extern_lib leancsdp_ffi (pkg) := do
  let name := nameToStaticLib "leancsdp_ffi"
  let oTargets ← bridgeSrcs.mapM (bridgeOTarget pkg)
  buildStaticLib (pkg.staticLibDir / name) oTargets

/-! ## Lean library and executables. -/

@[default_target]
lean_lib LeanCsdp where
  precompileModules := true
  moreLinkArgs :=
    let csdp := defaultBuildDir / "lib" / nameToStaticLib "csdp"
    let bridge := defaultBuildDir / "lib" / nameToStaticLib "leancsdp_ffi"
    -- Order matters: bridge depends on csdp; csdp depends on BLAS/LAPACK.
    #[bridge.toString, csdp.toString] ++ blasLapackLinkArgs

lean_exe «csdp-example» where
  root := `Main
  moreLinkArgs :=
    let csdp := defaultBuildDir / "lib" / nameToStaticLib "csdp"
    let bridge := defaultBuildDir / "lib" / nameToStaticLib "leancsdp_ffi"
    #[bridge.toString, csdp.toString] ++ blasLapackLinkArgs
