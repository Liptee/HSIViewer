// TiffHelper.h
#ifndef TiffHelper_h
#define TiffHelper_h

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    double *data;    // длина = dims[0] * dims[1] * dims[2]
    size_t dims[3];  // (C, H, W)
    int rank;        // 3, если успешно
} TiffCube3D;

bool load_tiff_cube(const char *path, TiffCube3D *outCube);
void free_tiff_cube(TiffCube3D *cube);

#ifdef __cplusplus
}
#endif

#endif /* TiffHelper_h */
