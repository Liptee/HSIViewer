#!/usr/bin/env python3
"""
Создание тестового TIFF файла для проверки парсера (только PIL)
"""

import numpy as np
from PIL import Image

print("Создание тестовых TIFF файлов...")

# Тест 1: Multi-page TIFF с градиентами
H, W, C = 100, 150, 3
channels = []

# Канал 0: вертикальный градиент
ch0 = np.zeros((H, W), dtype=np.uint8)
for h in range(H):
    ch0[h, :] = int(255 * h / (H - 1))
channels.append(Image.fromarray(ch0))

# Канал 1: горизонтальный градиент
ch1 = np.zeros((H, W), dtype=np.uint8)
for w in range(W):
    ch1[:, w] = int(255 * w / (W - 1))
channels.append(Image.fromarray(ch1))

# Канал 2: диагональный градиент
ch2 = np.zeros((H, W), dtype=np.uint8)
for h in range(H):
    for w in range(W):
        ch2[h, w] = int(255 * (h + w) / (H + W - 2))
channels.append(Image.fromarray(ch2))

# Сохраняем как multi-page TIFF
channels[0].save(
    'test_gradient_multipage.tiff',
    save_all=True,
    append_images=channels[1:],
    compression='none'
)
print(f"✅ test_gradient_multipage.tiff создан (H={H}, W={W}, {len(channels)} pages)")

# Тест 2: Файл с известными значениями по каналам
test_channels = []
for c in range(5):
    value = (c + 1) * 50  # 50, 100, 150, 200, 250
    img = np.full((50, 50), value, dtype=np.uint8)
    test_channels.append(Image.fromarray(img))

test_channels[0].save(
    'test_pattern_multipage.tiff',
    save_all=True,
    append_images=test_channels[1:],
    compression='none'
)
print(f"✅ test_pattern_multipage.tiff создан (50×50, 5 pages)")

print("\nТеперь откройте эти файлы в HSIView:")
print("\n1. test_gradient_multipage.tiff должен показывать:")
print("   - Канал 0: вертикальный градиент (темный сверху, светлый снизу)")
print("   - Канал 1: горизонтальный градиент (темный слева, светлый справа)")
print("   - Канал 2: диагональный градиент")
print("")
print("2. test_pattern_multipage.tiff должен показывать:")
print("   - Канал 0: равномерный серый 50")
print("   - Канал 1: равномерный серый 100")
print("   - Канал 2: равномерный серый 150")
print("   - Канал 3: равномерный серый 200")
print("   - Канал 4: равномерный серый 250")
print("")
print("Если видите полосы/шум/неправильные градиенты - проблема в парсере!")
print("")
print("Также можете проверить файлы Python:")
print("  python3 check_tiff_structure.py test_gradient_multipage.tiff")

