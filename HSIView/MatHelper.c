// MatHelper.c
#include "MatHelper.h"

#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <zlib.h>

enum {
    MI_INT8 = 1,
    MI_UINT8 = 2,
    MI_INT16 = 3,
    MI_UINT16 = 4,
    MI_INT32 = 5,
    MI_UINT32 = 6,
    MI_SINGLE = 7,
    MI_DOUBLE = 9,
    MI_INT64 = 12,
    MI_UINT64 = 13,
    MI_MATRIX = 14,
    MI_COMPRESSED = 15,
    MI_UTF8 = 16,
    MI_UTF16 = 17,
    MI_UTF32 = 18
};

enum {
    MX_DOUBLE_CLASS = 6,
    MX_SINGLE_CLASS = 7,
    MX_INT8_CLASS = 8,
    MX_UINT8_CLASS = 9,
    MX_INT16_CLASS = 10,
    MX_UINT16_CLASS = 11
};

typedef struct {
    const uint8_t *data;
    size_t size;
    size_t pos;
    bool little_endian;
} MatReader;

typedef struct {
    uint32_t type;
    uint32_t num_bytes;
    const uint8_t *payload;
} MatElement;

typedef struct {
    bool supported;
    char name[256];
    size_t dims[3];
    int rank;
    MatDataType data_type;
    const uint8_t *real_data;
    size_t real_data_bytes;
    size_t element_size;
} ParsedMatrix;

typedef struct {
    uint8_t *data;
    size_t size;
    bool little_endian;
    bool is_mapped;
} MatFileBuffer;

typedef bool (*MatMatrixVisitor)(const ParsedMatrix *matrix,
                                 bool little_endian,
                                 void *context,
                                 bool *stop);

static void clear_cube(MatCube3D *cube) {
    if (!cube) {
        return;
    }

    cube->data = NULL;
    cube->rank = 0;
    cube->dims[0] = 0;
    cube->dims[1] = 0;
    cube->dims[2] = 0;
    cube->data_type = MAT_DATA_FLOAT64;
}

static bool host_is_little_endian(void) {
    uint16_t marker = 1;
    return *((uint8_t *)&marker) == 1;
}

static uint16_t bswap16(uint16_t value) {
    return (uint16_t)((value << 8) | (value >> 8));
}

static uint32_t bswap32(uint32_t value) {
    return ((value & 0x000000FFU) << 24) |
           ((value & 0x0000FF00U) << 8) |
           ((value & 0x00FF0000U) >> 8) |
           ((value & 0xFF000000U) >> 24);
}

static uint64_t bswap64(uint64_t value) {
    return ((value & 0x00000000000000FFULL) << 56) |
           ((value & 0x000000000000FF00ULL) << 40) |
           ((value & 0x0000000000FF0000ULL) << 24) |
           ((value & 0x00000000FF000000ULL) << 8) |
           ((value & 0x000000FF00000000ULL) >> 8) |
           ((value & 0x0000FF0000000000ULL) >> 24) |
           ((value & 0x00FF000000000000ULL) >> 40) |
           ((value & 0xFF00000000000000ULL) >> 56);
}

static uint32_t read_u32(const uint8_t *bytes, bool little_endian) {
    uint32_t value = (uint32_t)bytes[0] |
                     ((uint32_t)bytes[1] << 8) |
                     ((uint32_t)bytes[2] << 16) |
                     ((uint32_t)bytes[3] << 24);
    if (!little_endian) {
        value = bswap32(value);
    }
    return value;
}

static uint64_t read_u64(const uint8_t *bytes, bool little_endian) {
    uint64_t value = (uint64_t)bytes[0] |
                     ((uint64_t)bytes[1] << 8) |
                     ((uint64_t)bytes[2] << 16) |
                     ((uint64_t)bytes[3] << 24) |
                     ((uint64_t)bytes[4] << 32) |
                     ((uint64_t)bytes[5] << 40) |
                     ((uint64_t)bytes[6] << 48) |
                     ((uint64_t)bytes[7] << 56);
    if (!little_endian) {
        value = bswap64(value);
    }
    return value;
}

static bool checked_mul_size(size_t a, size_t b, size_t *out) {
    if (!out) {
        return false;
    }
    if (a == 0 || b == 0) {
        *out = 0;
        return true;
    }
    if (a > SIZE_MAX / b) {
        return false;
    }
    *out = a * b;
    return true;
}

static bool checked_add_size(size_t a, size_t b, size_t *out) {
    if (!out) {
        return false;
    }
    if (a > SIZE_MAX - b) {
        return false;
    }
    *out = a + b;
    return true;
}

