# Исправление загрузки .npy файлов

## Проблема

При загрузке файла `sponges.npy` (512×512×31, float64, Fortran order) возникала ошибка "Поврежденные данные".

## Исправления

### 1. Улучшен парсинг заголовка

**Было:** Использовались регулярные выражения, которые не всегда корректно обрабатывали формат Python dict.

**Стало:** Посимвольный парсинг с учетом вложенности скобок:

```swift
// Извлечение shape
// Находим 'shape': (...) и корректно парсим tuple
// Обрабатываем случаи: (512, 512, 31) и (512, 512, 31,)

// Извлечение dtype  
// Находим 'descr': '...' между кавычками
// Поддержка '<f8', '>f4', '=i4' и т.д.
```

### 2. Добавлена поддержка Fortran order для 2D

```swift
// Теперь reorderFromFortran работает как для 2D, так и для 3D
if shape.count == 2 {
    // Транспонирование для 2D
}
```

### 3. Более надежное извлечение данных

Улучшена обработка различных форматов заголовков NumPy версий 1.0, 2.0, 3.0.

## Тестирование исправлений

### Шаг 1: Анализ файла

```bash
cd /Users/mac/Desktop/HSIView
python3 debug_npy.py test_data/sponges.npy
```

Результат:
```
✅ Совместимость с HSIView:
  ✓ 3D гиперкуб - поканальный просмотр доступен
  ✓ Тип данных float64 поддерживается
  ✓ Fortran order - будет автоматически конвертирован
```

### Шаг 2: Сборка и запуск HSIView

1. Откройте проект в Xcode:
   ```bash
   open HSIView.xcodeproj
   ```

2. Пересоберите проект (Cmd+B)

3. Запустите (Cmd+R)

### Шаг 3: Загрузка файла

1. В HSIView: "Открыть файл…"
2. Выберите `test_data/sponges.npy`
3. Проверьте:
   - ✅ Файл открылся
   - ✅ Информационная панель показывает:
     - Формат: NumPy (.npy)
     - Тип данных: Float64
     - Разрешение: 512 × 512 × 31
     - Каналы: 31 (при HWC) или 512 (при CHW)
   - ✅ Изображение отображается
   - ✅ Можно переключать каналы слайдером

## Структура файла sponges.npy

```
Magic:    '\x93NUMPY'
Version:  1.0
Header:   {'descr': '<f8', 'fortran_order': True, 'shape': (512, 512, 31), }
Data:     512×512×31 × 8 bytes = 62 МБ
Layout:   Fortran order (column-major)
```

## Как работает исправление

### Парсинг заголовка:

1. **Чтение magic** (6 bytes): `\x93NUMPY`
2. **Версия** (2 bytes): major=1, minor=0
3. **Длина заголовка** (2 или 4 bytes): 118 bytes
4. **Заголовок** (118 bytes): Python dict в виде строки
5. **Данные** (остальное): бинарные данные

### Извлечение shape:

```
Input:  "{'descr': '<f8', 'fortran_order': True, 'shape': (512, 512, 31), }"
                                                           ^-----------^
Extract: (512, 512, 31)
Parse:   [512, 512, 31]
```

### Извлечение dtype:

```
Input:  "{'descr': '<f8', ..."
                     ^--^
Extract: '<f8'
Map:     '<f8' → float64 (little-endian)
```

### Конвертация Fortran → C order:

```
Fortran order: элементы идут по первому индексу
  data[0,0,0], data[1,0,0], data[2,0,0], ..., data[511,0,0],
  data[0,1,0], ...

C order: элементы идут по последнему индексу
  data[0,0,0], data[0,0,1], data[0,0,2], ..., data[0,0,30],
  data[0,1,0], ...

Транспонирование: i_fortran = i0 + d0*(i1 + d1*i2)
                  i_c = i2 + d2*(i1 + d1*i0)
```

## Дополнительная отладка

### Если проблема сохраняется:

1. **Проверьте в Python:**
   ```python
   import numpy as np
   data = np.load('test_data/sponges.npy')
   print(f"Shape: {data.shape}")
   print(f"Dtype: {data.dtype}")
   print(f"Fortran: {data.flags['F_CONTIGUOUS']}")
   print(f"Sample: {data[0,0,0]}")
   ```

2. **Пересохраните в C-order:**
   ```python
   data_c = np.ascontiguousarray(data)
   np.save('test_data/sponges_c_order.npy', data_c)
   ```

3. **Попробуйте открыть C-order версию** в HSIView

### Логирование

Если нужна дополнительная отладка, добавьте print в NpyImageLoader.swift:

```swift
print("DEBUG: Header string: \(headerString)")
print("DEBUG: Extracted shape: \(shape)")
print("DEBUG: Extracted dtype: \(dtype)")
print("DEBUG: Fortran order: \(fortranOrder)")
```

## Файлы изменены

- `HSIView/Services/NpyImageLoader.swift` - исправлен парсинг
- `debug_npy.py` - новый скрипт для отладки
- `NPY_SUPPORT.md` - обновлена документация
- `.gitignore` - добавлены debug скрипты

## Тестовые файлы

Создайте дополнительные тестовые файлы:

```bash
python3 create_test_npy.py
```

Откройте файлы из `test_npy_files/` для проверки различных случаев.

---

**Теперь .npy файлы с Fortran order должны загружаться корректно!** ✅

