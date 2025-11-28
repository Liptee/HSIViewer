#!/usr/bin/env python3
"""
Создание тестовых NPY файлов в C-order и Fortran-order для проверки
"""

import numpy as np

print("="*70)
print("СОЗДАНИЕ ТЕСТОВЫХ ФАЙЛОВ")
print("="*70)

# Создаем простой градиентный паттерн для легкой проверки
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

# C-order (по умолчанию)
data_c = np.ascontiguousarray(data)
np.save('test_gradient_c_order.npy', data_c)
print(f"\n✅ test_gradient_c_order.npy")
print(f"   Shape: {data_c.shape}")
print(f"   C_CONTIGUOUS: {data_c.flags['C_CONTIGUOUS']}")
print(f"   F_CONTIGUOUS: {data_c.flags['F_CONTIGUOUS']}")

# Fortran-order
data_f = np.asfortranarray(data)
np.save('test_gradient_f_order.npy', data_f)
print(f"\n✅ test_gradient_f_order.npy")
print(f"   Shape: {data_f.shape}")
print(f"   C_CONTIGUOUS: {data_f.flags['C_CONTIGUOUS']}")
print(f"   F_CONTIGUOUS: {data_f.flags['F_CONTIGUOUS']}")

print(f"\n{'='*70}")
print("ОЖИДАЕМЫЙ РЕЗУЛЬТАТ В ПРИЛОЖЕНИИ")
print("="*70)
print("\nОБА файла должны отображаться ОДИНАКОВО:")
print("  Канал 0: Вертикальный градиент (темный сверху, светлый снизу)")
print("  Канал 1: Горизонтальный градиент (темный слева, светлый справа)")
print("  Канал 2: Диагональный градиент (темный левый-верхний угол)")
print("\nЕсли видны полосы или изображения разные - есть ошибка!")

# Проверим, что оба файла читаются одинаково
loaded_c = np.load('test_gradient_c_order.npy')
loaded_f = np.load('test_gradient_f_order.npy')

if np.allclose(loaded_c, loaded_f):
    print("\n✅ NumPy читает оба файла одинаково")
else:
    print("\n❌ NumPy читает файлы по-разному (ошибка!)")

# Сохраним визуальное представление
try:
    from PIL import Image
    
    # Канал 0 из обоих файлов
    img_c = Image.fromarray(loaded_c[:, :, 0])
    img_c.save('test_gradient_c_order_ch0.png')
    
    img_f = Image.fromarray(loaded_f[:, :, 0])
    img_f.save('test_gradient_f_order_ch0.png')
    
    print("\n✅ Сохранены PNG для сравнения:")
    print("   test_gradient_c_order_ch0.png")
    print("   test_gradient_f_order_ch0.png")
except ImportError:
    print("\n⚠️  PIL не установлен, PNG не созданы")

print(f"\n{'='*70}")
print("ГОТОВО!")
print("="*70)

