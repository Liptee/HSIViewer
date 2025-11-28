#!/usr/bin/env python3
"""
Проверка структуры TIFF файла и сравнение с нашим C кодом
"""

import numpy as np
import tifffile
from PIL import Image
import sys

if len(sys.argv) < 2:
    print("Usage: python3 check_tiff_structure.py <file.tiff>")
    print("\nИли укажите путь к вашему тестовому файлу:")
    print("  python3 check_tiff_structure.py test_data/tis_video20250925_0419_9641.tiff")
    sys.exit(1)

filepath = sys.argv[1]
print(f"="*70)
print(f"АНАЛИЗ TIFF: {filepath}")
print("="*70)

# Читаем с tifffile
data = tifffile.imread(filepath)
print(f"\ntifffile.imread():")
print(f"  Shape: {data.shape}")
print(f"  Dtype: {data.dtype}")
print(f"  Range: [{data.min()}, {data.max()}]")
print(f"  Memory order: C={data.flags['C_CONTIGUOUS']}, F={data.flags['F_CONTIGUOUS']}")

# Метаданные
with tifffile.TiffFile(filepath) as tif:
    page = tif.pages[0]
    print(f"\nTIFF Metadata (first page):")
    print(f"  ImageWidth: {page.imagewidth}")
    print(f"  ImageLength: {page.imagelength}")
    print(f"  SamplesPerPixel: {page.samplesperpixel}")
    print(f"  BitsPerSample: {page.bitspersample}")
    print(f"  PlanarConfiguration: {page.planarconfig} ({'SEPARATE' if page.planarconfig == 2 else 'CONTIG'})")
    print(f"  PhotometricInterpretation: {page.photometric}")
    print(f"  Number of pages: {len(tif.pages)}")

# Проверим разные интерпретации
if data.ndim == 3:
    d0, d1, d2 = data.shape
    print(f"\nИнтерпретация shape {data.shape}:")
    
    # Определяем layout
    if d2 < d0 and d2 < d1:
        print(f"  ✅ Это (H, W, C): H={d0}, W={d1}, C={d2}")
        layout = "HWC"
        H, W, C = d0, d1, d2
    elif d0 < d1 and d0 < d2:
        print(f"  ✅ Это (C, H, W): C={d0}, H={d1}, W={d2}")
        layout = "CHW"
        C, H, W = d0, d1, d2
    else:
        print(f"  ⚠️  Неоднозначно: {d0} × {d1} × {d2}")
        layout = "???"
        H, W, C = d0, d1, d2
    
    print(f"\n  Наш C код возвращает: dims[0]={H}, dims[1]={W}, dims[2]={C}")
    print(f"  Это (H, W, C) в column-major (Fortran) порядке")
    
    # Проверим первый пиксель всех каналов
    print(f"\n  Первый пиксель [0, 0, :] (все каналы):")
    if layout == "HWC":
        print(f"    {data[0, 0, :10]}...")  # Первые 10 каналов
    elif layout == "CHW":
        print(f"    {data[:10, 0, 0]}...")  # Первые 10 каналов
    
    # Сохраним первый канал для визуальной проверки
    if layout == "HWC":
        channel0 = data[:, :, 0]
    elif layout == "CHW":
        channel0 = data[0, :, :]
    else:
        channel0 = data[0, :, :] if d0 < d1 else data[:, :, 0]
    
    # Нормализуем и сохраним
    ch0_norm = ((channel0 - channel0.min()) / (channel0.max() - channel0.min()) * 255).astype(np.uint8)
    Image.fromarray(ch0_norm).save('tiff_python_channel0.png')
    print(f"\n  ✅ Сохранен первый канал: tiff_python_channel0.png")
    print(f"     Range: [{channel0.min()}, {channel0.max()}]")

# Симуляция нашего C кода
print(f"\n{'='*70}")
print("СИМУЛЯЦИЯ НАШЕГО C КОДА")
print("="*70)

if data.ndim == 3:
    # Наш C код:
    # 1. Читает каналы по порядку (PLANARCONFIG_SEPARATE)
    # 2. Для каждого канала читает строки (row-major)
    # 3. Записывает в Fortran-order: colMajorIdx = row + H * (col + W * s)
    
    if layout == "HWC":
        H, W, C = data.shape
        
        # Создаем массив как наш C код
        simulated = np.zeros((H, W, C), dtype=np.float64, order='F')  # Fortran order
        
        # Заполняем как C код
        for c in range(C):
            for h in range(H):
                for w in range(W):
                    simulated[h, w, c] = data[h, w, c]
        
        print(f"Симуляция создана: shape={simulated.shape}")
        print(f"  C_CONTIGUOUS: {simulated.flags['C_CONTIGUOUS']}")
        print(f"  F_CONTIGUOUS: {simulated.flags['F_CONTIGUOUS']}")
        
        # Проверим первые элементы в памяти
        orig_flat = data.ravel(order='K')
        sim_flat = simulated.ravel(order='K')
        
        print(f"\nПервые 20 элементов в памяти:")
        print(f"  Python:    {orig_flat[:20]}")
        print(f"  Simulated: {sim_flat[:20]}")
        print(f"  Match: {np.allclose(orig_flat[:20], sim_flat[:20])}")
        
        # Сравним визуально
        sim_ch0 = simulated[:, :, 0]
        sim_ch0_norm = ((sim_ch0 - sim_ch0.min()) / (sim_ch0.max() - sim_ch0.min()) * 255).astype(np.uint8)
        Image.fromarray(sim_ch0_norm).save('tiff_simulated_channel0.png')
        print(f"\n  ✅ Сохранен симулированный первый канал: tiff_simulated_channel0.png")

print(f"\n{'='*70}")
print("ВЫВОД")
print("="*70)
print("\nСравните PNG файлы:")
print("  tiff_python_channel0.png     - как читает Python")
print("  tiff_simulated_channel0.png  - как должен читать наш C код")
print("\nЕсли они РАЗНЫЕ - проблема в индексации C кода!")

