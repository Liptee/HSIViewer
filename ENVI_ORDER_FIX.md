# Исправление порядка данных для ENVI

## Критическая проблема

ENVI файлы открывались с **неправильно считанными данными** (полосы, искаженные изображения).

## Причина

**Несоответствие между порядком данных и флагом `isFortranOrder`:**

### Что было неправильно (v1-v2):

```swift
// dims = (H, W, C) = (header.height, header.width, header.channels)
// isFortranOrder = true

// Данные переупорядочивались в (C, H, W) column-major:
for c in 0..<C {
    for h in 0..<H {
        for w in 0..<W {
            result.append(...)  // Создает Fortran order для (C,H,W)
        }
    }
}
```

**Проблема:** `dims=(H,W,C)` + `isFortranOrder=true` ожидает данные в Fortran order для (H,W,C), но данные были в Fortran order для (C,H,W)!

### Формула `linearIndex`:

```swift
if isFortranOrder {
    return i0 + d0 * (i1 + d1 * i2)  // Для dims=(H,W,C): h + H*(w + W*c)
} else {
    return i2 + d2 * (i1 + d1 * i0)  // Для dims=(H,W,C): c + C*(w + W*h)
}
```

**Проблема:** При `isFortranOrder=true` и `dims=(H,W,C)`, код ожидает порядок:
```
[h=0,w=0,c=0], [h=1,w=0,c=0], ..., [h=H-1,w=0,c=0], [h=0,w=1,c=0], ...
```

Но мы создавали порядок:
```
[c=0,h=0,w=0], [c=0,h=1,w=0], ..., [c=0,h=H-1,w=0], [c=0,h=0,w=1], ...
```

Это порядок для `dims=(C,H,W)` с Fortran order, а не для `dims=(H,W,C)`!

## Решение

### Вариант 1: Изменить порядок данных на C-order (row-major) ✅ ВЫБРАНО

```swift
// dims = (H, W, C)
// isFortranOrder = false

// Переупорядочиваем данные в C-order:
for h in 0..<H {
    for w in 0..<W {
        for c in 0..<C {
            result.append(...)  // Создает C-order для (H,W,C)
        }
    }
}
```

Порядок данных: `[h=0,w=0,c=0], [h=0,w=0,c=1], ..., [h=0,w=0,c=C-1], [h=0,w=1,c=0], ...`

Формула `linearIndex` с `isFortranOrder=false`:
```
idx = c + C * (w + W * h)
```

**Преимущества:**
- Естественный порядок для ENVI (lines=H, samples=W, bands=C)
- Соответствует определению в .hdr файле
- Последний индекс (C) меняется быстрее всего

### Вариант 2: Изменить dims на (C,H,W) ❌ НЕ ВЫБРАНО

Это требовало бы изменения `AppState.layout` на `.chw`, что влияет на весь UI и другую логику.

## Реализация

### 1. Переупорядочивание для каждого interleave:

**BSQ (Band Sequential):**
```swift
// Файл: (C, H, W) - каналы последовательно
// Цель: (H, W, C) C-order

for h in 0..<H {
    for w in 0..<W {
        for c in 0..<C {
            srcIdx = c * H * W + h * W + w  // Читаем из (C,H,W)
            result.append(arr[srcIdx])       // Пишем в (H,W,C) C-order
        }
    }
}
```

**BIL (Band Interleaved by Line):**
```swift
// Файл: (H, C, W) - строки с чередующимися каналами
// Цель: (H, W, C) C-order

for h in 0..<H {
    for w in 0..<W {
        for c in 0..<C {
            srcIdx = h * C * W + c * W + w  // Читаем из (H,C,W)
            result.append(arr[srcIdx])       // Пишем в (H,W,C) C-order
        }
    }
}
```

**BIP (Band Interleaved by Pixel):**
```swift
// Файл: (H, W, C) - пиксели с чередующимися каналами
// Цель: (H, W, C) C-order
// УЖЕ В ПРАВИЛЬНОМ ФОРМАТЕ! Не нужно переупорядочивать.

return wrapInStorage(arr)
```

### 2. Установка правильного флага:

```swift
let cube = HyperCube(
    dims: (header.height, header.width, header.channels),  // (H, W, C)
    storage: storage,
    sourceFormat: "ENVI (\(header.interleave.uppercased()))",
    isFortranOrder: false,  // C-order / row-major ✅
    wavelengths: header.wavelength
)
```

## Тестирование

### Python скрипты для проверки:

**`python_tests/verify_envi_order.py`:**
- Проверяет правильность переупорядочивания BSQ, BIL, BIP
- Все три формата корректно преобразуются в (H, W, C)

**`python_tests/test_fortran_order.py`:**
- Проверяет формулу `linearIndex` для Fortran и C order
- Подтверждает, что C-order с формулой `c + C*(w + W*h)` правильный

**`python_tests/read_envi_test.py`:**
- Читает реальные ENVI файлы и показывает их структуру
- Проверено на `pre_katrina05.hdr` (BSQ, uint8, 1 канал)
- Проверено на `AV320240720...hdr` (BIL, float32, 284 канала)

### Результаты:

✅ `test_data/pre_katrina05.dat` (5270×5720×1, BSQ, uint8)  
✅ `test_data/AV320240720...dat` (1341×1381×284, BIL, float32)

## Изменения в коде

**HSIView/Services/EnviImageLoader.swift:**
1. `isFortranOrder: true` → `isFortranOrder: false`
2. Переименованы функции:
   - `reorderBILToColumnMajor` → `reorderBILToHWC`
   - `reorderBIPToColumnMajor` → удалена (не нужна)
   - Добавлена `reorderBSQToHWC`
3. Изменен порядок циклов в reorder функциях:
   - Было: `for c, for h, for w` (создает Fortran order для (C,H,W))
   - Стало: `for h, for w, for c` (создает C-order для (H,W,C))

## До и После

### До (НЕПРАВИЛЬНО):
```
dims = (H, W, C) = (1341, 1381, 284)
isFortranOrder = true
Данные в порядке: (C, H, W) Fortran order
→ НЕСООТВЕТСТВИЕ! Изображение искажено!
```

### После (ПРАВИЛЬНО):
```
dims = (H, W, C) = (1341, 1381, 284)
isFortranOrder = false
Данные в порядке: (H, W, C) C-order
→ СООТВЕТСТВИЕ! Изображение корректное!
```

## Дата

2025-11-28 (v4 - исправлен порядок данных)

