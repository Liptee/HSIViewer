# Анализ проблемы парсинга TIFF файлов

## 🔍 Проблема

TIFF файлы отображаются некорректно (полосы, искажения) несмотря на исправление нормализации.

## 📊 Анализ текущего кода

### TiffHelper.c - текущая реализация

```c
// Строка 89:
size_t colMajorIdx = row + H * (col + W * (size_t)s);
data[colMajorIdx] = (double)buf[i];
```

**Проблема:** Индексация для Fortran-order (column-major), но порядок чтения может не соответствовать.

### Структура TIFF multi-page

TIFF файлы могут хранить данные двумя способами:

#### 1. PLANARCONFIG_CONTIG (interleaved)
```
Память: R0 G0 B0 R1 G1 B1 R2 G2 B2 ...
Каналы чередуются
```

#### 2. PLANARCONFIG_SEPARATE (planar)
```
Память: R0 R1 R2 ... G0 G1 G2 ... B0 B1 B2 ...
Каналы идут блоками
```

Наш код поддерживает **только PLANARCONFIG_SEPARATE** (строка 36).

### Как Python читает TIFF

**tifffile.imread():**
```python
# Для multi-page TIFF:
data = tifffile.imread('file.tiff')
# Возвращает: (H, W, C) в C-order (row-major)
```

**PIL.Image:**
```python
img = Image.open('file.tiff')
# Multi-page: каждая страница = один канал
for i in range(img.n_frames):
    img.seek(i)
    channel = np.array(img)  # (H, W)
```

## 🐛 Возможные причины проблем

### 1. Неправильная индексация при транспонировании

Наш код:
```c
for (uint16 s = 0; s < samplesPerPixel; ++s) {     // Для каждого канала
    for (tstrip_t j = 0; j < stripsPerPlane; ++j) { // Для каждого strip'а
        // Читаем данные в row-major порядке
        for (size_t i = 0; i < bytes; ++i, ++written) {
            size_t row = written / W;
            size_t col = written % W;
            // Записываем в column-major (Fortran)
            size_t colMajorIdx = row + H * (col + W * (size_t)s);
            data[colMajorIdx] = (double)buf[i];
        }
    }
}
```

**Проблема:** 
- Читаем в row-major (по строкам)
- Записываем в column-major индекс
- Транспонирование может быть неправильным

### 2. Multi-page vs. Planar Separate

**Multi-page TIFF:**
- Каждая страница = отдельный IFD (Image File Directory)
- Страницы могут быть независимыми изображениями

**Planar Separate TIFF:**
- Один IFD с несколькими плоскостями
- Плоскости = каналы одного изображения

**Наш код предполагает одно, но файлы могут быть другими!**

## ✅ Решение

### Вариант 1: Упростить - не транспонировать

```c
// Читаем данные как есть в row-major (C-order)
for (uint16 s = 0; s < samplesPerPixel; ++s) {
    size_t channelOffset = s * planeSize;
    size_t written = 0;
    
    for (tstrip_t j = 0; j < stripsPerPlane; ++j) {
        tstrip_t stripIndex = s * stripsPerPlane + j;
        // ... чтение strip'а ...
        
        for (size_t i = 0; i < bytes && written < planeSize; ++i, ++written) {
            // Простая row-major индексация (C,H,W)
            data[channelOffset + written] = (double)buf[i];
        }
    }
}

// Возвращаем dims как (C, H, W) вместо (H, W, C)
outCube->dims[0] = C;
outCube->dims[1] = H;
outCube->dims[2] = W;
```

Затем в Swift:
```swift
// Транспонируем (C,H,W) → (H,W,C) если нужно
// Или помечаем как CHW layout и обрабатываем правильно
```

### Вариант 2: Использовать libtiff правильно

```c
// Для PLANARCONFIG_SEPARATE можно читать всю плоскость сразу:
for (uint16 s = 0; s < samplesPerPixel; ++s) {
    uint32 *raster = (uint32 *)_TIFFmalloc(W * H * sizeof(uint32));
    
    // TIFFReadRGBAImageOriented - правильно обрабатывает ориентацию
    if (TIFFReadRGBAImageOriented(tif, W, H, raster, ORIENTATION_TOPLEFT, 0)) {
        // Копируем в наш массив
        for (size_t y = 0; y < H; ++y) {
            for (size_t x = 0; x < W; ++x) {
                // ... извлекаем канал s из RGBA ...
            }
        }
    }
    
    _TIFFfree(raster);
}
```

### Вариант 3: Поддержать multi-page правильно

```c
// Подсчитаем количество страниц (directories)
int num_pages = 0;
do {
    num_pages++;
} while (TIFFReadDirectory(tif));

// Вернемся к первой странице
TIFFSetDirectory(tif, 0);

// Если num_pages > 1, это multi-page
// Каждая страница = один канал (H, W)
```

## 🔬 Диагностика

### Шаг 1: Создайте тестовые файлы

Установите библиотеки:
```bash
pip3 install pillow tifffile numpy
```

Запустите:
```bash
python3 create_test_tiff_pil.py
```

### Шаг 2: Проверьте в HSIView

Откройте `test_gradient_multipage.tiff`:
- **Правильно:** градиенты четкие
- **Неправильно:** полосы, шум, искажения

### Шаг 3: Анализ с Python

```bash
python3 check_tiff_structure.py test_gradient_multipage.tiff
```

Сравните PNG файлы:
- `tiff_python_channel0.png` - как читает Python
- `tiff_simulated_channel0.png` - как должен читать C код

**Если они разные - проблема в индексации!**

### Шаг 4: Проверка реального файла

```bash
python3 diagnose_tiff.py ваш_файл.tiff
```

Проверьте:
- `PlanarConfiguration`: SEPARATE (2) или CONTIG (1)?
- `Number of pages`: сколько?
- Shape: (H, W, C) или (C, H, W)?

## 📝 Рекомендуемое исправление

**Самое простое:** не транспонировать, читать как (C, H, W):

```c
// В TiffHelper.c, строка 86-92:
for (size_t i = 0; i < bytes && written < planeSize; ++i, ++written) {
    // Простая row-major индексация: канал за каналом
    size_t channelOffset = s * planeSize;
    data[channelOffset + written] = (double)buf[i];
}

// Строка 100-104:
outCube->data = data;
outCube->rank = 3;
outCube->dims[0] = C;  // ← Изменено!
outCube->dims[1] = H;  // ← Изменено!
outCube->dims[2] = W;  // ← Изменено!
```

Затем в `TiffImageLoader.swift`:
```swift
// Пометить как C-order, не Fortran
isFortranOrder: false  // ← Изменено!

// ИЛИ транспонировать явно:
// Транспонируем (C,H,W) → (H,W,C)
```

## 🧪 Тестирование

После исправления проверьте:
1. ✅ Тестовый файл `test_gradient_multipage.tiff` - градиенты правильные
2. ✅ Тестовый файл `test_pattern_multipage.tiff` - равномерные серые
3. ✅ Ваш реальный файл - изображение без полос

## 📚 Полезные ссылки

- LibTIFF документация: http://www.libtiff.org/man/
- TIFF спецификация: https://www.adobe.io/content/dam/udp/en/open/standards/tiff/TIFF6.pdf
- tifffile (Python): https://github.com/cgohlke/tifffile

---

**Дата:** 2025-11-28