static bool count_elements(const size_t *dims, int rank, size_t *out_count) {
    if (!dims || !out_count || rank <= 0) {
        return false;
    }

    size_t total = 1;
    for (int i = 0; i < rank; i++) {
        if (dims[i] == 0) {
            return false;
        }
        if (!checked_mul_size(total, dims[i], &total)) {
            return false;
        }
    }

    *out_count = total;
    return true;
}

static size_t aligned8(size_t value) {
    if (value > SIZE_MAX - 7U) {
        return SIZE_MAX;
    }
    return (value + 7U) & ~(size_t)7U;
}

static bool is_supported_numeric_class(uint32_t class_type) {
    switch (class_type) {
        case MX_DOUBLE_CLASS:
        case MX_SINGLE_CLASS:
        case MX_UINT8_CLASS:
        case MX_UINT16_CLASS:
        case MX_INT8_CLASS:
        case MX_INT16_CLASS:
            return true;
        default:
            return false;
    }
}

static bool map_numeric_mi_type(uint32_t mi_type,
                                MatDataType *data_type,
                                size_t *element_size) {
    if (!data_type || !element_size) {
        return false;
    }

    switch (mi_type) {
        case MI_DOUBLE:
            *data_type = MAT_DATA_FLOAT64;
            *element_size = sizeof(double);
            return true;
        case MI_SINGLE:
            *data_type = MAT_DATA_FLOAT32;
            *element_size = sizeof(float);
            return true;
        case MI_UINT8:
            *data_type = MAT_DATA_UINT8;
            *element_size = sizeof(uint8_t);
            return true;
        case MI_UINT16:
            *data_type = MAT_DATA_UINT16;
            *element_size = sizeof(uint16_t);
            return true;
        case MI_INT8:
            *data_type = MAT_DATA_INT8;
            *element_size = sizeof(int8_t);
            return true;
        case MI_INT16:
            *data_type = MAT_DATA_INT16;
            *element_size = sizeof(int16_t);
            return true;
        default:
            return false;
    }
}

static bool is_name_type(uint32_t type) {
    return type == MI_INT8 ||
           type == MI_UINT8 ||
           type == MI_UTF8 ||
           type == MI_UTF16 ||
           type == MI_UTF32;
}

static void copy_name_from_element(const MatElement *element,
                                   char *out_name,
                                   size_t out_len) {
    if (!out_name || out_len == 0) {
        return;
    }

    out_name[0] = '\0';
    if (!element || !element->payload || element->num_bytes == 0) {
        return;
    }

    size_t copy_len = element->num_bytes;
    if (copy_len > out_len - 1) {
        copy_len = out_len - 1;
    }

    memcpy(out_name, element->payload, copy_len);
    out_name[copy_len] = '\0';
}

static bool parse_dimensions_element(const MatElement *element,
                                     bool little_endian,
                                     size_t out_dims[3],
                                     int *out_rank) {
    if (!element || !element->payload || !out_dims || !out_rank) {
        return false;
    }

    size_t elem_size = 0;
    switch (element->type) {
        case MI_INT32:
        case MI_UINT32:
            elem_size = 4;
            break;
        case MI_INT64:
        case MI_UINT64:
            elem_size = 8;
            break;
        default:
            return false;
    }

    if (element->num_bytes == 0 || (element->num_bytes % elem_size) != 0) {
        return false;
    }

    size_t rank = element->num_bytes / elem_size;
    if (rank == 0 || rank > 16) {
        return false;
    }

    size_t dims[3] = {1, 1, 1};
    for (size_t i = 0; i < rank; i++) {
        uint64_t raw_value = 0;
        if (elem_size == 4) {
            uint32_t v = read_u32(element->payload + (i * 4), little_endian);
            if (element->type == MI_INT32) {
                int32_t signed_v = (int32_t)v;
                if (signed_v <= 0) {
                    return false;
                }
                raw_value = (uint64_t)signed_v;
            } else {
                if (v == 0) {
                    return false;
                }
                raw_value = (uint64_t)v;
            }
        } else {
            uint64_t v = read_u64(element->payload + (i * 8), little_endian);
            if (element->type == MI_INT64) {
                int64_t signed_v = (int64_t)v;
                if (signed_v <= 0) {
                    return false;
                }
                raw_value = (uint64_t)signed_v;
            } else {
                if (v == 0) {
                    return false;
                }
                raw_value = v;
            }
        }

        if (raw_value > SIZE_MAX) {
            return false;
        }

        if (i < 3) {
            dims[i] = (size_t)raw_value;
        }
    }

    out_dims[0] = dims[0];
    out_dims[1] = dims[1];
    out_dims[2] = dims[2];
    *out_rank = (int)rank;
    return true;
}

