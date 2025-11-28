#!/usr/bin/env python3
"""Проверка порядка данных в NPY файле"""

import numpy as np
import sys

if len(sys.argv) < 2:
    print("Usage: python3 check_npy_order.py <file.npy>")
    sys.exit(1)

filepath = sys.argv[1]
print(f"Проверка файла: {filepath}\n")

# Загружаем без изменений
data = np.load(filepath, mmap_mode='r')

print("="*60)
print("ИНФОРМАЦИЯ О МАССИВЕ")
print("="*60)
print(f"Shape: {data.shape}")
print(f"Dtype: {data.dtype}")
print(f"Size: {data.size:,} элементов")
print(f"Nbytes: {data.nbytes / (1024**3):.2f} ГБ")
print()

print("Флаги памяти:")
print(f"  C_CONTIGUOUS (row-major):    {data.flags['C_CONTIGUOUS']}")
print(f"  F_CONTIGUOUS (column-major): {data.flags['F_CONTIGUOUS']}")
print(f"  OWNDATA:                     {data.flags['OWNDATA']}")
print()

print("="*60)
print("ПОРЯДОК ДАННЫХ В ПАМЯТИ")
print("="*60)

# Для shape (H, W, C), какой индекс меняется быстрее?
if len(data.shape) == 3:
    H, W, C = data.shape
    print(f"Интерпретация как (H={H}, W={W}, C={C})")
    print()
    
    # Проверим stride
    print(f"Strides: {data.strides}")
    stride_h, stride_w, stride_c = data.strides
    print(f"  Stride по H: {stride_h}")
    print(f"  Stride по W: {stride_w}")
    print(f"  Stride по C: {stride_c}")
    print()
    
    if data.flags['C_CONTIGUOUS']:
        print("C-order (row-major):")
        print("  Последний индекс (C) меняется быстрее всего")
        print("  Порядок в памяти: [H][W][C]")
        print("  Правильно для нашего рендерера!")
    elif data.flags['F_CONTIGUOUS']:
        print("Fortran-order (column-major):")
        print("  Первый индекс (H) меняется быстрее всего")
        print("  Порядок в памяти: [H][W][C] но с другими strides")
        print("  ⚠️  МОЖЕТ ПОТРЕБОВАТЬСЯ ТРАНСПОНИРОВАНИЕ!")
        print()
        print("Решение:")
        print("  1. np.ascontiguousarray(data) - конвертация в C-order")
        print("  2. Или правильная индексация при чтении")

print()
print("="*60)
print("ТЕСТ ДАННЫХ")
print("="*60)

# Выведем несколько значений
print("Первые 10 элементов в памяти:")
flat = data.ravel(order='K')  # 'K' = keep order as in memory
print(flat[:10])
print()

print("Пример: data[0, 0, :5] (первые 5 каналов пикселя (0,0)):")
print(data[0, 0, :5])
print()

print("Пример: data[:5, 0, 0] (первые 5 строк пикселя (0,0) канала 0):")
print(data[:5, 0, 0])

