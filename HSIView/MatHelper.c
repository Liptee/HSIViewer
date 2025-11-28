// MatHelper.c
#include "MatHelper.h"
#include <matio.h>   // заголовок из libmatio
#include <stdlib.h>
#include <string.h>

bool load_first_3d_double_cube(const char *path,
                               MatCube3D *outCube,
                               char *outName,
                               size_t outNameLen)
{
    if (!outCube) return false;
    outCube->data = NULL;
    outCube->rank = 0;
    outCube->dims[0] = outCube->dims[1] = outCube->dims[2] = 0;

    mat_t *mat = Mat_Open(path, MAT_ACC_RDONLY);
    if (!mat) {
        return false;
    }

    matvar_t *info = NULL;
    bool ok = false;

    while ((info = Mat_VarReadNextInfo(mat)) != NULL) {
        // Поддерживаем 3D массивы различных типов
        if (info->rank == 3 &&
            (info->class_type == MAT_C_DOUBLE || 
             info->class_type == MAT_C_SINGLE ||
             info->class_type == MAT_C_UINT8 ||
             info->class_type == MAT_C_UINT16 ||
             info->class_type == MAT_C_INT8 ||
             info->class_type == MAT_C_INT16)) {

            matvar_t *full = Mat_VarRead(mat, info->name);
            if (!full || !full->data) {
                if (full) Mat_VarFree(full);
                Mat_VarFree(info);
                continue;
            }

            // Проверяем поддерживаемые типы
            if (!(full->class_type == MAT_C_DOUBLE || 
                  full->class_type == MAT_C_SINGLE ||
                  full->class_type == MAT_C_UINT8 ||
                  full->class_type == MAT_C_UINT16 ||
                  full->class_type == MAT_C_INT8 ||
                  full->class_type == MAT_C_INT16)) {
                Mat_VarFree(full);
                Mat_VarFree(info);
                continue;
            }

            size_t d0 = full->dims[0];
            size_t d1 = full->dims[1];
            size_t d2 = full->dims[2];
            size_t total = d0 * d1 * d2;

            double *buf = (double *)malloc(total * sizeof(double));
            if (!buf) {
                Mat_VarFree(full);
                Mat_VarFree(info);
                break;
            }

            // Конвертируем различные типы в double для единообразия
            if (full->class_type == MAT_C_DOUBLE && full->data_type == MAT_T_DOUBLE) {
                memcpy(buf, full->data, total * sizeof(double));
            } else if (full->class_type == MAT_C_SINGLE && full->data_type == MAT_T_SINGLE) {
                float *src = (float *)full->data;
                for (size_t i = 0; i < total; ++i) {
                    buf[i] = (double)src[i];
                }
            } else if (full->class_type == MAT_C_UINT8 && full->data_type == MAT_T_UINT8) {
                uint8_t *src = (uint8_t *)full->data;
                for (size_t i = 0; i < total; ++i) {
                    buf[i] = (double)src[i];
                }
            } else if (full->class_type == MAT_C_UINT16 && full->data_type == MAT_T_UINT16) {
                uint16_t *src = (uint16_t *)full->data;
                for (size_t i = 0; i < total; ++i) {
                    buf[i] = (double)src[i];
                }
            } else if (full->class_type == MAT_C_INT8 && full->data_type == MAT_T_INT8) {
                int8_t *src = (int8_t *)full->data;
                for (size_t i = 0; i < total; ++i) {
                    buf[i] = (double)src[i];
                }
            } else if (full->class_type == MAT_C_INT16 && full->data_type == MAT_T_INT16) {
                int16_t *src = (int16_t *)full->data;
                for (size_t i = 0; i < total; ++i) {
                    buf[i] = (double)src[i];
                }
            } else {
                free(buf);
                Mat_VarFree(full);
                Mat_VarFree(info);
                continue;
            }

            outCube->data = buf;
            outCube->dims[0] = d0;
            outCube->dims[1] = d1;
            outCube->dims[2] = d2;
            outCube->rank = 3;

            if (outName && outNameLen > 0) {
                strncpy(outName, full->name, outNameLen - 1);
                outName[outNameLen - 1] = '\0';
            }

            Mat_VarFree(full);
            Mat_VarFree(info);
            ok = true;
            break;
        }

        Mat_VarFree(info);
    }

    Mat_Close(mat);
    return ok;
}

void free_cube(MatCube3D *cube)
{
    if (!cube) return;
    if (cube->data) {
        free(cube->data);
        cube->data = NULL;
    }
}