static bool read_element(MatReader *reader, MatElement *out_element) {
    if (!reader || !out_element) {
        return false;
    }

    if (reader->pos > reader->size || reader->size - reader->pos < 8) {
        return false;
    }

    const uint8_t *base = reader->data + reader->pos;
    uint32_t word0 = read_u32(base, reader->little_endian);
    uint32_t word1 = read_u32(base + 4, reader->little_endian);

    uint32_t type = 0;
    uint32_t num_bytes = 0;
    const uint8_t *payload = NULL;
    size_t next_pos = 0;

    if ((word0 >> 16U) != 0U) {
        type = (word0 & 0xFFFFU);
        num_bytes = (word0 >> 16U) & 0xFFFFU;
        if (num_bytes > 4U) {
            return false;
        }

        payload = base + 4;
        next_pos = reader->pos + 8;
    } else {
        type = word0;
        num_bytes = word1;
        size_t payload_pos = 0;
        if (!checked_add_size(reader->pos, 8, &payload_pos)) {
            return false;
        }
        if (payload_pos > reader->size || num_bytes > (reader->size - payload_pos)) {
            return false;
        }
        size_t payload_end = payload_pos + (size_t)num_bytes;

        size_t padded = aligned8((size_t)num_bytes);
        if (padded == SIZE_MAX) {
            return false;
        }
        if (!checked_add_size(payload_pos, padded, &next_pos)) {
            return false;
        }
        if (next_pos > reader->size) {
            // Некоторые MAT-файлы не дописывают padding в самом конце элемента.
            next_pos = payload_end;
        }

        payload = reader->data + payload_pos;
    }

    out_element->type = type;
    out_element->num_bytes = num_bytes;
    out_element->payload = payload;

    reader->pos = next_pos;
    return true;
}

static bool parse_matrix_payload(const uint8_t *payload,
                                 size_t payload_size,
                                 bool little_endian,
                                 ParsedMatrix *out_matrix) {
    if (!payload || !out_matrix) {
        return false;
    }

    memset(out_matrix, 0, sizeof(ParsedMatrix));
    out_matrix->supported = false;
    out_matrix->dims[0] = 1;
    out_matrix->dims[1] = 1;
    out_matrix->dims[2] = 1;
    out_matrix->rank = 0;

    MatReader sub_reader = {
        .data = payload,
        .size = payload_size,
        .pos = 0,
        .little_endian = little_endian
    };

    bool has_flags = false;
    bool has_dims = false;
    bool has_name = false;
    bool has_real_data = false;

    while (sub_reader.pos + 8 <= sub_reader.size) {
        MatElement element;
        if (!read_element(&sub_reader, &element)) {
            return false;
        }

        if (!has_flags && element.type == MI_UINT32 && element.num_bytes >= 8) {
            uint32_t flags0 = read_u32(element.payload, little_endian);
            uint32_t class_type = flags0 & 0xFFU;
            bool is_complex = (flags0 & 0x0800U) != 0U;

            if (!is_complex && is_supported_numeric_class(class_type)) {
                out_matrix->supported = true;
            } else {
                out_matrix->supported = false;
            }

            has_flags = true;
            continue;
        }

        if (!has_dims &&
            (element.type == MI_INT32 || element.type == MI_UINT32 ||
             element.type == MI_INT64 || element.type == MI_UINT64)) {
            if (!parse_dimensions_element(&element, little_endian, out_matrix->dims, &out_matrix->rank)) {
                out_matrix->supported = false;
                out_matrix->rank = 0;
            }
            has_dims = true;
            continue;
        }

        if (!has_name && is_name_type(element.type)) {
            copy_name_from_element(&element, out_matrix->name, sizeof(out_matrix->name));
            has_name = true;
            continue;
        }

        if (!has_real_data &&
            out_matrix->supported &&
            has_flags) {
            MatDataType mapped_type = MAT_DATA_FLOAT64;
            size_t mapped_element_size = 0;
            if (map_numeric_mi_type(element.type, &mapped_type, &mapped_element_size)) {
                out_matrix->data_type = mapped_type;
                out_matrix->element_size = mapped_element_size;
                out_matrix->real_data = element.payload;
                out_matrix->real_data_bytes = element.num_bytes;
                has_real_data = true;
                continue;
            }
        }
    }

    if (!has_flags || !has_dims) {
        out_matrix->supported = false;
        return true;
    }

    if (!has_name) {
        out_matrix->name[0] = '\0';
    }

    if (!out_matrix->supported || !has_real_data) {
        out_matrix->supported = false;
        return true;
    }

    size_t expected_count = 0;
    if (!count_elements(out_matrix->dims, out_matrix->rank, &expected_count)) {
        out_matrix->supported = false;
        return true;
    }

    size_t expected_bytes = 0;
    if (!checked_mul_size(expected_count, out_matrix->element_size, &expected_bytes)) {
        out_matrix->supported = false;
        return true;
    }

    if (expected_bytes != out_matrix->real_data_bytes) {
        out_matrix->supported = false;
    }

    return true;
}

