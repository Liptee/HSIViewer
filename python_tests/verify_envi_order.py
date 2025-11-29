#!/usr/bin/env python3
"""
Проверка правильности переупорядочивания ENVI данных
"""

import numpy as np

# Создадим тестовый массив 2x3x4 (H=2, W=3, C=4)
H, W, C = 2, 3, 4

print("="*70)
print("ТЕСТ ПЕРЕУПОРЯДОЧИВАНИЯ ENVI")
print("="*70)
print(f"Размеры: H={H}, W={W}, C={C}")
print()

# Создаем тестовые данные (H, W, C) с уникальными значениями
test_hwc = np.arange(H * W * C).reshape((H, W, C))
print("Исходные данные (H, W, C):")
print(test_hwc)
print()

# BSQ: (C, H, W) в файле
print("="*70)
print("BSQ (Band Sequential)")
print("="*70)
test_bsq = np.transpose(test_hwc, (2, 0, 1))  # (H,W,C) -> (C,H,W)
flat_bsq = test_bsq.flatten()
print(f"В файле (C, H, W): shape={test_bsq.shape}")
print(f"Flat: {flat_bsq[:12]}...")
print()

# Переупорядочиваем BSQ -> HWC (как Swift код)
result_bsq = []
for h in range(H):
    for w in range(W):
        for c in range(C):
            srcIdx = c * H * W + h * W + w
            result_bsq.append(flat_bsq[srcIdx])

result_bsq = np.array(result_bsq).reshape((H, W, C))
print(f"После reorderBSQToHWC:")
print(result_bsq)
print(f"Совпадает с исходным: {np.array_equal(result_bsq, test_hwc)}")
print()

# BIL: (H, C, W) в файле
print("="*70)
print("BIL (Band Interleaved by Line)")
print("="*70)
test_bil = np.transpose(test_hwc, (0, 2, 1))  # (H,W,C) -> (H,C,W)
flat_bil = test_bil.flatten()
print(f"В файле (H, C, W): shape={test_bil.shape}")
print(f"Flat: {flat_bil[:12]}...")
print()

# Переупорядочиваем BIL -> HWC (как Swift код)
result_bil = []
for h in range(H):
    for w in range(W):
        for c in range(C):
            srcIdx = h * C * W + c * W + w
            result_bil.append(flat_bil[srcIdx])

result_bil = np.array(result_bil).reshape((H, W, C))
print(f"После reorderBILToHWC:")
print(result_bil)
print(f"Совпадает с исходным: {np.array_equal(result_bil, test_hwc)}")
print()

# BIP: (H, W, C) в файле - уже правильный порядок
print("="*70)
print("BIP (Band Interleaved by Pixel)")
print("="*70)
flat_bip = test_hwc.flatten()
print(f"В файле (H, W, C): shape={test_hwc.shape}")
print(f"Flat: {flat_bip[:12]}...")
print(f"Переупорядочивание: НЕ ТРЕБУЕТСЯ (уже в правильном формате)")
print()

# Проверка column-major индексации
print("="*70)
print("ПРОВЕРКА COLUMN-MAJOR ИНДЕКСАЦИИ")
print("="*70)
print(f"dims = ({H}, {W}, {C})  # (H, W, C)")
print(f"isFortranOrder = true")
print()
print("linearIndex(h, w, c) = h + H * (w + W * c)")
print()

for c in range(min(2, C)):
    for h in range(H):
        for w in range(W):
            expected_idx = h + H * (w + W * c)
            expected_value = test_hwc[h, w, c]
            print(f"  [{h},{w},{c}] -> idx={expected_idx:2d}, value={expected_value:2d}")

print()
print("✅ Если Swift код использует эту же формулу, данные будут читаться правильно!")



