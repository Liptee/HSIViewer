#!/usr/bin/env python3
"""
Инспектирование реального NPY файла
"""

import numpy as np
import sys

if len(sys.argv) < 2:
    print("Использование: python3 inspect_real_npy.py <file.npy>")
    sys.exit(1)

filepath = sys.argv[1]
print(f"Файл: {filepath}\n")

# Загружаем
data = np.load(filepath)

print("="*70)
print("ИНФОРМАЦИЯ О ФАЙЛЕ")
print("="*70)
print(f"Shape: {data.shape}")
print(f"Dtype: {data.dtype}")
print(f"C_CONTIGUOUS: {data.flags['C_CONTIGUOUS']}")
print(f"F_CONTIGUOUS: {data.flags['F_CONTIGUOUS']}")
print(f"Strides: {data.strides}")
print()

# Определяем ожидаемые strides для C и F order
if len(data.shape) == 3:
    H, W, C = data.shape
    itemsize = data.itemsize
    
    # C-order: последний индекс меняется быстрее
    # Элемент [h, w, c] = базовый_адрес + h*W*C*itemsize + w*C*itemsize + c*itemsize
    c_strides = (W * C * itemsize, C * itemsize, itemsize)
    
    # Fortran-order: первый индекс меняется быстрее
    # Элемент [h, w, c] = базовый_адрес + h*itemsize + w*H*itemsize + c*H*W*itemsize
    f_strides = (itemsize, H * itemsize, H * W * itemsize)
    
    print("Ожидаемые strides:")
    print(f"  C-order:       {c_strides}")
    print(f"  Fortran-order: {f_strides}")
    print(f"  Фактические:   {data.strides}")
    print()
    
    if data.strides == c_strides:
        print("✅ Данные в C-order (row-major)")
        order_type = "C"
    elif data.strides == f_strides:
        print("✅ Данные в Fortran-order (column-major)")
        order_type = "F"
    else:
        print("❓ Данные в нестандартном порядке")
        order_type = "?"
    
    print()
    print("="*70)
    print("ПОРЯДОК ЭЛЕМЕНТОВ В ПАМЯТИ (первые 20)")
    print("="*70)
    
    # Читаем сырые данные как они лежат в памяти
    flat_memory = data.ravel(order='K')  # 'K' = keep order as in memory
    print(f"Первые 20 элементов: {flat_memory[:20]}")
    print()
    
    # Покажем соответствие с координатами
    print("Если это C-order, первые элементы должны быть:")
    print("  [0,0,0], [0,0,1], ..., [0,0,C-1], [0,1,0], ...")
    c_order_values = []
    count = 0
    for h in range(H):
        for w in range(W):
            for c in range(C):
                c_order_values.append(data[h, w, c])
                count += 1
                if count >= 20:
                    break
            if count >= 20:
                break
        if count >= 20:
            break
    print(f"C-order индексация: {c_order_values}")
    print()
    
    print("Если это Fortran-order, первые элементы должны быть:")
    print("  [0,0,0], [1,0,0], ..., [H-1,0,0], [0,1,0], ...")
    f_order_values = []
    count = 0
    for c in range(C):
        for w in range(W):
            for h in range(H):
                f_order_values.append(data[h, w, c])
                count += 1
                if count >= 20:
                    break
            if count >= 20:
                break
        if count >= 20:
            break
    print(f"Fortran-order индексация: {f_order_values}")
    print()
    
    # Сравнение
    if list(flat_memory[:20]) == c_order_values:
        print("✅ СОВПАДАЕТ С C-ORDER!")
        detected_order = "C"
    elif list(flat_memory[:20]) == f_order_values:
        print("✅ СОВПАДАЕТ С FORTRAN-ORDER!")
        detected_order = "F"
    else:
        print("❓ Не совпадает ни с одним")
        detected_order = "?"
    
    print()
    print("="*70)
    print("ИТОГ")
    print("="*70)
    print(f"По strides: {order_type}")
    print(f"По данным:  {detected_order}")
    
    if order_type == detected_order:
        print(f"✅ Консистентно: данные в {order_type}-order")
    else:
        print(f"⚠️  Несоответствие!")