static bool decompress_zlib(const uint8_t *input,
                            size_t input_size,
                            uint8_t **out_data,
                            size_t *out_size) {
    if (!input || !out_data || !out_size || input_size == 0 || input_size > UINT_MAX) {
        return false;
    }

    *out_data = NULL;
    *out_size = 0;

    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_size;

    if (inflateInit(&stream) != Z_OK) {
        return false;
    }

    size_t capacity = 64 * 1024;

    uint8_t *buffer = (uint8_t *)malloc(capacity);
    if (!buffer) {
        inflateEnd(&stream);
        return false;
    }

    int z_result = Z_OK;
    while (z_result == Z_OK) {
        if (stream.total_out >= capacity) {
            size_t new_capacity = capacity * 2;
            if (new_capacity <= capacity) {
                free(buffer);
                inflateEnd(&stream);
                return false;
            }
            uint8_t *grown = (uint8_t *)realloc(buffer, new_capacity);
            if (!grown) {
                free(buffer);
                inflateEnd(&stream);
                return false;
            }
            buffer = grown;
            capacity = new_capacity;
        }

        size_t remaining = capacity - stream.total_out;
        if (remaining == 0) {
            free(buffer);
            inflateEnd(&stream);
            return false;
        }
        if (remaining > UINT_MAX) {
            remaining = UINT_MAX;
        }

        stream.next_out = buffer + stream.total_out;
        stream.avail_out = (uInt)remaining;

        z_result = inflate(&stream, Z_NO_FLUSH);
    }

    if (z_result != Z_STREAM_END) {
        free(buffer);
        inflateEnd(&stream);
        return false;
    }

    *out_size = (size_t)stream.total_out;
    *out_data = buffer;
    inflateEnd(&stream);
    return true;
}

static bool scan_elements(const uint8_t *data,
                          size_t data_size,
                          size_t start_offset,
                          bool little_endian,
                          MatMatrixVisitor visitor,
                          void *context,
                          bool *out_stop) {
    if (!data || !visitor || start_offset > data_size) {
        return false;
    }

    MatReader reader = {
        .data = data,
        .size = data_size,
        .pos = start_offset,
        .little_endian = little_endian
    };

    while (reader.pos + 8 <= reader.size) {
        MatElement element;
        if (!read_element(&reader, &element)) {
            // Некоторые файлы содержат хвост без полного MAT-тега.
            break;
        }

        if (element.type == MI_MATRIX) {
            ParsedMatrix matrix;
            if (!parse_matrix_payload(element.payload, element.num_bytes, little_endian, &matrix)) {
                continue;
            }

            if (matrix.supported) {
                bool stop = false;
                if (!visitor(&matrix, little_endian, context, &stop)) {
                    return false;
                }
                if (stop) {
                    if (out_stop) {
                        *out_stop = true;
                    }
                    return true;
                }
            }
        } else if (element.type == MI_COMPRESSED) {
            uint8_t *decompressed = NULL;
            size_t decompressed_size = 0;
            if (!decompress_zlib(element.payload, element.num_bytes, &decompressed, &decompressed_size)) {
                return false;
            }

            bool nested_stop = false;
            bool nested_ok = scan_elements(decompressed,
                                           decompressed_size,
                                           0,
                                           little_endian,
                                           visitor,
                                           context,
                                           &nested_stop);
            free(decompressed);
            if (!nested_ok) {
                return false;
            }
            if (nested_stop) {
                if (out_stop) {
                    *out_stop = true;
                }
                return true;
            }
        }
    }

    return true;
}

