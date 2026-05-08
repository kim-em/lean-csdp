/*
 * Lean-callable bridge for lean_csdp_solve.
 *
 * The Lean side packs all integer arrays into a single ByteArray (4 bytes
 * per int32, little-endian on every platform Lean targets) and all double
 * arrays into FloatArrays. This file unpacks them, calls lean_csdp_solve,
 * and returns the result as a Lean ADT.
 */

#include <lean/lean.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#include "lean_csdp.h"

static inline const int *byte_array_as_int(b_lean_obj_arg arr) {
  return (const int *)lean_sarray_cptr(arr);
}

static inline const double *float_array_cptr_const(b_lean_obj_arg arr) {
  return lean_float_array_cptr(arr);
}

/*
 * Returns the X / Z output buffer length needed for a given block_sizes
 * ByteArray. Used by the Lean side to size the output FloatArrays.
 */
LEAN_EXPORT uint64_t lean_csdp_blockmatrix_size_ffi(b_lean_obj_arg block_sizes) {
  int nblocks = (int)(lean_sarray_size(block_sizes) / sizeof(int));
  long sz = lean_csdp_blockmatrix_size(nblocks, byte_array_as_int(block_sizes));
  return (uint64_t)sz;
}

LEAN_EXPORT uint32_t lean_csdp_total_dim_ffi(b_lean_obj_arg block_sizes) {
  int nblocks = (int)(lean_sarray_size(block_sizes) / sizeof(int));
  return (uint32_t)lean_csdp_total_dim(nblocks,
                                       byte_array_as_int(block_sizes));
}

/*
 * Solve an SDP. Returns a Lean structure
 *   { ret : Int32, pobj : Float, dobj : Float,
 *     X : FloatArray, y : FloatArray, Z : FloatArray }
 *
 * `block_sizes`, `c_blocks`, `c_i`, `c_j`, `a_constraints`, `a_blocks`,
 * `a_i`, `a_j` are ByteArrays of int32 entries.
 * `b`, `c_vals`, `a_vals` are FloatArrays.
 */
LEAN_EXPORT lean_obj_res lean_csdp_solve_ffi(
    b_lean_obj_arg block_sizes,
    b_lean_obj_arg b_arr,
    b_lean_obj_arg c_blocks, b_lean_obj_arg c_i, b_lean_obj_arg c_j,
    b_lean_obj_arg c_vals,
    b_lean_obj_arg a_constraints, b_lean_obj_arg a_blocks,
    b_lean_obj_arg a_i, b_lean_obj_arg a_j, b_lean_obj_arg a_vals,
    double constant_offset) {
  int nblocks = (int)(lean_sarray_size(block_sizes) / sizeof(int));
  int num_constraints = (int)lean_sarray_size(b_arr);
  int c_nnz = (int)(lean_sarray_size(c_blocks) / sizeof(int));
  int a_nnz = (int)(lean_sarray_size(a_blocks) / sizeof(int));

  long X_size = lean_csdp_blockmatrix_size(nblocks,
                                           byte_array_as_int(block_sizes));

  /*
   * Allocate output FloatArrays as scalar arrays of doubles. Lean's
   * FloatArray is a scalar-array object with elem_size=sizeof(double).
   */
  lean_object *X_out = lean_alloc_sarray(sizeof(double), (size_t)X_size,
                                         (size_t)X_size);
  lean_object *Z_out = lean_alloc_sarray(sizeof(double), (size_t)X_size,
                                         (size_t)X_size);
  lean_object *y_out = lean_alloc_sarray(sizeof(double),
                                         (size_t)num_constraints,
                                         (size_t)num_constraints);

  double pobj = 0.0, dobj = 0.0;
  int ret = lean_csdp_solve(
      nblocks, byte_array_as_int(block_sizes),
      num_constraints, float_array_cptr_const(b_arr),
      c_nnz, byte_array_as_int(c_blocks), byte_array_as_int(c_i),
      byte_array_as_int(c_j), float_array_cptr_const(c_vals),
      a_nnz, byte_array_as_int(a_constraints), byte_array_as_int(a_blocks),
      byte_array_as_int(a_i), byte_array_as_int(a_j),
      float_array_cptr_const(a_vals),
      constant_offset, &pobj, &dobj,
      lean_float_array_cptr(X_out), lean_float_array_cptr(y_out),
      lean_float_array_cptr(Z_out));

  /*
   * Build the Lean `RawSolution` ctor.
   *
   * Lean lays out structure fields with object-pointer fields first (in
   * declaration order) and scalar fields after (also in declaration order).
   * `RawSolution` has:
   *   ret  : Nat        -- object pointer (small values are tagged scalars)
   *   pobj : Float      -- scalar (double, 8 bytes)
   *   dobj : Float      -- scalar (double, 8 bytes)
   *   X    : FloatArray -- object pointer
   *   y    : FloatArray -- object pointer
   *   Z    : FloatArray -- object pointer
   *
   * So the ctor has 4 object slots (ret, X, y, Z, in that order) and a
   * 16-byte scalar area holding pobj at offset 0 and dobj at offset 8.
   */
  lean_object *res = lean_alloc_ctor(0, 4, 2 * sizeof(double));
  /* Map negative (e.g. -1 OOM) to a nonzero positive sentinel, success = 0. */
  unsigned ret_u = (ret < 0) ? 99u : (unsigned)ret;
  lean_ctor_set(res, 0, lean_unsigned_to_nat(ret_u));
  lean_ctor_set(res, 1, X_out);
  lean_ctor_set(res, 2, y_out);
  lean_ctor_set(res, 3, Z_out);
  lean_ctor_set_float(res, sizeof(void *) * 4, pobj);
  lean_ctor_set_float(res, sizeof(void *) * 4 + sizeof(double), dobj);
  return res;
}
