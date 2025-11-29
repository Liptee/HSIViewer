#!/usr/bin/env python3
"""
Проверка правильности isFortranOrder для ENVI
"""

import numpy as np

H, W, C = 2, 3, 4

# Создаем тестовые данные
test = np.arange(H * W * C).reshape((H, W, C))

print("Данные (H, W, C):")
print(test)
print()

# Flatten в column-major (Fortran) порядке
flat_f = test.flatten('F')
print("Flatten('F') - Fortran order (column-major):")
print(flat_f)
print()

# Flatten в row-major (C) порядке
flat_c = test.flatten('C')
print("Flatten('C') - C order (row-major):")
print(flat_c)
print()

# Проверка формулы linearIndex для Fortran order
print("="*70)
print("ПРОВЕРКА FORTRAN ORDER")
print("="*70)
print("Формула: idx = h + H * (w + W * c)")
print()

matches = True
for c in range(C):
    for w in range(W):
        for h in range(H):
            idx = h + H * (w + W * c)
            expected = test[h, w, c]
            actual = flat_f[idx]
            match = (expected == actual)
            if c < 2:  # Показываем только первые 2 канала
                print(f"  [{h},{w},{c}] -> idx={idx:2d}, expected={expected:2d}, flat_f[{idx}]={actual:2d}  {'✅' if match else '❌'}")
            matches = matches and match

print()
print(f"{'✅ Fortran order ПРАВИЛЬНЫЙ!' if matches else '❌ Fortran order НЕПРАВИЛЬНЫЙ!'}")
print()

# Проверка формулы linearIndex для C order
print("="*70)
print("ПРОВЕРКА C ORDER")
print("="*70)
print("Формула: idx = c + C * (w + W * h)")
print()

matches_c = True
for h in range(H):
    for w in range(W):
        for c in range(C):
            idx = c + C * (w + W * h)
            expected = test[h, w, c]
            actual = flat_c[idx]
            match = (expected == actual)
            if h == 0:  # Показываем только первую строку
                print(f"  [{h},{w},{c}] -> idx={idx:2d}, expected={expected:2d}, flat_c[{idx}]={actual:2d}  {'✅' if match else '❌'}")
            matches_c = matches_c and match

print()
print(f"{'✅ C order ПРАВИЛЬНЫЙ!' if matches_c else '❌ C order НЕПРАВИЛЬНЫЙ!'}")



