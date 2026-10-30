#ifndef Foliance_RAPIDFUZZ_H
#define Foliance_RAPIDFUZZ_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Inputs are Unicode scalar values, not UTF-8 bytes or UTF-16 code units. */
size_t foliance_levenshtein_scalars(const uint32_t *left, size_t left_length,
                                const uint32_t *right, size_t right_length,
                                size_t score_cutoff);

#ifdef __cplusplus
}
#endif
#endif
