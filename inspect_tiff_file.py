#!/usr/bin/env python3
"""
Быстрая диагностика TIFF файла
"""

import sys
from PIL import Image

if len(sys.argv) < 2:
    print("Usage: python3 inspect_tiff_file.py <file.tiff>")
    sys.exit(1)

filepath = sys.argv[1]
print(f"Проверка TIFF: {filepath}\n")

try:
    with Image.open(filepath) as img:
        print("="*70)
        print("ОСНОВНАЯ ИНФОРМАЦИЯ")
        print("="*70)
        print(f"Format: {img.format}")
        print(f"Mode: {img.mode}")
        print(f"Size: {img.size} (width × height)")
        print(f"Number of frames/pages: {getattr(img, 'n_frames', 1)}")
        
        # Получаем TIFF теги
        print("\n" + "="*70)
        print("TIFF TAGS")
        print("="*70)
        
        # Основные теги
        tags_of_interest = {
            256: 'ImageWidth',
            257: 'ImageLength',
            258: 'BitsPerSample',
            259: 'Compression',
            262: 'PhotometricInterpretation',
            277: 'SamplesPerPixel',
            284: 'PlanarConfiguration',
            278: 'RowsPerStrip',
        }
        
        for tag_id, tag_name in tags_of_interest.items():
            if tag_id in img.tag_v2:
                value = img.tag_v2[tag_id]
                print(f"{tag_name} ({tag_id}): {value}")
        
        # Расшифровка некоторых значений
        if 284 in img.tag_v2:
            planar = img.tag_v2[284]
            planar_str = "CONTIG (interleaved)" if planar == 1 else "SEPARATE (planar)" if planar == 2 else "Unknown"
            print(f"  → PlanarConfiguration: {planar_str}")
        
        if 259 in img.tag_v2:
            compression = img.tag_v2[259]
            compression_names = {1: "None", 2: "CCITT", 3: "CCITT Group 3", 4: "CCITT Group 4", 
                               5: "LZW", 6: "JPEG (old)", 7: "JPEG", 8: "Deflate", 32773: "PackBits"}
            comp_str = compression_names.get(compression, f"Unknown ({compression})")
            print(f"  → Compression: {comp_str}")
        
        if 262 in img.tag_v2:
            photo = img.tag_v2[262]
            photo_names = {0: "WhiteIsZero", 1: "BlackIsZero", 2: "RGB", 3: "Palette", 
                          4: "Transparency Mask", 5: "CMYK", 6: "YCbCr"}
            photo_str = photo_names.get(photo, f"Unknown ({photo})")
            print(f"  → PhotometricInterpretation: {photo_str}")
        
        print("\n" + "="*70)
        print("НАШИ ТРЕБОВАНИЯ (TiffHelper.c)")
        print("="*70)
        
        bits_per_sample = img.tag_v2.get(258, None)
        planar_config = img.tag_v2.get(284, None)
        
        print("Требования:")
        print("  1. BitsPerSample = 8")
        print("  2. PlanarConfiguration = 2 (SEPARATE)")
        print("\nФайл:")
        print(f"  1. BitsPerSample = {bits_per_sample} {'✅' if bits_per_sample == 8 else '❌'}")
        print(f"  2. PlanarConfiguration = {planar_config} {'✅' if planar_config == 2 else '❌'}")
        
        if bits_per_sample != 8 or planar_config != 2:
            print("\n⚠️  ФАЙЛ НЕ СООТВЕТСТВУЕТ ТРЕБОВАНИЯМ!")
            print("\nРешение:")
            if planar_config == 1:
                print("  - Добавить поддержку PLANARCONFIG_CONTIG (interleaved)")
            if bits_per_sample != 8:
                print(f"  - Добавить поддержку {bits_per_sample}-bit данных")
        else:
            print("\n✅ Файл должен открываться!")
            print("   Проблема может быть в другом...")
        
        # Если multi-page, покажем первый кадр
        if hasattr(img, 'n_frames') and img.n_frames > 1:
            print(f"\n" + "="*70)
            print(f"MULTI-PAGE TIFF ({img.n_frames} страниц)")
            print("="*70)
            import numpy as np
            frames = []
            for i in range(min(3, img.n_frames)):  # Первые 3 страницы
                img.seek(i)
                arr = np.array(img)
                frames.append(arr)
                print(f"Page {i}: shape={arr.shape}, dtype={arr.dtype}, range=[{arr.min()}, {arr.max()}]")
            
            if img.n_frames >= 3:
                print(f"... и еще {img.n_frames - 3} страниц")
        
except Exception as e:
    print(f"❌ ОШИБКА: {e}")
    import traceback
    traceback.print_exc()