static bool load_file(const char *path, MatFileBuffer *out_file) {
    if (!path || !out_file) {
        return false;
    }

    memset(out_file, 0, sizeof(*out_file));

    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        return false;
    }

    struct stat st;
    if (fstat(fd, &st) != 0) {
        close(fd);
        return false;
    }
    if (st.st_size < 128) {
        close(fd);
        return false;
    }
    if (st.st_size <= 0) {
        close(fd);
        return false;
    }

    size_t file_size = (size_t)st.st_size;
    if ((off_t)file_size != st.st_size) {
        close(fd);
        return false;
    }

    uint8_t *buffer = (uint8_t *)mmap(NULL, file_size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (buffer != MAP_FAILED) {
        out_file->data = buffer;
        out_file->size = file_size;
        out_file->is_mapped = true;
        close(fd);
    } else {
        close(fd);
        FILE *file = fopen(path, "rb");
        if (!file) {
            return false;
        }
        buffer = (uint8_t *)malloc(file_size);
        if (!buffer) {
            fclose(file);
            return false;
        }
        size_t read_size = fread(buffer, 1, file_size, file);
        fclose(file);
        if (read_size != file_size) {
            free(buffer);
            return false;
        }
        out_file->data = buffer;
        out_file->size = file_size;
        out_file->is_mapped = false;
    }

    uint8_t endian0 = out_file->data[126];
    uint8_t endian1 = out_file->data[127];
    if (endian0 == 'I' && endian1 == 'M') {
        out_file->little_endian = true;
    } else if (endian0 == 'M' && endian1 == 'I') {
        out_file->little_endian = false;
    } else {
        if (out_file->is_mapped) {
            munmap(out_file->data, out_file->size);
        } else {
            free(out_file->data);
        }
        memset(out_file, 0, sizeof(*out_file));
        return false;
    }

    return true;
}

static void release_file(MatFileBuffer *file) {
    if (!file || !file->data) {
        return;
    }

    if (file->is_mapped) {
        munmap(file->data, file->size);
    } else {
        free(file->data);
    }

    file->data = NULL;
    file->size = 0;
    file->little_endian = true;
    file->is_mapped = false;
}

static void swap_elements_in_place(void *data, size_t count, size_t elem_size) {
    if (!data || count == 0 || elem_size <= 1) {
        return;
    }

    uint8_t *bytes = (uint8_t *)data;
    for (size_t i = 0; i < count; i++) {
        uint8_t *elem = bytes + (i * elem_size);
        for (size_t j = 0; j < elem_size / 2; j++) {
            uint8_t tmp = elem[j];
            elem[j] = elem[elem_size - 1 - j];
            elem[elem_size - 1 - j] = tmp;
        }
    }
}

typedef struct {
    const char *target_name;
    bool first_only;
    int expected_rank;
    MatCube3D *out_cube;
    char *out_name;
    size_t out_name_len;
    bool found;
} LoadContext;

static bool load_visitor(const ParsedMatrix *matrix,
                         bool little_endian,
                         void *context,
                         bool *stop) {
    if (!matrix || !context || !stop) {
        return false;
    }

    LoadContext *ctx = (LoadContext *)context;
    if (ctx->found) {
        *stop = true;
        return true;
    }

    if (matrix->rank != ctx->expected_rank) {
        return true;
    }

    if (!ctx->first_only && ctx->target_name) {
        if (strcmp(matrix->name, ctx->target_name) != 0) {
            return true;
        }
    }

    size_t element_count = 0;
    if (!count_elements(matrix->dims, matrix->rank, &element_count)) {
        return false;
    }

    size_t byte_count = 0;
    if (!checked_mul_size(element_count, matrix->element_size, &byte_count)) {
        return false;
    }
    if (byte_count != matrix->real_data_bytes) {
        return false;
    }

    void *copy = malloc(byte_count);
    if (!copy) {
        return false;
    }
    memcpy(copy, matrix->real_data, byte_count);

    if (!little_endian && matrix->element_size > 1) {
        swap_elements_in_place(copy, element_count, matrix->element_size);
    }

    ctx->out_cube->data = copy;
    ctx->out_cube->dims[0] = matrix->dims[0];
    ctx->out_cube->dims[1] = matrix->dims[1];
    ctx->out_cube->dims[2] = (ctx->expected_rank == 3) ? matrix->dims[2] : 1;
    ctx->out_cube->rank = ctx->expected_rank;
    ctx->out_cube->data_type = matrix->data_type;

    if (ctx->out_name && ctx->out_name_len > 0) {
        strncpy(ctx->out_name, matrix->name, ctx->out_name_len - 1);
        ctx->out_name[ctx->out_name_len - 1] = '\0';
    }

    ctx->found = true;
    *stop = true;
    return true;
}

typedef struct {
    MatCubeInfo *list;
    size_t count;
    size_t capacity;
    int expected_rank;
} ListContext;

