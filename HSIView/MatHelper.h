// MatHelper.h
#ifndef MatHelper_h
#define MatHelper_h

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    double *data;    // length = dims[0] * dims[1] * dims[2]
    size_t dims[3];  // dims[0], dims[1], dims[2]
    int rank;        // должно быть 3
} MatCube3D;

bool load_first_3d_double_cube(const char *path,
                               MatCube3D *outCube,
                               char *outName,
                               size_t outNameLen);

void free_cube(MatCube3D *cube);

#ifdef __cplusplus
}
#endif

#endif /* MatHelper_h */
