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

    // Поддерживаем только 8 бит, оба типа planar config
    if (bitsPerSample != 8) {
        TIFFClose(tif);
        return false;
    }
    
    // Поддерживаем CONTIG (interleaved) и SEPARATE (planar)
    if (planarConfig != PLANARCONFIG_CONTIG && planarConfig != PLANARCONFIG_SEPARATE) {
        TIFFClose(tif);
        return false;
    }

    tdir_t dirCount = TIFFNumberOfDirectories(tif);
    if (dirCount == 0) {
        dirCount = 1;
    }
    bool useDirectoriesAsChannels = (dirCount > 1 && samplesPerPixel == 1);

    size_t W = (size_t)width;
    size_t H = (size_t)height;
    size_t C = useDirectoriesAsChannels ? (size_t)dirCount : (size_t)samplesPerPixel;
    size_t planeSize = W * H;
    size_t total = planeSize * C;

    double *data = (double *)malloc(total * sizeof(double));
    if (!data) {
        TIFFClose(tif);
        return false;
    }

    if (useDirectoriesAsChannels) {
        for (tdir_t dir = 0; dir < dirCount; ++dir) {
            if (!TIFFSetDirectory(tif, dir)) {
                free(data);
                TIFFClose(tif);
                return false;
            }

            uint32 dirWidth = 0;
            uint32 dirHeight = 0;
            uint16 dirSamples = 0;
            uint16 dirBits = 0;
            uint16 dirPlanar = 0;
            uint32 dirRowsPerStrip = 0;

            if (!TIFFGetField(tif, TIFFTAG_IMAGEWIDTH, &dirWidth) ||
                !TIFFGetField(tif, TIFFTAG_IMAGELENGTH, &dirHeight) ||
                !TIFFGetField(tif, TIFFTAG_SAMPLESPERPIXEL, &dirSamples) ||
                !TIFFGetField(tif, TIFFTAG_BITSPERSAMPLE, &dirBits) ||
                !TIFFGetField(tif, TIFFTAG_PLANARCONFIG, &dirPlanar) ||
                !TIFFGetField(tif, TIFFTAG_ROWSPERSTRIP, &dirRowsPerStrip)) {
                free(data);
                TIFFClose(tif);
                return false;
            }

            if (dirWidth != width || dirHeight != height || dirBits != 8 || dirSamples != 1) {
                free(data);
                TIFFClose(tif);
                return false;
            }

            tsize_t stripSize = TIFFStripSize(tif);
            tstrip_t totalStrips = TIFFNumberOfStrips(tif);
            size_t written = 0;

            for (tstrip_t strip = 0; strip < totalStrips; ++strip) {
                uint8 *buf = (uint8 *)_TIFFmalloc(stripSize);
                if (!buf) {
                    free(data);
                    TIFFClose(tif);
                    return false;
                }

                tsize_t n = TIFFReadEncodedStrip(tif, strip, buf, stripSize);
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
                    size_t colMajorIdx = row + H * (col + W * (size_t)dir);
                    data[colMajorIdx] = (double)buf[i];
                }

                _TIFFfree(buf);
            }
        }
    } else if (planarConfig == PLANARCONFIG_CONTIG) {
        // CONTIG: каналы чередуются (R0,G0,B0,R1,G1,B1,...)
        tstrip_t totalStrips = TIFFNumberOfStrips(tif);
        tsize_t stripSize = TIFFStripSize(tif);
        
        size_t pixelIndex = 0;
        for (tstrip_t strip = 0; strip < totalStrips; ++strip) {
            uint8 *buf = (uint8 *)_TIFFmalloc(stripSize);
            if (!buf) {
                free(data);
                TIFFClose(tif);
                return false;
            }

            tsize_t n = TIFFReadEncodedStrip(tif, strip, buf, stripSize);
            if (n < 0) {
                _TIFFfree(buf);
                free(data);
                TIFFClose(tif);
                return false;
            }

            // Читаем interleaved данные: R0 G0 B0 R1 G1 B1 ...
            size_t numPixels = (size_t)n / C;
            for (size_t p = 0; p < numPixels && pixelIndex < planeSize; ++p, ++pixelIndex) {
                size_t row = pixelIndex / W;
                size_t col = pixelIndex % W;
                
                for (size_t c = 0; c < C; ++c) {
                    uint8 value = buf[p * C + c];
                    size_t colMajorIdx = row + H * (col + W * c);
                    data[colMajorIdx] = (double)value;
                }
            }

            _TIFFfree(buf);
        }
    } else {
        // SEPARATE: каналы идут отдельными плоскостями
        tsize_t stripSize = TIFFStripSize(tif);
        tstrip_t totalStrips = TIFFNumberOfStrips(tif);

        if (samplesPerPixel == 0 || totalStrips == 0) {
            free(data);
            TIFFClose(tif);
            return false;
        }

        tstrip_t stripsPerPlane = totalStrips / samplesPerPixel;

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
