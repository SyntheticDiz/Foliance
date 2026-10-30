#include "foliance_rapidfuzz.h"
#include "rapidfuzz/distance/Levenshtein.hpp"
#include <vector>

extern "C" size_t foliance_levenshtein_scalars(const uint32_t *left, size_t left_length,
                                            const uint32_t *right, size_t right_length,
                                            size_t score_cutoff) {
    if ((!left && left_length != 0) || (!right && right_length != 0)) return score_cutoff + 1;
    const std::vector<uint32_t> lhs = left_length ? std::vector<uint32_t>(left, left + left_length) : std::vector<uint32_t>();
    const std::vector<uint32_t> rhs = right_length ? std::vector<uint32_t>(right, right + right_length) : std::vector<uint32_t>();
    return rapidfuzz::levenshtein_distance(lhs, rhs, {1, 1, 1}, score_cutoff);
}
