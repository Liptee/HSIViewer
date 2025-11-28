#!/usr/bin/env python3
"""
Создание тестового TIFF файла для проверки парсера
"""

import numpy as np
import tifffile

print("Создание тестовых TIFF файлов...")

# Тест 1: Маленький файл с градиентами (легко проверить визуально)
H, W, C = 100, 150, 3
data = np.zeros((H, W, C), dtype=np.uint8)

# Канал 0: вертикальный градиент (0-255 сверху вниз)
for h in range(H):
    data[h, :, 0] = int(255 * h / (H - 1))

# Канал 1: горизонтальный градиент (0-255 слева направо)
for w in range(W):
    data[:, w, 1] = int(255 * w / (W - 1))

# Канал 2: диагональный градиент
for h in range(H):
    for w in range(W):
        data[h, w, 2] = int(255 * (h + w) / (H + W - 2))

# Сохраняем с PLANARCONFIG_SEPARATE (как ваши файлы)
tifffile.imwrite(
    'test_gradient_separate.tiff',
    data,
    photometric='minisblack',
    planarconfig='separate',  # Channels stored separately
    metadata={'axes': 'YXS'}
)
print(f"✅ test_gradient_separate.tiff создан (H={H}, W={W}, C={C}, SEPARATE)")

# Тест 2: Такой же файл, но CONTIG (для сравнения)
tifffile.imwrite(
    'test_gradient_contig.tiff',
    data,
    photometric='minisblack',
    planarconfig='contig',  # Channels interleaved
    metadata={'axes': 'YXS'}
)
print(f"✅ test_gradient_contig.tiff создан (H={H}, W={W}, C={C}, CONTIG)")

# Тест 3: Файл с известными значениями
test_pattern = np.zeros((50, 50, 5), dtype=np.uint8)
for c in range(5):
    test_pattern[:, :, c] = (c + 1) * 50  # Канал 0=50, 1=100, 2=150, 3=200, 4=250

tifffile.imwrite(
    'test_pattern_separate.tiff',
    test_pattern,
    photometric='minisblack',
    planarconfig='separate',
    metadata={'axes': 'YXS'}
)
print(f"✅ test_pattern_separate.tiff создан (50×50×5, значения по каналам)")

print("\nТеперь откройте эти файлы в HSIView:")
print("1. test_gradient_separate.tiff должен показывать:")
print("   - Канал 0: вертикальный градиент (темный сверху)")
print("   - Канал 1: горизонтальный градиент (темный слева)")
print("   - Канал 2: диагональный градиент")
print("")
print("2. test_pattern_separate.tiff должен показывать:")
print("   - Канал 0: серый 50")
print("   - Канал 1: серый 100")
print("   - Канал 2: серый 150")
print("   - и т.д.")
print("")
print("Если видите полосы/шум - проблема в парсере!")