static bool list_visitor(const ParsedMatrix *matrix,
                         bool little_endian,
                         void *context,
                         bool *stop) {
    (void)little_endian;

    if (!matrix || !context || !stop) {
        return false;
    }

    ListContext *ctx = (ListContext *)context;
    if (matrix->rank != ctx->expected_rank) {
        return true;
    }

    if (ctx->count == ctx->capacity) {
        size_t new_capacity = (ctx->capacity == 0) ? 8 : (ctx->capacity * 2);
        MatCubeInfo *new_list = (MatCubeInfo *)realloc(ctx->list, new_capacity * sizeof(MatCubeInfo));
        if (!new_list) {
            return false;
        }
        ctx->list = new_list;
        ctx->capacity = new_capacity;
    }

    MatCubeInfo *slot = &ctx->list[ctx->count];
    memset(slot, 0, sizeof(MatCubeInfo));
    if (matrix->name[0] != '\0') {
        strncpy(slot->name, matrix->name, sizeof(slot->name) - 1);
    } else {
        strncpy(slot->name, "unnamed", sizeof(slot->name) - 1);
    }
    slot->name[sizeof(slot->name) - 1] = '\0';
    slot->dims[0] = matrix->dims[0];
    slot->dims[1] = matrix->dims[1];
    slot->dims[2] = (ctx->expected_rank == 3) ? matrix->dims[2] : 1;
    slot->data_type = matrix->data_type;

    ctx->count += 1;
    return true;
}

bool load_first_3d_double_cube(const char *path,
                               MatCube3D *outCube,
                               char *outName,
                               size_t outNameLen) {
    if (!path || !outCube) {
        return false;
    }

    clear_cube(outCube);

    MatFileBuffer file;
    if (!load_file(path, &file)) {
        return false;
    }

    LoadContext ctx = {
        .target_name = NULL,
        .first_only = true,
        .expected_rank = 3,
        .out_cube = outCube,
        .out_name = outName,
        .out_name_len = outNameLen,
        .found = false
    };

    bool stop = false;
    bool ok = scan_elements(file.data,
                            file.size,
                            128,
                            file.little_endian,
                            load_visitor,
                            &ctx,
                            &stop);
    release_file(&file);
    if (!ok) {
        free_cube(outCube);
        clear_cube(outCube);
        return false;
    }

    return ctx.found;
}

bool load_cube_by_name(const char *path,
                       const char *varName,
                       MatCube3D *outCube,
                       char *outName,
                       size_t outNameLen) {
    if (!path || !varName || !outCube) {
        return false;
    }

    clear_cube(outCube);

    MatFileBuffer file;
    if (!load_file(path, &file)) {
        return false;
    }

    LoadContext ctx = {
        .target_name = varName,
        .first_only = false,
        .expected_rank = 3,
        .out_cube = outCube,
        .out_name = outName,
        .out_name_len = outNameLen,
        .found = false
    };

    bool stop = false;
    bool ok = scan_elements(file.data,
                            file.size,
                            128,
                            file.little_endian,
                            load_visitor,
                            &ctx,
                            &stop);
    release_file(&file);
    if (!ok) {
        free_cube(outCube);
        clear_cube(outCube);
        return false;
    }

    return ctx.found;
}

bool list_mat_cube_variables(const char *path,
                             MatCubeInfo **outList,
                             size_t *outCount) {
    if (!path || !outList || !outCount) {
        return false;
    }

    *outList = NULL;
    *outCount = 0;

    MatFileBuffer file;
    if (!load_file(path, &file)) {
        return false;
    }

    ListContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.expected_rank = 3;

    bool stop = false;
    bool ok = scan_elements(file.data,
                            file.size,
                            128,
                            file.little_endian,
                            list_visitor,
                            &ctx,
                            &stop);
    release_file(&file);
    if (!ok) {
        free(ctx.list);
        return false;
    }

    *outList = ctx.list;
    *outCount = ctx.count;
    return true;
}

bool load_2d_array_by_name(const char *path,
                           const char *varName,
                           MatCube3D *outCube,
                           char *outName,
                           size_t outNameLen) {
    if (!path || !varName || !outCube) {
        return false;
    }

    clear_cube(outCube);

    MatFileBuffer file;
    if (!load_file(path, &file)) {
        return false;
    }

    LoadContext ctx = {
        .target_name = varName,
        .first_only = false,
        .expected_rank = 2,
        .out_cube = outCube,
        .out_name = outName,
        .out_name_len = outNameLen,
        .found = false
    };

    bool stop = false;
    bool ok = scan_elements(file.data,
                            file.size,
                            128,
                            file.little_endian,
                            load_visitor,
                            &ctx,
                            &stop);
    release_file(&file);
    if (!ok) {
        free_cube(outCube);
        clear_cube(outCube);
        return false;
    }

    return ctx.found;
}

