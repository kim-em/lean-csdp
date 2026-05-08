#ifndef LEAN_CSDP_H
#define LEAN_CSDP_H

#ifdef __cplusplus
extern "C" {
#endif

/*
 * High-level entry point for solving an SDP via CSDP's easy_sdp interface.
 *
 * Block representation: block_sizes[i] is the size of the i-th block. A
 * positive value denotes an SDP block (symmetric PSD); a negative value
 * denotes an LP-style diagonal block of size |block_sizes[i]|.
 *
 * Sparse triplet format for C and the constraint matrices uses 1-indexed
 * row/column/block/constraint values, matching CSDP's native indexing.
 * Only the upper triangle (i <= j) of each block needs to be supplied;
 * CSDP assumes symmetry.
 *
 * Output buffer layout (for X_out and Z_out): each block contributes a
 * contiguous segment, in the order given by block_sizes. SDP blocks of
 * size n contribute n*n entries in column-major order; diagonal blocks
 * of size n contribute n entries. The caller is responsible for sizing
 * X_out / Z_out to lean_csdp_blockmatrix_size(nblocks, block_sizes).
 *
 * Returns the CSDP return code: 0 success, otherwise a CSDP failure code.
 */
int lean_csdp_solve(
    int nblocks,
    const int *block_sizes,
    int num_constraints,
    const double *b,
    /* C matrix (sparse upper triangle) */
    int c_nnz,
    const int *c_blocks,
    const int *c_i,
    const int *c_j,
    const double *c_vals,
    /* Constraint matrices (sparse upper triangle, sorted by constraint then block) */
    int a_nnz,
    const int *a_constraints,
    const int *a_blocks,
    const int *a_i,
    const int *a_j,
    const double *a_vals,
    double constant_offset,
    /* Outputs */
    double *pobj_out,
    double *dobj_out,
    double *X_out,
    double *y_out,
    double *Z_out);

/* Total number of doubles needed for X / Z output buffers. */
long lean_csdp_blockmatrix_size(int nblocks, const int *block_sizes);

/* Total ambient dimension (sum of |block_sizes[i]|). */
int lean_csdp_total_dim(int nblocks, const int *block_sizes);

#ifdef __cplusplus
}
#endif

#endif
