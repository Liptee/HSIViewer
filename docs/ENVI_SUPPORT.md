# Поддержка ENVI формата

## Описание

Добавлена полная поддержка формата ENVI для гиперспектральных изображений.

ENVI формат состоит из **двух файлов**:
- **`.dat`** (или `.img`, `.bsq`, `.raw`) - бинарные данные
- **`.hdr`** - текстовый заголовок с метаданными

## Основные характеристики

### Обязательные поля .hdr:
- `samples` - ширина (W)
- `lines` - высота (H)
- `bands` - число каналов (C)
- `data type` - тип данных (код ENVI)
- `interleave` - порядок данных (bsq, bil, bip)
- `byte order` - endianness (0 = little, 1 = big)
- `header offset` - байты перед данными

### Поддерживаемые типы данных:

| data type | Тип | Байт |
|-----------|-----|------|
| 1 | int8 | 1 |
| 2 | int16 | 2 |
| 3 | int32 | 4 |
| 4 | float32 | 4 |
| 5 | float64 | 8 |
| 12 | uint16 | 2 |
| 13 | uint32 | 4 |

### Поддерживаемые форматы interleave:

**BSQ (Band Sequential):**
```
Порядок: (C, H, W)
Band0: все строки
Band1: все строки
...
```

**BIL (Band Interleaved by Line):**
```
Порядок: (H, C, W)
Line0: все каналы
Line1: все каналы
...
```

**BIP (Band Interleaved by Pixel):**
```
Порядок: (H, W, C)
Pixel0: все каналы
Pixel1: все каналы
...
```

## Использование

### Открытие файлов:

1. **Через меню:**
   - File → Открыть... (Cmd+O)
   - Выберите `.dat` или `.hdr` файл

2. **Через Finder:**
   - Двойной клик на `.dat` или `.hdr`

3. **Автоматический поиск:**
   - При открытии `.dat` → ищется `.hdr` с тем же именем
   - При открытии `.hdr` → ищется `.dat` с тем же именем

### Примеры имен файлов:

```
cube.dat + cube.hdr ✅
image.dat + image.hdr ✅
data.img + data.hdr ✅ (расширение .dat не обязательно)
```

**Важно:** Оба файла должны быть в одной директории!

## Реализация

### Компоненты:

**EnviHeader.swift:**
- Структура `EnviHeader` с метаданными
- Парсер `EnviHeaderParser` для .hdr файлов
- Поддержка всех обязательных и опциональных полей

**EnviImageLoader.swift:**
- Загрузчик ENVI данных
- Автоматический поиск парного файла
- Поддержка всех interleave (bsq, bil, bip)
- Поддержка byte order (little/big endian)
- Автоматическое переупорядочивание данных

### Алгоритм загрузки:

```
1. Определить .dat и .hdr файлы
   ↓
2. Проверить существование обоих
   ↓
3. Парсинг .hdr → EnviHeader
   ↓
4. Чтение .dat с учетом:
   - data type → правильный тип в Swift
   - byte order → правильный endianness
   - header offset → пропуск байт
   ↓
5. Переупорядочивание по interleave:
   - bsq: уже (C,H,W) для column-major
   - bil: (H,C,W) → (C,H,W)
   - bip: (H,W,C) → (C,H,W)
   ↓
6. Создание HyperCube с DataStorage
```

### Пример .hdr файла:

```
ENVI
description = {Hyperspectral cube}
samples = 512
lines = 512
bands = 31
header offset = 0
file type = ENVI Standard
data type = 4
interleave = bsq
byte order = 0
wavelength = {400.0, 410.0, 420.0, ...}
wavelength units = Nanometers
```

## Опциональные поля

Поддерживаются, но не используются в текущей версии:
- `wavelength` - длины волн (для будущего автозагрузки λ)
- `fwhm` - полная ширина на половине максимума
- `wavelength units` - единицы длин волн
- `description` - описание
- `band names` - имена каналов
- `map info` - геопривязка (для будущего GIS)

## Ограничения

**Не поддерживается:**
- Комплексные типы (data type 6, 9)
- Сжатие данных
- Multi-file format (когда данные в нескольких файлах)

**Требования:**
- Оба файла (.dat и .hdr) в одной директории
- data type в списке поддерживаемых
- Валидный формат .hdr

## Тестирование

### Создание тестового ENVI файла (Python):

```python
import numpy as np

# Создать данные
cube = np.random.rand(512, 512, 31).astype(np.float32)

# Сохранить .dat
with open('test.dat', 'wb') as f:
    if interleave == 'bsq':
        # (H, W, C) → (C, H, W)
        data = np.transpose(cube, (2, 0, 1))
    elif interleave == 'bil':
        # (H, W, C) → (H, C, W)
        data = np.transpose(cube, (0, 2, 1))
    else:  # bip
        data = cube
    data.tofile(f)

# Создать .hdr
hdr = f"""ENVI
description = {{Test cube}}
samples = 512
lines = 512
bands = 31
header offset = 0
file type = ENVI Standard
data type = 4
interleave = bsq
byte order = 0
"""

with open('test.hdr', 'w') as f:
    f.write(hdr)
```

### Проверка:

1. Создайте тестовые файлы
2. Откройте в приложении (test.dat или test.hdr)
3. Проверьте:
   - ✅ Размеры: 512 × 512 × 31
   - ✅ Тип: Float32
   - ✅ Изображение отображается корректно

## Совместимость

✅ ENVI Classic  
✅ ENVI 5.x  
✅ IDL  
✅ GDAL  
✅ Spectral Python  
✅ QGIS (с плагином)

## Важные исправления (v2)

### Проблемы в первой версии:
1. ❌ Неправильное переупорядочивание BIL/BIP
2. ❌ Использование `Array(repeating:)` с потенциальными проблемами
3. ❌ data type 1 читался как `Int8` вместо `UInt8`
4. ❌ Wavelengths не загружались автоматически

### Исправления:
1. ✅ Переписаны `reorderBILToColumnMajor` и `reorderBIPToColumnMajor`
   - Используют `append` вместо индексации
   - Правильно конвертируют в column-major формат
2. ✅ data type 1 теперь `UInt8`
3. ✅ Автоматическая загрузка wavelengths из .hdr в AppState
4. ✅ HyperCube теперь хранит wavelengths
5. ✅ Поддержка .dat и .hdr из Finder

### Алгоритм переупорядочивания:

**BSQ (Band Sequential):**
```
Файл: (C, H, W) порядок
Наш формат: column-major (C, H, W)
→ Копируем как есть
```

**BIL (Band Interleaved by Line):**
```
Файл: line 0 [C каналов], line 1 [C каналов]...
  → srcIdx = h * C * W + c * W + w
Наш формат: channel 0 [H×W], channel 1 [H×W]...
  → итерация: for c, for h, for w
```

**BIP (Band Interleaved by Pixel):**
```
Файл: pixel(0,0)[C каналов], pixel(0,1)[C каналов]...
  → srcIdx = h * W * C + w * C + c
Наш формат: channel 0 [H×W], channel 1 [H×W]...
  → итерация: for c, for h, for w
```

## Дата

2025-11-28 (v2 - исправлена)

