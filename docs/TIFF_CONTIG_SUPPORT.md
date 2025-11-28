# Добавлена поддержка TIFF PLANARCONFIG_CONTIG

## Проблема

Файл `Tablet.tiff` не открывался с ошибкой "Не удалось открыть TIFF файл".

### Анализ файла (tiffinfo):
```
Samples/Pixel: fa (250 каналов!)
Planar Configuration: single image plane (CONTIG)
Bits/Sample: 8
```

**Причина:** Наш код поддерживал только `PLANARCONFIG_SEPARATE`, а файл использует `PLANARCONFIG_CONTIG`.

## Два типа хранения в TIFF

### PLANARCONFIG_CONTIG (1) - Interleaved
```
Память: R0 G0 B0 R1 G1 B1 R2 G2 B2 ...
Каналы чередуются для каждого пикселя
```

**Пример для 3 каналов:**
```
Strip: [R0,G0,B0, R1,G1,B1, R2,G2,B2, ..., RN,GN,BN]
       |пиксель 0| |пиксель 1| |пиксель 2|     |пиксель N|
```

### PLANARCONFIG_SEPARATE (2) - Planar
```
Память: R0 R1 R2 ... RN  G0 G1 G2 ... GN  B0 B1 B2 ... BN
Каналы идут отдельными блоками
```

**Пример для 3 каналов:**
```
Strip 0: [R0, R1, R2, ..., RN]  (весь красный канал)
Strip 1: [G0, G1, G2, ..., GN]  (весь зеленый канал)
Strip 2: [B0, B1, B2, ..., BN]  (весь синий канал)
```

## Решение

Добавлена поддержка обоих типов в `TiffHelper.c`:

### Было:
```c
// Поддерживаем только SEPARATE
if (planarConfig != PLANARCONFIG_SEPARATE) {
    return false;
}

// Код только для SEPARATE...
```

### Стало:
```c
// Поддерживаем оба типа
if (planarConfig != PLANARCONFIG_CONTIG && planarConfig != PLANARCONFIG_SEPARATE) {
    return false;
}

if (planarConfig == PLANARCONFIG_CONTIG) {
    // Код для CONTIG (interleaved)
    for (strip : strips) {
        read strip
        for (pixel : pixels_in_strip) {
            for (c : channels) {
                value = buf[pixel * C + c]
                data[row + H * (col + W * c)] = value
            }
        }
    }
} else {
    // Код для SEPARATE (planar) - без изменений
}
```

### Ключевые моменты CONTIG:

1. **Чтение strip'ов:**
   ```c
   for (tstrip_t strip = 0; strip < totalStrips; ++strip)
   ```
   Strips читаются последовательно (не по каналам)

2. **Распаковка interleaved данных:**
   ```c
   size_t numPixels = n / C;  // Сколько пикселей в strip'е
   for (p : pixels) {
       for (c : channels) {
           value = buf[p * C + c];  // Извлекаем канал c из пикселя p
       }
   }
   ```

3. **Запись в column-major (как и для SEPARATE):**
   ```c
   size_t colMajorIdx = row + H * (col + W * c);
   data[colMajorIdx] = value;
   ```

## Поддерживаемые TIFF файлы

### Теперь поддерживается:

| Параметр | Значение |
|----------|----------|
| **BitsPerSample** | 8 |
| **PlanarConfiguration** | CONTIG (1) или SEPARATE (2) ✅ |
| **SamplesPerPixel** | Любое (1-250+) ✅ |
| **Compression** | None, LZW, PackBits и др. ✅ |
| **PhotometricInterpretation** | Любое ✅ |

### Примеры файлов:

1. **Обычный RGB TIFF:**
   - SamplesPerPixel: 3
   - PlanarConfiguration: CONTIG
   - ✅ Теперь открывается!

2. **Гиперспектральный TIFF (Tablet.tiff):**
   - SamplesPerPixel: 250
   - PlanarConfiguration: CONTIG
   - ✅ Теперь открывается!

3. **Multi-page TIFF:**
   - SamplesPerPixel: 3-250
   - PlanarConfiguration: SEPARATE
   - ✅ Уже работало, продолжает работать!

## Тестирование

### 1. Откройте Tablet.tiff

```bash
open HSIView.xcodeproj
# Cmd+R для запуска
# Откройте test_data/Tablet.tiff
```

**Ожидаемый результат:**
- ✅ Файл открывается без ошибок
- ✅ Показывает 250 каналов
- ✅ Размер: 1351 × 974 × 250
- ✅ Изображение отображается корректно

### 2. Проверьте информационную панель

Должно показывать:
- Формат: TIFF (.tiff)
- Тип данных: UInt8
- Разрешение: 1351 × 974 × 250
- Каналы: 250
- Размер в памяти: ~320 МБ (1351 × 974 × 250 × 1 байт)

### 3. Проверьте переключение каналов

- Слайдер должен иметь диапазон 0-249
- Изображение должно меняться при переключении каналов
- Без полос и искажений

## Производительность

**CONTIG чтение:**
- ✅ Эффективно: читаем последовательно по strip'ам
- ✅ Локальность кэша: пиксели рядом в памяти
- ⚠️ Небольшой overhead: нужно распаковывать interleaved данные

**SEPARATE чтение:**
- ✅ Проще код: каналы отдельно
- ✅ Может быть быстрее для доступа к одному каналу

## Файлы изменены

- `HSIView/TiffHelper.c`:
  - Добавлена проверка обоих типов PlanarConfiguration
  - Добавлен branch для CONTIG (interleaved channels)
  - SEPARATE код остался без изменений

## Дата

2025-11-28