bool list_mat_2d_variables(const char *path,
                           MatCubeInfo **outList,
                           size_t *outCount) {
    if (!path || !outList || !outCount) {
        return false;
    }

    *outList = NULL;
    *outCount = 0;

    MatFileBuffer file;
    if (!load_file(path, &file)) {
        return false;
    }

    ListContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.expected_rank = 2;

    bool stop = false;
    bool ok = scan_elements(file.data,
                            file.size,
                            128,
                            file.little_endian,
                            list_visitor,
                            &ctx,
                            &stop);
    release_file(&file);
    if (!ok) {
        free(ctx.list);
        return false;
    }

    *outList = ctx.list;
    *outCount = ctx.count;
    return true;
}

void free_mat_cube_info(MatCubeInfo *list) {
    if (list) {
        free(list);
    }
}

static bool write_all(FILE *file, const void *bytes, size_t length) {
    if (!file || !bytes || length == 0) {
        return length == 0;
    }
    return fwrite(bytes, 1, length, file) == length;
}

static bool write_u16_le(FILE *file, uint16_t value) {
    uint16_t le = host_is_little_endian() ? value : bswap16(value);
    return write_all(file, &le, sizeof(le));
}

static bool write_u32_le(FILE *file, uint32_t value) {
    uint32_t le = host_is_little_endian() ? value : bswap32(value);
    return write_all(file, &le, sizeof(le));
}

static bool write_padding(FILE *file, size_t padding) {
    static const uint8_t zeros[8] = {0};
    while (padding > 0) {
        size_t chunk = padding > sizeof(zeros) ? sizeof(zeros) : padding;
        if (!write_all(file, zeros, chunk)) {
            return false;
        }
        padding -= chunk;
    }
    return true;
}

static bool write_tag(FILE *file, uint32_t type, uint32_t num_bytes) {
    return write_u32_le(file, type) && write_u32_le(file, num_bytes);
}

static bool map_write_type(MatDataType data_type,
                           uint32_t *mx_class,
                           uint32_t *mi_type,
                           size_t *element_size) {
    if (!mx_class || !mi_type || !element_size) {
        return false;
    }

    switch (data_type) {
        case MAT_DATA_FLOAT64:
            *mx_class = MX_DOUBLE_CLASS;
            *mi_type = MI_DOUBLE;
            *element_size = sizeof(double);
            return true;
        case MAT_DATA_FLOAT32:
            *mx_class = MX_SINGLE_CLASS;
            *mi_type = MI_SINGLE;
            *element_size = sizeof(float);
            return true;
        case MAT_DATA_UINT8:
            *mx_class = MX_UINT8_CLASS;
            *mi_type = MI_UINT8;
            *element_size = sizeof(uint8_t);
            return true;
        case MAT_DATA_UINT16:
            *mx_class = MX_UINT16_CLASS;
            *mi_type = MI_UINT16;
            *element_size = sizeof(uint16_t);
            return true;
        case MAT_DATA_INT8:
            *mx_class = MX_INT8_CLASS;
            *mi_type = MI_INT8;
            *element_size = sizeof(int8_t);
            return true;
        case MAT_DATA_INT16:
            *mx_class = MX_INT16_CLASS;
            *mi_type = MI_INT16;
            *element_size = sizeof(int16_t);
            return true;
        default:
            return false;
    }
}

static bool write_data_le(FILE *file,
                          const void *data,
                          size_t element_count,
                          size_t element_size) {
    if (!file || !data) {
        return false;
    }

    size_t byte_count = 0;
    if (!checked_mul_size(element_count, element_size, &byte_count)) {
        return false;
    }

    if (host_is_little_endian() || element_size == 1) {
        return write_all(file, data, byte_count);
    }

    uint8_t *copy = (uint8_t *)malloc(byte_count);
    if (!copy) {
        return false;
    }

    memcpy(copy, data, byte_count);
    swap_elements_in_place(copy, element_count, element_size);
    bool ok = write_all(file, copy, byte_count);
    free(copy);
    return ok;
}

