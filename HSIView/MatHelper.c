// MatHelper.c
#include "MatHelper.h"
#include <matio.h>   // заголовок из libmatio
#include <stdlib.h>
#include <string.h>

static bool is_supported_class(enum matio_classes class_type) {
    switch (class_type) {
        case MAT_C_DOUBLE:
        case MAT_C_SINGLE:
        case MAT_C_UINT8:
        case MAT_C_UINT16:
        case MAT_C_INT8:
        case MAT_C_INT16:
            return true;
        default:
            return false;
    }
}

static bool is_supported_type(enum matio_classes class_type,
                              enum matio_types data_type) {
    switch (class_type) {
        case MAT_C_DOUBLE:
            return data_type == MAT_T_DOUBLE;
        case MAT_C_SINGLE:
            return data_type == MAT_T_SINGLE;
        case MAT_C_UINT8:
            return data_type == MAT_T_UINT8;
        case MAT_C_UINT16:
            return data_type == MAT_T_UINT16;
        case MAT_C_INT8:
            return data_type == MAT_T_INT8;
        case MAT_C_INT16:
            return data_type == MAT_T_INT16;
        default:
            return false;
    }
}

static MatDataType map_data_type(enum matio_classes class_type) {
    switch (class_type) {
        case MAT_C_DOUBLE: return MAT_DATA_FLOAT64;
        case MAT_C_SINGLE: return MAT_DATA_FLOAT32;
        case MAT_C_UINT8:  return MAT_DATA_UINT8;
        case MAT_C_UINT16: return MAT_DATA_UINT16;
        case MAT_C_INT8:   return MAT_DATA_INT8;
        case MAT_C_INT16:  return MAT_DATA_INT16;
        default:           return MAT_DATA_FLOAT64;
    }
}

static bool is_supported_cube(matvar_t *var) {
    if (!var) return false;
    if (var->rank != 3) return false;
    if (!is_supported_class(var->class_type)) return false;
    return is_supported_type(var->class_type, var->data_type);
}

static bool copy_matvar_to_cube(matvar_t *var, MatCube3D *outCube) {
    if (!var || !outCube || !is_supported_cube(var) || !var->data) {
        return false;
    }
    
    size_t d0 = var->dims[0];
    size_t d1 = var->dims[1];
    size_t d2 = var->dims[2];
    size_t total = d0 * d1 * d2;
    
    void *buf = NULL;
    MatDataType dataType = map_data_type(var->class_type);
    
    size_t elementSize = 0;
    switch (dataType) {
        case MAT_DATA_FLOAT64: elementSize = sizeof(double); break;
        case MAT_DATA_FLOAT32: elementSize = sizeof(float); break;
        case MAT_DATA_UINT8: elementSize = sizeof(uint8_t); break;
        case MAT_DATA_UINT16: elementSize = sizeof(uint16_t); break;
        case MAT_DATA_INT8: elementSize = sizeof(int8_t); break;
        case MAT_DATA_INT16: elementSize = sizeof(int16_t); break;
        default: return false;
    }
    
    buf = malloc(total * elementSize);
    if (!buf) {
        return false;
    }
    
    memcpy(buf, var->data, total * elementSize);
    
    outCube->data = buf;
    outCube->dims[0] = d0;
    outCube->dims[1] = d1;
    outCube->dims[2] = d2;
    outCube->rank = 3;
    outCube->data_type = dataType;
    
    return true;
}

static void clear_cube(MatCube3D *cube) {
    if (!cube) return;
    cube->data = NULL;
    cube->rank = 0;
    cube->dims[0] = cube->dims[1] = cube->dims[2] = 0;
    cube->data_type = MAT_DATA_FLOAT64;
}

bool load_first_3d_double_cube(const char *path,
                               MatCube3D *outCube,
                               char *outName,
                               size_t outNameLen)
{
    if (!outCube) return false;
    MatCubeInfo *list = NULL;
    size_t count = 0;
    clear_cube(outCube);
    
    if (!list_mat_cube_variables(path, &list, &count) || count == 0) {
        if (list) {
            free_mat_cube_info(list);
        }
        return false;
    }
    
    const char *targetName = list[0].name;
    bool ok = load_cube_by_name(path, targetName, outCube, outName, outNameLen);
    free_mat_cube_info(list);
    return ok;
}

bool load_cube_by_name(const char *path,
                       const char *varName,
                       MatCube3D *outCube,
                       char *outName,
                       size_t outNameLen)
{
    if (!path || !varName || !outCube) {
        return false;
    }
    
    clear_cube(outCube);
    
    mat_t *mat = Mat_Open(path, MAT_ACC_RDONLY);
    if (!mat) {
        return false;
    }
    
    matvar_t *var = Mat_VarRead(mat, varName);
    if (!var) {
        Mat_Close(mat);
        return false;
    }
    
    bool ok = copy_matvar_to_cube(var, outCube);
    if (ok && outName && outNameLen > 0) {
        strncpy(outName, var->name, outNameLen - 1);
        outName[outNameLen - 1] = '\0';
    }
    
    Mat_VarFree(var);
    Mat_Close(mat);
    return ok;
}

