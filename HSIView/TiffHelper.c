// TiffHelper.c
#include "TiffHelper.h"
#include <tiffio.h>
#include <stdlib.h>

bool load_tiff_cube(const char *path, TiffCube3D *outCube) {
    if (!outCube) return false;

    outCube->data = NULL;
    outCube->rank = 0;
    outCube->dims[0] = outCube->dims[1] = outCube->dims[2] = 0;

    TIFF *tif = TIFFOpen(path, "r");
    if (!tif) {
        return false;
    }

    uint32 width = 0;
    uint32 height = 0;
    uint16 samplesPerPixel = 0;
    uint16 bitsPerSample = 0;
    uint16 planarConfig = 0;
    uint32 rowsPerStrip = 0;

    if (!TIFFGetField(tif, TIFFTAG_IMAGEWIDTH, &width) ||
        !TIFFGetField(tif, TIFFTAG_IMAGELENGTH, &height) ||
        !TIFFGetField(tif, TIFFTAG_SAMPLESPERPIXEL, &samplesPerPixel) ||
        !TIFFGetField(tif, TIFFTAG_BITSPERSAMPLE, &bitsPerSample) ||
        !TIFFGetField(tif, TIFFTAG_PLANARCONFIG, &planarConfig) ||
        !TIFFGetField(tif, TIFFTAG_ROWSPERSTRIP, &rowsPerStrip)) {
        TIFFClose(tif);
        return false;
    }

    // Поддерживаем только 8 бит, planar separate (как твой файл)
    if (bitsPerSample != 8 || planarConfig != PLANARCONFIG_SEPARATE) {
        TIFFClose(tif);
        return false;
    }

    tsize_t stripSize = TIFFStripSize(tif);
    tstrip_t totalStrips = TIFFNumberOfStrips(tif);

    if (samplesPerPixel == 0 || totalStrips == 0) {
        TIFFClose(tif);
        return false;
    }

    tstrip_t stripsPerPlane = totalStrips / samplesPerPixel;

    size_t W = (size_t)width;
    size_t H = (size_t)height;
    size_t C = (size_t)samplesPerPixel;
    size_t planeSize = W * H;
    size_t total = planeSize * C;

    double *data = (double *)malloc(total * sizeof(double));
    if (!data) {
        TIFFClose(tif);
        return false;
    }

    for (uint16 s = 0; s < samplesPerPixel; ++s) {
        size_t written = 0;

        for (tstrip_t j = 0; j < stripsPerPlane; ++j) {
            tstrip_t stripIndex = s * stripsPerPlane + j;

            tsize_t bufSize = stripSize;
            uint8 *buf = (uint8 *)_TIFFmalloc(bufSize);
            if (!buf) {
                free(data);
                TIFFClose(tif);
                return false;
            }

            tsize_t n = TIFFReadEncodedStrip(tif, stripIndex, buf, bufSize);
            if (n < 0) {
                _TIFFfree(buf);
                free(data);
                TIFFClose(tif);
                return false;
            }

            size_t bytes = (size_t)n;
            for (size_t i = 0; i < bytes && written < planeSize; ++i, ++written) {
                size_t row = written / W;
                size_t col = written % W;
                size_t colMajorIdx = row + H * (col + W * (size_t)s);
                // Сохраняем как есть (0-255), без нормализации
                data[colMajorIdx] = (double)buf[i];
            }

            _TIFFfree(buf);
        }
    }

    TIFFClose(tif);

    outCube->data = data;
    outCube->rank = 3;
    outCube->dims[0] = H;
    outCube->dims[1] = W;
    outCube->dims[2] = C;

    return true;
}

void free_tiff_cube(TiffCube3D *cube) {
    if (!cube) return;
    if (cube->data) {
        free(cube->data);
        cube->data = NULL;
    }
}
