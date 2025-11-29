# Python Test Scripts

Коллекция Python скриптов для тестирования, отладки и проверки гиперспектральных форматов.

## 📋 Категории скриптов

### Создание тестовых данных

- **create_test_npy.py** - Создание простых NPY тестовых файлов
- **create_large_test_npy.py** - Создание больших NPY файлов (>2GB)
- **create_test_tiff.py** - Создание TIFF файлов через libtiff
- **create_test_tiff_pil.py** - Создание TIFF через PIL/Pillow
- **test_c_order.npy** - Тестовый NPY файл (C-order)
- **test_f_order.npy** - Тестовый NPY файл (Fortran-order)
- **test_gradient_c_order.npy** - Градиент (C-order)
- **test_gradient_f_order.npy** - Градиент (Fortran-order)

### Проверка порядка данных (Order)

- **check_npy_order.py** - Проверка C/Fortran order в NPY
- **test_npy_orders.py** - Тестирование обоих порядков
- **test_both_orders.py** - Сравнение C vs Fortran
- **test_fortran_order.py** - Специфичные тесты Fortran
- **inspect_real_npy.py** - Инспекция реальных NPY файлов

### Диагностика форматов

- **npy_file_reader.py** - Чтение и анализ NPY файлов
- **mat_file_reader.py** - Чтение и анализ MAT файлов
- **tiff_file_reader.py** - Чтение и анализ TIFF файлов
- **inspect_mat_file.py** - Детальная инспекция MAT
- **inspect_tiff_file.py** - Детальная инспекция TIFF
- **check_tiff_structure.py** - Проверка структуры TIFF

### ENVI формат

- **check_envi.py** - Проверка ENVI файлов
- **read_envi_test.py** - Тестовое чтение ENVI
- **verify_envi_order.py** - Проверка порядка ENVI данных

### Отладка

- **debug_npy.py** - Отладка NPY загрузчика
- **diagnose_tiff.py** - Диагностика TIFF проблем

---

## 🚀 Использование

### Требования

```bash
# Установить зависимости
pip3 install numpy pillow tifffile scipy
```

### Создание тестовых данных

```bash
# NPY файл (простой)
python3 create_test_npy.py

# NPY файл (большой, >2GB)
python3 create_large_test_npy.py

# TIFF файл
python3 create_test_tiff_pil.py
```

### Проверка файлов

```bash
# Проверить NPY файл
python3 check_npy_order.py /path/to/file.npy

# Проверить MAT файл
python3 inspect_mat_file.py /path/to/file.mat

# Проверить TIFF файл
python3 inspect_tiff_file.py /path/to/file.tiff

# Проверить ENVI файлы
python3 check_envi.py /path/to/file.hdr
```

---

## 📊 Примеры

### Пример 1: Создать тестовый NPY (Fortran order)

```bash
python3 create_test_npy.py

# Создаёт:
# - test_c_order.npy (C-order)
# - test_f_order.npy (Fortran-order)
```

Проверка:
```bash
python3 check_npy_order.py test_f_order.npy

# Вывод:
# File: test_f_order.npy
# Shape: (100, 512, 512)
# Dtype: float32
# Order: Fortran (column-major)
# Size: 100 MB
```

### Пример 2: Проверить MAT файл

```bash
python3 inspect_mat_file.py test_data/asphalt2.mat

# Вывод:
# Variables:
#   - asphalt (100, 512, 512) uint8
# First 3D variable: asphalt
# Data type: uint8
# Min/Max: 0, 255
```

### Пример 3: Диагностика ENVI

```bash
python3 check_envi.py test_data/ang20200709t213509.hdr

# Вывод:
# Header: ang20200709t213509.hdr
# Data: ang20200709t213509.dat
# Samples: 512
# Lines: 217
# Bands: 204
# Interleave: BIP
# Data type: 4 (float32)
# Byte order: 0 (little endian)
# Wavelengths: 204 values
```

---

## 🛠️ Разработка новых тестов

### Шаблон скрипта

```python
#!/usr/bin/env python3
"""
Краткое описание скрипта
"""
import numpy as np
import sys

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 script.py <file>")
        sys.exit(1)
    
    filepath = sys.argv[1]
    
    # Ваш код тестирования
    
    print(f"✅ Test passed")

if __name__ == "__main__":
    main()
```

### Добавление нового скрипта

1. Создайте файл в `python_tests/`
2. Сделайте его исполняемым: `chmod +x script.py`
3. Добавьте в этот README описание
4. Протестируйте на реальных данных

---

## 📁 Структура

```
python_tests/
├── README.md              # Этот файл
│
├── create_*.py            # Создание тестовых данных
├── check_*.py             # Проверка форматов
├── inspect_*.py           # Детальная инспекция
├── test_*.py              # Тесты функционала
├── diagnose_*.py          # Диагностика проблем
├── verify_*.py            # Верификация данных
│
├── *_file_reader.py       # Универсальные читалки
└── *.npy                  # Тестовые NPY файлы (игнорируются git)
```

---

## 🎯 Советы

### Создание тестовых данных
```bash
# Разные размеры для тестирования
python3 -c "import numpy as np; np.save('small.npy', np.random.rand(10,10,10))"
python3 -c "import numpy as np; np.save('medium.npy', np.random.rand(100,100,100))"
python3 create_large_test_npy.py  # Большой >2GB
```

### Быстрая проверка
```bash
# NPY
python3 -c "import numpy as np; a=np.load('file.npy'); print(a.shape, a.dtype)"

# MAT
python3 -c "from scipy.io import loadmat; print(loadmat('file.mat').keys())"

# TIFF
python3 -c "from tifffile import imread; print(imread('file.tiff').shape)"
```

### Отладка проблем HSIView
```bash
# 1. Создать упрощённый тестовый файл
python3 create_test_npy.py

# 2. Проверить что Python читает корректно
python3 check_npy_order.py test_c_order.npy

# 3. Открыть в HSIView и сравнить
# 4. Если не совпадает - использовать inspect_*.py
```

---

Вернуться в корень: [README.md](../README.md)  
Документация: [docs/README_DOCS.md](../docs/README_DOCS.md)


