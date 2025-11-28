#!/usr/bin/env python3
"""
Диагностика TIFF файлов - проверка структуры и порядка данных
"""

import numpy as np
from PIL import Image
import tifffile
import sys

if len(sys.argv) < 2:
    print("Usage: python3 diagnose_tiff.py <file.tiff>")
    sys.exit(1)

filepath = sys.argv[1]
print(f"Анализ TIFF файла: {filepath}\n")

print("="*70)
print("1. ЧТЕНИЕ С ПОМОЩЬЮ PIL (Pillow)")
print("="*70)

try:
    img = Image.open(filepath)
    print(f"Mode: {img.mode}")
    print(f"Size: {img.size}")
    print(f"Format: {img.format}")
    print(f"N Frames: {getattr(img, 'n_frames', 1)}")
    
    # Проверим первый кадр
    img.seek(0)
    data_pil = np.array(img)
    print(f"First frame shape: {data_pil.shape}")
    print(f"First frame dtype: {data_pil.dtype}")
    print(f"First frame range: [{data_pil.min()}, {data_pil.max()}]")
    
    # Если multi-page, соберем все кадры
    if hasattr(img, 'n_frames') and img.n_frames > 1:
        frames = []
        for i in range(img.n_frames):
            img.seek(i)
            frames.append(np.array(img))
        
        # Попробуем разные варианты стекинга
        stack_axis0 = np.stack(frames, axis=0)  # (C, H, W)
        stack_axis2 = np.stack(frames, axis=2)  # (H, W, C)
        
        print(f"\nMulti-page TIFF:")
        print(f"  Number of pages: {img.n_frames}")
        print(f"  Stack axis=0 (C,H,W): {stack_axis0.shape}")
        print(f"  Stack axis=2 (H,W,C): {stack_axis2.shape}")
        
        # Сохраним первую страницу для визуальной проверки
        if data_pil.ndim == 2:
            Image.fromarray(data_pil).save('tiff_page0_pil.png')
            print(f"  Saved first page: tiff_page0_pil.png")
except Exception as e:
    print(f"PIL Error: {e}")

print()
print("="*70)
print("2. ЧТЕНИЕ С ПОМОЩЬЮ tifffile")
print("="*70)

try:
    data_tifffile = tifffile.imread(filepath)
    print(f"Shape: {data_tifffile.shape}")
    print(f"Dtype: {data_tifffile.dtype}")
    print(f"Range: [{data_tifffile.min()}, {data_tifffile.max()}]")
    print(f"Mean: {data_tifffile.mean():.2f}")
    
    # Проверим метаданные
    with tifffile.TiffFile(filepath) as tif:
        print(f"\nTIFF Tags:")
        for page in tif.pages[:1]:  # Первая страница
            print(f"  ImageWidth: {page.imagewidth}")
            print(f"  ImageLength: {page.imagelength}")
            print(f"  BitsPerSample: {page.bitspersample}")
            print(f"  SamplesPerPixel: {page.samplesperpixel}")
            print(f"  PhotometricInterpretation: {page.photometric}")
            print(f"  PlanarConfiguration: {page.planarconfig}")
            print(f"  Compression: {page.compression}")
            
    # Если 3D, посмотрим на разные интерпретации
    if data_tifffile.ndim == 3:
        print(f"\nИнтерпретации shape {data_tifffile.shape}:")
        d0, d1, d2 = data_tifffile.shape
        
        # Вариант 1: (C, H, W)
        print(f"  Вариант 1 (C,H,W): C={d0}, H={d1}, W={d2}")
        
        # Вариант 2: (H, W, C)
        print(f"  Вариант 2 (H,W,C): H={d0}, W={d1}, C={d2}")
        
        # Сохраним визуализацию для обоих вариантов
        # Вариант 1: первый канал если (C,H,W)
        if d0 < d1 and d0 < d2:
            img1 = data_tifffile[0]  # Первый канал
            Image.fromarray(img1.astype(np.uint8)).save('tiff_chw_first_channel.png')
            print(f"  Saved (C,H,W) first channel: tiff_chw_first_channel.png")
            
        # Вариант 2: первый канал если (H,W,C)
        if d2 < d0 and d2 < d1:
            img2 = data_tifffile[:, :, 0]  # Первый канал
            Image.fromarray(img2.astype(np.uint8)).save('tiff_hwc_first_channel.png')
            print(f"  Saved (H,W,C) first channel: tiff_hwc_first_channel.png")
            
except Exception as e:
    print(f"tifffile Error: {e}")

print()
print("="*70)
print("3. АНАЛИЗ ПАМЯТИ")
print("="*70)

# Проверим порядок данных в памяти
if 'data_tifffile' in locals() and data_tifffile.ndim == 3:
    print(f"C_CONTIGUOUS: {data_tifffile.flags['C_CONTIGUOUS']}")
    print(f"F_CONTIGUOUS: {data_tifffile.flags['F_CONTIGUOUS']}")
    print(f"Strides: {data_tifffile.strides}")
    
    # Первые элементы в памяти
    flat = data_tifffile.ravel(order='K')  # Keep order
    print(f"First 20 elements in memory: {flat[:20]}")

print()
print("="*70)
print("4. РЕКОМЕНДАЦИИ")
print("="*70)

if 'data_tifffile' in locals() and data_tifffile.ndim == 3:
    d0, d1, d2 = data_tifffile.shape
    
    # Определяем вероятный layout
    if d0 < d1 and d0 < d2:
        print("✅ Вероятный layout: (C, H, W) - channels first")
        print(f"   Channels: {d0}, Height: {d1}, Width: {d2}")
        print("\n   Для HSIView нужно транспонировать в (H, W, C):")
        print(f"   data = np.transpose(data, (1, 2, 0))")
        
    elif d2 < d0 and d2 < d1:
        print("✅ Вероятный layout: (H, W, C) - channels last")
        print(f"   Height: {d0}, Width: {d1}, Channels: {d2}")
        print("\n   Для HSIView это правильный порядок!")
        
    else:
        print("⚠️  Неоднозначный layout")
        print(f"   Dimensions: {d0} × {d1} × {d2}")
        print("   Нужна ручная проверка")

print("\n" + "="*70)
print("ПРОВЕРЬТЕ СОХРАНЕННЫЕ PNG ФАЙЛЫ ДЛЯ ВИЗУАЛЬНОЙ ПРОВЕРКИ")
print("="*70)

