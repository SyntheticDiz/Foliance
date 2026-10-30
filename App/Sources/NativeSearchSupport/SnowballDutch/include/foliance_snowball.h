#ifndef Foliance_SNOWBALL_H
#define Foliance_SNOWBALL_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct foliance_dutch_stemmer foliance_dutch_stemmer;
foliance_dutch_stemmer *foliance_dutch_stemmer_create(void);
void foliance_dutch_stemmer_destroy(foliance_dutch_stemmer *stemmer);
/* Returns output byte count (0 is a valid empty stem), required capacity if too small,
   or SIZE_MAX for invalid input or a Snowball runtime error. */
size_t foliance_dutch_stemmer_stem(foliance_dutch_stemmer *stemmer,
                               const char *input, size_t input_length,
                               char *output, size_t output_capacity);

#ifdef __cplusplus
}
#endif
#endif