bool list_mat_cube_variables(const char *path,
                             MatCubeInfo **outList,
                             size_t *outCount)
{
    if (!outList || !outCount) {
        return false;
    }
    
    *outList = NULL;
    *outCount = 0;
    
    mat_t *mat = Mat_Open(path, MAT_ACC_RDONLY);
    if (!mat) {
        return false;
    }
    
    size_t capacity = 0;
    MatCubeInfo *list = NULL;
    matvar_t *info = NULL;
    bool success = true;
    
    while ((info = Mat_VarReadNextInfo(mat)) != NULL) {
        if (is_supported_class(info->class_type) && info->rank == 3) {
            if (*outCount == capacity) {
                size_t newCap = capacity == 0 ? 4 : capacity * 2;
                MatCubeInfo *newList = realloc(list, newCap * sizeof(MatCubeInfo));
                if (!newList) {
                    success = false;
                    Mat_VarFree(info);
                    break;
                }
                list = newList;
                capacity = newCap;
            }
            
            MatCubeInfo *slot = &list[*outCount];
            memset(slot, 0, sizeof(MatCubeInfo));
            strncpy(slot->name, info->name, sizeof(slot->name) - 1);
            slot->name[sizeof(slot->name) - 1] = '\0';
            slot->dims[0] = info->dims[0];
            slot->dims[1] = info->dims[1];
            slot->dims[2] = info->dims[2];
            slot->data_type = map_data_type(info->class_type);
            (*outCount)++;
        }
        
        Mat_VarFree(info);
    }
    
    Mat_Close(mat);
    
    if (!success) {
        if (list) {
            free(list);
        }
        *outList = NULL;
        *outCount = 0;
        return false;
    }
    
    *outList = list;
    return true;
}

void free_mat_cube_info(MatCubeInfo *list) {
    if (list) {
        free(list);
    }
}

bool save_3d_cube(const char *path,
                  const char *varName,
                  const MatCube3D *cube)
{
    if (!path || !varName || !cube || !cube->data) {
        return false;
    }
    
    if (cube->rank != 3) {
        return false;
    }
    
    mat_t *mat = Mat_CreateVer(path, NULL, MAT_FT_MAT5);
    if (!mat) {
        return false;
    }
    
    size_t dims[3] = {cube->dims[0], cube->dims[1], cube->dims[2]};
    
    enum matio_classes class_type;
    enum matio_types data_type;
    size_t element_size;
    
    switch (cube->data_type) {
        case MAT_DATA_FLOAT64:
            class_type = MAT_C_DOUBLE;
            data_type = MAT_T_DOUBLE;
            element_size = sizeof(double);
            break;
            
        case MAT_DATA_FLOAT32:
            class_type = MAT_C_SINGLE;
            data_type = MAT_T_SINGLE;
            element_size = sizeof(float);
            break;
            
        case MAT_DATA_UINT8:
            class_type = MAT_C_UINT8;
            data_type = MAT_T_UINT8;
            element_size = sizeof(uint8_t);
            break;
            
        case MAT_DATA_UINT16:
            class_type = MAT_C_UINT16;
            data_type = MAT_T_UINT16;
            element_size = sizeof(uint16_t);
            break;
            
        case MAT_DATA_INT8:
            class_type = MAT_C_INT8;
            data_type = MAT_T_INT8;
            element_size = sizeof(int8_t);
            break;
            
        case MAT_DATA_INT16:
            class_type = MAT_C_INT16;
            data_type = MAT_T_INT16;
            element_size = sizeof(int16_t);
            break;
            
        default:
            Mat_Close(mat);
            return false;
    }
    
    size_t total = dims[0] * dims[1] * dims[2];
    void *data_copy = malloc(total * element_size);
    if (!data_copy) {
        Mat_Close(mat);
        return false;
    }
    
    memcpy(data_copy, cube->data, total * element_size);
    
    matvar_t *matvar = Mat_VarCreate(varName, class_type, data_type,
                                     3, dims, data_copy, MAT_F_DONT_COPY_DATA);
    
    if (!matvar) {
        free(data_copy);
        Mat_Close(mat);
        return false;
    }
    
    int result = Mat_VarWrite(mat, matvar, MAT_COMPRESSION_NONE);
    
    Mat_VarFree(matvar);
    Mat_Close(mat);
    
    return (result == 0);
}

bool save_wavelengths(const char *path,
                      const char *varName,
                      const double *wavelengths,
                      size_t count)
{
    if (!path || !varName || !wavelengths || count == 0) {
        return false;
    }
    
    mat_t *mat = Mat_Open(path, MAT_ACC_RDWR);
    if (!mat) {
        return false;
    }
    
    size_t dims[2] = {count, 1};
    
    double *data_copy = malloc(count * sizeof(double));
    if (!data_copy) {
        Mat_Close(mat);
        return false;
    }
    
    memcpy(data_copy, wavelengths, count * sizeof(double));
    
    matvar_t *matvar = Mat_VarCreate(varName, MAT_C_DOUBLE, MAT_T_DOUBLE,
                                     2, dims, data_copy, MAT_F_DONT_COPY_DATA);
    
    if (!matvar) {
        free(data_copy);
        Mat_Close(mat);
        return false;
    }
    
    int result = Mat_VarWrite(mat, matvar, MAT_COMPRESSION_NONE);
    
    Mat_VarFree(matvar);
    Mat_Close(mat);
    
    return (result == 0);
}

void free_cube(MatCube3D *cube)
{
    if (!cube) return;
    if (cube->data) {
        free(cube->data);
        cube->data = NULL;
    }
}