static bool write_numeric_matrix(FILE *file,
                                 const char *name,
                                 const size_t *dims,
                                 int rank,
                                 MatDataType data_type,
                                 const void *data_ptr) {
    if (!file || !name || !dims || rank <= 0 || !data_ptr) {
        return false;
    }

    uint32_t mx_class = 0;
    uint32_t mi_data_type = 0;
    size_t element_size = 0;
    if (!map_write_type(data_type, &mx_class, &mi_data_type, &element_size)) {
        return false;
    }

    size_t element_count = 0;
    if (!count_elements(dims, rank, &element_count)) {
        return false;
    }

    size_t raw_data_bytes = 0;
    if (!checked_mul_size(element_count, element_size, &raw_data_bytes)) {
        return false;
    }
    if (raw_data_bytes > UINT32_MAX) {
        return false;
    }
    uint32_t data_bytes = (uint32_t)raw_data_bytes;
    size_t data_pad = aligned8(data_bytes) - data_bytes;

    size_t name_len = strlen(name);
    if (name_len > UINT32_MAX) {
        return false;
    }
    uint32_t name_bytes = (uint32_t)name_len;
    size_t name_pad = aligned8(name_bytes) - name_bytes;

    if (rank > INT_MAX || rank > (int)(UINT32_MAX / 4U)) {
        return false;
    }
    uint32_t dims_bytes = (uint32_t)(rank * 4);
    size_t dims_pad = aligned8(dims_bytes) - dims_bytes;

    uint64_t matrix_bytes = 0;
    matrix_bytes += 16; // array flags
    matrix_bytes += (uint64_t)8 + (uint64_t)dims_bytes + (uint64_t)dims_pad;
    matrix_bytes += (uint64_t)8 + (uint64_t)name_bytes + (uint64_t)name_pad;
    matrix_bytes += (uint64_t)8 + (uint64_t)data_bytes + (uint64_t)data_pad;
    if (matrix_bytes > UINT32_MAX) {
        return false;
    }

    if (!write_tag(file, MI_MATRIX, (uint32_t)matrix_bytes)) {
        return false;
    }

    if (!write_tag(file, MI_UINT32, 8)) {
        return false;
    }
    if (!write_u32_le(file, mx_class)) {
        return false;
    }
    if (!write_u32_le(file, 0)) {
        return false;
    }

    if (!write_tag(file, MI_INT32, dims_bytes)) {
        return false;
    }
    for (int i = 0; i < rank; i++) {
        if (dims[i] > INT32_MAX) {
            return false;
        }
        if (!write_u32_le(file, (uint32_t)dims[i])) {
            return false;
        }
    }
    if (!write_padding(file, dims_pad)) {
        return false;
    }

    if (!write_tag(file, MI_INT8, name_bytes)) {
        return false;
    }
    if (name_bytes > 0 && !write_all(file, name, name_bytes)) {
        return false;
    }
    if (!write_padding(file, name_pad)) {
        return false;
    }

    if (!write_tag(file, mi_data_type, data_bytes)) {
        return false;
    }
    if (!write_data_le(file, data_ptr, element_count, element_size)) {
        return false;
    }
    if (!write_padding(file, data_pad)) {
        return false;
    }

    return true;
}

static bool write_mat_header(FILE *file) {
    if (!file) {
        return false;
    }

    uint8_t header[116];
    memset(header, ' ', sizeof(header));
    const char *text = "MATLAB 5.0 MAT-file, Platform: macOS, Created by HSIView";
    size_t text_len = strlen(text);
    if (text_len > sizeof(header)) {
        text_len = sizeof(header);
    }
    memcpy(header, text, text_len);

    uint8_t subsys[8] = {0};
    uint8_t endian[2] = {'I', 'M'};

    if (!write_all(file, header, sizeof(header))) {
        return false;
    }
    if (!write_all(file, subsys, sizeof(subsys))) {
        return false;
    }
    if (!write_u16_le(file, 0x0100)) {
        return false;
    }
    return write_all(file, endian, sizeof(endian));
}

bool save_3d_cube(const char *path,
                  const char *varName,
                  const MatCube3D *cube) {
    if (!path || !varName || !cube || !cube->data) {
        return false;
    }
    if (cube->rank != 3) {
        return false;
    }

    FILE *file = fopen(path, "wb");
    if (!file) {
        return false;
    }

    bool ok = write_mat_header(file) &&
              write_numeric_matrix(file, varName, cube->dims, 3, cube->data_type, cube->data);
    fclose(file);
    return ok;
}

bool save_wavelengths(const char *path,
                      const char *varName,
                      const double *wavelengths,
                      size_t count) {
    if (!path || !varName || !wavelengths || count == 0) {
        return false;
    }

    FILE *file = fopen(path, "rb+");
    if (!file) {
        return false;
    }

    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return false;
    }

    size_t dims[2];
    dims[0] = count;
    dims[1] = 1;
    bool ok = write_numeric_matrix(file, varName, dims, 2, MAT_DATA_FLOAT64, wavelengths);
    fclose(file);
    return ok;
}

void free_cube(MatCube3D *cube) {
    if (!cube) {
        return;
    }
    if (cube->data) {
        free(cube->data);
        cube->data = NULL;
    }
}
