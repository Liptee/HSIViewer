// MatHelper.h
#ifndef MatHelper_h
#define MatHelper_h

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    MAT_DATA_FLOAT64 = 0,
    MAT_DATA_FLOAT32 = 1,
    MAT_DATA_UINT8 = 2,
    MAT_DATA_UINT16 = 3,
    MAT_DATA_INT8 = 4,
    MAT_DATA_INT16 = 5
} MatDataType;

typedef struct {
    void *data;      // Указатель на данные (может быть double*, float*, uint8_t*, и т.д.)
    size_t dims[3];  // dims[0], dims[1], dims[2]
    int rank;        // должно быть 3
    MatDataType data_type;  // Тип данных
} MatCube3D;

typedef struct {
    char name[256];
    size_t dims[3];
    MatDataType data_type;
} MatCubeInfo;

bool load_first_3d_double_cube(const char *path,
                               MatCube3D *outCube,
                               char *outName,
                               size_t outNameLen);

bool load_cube_by_name(const char *path,
                       const char *varName,
                       MatCube3D *outCube,
                       char *outName,
                       size_t outNameLen);

bool list_mat_cube_variables(const char *path,
                             MatCubeInfo **outList,
                             size_t *outCount);

void free_mat_cube_info(MatCubeInfo *list);

bool save_3d_cube(const char *path,
                  const char *varName,
                  const MatCube3D *cube);

bool save_wavelengths(const char *path,
                      const char *varName,
                      const double *wavelengths,
                      size_t count);

void free_cube(MatCube3D *cube);

#ifdef __cplusplus
}
#endif

#endif /* MatHelper_h */
