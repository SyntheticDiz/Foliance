#include "foliance_snowball.h"
#include "header.h"
#include "stem_UTF_8_dutch.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

struct foliance_dutch_stemmer {
    struct SN_env *environment;
};

foliance_dutch_stemmer *foliance_dutch_stemmer_create(void) {
    foliance_dutch_stemmer *stemmer = (foliance_dutch_stemmer *)malloc(sizeof(*stemmer));
    if (!stemmer) return NULL;
    stemmer->environment = dutch_UTF_8_create_env();
    if (!stemmer->environment) {
        free(stemmer);
        return NULL;
    }
    return stemmer;
}

void foliance_dutch_stemmer_destroy(foliance_dutch_stemmer *stemmer) {
    if (!stemmer) return;
    dutch_UTF_8_close_env(stemmer->environment);
    free(stemmer);
}

size_t foliance_dutch_stemmer_stem(foliance_dutch_stemmer *stemmer,
                               const char *input, size_t input_length,
                               char *output, size_t output_capacity) {
    if (!stemmer || (!input && input_length != 0) || !output || input_length > 2147483647u) return SIZE_MAX;
    struct SN_env *environment = stemmer->environment;
    if (SN_set_current(environment, (int)input_length, (const symbol *)input) < 0) return SIZE_MAX;
    if (dutch_UTF_8_stem(environment) < 0 || environment->l < 0) return SIZE_MAX;
    size_t length = (size_t)environment->l;
    if (length > output_capacity) return length;
    if (length != 0) memcpy(output, environment->p, length);
    return length;
}
