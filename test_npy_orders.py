#!/usr/bin/env python3
"""
Тест для понимания того, как NumPy хранит данные в C-order vs Fortran-order
"""

import numpy as np

# Создаем простой тестовый массив
print("="*60)
print("ТЕСТ: C-order vs Fortran-order")
print("="*60)

# Маленький массив для наглядности
shape = (3, 4, 2)  # (H=3, W=4, C=2)
data = np.arange(24).reshape(shape)  # 0..23

print(f"\nShape: {shape}")
print(f"Data:\n{data}")

# C-order (по умолчанию)
data_c = np.ascontiguousarray(data)
print(f"\n--- C-order (row-major) ---")
print(f"C_CONTIGUOUS: {data_c.flags['C_CONTIGUOUS']}")
print(f"F_CONTIGUOUS: {data_c.flags['F_CONTIGUOUS']}")
print(f"Strides: {data_c.strides}")
print(f"Flat (порядок в памяти): {data_c.ravel(order='K')[:12]}...")

# Fortran-order
data_f = np.asfortranarray(data)
print(f"\n--- Fortran-order (column-major) ---")
print(f"C_CONTIGUOUS: {data_f.flags['C_CONTIGUOUS']}")
print(f"F_CONTIGUOUS: {data_f.flags['F_CONTIGUOUS']}")
print(f"Strides: {data_f.strides}")
print(f"Flat (порядок в памяти): {data_f.ravel(order='K')[:12]}...")

# Проверим, что элементы одинаковые
print(f"\n--- Проверка индексации ---")
print(f"data_c[1, 2, 0] = {data_c[1, 2, 0]}")
print(f"data_f[1, 2, 0] = {data_f[1, 2, 0]}")
print("Элементы одинаковые, но порядок в памяти разный!")

# Сохраним оба
np.save('test_c_order.npy', data_c)
np.save('test_f_order.npy', data_f)

print(f"\n{'='*60}")
print("Файлы сохранены: test_c_order.npy, test_f_order.npy")
print("="*60)

# Прочитаем обратно и проверим
print("\n--- Чтение обратно ---")
loaded_c = np.load('test_c_order.npy')
loaded_f = np.load('test_f_order.npy')

print(f"loaded_c C_CONTIGUOUS: {loaded_c.flags['C_CONTIGUOUS']}")
print(f"loaded_f F_CONTIGUOUS: {loaded_f.flags['F_CONTIGUOUS']}")

print(f"\nloaded_c[1, 2, 0] = {loaded_c[1, 2, 0]}")
print(f"loaded_f[1, 2, 0] = {loaded_f[1, 2, 0]}")

print("\nNumPy всегда читает правильно, независимо от order!")
print("Секрет: NumPy использует strides для правильной индексации")

# Покажем как работает индексация
print(f"\n{'='*60}")
print("КАК РАБОТАЕТ ИНДЕКСАЦИЯ")
print("="*60)

H, W, C = shape
h, w, c = 1, 2, 0  # элемент который мы ищем

print(f"\nИщем элемент [{h}, {w}, {c}]")

# C-order
stride_h_c, stride_w_c, stride_c_c = data_c.strides
offset_c = h * stride_h_c + w * stride_w_c + c * stride_c_c
byte_offset_c = offset_c // data_c.itemsize
print(f"\nC-order:")
print(f"  Strides: {data_c.strides}")
print(f"  Offset = {h}*{stride_h_c} + {w}*{stride_w_c} + {c}*{stride_c_c} = {offset_c} bytes")
print(f"  Индекс в flat array: {byte_offset_c}")
print(f"  Значение: {data_c.ravel(order='K')[byte_offset_c]}")

# Fortran-order
stride_h_f, stride_w_f, stride_c_f = data_f.strides
offset_f = h * stride_h_f + w * stride_w_f + c * stride_c_f
byte_offset_f = offset_f // data_f.itemsize
print(f"\nFortran-order:")
print(f"  Strides: {data_f.strides}")
print(f"  Offset = {h}*{stride_h_f} + {w}*{stride_w_f} + {c}*{stride_c_f} = {offset_f} bytes")
print(f"  Индекс в flat array: {byte_offset_f}")
print(f"  Значение: {data_f.ravel(order='K')[byte_offset_f]}")

print(f"\n{'='*60}")
print("ВЫВОД: NumPy НЕ переупорядочивает данные!")
print("Он просто использует правильные strides для индексации!")
print("="*60)

