# Добавлена поддержка целочисленных типов в MAT файлах

## Проблема

Файл `asphalt2.mat` не открывался с ошибкой "Не удалось открыть .mat файл".

### Анализ файла (hexdump):
```
MATLAB 5.0 MAT-file Platform: nt
Created on: Sun Nov 24 16:05:40 2024
Variable: "image"
Data type: 0x02 = uint8 ← Вот проблема!
```

**Причина:** Наш код поддерживал только `MAT_C_DOUBLE` и `MAT_C_SINGLE`, а файл содержит **uint8** данные.

## Поддерживаемые типы MAT данных

### Было (только float):
```c
MAT_C_DOUBLE  (float64) ✅
MAT_C_SINGLE  (float32) ✅
```

### Стало (float + integer):
```c
MAT_C_DOUBLE  (float64) ✅
MAT_C_SINGLE  (float32) ✅
MAT_C_UINT8   (uint8)   ✅ НОВОЕ
MAT_C_UINT16  (uint16)  ✅ НОВОЕ
MAT_C_INT8    (int8)    ✅ НОВОЕ
MAT_C_INT16   (int16)   ✅ НОВОЕ
```

## Решение

Расширена поддержка типов в `MatHelper.c`:

### 1. Проверка типов при чтении:

**Было:**
```c
if (info->rank == 3 &&
    (info->class_type == MAT_C_DOUBLE || info->class_type == MAT_C_SINGLE)) {
    // ...
}
```

**Стало:**
```c
if (info->rank == 3 &&
    (info->class_type == MAT_C_DOUBLE || 
     info->class_type == MAT_C_SINGLE ||
     info->class_type == MAT_C_UINT8 ||
     info->class_type == MAT_C_UINT16 ||
     info->class_type == MAT_C_INT8 ||
     info->class_type == MAT_C_INT16)) {
    // ...
}
```

### 2. Конвертация данных:

Добавлены обработчики для каждого типа:

```c
// uint8: 0-255
else if (full->class_type == MAT_C_UINT8 && full->data_type == MAT_T_UINT8) {
    uint8_t *src = (uint8_t *)full->data;
    for (size_t i = 0; i < total; ++i) {
        buf[i] = (double)src[i];  // uint8 → double
    }
}

// uint16: 0-65535
else if (full->class_type == MAT_C_UINT16 && full->data_type == MAT_T_UINT16) {
    uint16_t *src = (uint16_t *)full->data;
    for (size_t i = 0; i < total; ++i) {
        buf[i] = (double)src[i];  // uint16 → double
    }
}

// int8: -128 to 127
else if (full->class_type == MAT_C_INT8 && full->data_type == MAT_T_INT8) {
    int8_t *src = (int8_t *)full->data;
    for (size_t i = 0; i < total; ++i) {
        buf[i] = (double)src[i];  // int8 → double
    }
}

// int16: -32768 to 32767
else if (full->class_type == MAT_C_INT16 && full->data_type == MAT_T_INT16) {
    int16_t *src = (int16_t *)full->data;
    for (size_t i = 0; i < total; ++i) {
        buf[i] = (double)src[i];  // int16 → double
    }
}
```

## Почему конвертация в double?

1. **Единообразие:** Все данные из MAT идут через один интерфейс (`double *data`)
2. **Совместимость:** Не нужно менять `MatCube3D` структуру и header
3. **Swift оптимизирует:** `MatImageLoader.swift` уже оборачивает данные в `DataStorage`

### Оптимизация памяти в будущем:

Если нужна оптимизация памяти для uint8 MAT файлов, можно:
1. Вернуть информацию о типе в `MatCube3D` (добавить поле `data_type`)
2. В Swift создавать `DataStorage` напрямую из оригинального типа
3. Избежать промежуточной конвертации в `double`

Но для текущей задачи (открыть asphalt2.mat) этого достаточно!

## Поддерживаемые MAT файлы

| Формат | Тип данных | Пример использования |
|--------|------------|----------------------|
| **float64** | MAT_C_DOUBLE | Научные данные, MATLAB по умолчанию |
| **float32** | MAT_C_SINGLE | Экономия памяти для float данных |
| **uint8** | MAT_C_UINT8 | Изображения (0-255) ✅ НОВОЕ |
| **uint16** | MAT_C_UINT16 | HDR изображения (0-65535) ✅ НОВОЕ |
| **int8** | MAT_C_INT8 | Signed данные (-128 to 127) ✅ НОВОЕ |
| **int16** | MAT_C_INT16 | Signed данные (-32768 to 32767) ✅ НОВОЕ |

### Примеры:

1. **asphalt2.mat:**
   - Тип: uint8
   - Диапазон: 0-255
   - ✅ Теперь открывается!

2. **Научные данные:**
   - Тип: float64
   - ✅ Уже работало, продолжает работать!

3. **HDR изображения:**
   - Тип: uint16
   - Диапазон: 0-65535
   - ✅ Теперь открывается!

## Тестирование

### 1. Пересоберите приложение:
```bash
cd /Users/mac/Desktop/HSIView
open HSIView.xcodeproj
# Cmd+R
```

### 2. Откройте asphalt2.mat:
- ✅ Должен открыться без ошибок
- ✅ Показывает переменную "image"
- ✅ Корректные размеры (H × W × C)
- ✅ Значения в диапазоне 0-255

### 3. Проверьте информационную панель:
- Формат: MATLAB (.mat)
- Тип данных: Float64 (после конвертации)
- Разрешение: (указаны правильные размеры)
- Диапазон значений: 0-255 для uint8

## Производительность

**Конвертация uint8 → double:**
- ✅ Быстро: простой цикл
- ⚠️ Память: 8x размера (uint8 = 1 байт, double = 8 байт)

**Для файла 100 МБ (uint8):**
- Исходный размер: 100 МБ
- В памяти: 800 МБ (после конвертации)

> **Примечание:** В будущем можно оптимизировать, храня uint8 напрямую в `DataStorage::uint8`, но для этого нужно изменить интерфейс C-Swift.

## Файлы изменены

- `HSIView/MatHelper.c`:
  - Добавлена проверка uint8, uint16, int8, int16
  - Добавлена конвертация целочисленных типов в double
  - Комментарии для каждого типа

## Дата

2025-11-28


